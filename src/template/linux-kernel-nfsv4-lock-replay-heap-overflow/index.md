---
title: Linux Kernel NFSv4 LOCK Replay Heap Overflow
description: Heap overflow in Linux NFSv4 replay cache lets unauthenticated attackers trigger out-of-bounds writes via crafted conflicting LOCK requests.
tags: linux, cve, nfs
date: 2026-04-13
time: 02:21:30
slug: linux-kernel-nfsv4-lock-replay-heap-overflow
---

> ## TL;DR
>
> - **Heap overflow** in Linux kernel NFSv4.0 server replay cache allows slab-out-of-bounds write of up to 944 bytes when caching LOCK denial responses containing large lock owner strings
> - **High severity** (CVSS 3.x: 8.1) - remotely exploitable by unauthenticated attackers with network access to NFSv4.0 services; no known exploits in the wild yet
> - **Immediate action**: Upgrade to patched kernel versions (6.1.167+, 6.6.130+, 6.12.78+, 6.18.20+, 6.19.10+, or 7.0-rc5+) or apply vendor patches
> - **Discovered by Nicholas Carlini** and disclosed April 3, 2026; affects all Linux kernels from 2.6.12 through stable branches prior to March 2025 fixes

## Vulnerability Summary

| Field | Value |
|---|---|
| `CVE` ID | CVE-2026-31402 |
| `CVSS` Score | 8.1 (CVSS 3.x) |
| `CVSS` Vector | CVSS:3.0/AV:A/AC:L/PR:N/UI:N/S:U/C:N/I:H/A:H |
| `CVSS` Version | 3.0 |
| `CVSS` Source | Tenable (NVD awaiting enrichment) |
| Vulnerability Type | Heap-based Buffer Overflow (CWE-122) |
| Affected Software | Linux Kernel NFSv4.0 server (`nfsd`) |
| Affected Versions | 2.6.12 through 6.1.166, 6.6.129, 6.12.77, 6.18.19, 6.19.9 |
| Patch Status | Fixed in stable branches (see Remediation section) |
| `PoC` Publicly Available | No |

## Context

CVE-2026-31402 represents a classic buffer sizing miscalculation in the Linux kernel's NFSv4.0 server implementation. The vulnerability has existed since Linux 2.6.12-rc2 (commit `1da177e4c3f4`) and went undetected for nearly two decades until security researcher Nicholas Carlini identified and reported it in early 2026.

The flaw matters now because NFSv4.0 remains widely deployed in enterprise storage environments, and the exploitation prerequisites are minimal: network access to an NFSv4.0 server and the ability to establish two cooperating client connections. No authentication credentials are required.

Organizations running NFS servers on unpatched kernels face potential kernel memory corruption, denial of service, or privilege escalation. The vulnerability is particularly concerning for shared hosting environments, cloud storage gateways, and enterprise NAS systems where multi-tenant isolation depends on kernel integrity.

## Disclosure Timeline

| Date (UTC) | Event |
|---|---|
| 2026-03-09 | CVE ID reserved by Linux CNA |
| 2026-02-24 | Patch authored by Jeff Layton |
| 2026-03-16 to 2026-03-25 | Fixes merged across stable kernel branches |
| 2026-04-03 | CVE published to NVD; public disclosure |
| 2026-04-05 | Tenable Nessus plugin 304931 released |
| 2026-04-07 | NVD record last updated |

## Technical Detail

### Root Cause

The NFSv4.0 protocol implements a **replay cache** to handle idempotent operation retransmissions. When a client retries an operation, the server can replay the cached response rather than re-executing the operation. The kernel stores these encoded responses in a fixed-size inline buffer within each `nfs4_stateowner` structure.

The buffer size constant `NFSD4_REPLAY_ISIZE` was set to **112 bytes** based on calculations for OPEN operation responses:

```diff
--- a/fs/nfsd/state.h
+++ b/fs/nfsd/state.h
@@ -430,11 +430,18 @@ struct nfs4_client_reclaim {
 	struct xdr_netobj	cr_princhash;
 };
 
-/* A reasonable value for REPLAY_ISIZE was estimated as follows:  
- * The OPEN response, typically the largest, requires 
- *   4(status) + 8(stateid) + 20(changeinfo) + 4(rflags) +  8(verifier) + 
- *   4(deleg. type) + 8(deleg. stateid) + 4(deleg. recall flag) + 
- *   20(deleg. space limit) + ~32(deleg. ace) = 112 bytes 
+/*
+ * REPLAY_ISIZE is sized for an OPEN response with delegation:
+ *   4(status) + 8(stateid) + 20(changeinfo) + 4(rflags) +
+ *   8(verifier) + 4(deleg. type) + 8(deleg. stateid) +
+ *   4(deleg. recall flag) + 20(deleg. space limit) +
+ *   ~32(deleg. ace) = 112 bytes
+ *
+ * Some responses can exceed this. A LOCK denial includes the conflicting
+ * lock owner, which can be up to 1024 bytes (NFS4_OPAQUE_LIMIT). Responses
+ * larger than REPLAY_ISIZE are not cached in rp_ibuf; only rp_status is
+ * saved. Enlarging this constant increases the size of every
+ * nfs4_stateowner.
```

This sizing did not account for **LOCK denied responses**, which must include the conflicting lock owner as a variable-length opaque field up to **1024 bytes** (`NFS4_OPAQUE_LIMIT`).

### Triggering Condition

When `nfsd4_encode_operation()` processes a LOCK denial, it copies the full encoded response into `rp_ibuf[NFSD4_REPLAY_ISIZE]` via `read_bytes_from_xdr_buf()` without bounds checking. A lock owner string near the 1024-byte limit produces a response exceeding the 112-byte buffer by up to **944 bytes**, resulting in slab-out-of-bounds heap corruption.

### Attack Vector

An unauthenticated remote attacker with two cooperating NFSv4.0 clients can trigger this:

1. **Client A** establishes a lock on a file with a large owner string (approaching 1024 bytes)
2. **Client B** requests a conflicting lock on the same file region
3. The server denies Client B's request and attempts to cache the denial response including Client A's large owner string
4. The oversized response overflows the replay buffer, corrupting adjacent heap memory

### The Fix

The patch adds a length check before copying into the replay buffer. If the encoded response exceeds `NFSD4_REPLAY_ISIZE`, the server sets `rp_buflen = 0` to skip caching the payload while preserving the status code. This approach avoids increasing the size of every `nfs4_stateowner` structure, which would waste memory for the common case of small lock owners.

```diff
--- a/fs/nfsd/nfs4xdr.c
+++ b/fs/nfsd/nfs4xdr.c
@@ -5438,9 +5438,14 @@ nfsd4_encode_operation(struct nfsd4_compoundres *resp, struct nfsd4_op *op)
 		int len = xdr->buf->len - post_err_offset;
 
 		so->so_replay.rp_status = op->status;
-		so->so_replay.rp_buflen = len;
-		read_bytes_from_xdr_buf(xdr->buf, post_err_offset,
+		if (len <= NFSD4_REPLAY_ISIZE) {
+			so->so_replay.rp_buflen = len;
+			read_bytes_from_xdr_buf(xdr->buf,
+						post_err_offset,
 						so->so_replay.rp_buf, len);
+		} else {
+			so->so_replay.rp_buflen = 0;
+		}
```

The header file `fs/nfsd/state.h` was also updated to document that responses larger than `NFSD4_REPLAY_ISIZE` are not cached in `rp_ibuf`, with only `rp_status` preserved.

## Mitigation

Until patches can be applied, consider these exposure-reduction measures:

- **Restrict NFSv4.0 access** to trusted client IP ranges via firewall rules or `/etc/exports` configuration
- **Monitor for suspicious patterns**: Two clients from the same source establishing locks followed by conflicting lock requests with abnormally large owner strings
- **Enable kernel memory debugging** (KASAN, KFENCE) in test environments to detect heap corruption early
- **Network segmentation**: Isolate NFS servers from untrusted network segments where possible

Note that upgrading to NFSv4.1 or later may provide different replay cache implementations, but this should be tested thoroughly before production deployment as protocol behavior changes may affect client compatibility.

## Remediation

Apply the appropriate kernel patch for your stable branch. The fix has been merged to the following stable kernel versions:

| Kernel Branch | Fixed Version | Commit |
|---|---|---|
| 6.1.x | 6.1.167 | `c9452c0797c95cf2378170df96cf4f4b3bca7eff` |
| 6.6.x | 6.6.130 | `8afb437ea1f70cacb4bbdf11771fb5c4d720b965` |
| 6.12.x | 6.12.78 | `dad0c3c0a8e5d1d6eb0fc455694ce3e25e6c57d0` |
| 6.18.x | 6.18.20 | `ae8498337dfdfda71bdd0b807c9a23a126011d76` |
| 6.19.x | 6.19.10 | `0f0e2a54a31a7f9ad2915db99156114872317388` |
| 7.0-rc | 7.0-rc5 | `5133b61aaf437e5f25b1b396b14242a6bb0508e2` |

Upstream commit `5133b61aaf437e5f25b1b396b14242a6bb0508e2` authored by Jeff Layton contains the canonical fix. Distribution-specific packages should reference these commits for backport verification.

## Verification

### Check Kernel Version

```bash
# Verify current kernel version
uname -r

# Check if vulnerable (examples of vulnerable ranges)
# 5.15.0-105-generic - vulnerable
# 6.1.0-20-amd64 - vulnerable
# 6.1.167 or higher - patched
```

### Verify Patch Presence in Source

If you have kernel source access, verify the fix is present:

```bash
# Check for the bounds check in nfs4xdr.c
grep -A5 "NFSD4_REPLAY_ISIZE" fs/nfsd/nfs4xdr.c

# Expected output should show the if/else block checking len <= NFSD4_REPLAY_ISIZE
# before calling read_bytes_from_xdr_buf()
```

### Runtime Detection (KASAN)

If running a KASAN-enabled debug kernel, exploitation attempts would produce logs similar to:

```
==================================================================
BUG: KASAN: slab-out-of-bounds in nfsd4_encode_operation+0x...
Write of size 944 at addr ... by task nfsd/...
```

## References

- [NVD - CVE-2026-31402](https://nvd.nist.gov/vuln/detail/CVE-2026-31402)
- [SentinelOne - CVE-2026-31402 Analysis](https://www.sentinelone.com/vulnerability-database/cve-2026-31402/)
- [Tenable - Nessus Plugin 304931](https://www.tenable.com/plugins/nessus/304931)
- [Snyk - SNYK-CENTOS8-KERNELCORE-15943629](https://security.snyk.io/vuln/SNYK-CENTOS8-KERNELCORE-15943629)
- [OSV - ROOT-OS-DEBIAN-13-CVE-2026-31402](https://osv.dev/vulnerability/ROOT-OS-DEBIAN-13-CVE-2026-31402)
- [Linux Kernel Git - Commit 5133b61](https://git.kernel.org/stable/c/5133b61aaf437e5f25b1b396b14242a6bb0508e2)
- [Linux Kernel Git - Commit 0f0e2a5](https://git.kernel.org/stable/c/0f0e2a54a31a7f9ad2915db99156114872317388)
- [Linux Kernel Git - Commit 8afb437](https://git.kernel.org/stable/c/8afb437ea1f70cacb4bbdf11771fb5c4d720b965)
- [Linux Kernel Git - Commit ae84983](https://git.kernel.org/stable/c/ae8498337dfdfda71bdd0b807c9a23a126011d76)
- [Linux Kernel Git - Commit c9452c0](https://git.kernel.org/stable/c/c9452c0797c95cf2378170df96cf4f4b3bca7eff)
- [Linux Kernel Git - Commit dad0c3c](https://git.kernel.org/stable/c/dad0c3c0a8e5d1d6eb0fc455694ce3e25e6c57d0)
- [Red Hat Bugzilla - Bug 2454844](https://bugzilla.redhat.com/showbug.cgi?id=2454844)
