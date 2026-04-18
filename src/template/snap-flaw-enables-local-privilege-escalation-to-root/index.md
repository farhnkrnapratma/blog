---
title: Snap Flaw Enables Local Privilege Escalation To Root
description: Local privilege escalation in snapd on Linux allows local attackers to get root privilege.
tags: linux, snapd, cve
date: 2026-04-13
time: 03:30:23
slug: snap-flaw-enables-local-privilege-escalation-to-root
---

> ## TL;DR
>
> - CVE-2026-3888 is a local privilege escalation in snapd where systemd-tmpfiles cleanup of `/tmp/.snap` creates a window for an attacker to inject attacker-controlled files that snap-confine later bind-mounts as root
> - Rated High severity with a CVSS 3.1 score of 7.8; exploitation requires a low-privileged local account and a waiting period of 10 to 30 days, with no user interaction needed
> - Update snapd immediately to the vendor-patched release; Ubuntu Server installations are unaffected in default configurations because the cleanup timer is disabled
> - The flaw is a TOCTOU race condition affecting Ubuntu Desktop 24.04 and later; legacy LTS releases received hardening patches though they are not vulnerable by default

| Field | Value |
|---|---|
| CVE ID | CVE-2026-3888 |
| CVSS Score | 7.8 |
| CVSS Vector | CVSS:3.1/AV:L/AC:H/PR:L/UI:N/S:C/C:H/I:H/A:H |
| CVSS Version | 3.1 |
| CVSS Source | Canonical |
| Vulnerability Type | Local Privilege Escalation / TOCTOU Race Condition |
| Affected Software | snapd |
| Affected Versions | Ubuntu Desktop >= 24.04 default installations; upstream snapd prior to 2.75 |
| Patch Status | Patched |
| PoC Publicly Available | Exploitation methodology publicly documented |

## Context

snapd is the daemon behind Ubuntu's Snap packaging system, installed and active by default on millions of Ubuntu Desktop hosts. The vulnerability lies in an interaction between two privileged components: `snap-confine`, the setuid root binary that constructs sandbox environments, and `systemd-tmpfiles`, which handles lifecycle management of volatile directories like `/tmp`.

In default Ubuntu Desktop configurations, `systemd-tmpfiles` periodically removes stale directories under `/tmp`. One of those directories, `/tmp/.snap`, is used by `snap-confine` during sandbox initialization. When the cleanup routine deletes it, a local attacker can recreate the directory and populate it with malicious content before `snap-confine` executes again. Because `snap-confine` runs with elevated privileges and performs bind mounts on that path, the attacker achieves arbitrary code execution as root.

The attack complexity is high because it depends on timing. On Ubuntu 24.04, the cleanup interval is roughly 30 days; on 25.10, it drops to about 10 days. No user interaction is required, and the attacker only needs a low-privileged local account. I have not seen evidence of active in-the-wild exploitation, but the mechanism has been reliably reproduced in research and training environments.

## Disclosure Timeline

| Date | Event |
|---|---|
| 2026-03-17 | Qualys publishes advisory; Ubuntu releases USN-8102-1 and USN-8102-2; NVD publishes entry |
| 2026-03-18 | NVD last modified |
| 2026-03-25 | Ubuntu security page last updated |

## Technical Detail

The root cause is a **time-of-check to time-of-use (TOCTOU)** gap combined with predictable cleanup behavior. `snap-confine` assumes that `/tmp/.snap` is a trusted directory created and managed by the system. `systemd-tmpfiles`, configured via drop-in files under `/usr/lib/tmpfiles.d/`, automatically deletes directories that exceed a staleness threshold.

The triggering condition is straightforward:

1. `systemd-tmpfiles` removes `/tmp/.snap` during its scheduled cleanup.
2. The attacker detects the deletion and recreates `/tmp/.snap` with attacker-owned files or symlinks.
3. The next time `snap-confine` initializes a sandbox, it bind-mounts the attacker-controlled directory into the mount namespace with root privileges.

This is not a memory corruption bug. It is a logic flaw in how two legitimate system utilities trust shared state in a world-writable parent directory. Server installations avoid the issue by default because `systemd-tmpfiles-clean.timer` is not enabled on Ubuntu Server, so the directory is never automatically removed.

During the same review window, Qualys also identified a race condition in the `uutils` coreutils `rm` utility affecting Ubuntu 25.10. That flaw allowed arbitrary file deletion during root-owned cron jobs. Ubuntu reverted the default `rm` to GNU coreutils prior to release and patched the upstream package separately. While related to the same research effort, it is a distinct vulnerability tracked outside CVE-2026-3888.

## Mitigation

Until patching is complete, reduce exposure with the following controls:

- **Restrict local access**: This vulnerability requires a local account. Remove unnecessary users and enforce least-privilege access on shared workstations.
- **Monitor `/tmp/.snap`**: Audit for unexpected ownership or permission changes on `/tmp/.snap`. A directory owned by an unprivileged user is a clear anomaly.
- **Audit temporary directory activity**: Look for unusual file creation or symlink activity immediately under `/tmp`.

These steps do not eliminate the vulnerability, but they increase the probability of detecting precursor activity.

## Remediation

Canonical has released patches for all supported Ubuntu releases. Upgrade `snapd` to the fixed version for your distribution:

- **Ubuntu 24.04 LTS**: `snapd` 2.73+ubuntu24.04.2 or later
- **Ubuntu 25.10 LTS**: `snapd` 2.73+ubuntu25.10.1 or later
- **Ubuntu 26.04 LTS (Dev)**: `snapd` 2.74.1+ubuntu26.04.1 or later
- **Ubuntu 22.04 LTS**: `snapd` 2.73+ubuntu22.04.1 or later
- **Ubuntu 20.04 LTS**: `snapd` 2.67.1+20.04ubuntu1~esm1 or later (via Ubuntu Pro)
- **Ubuntu 18.04/16.04 LTS**: ESM patches available via Ubuntu Pro

Upstream `snapd` versions prior to 2.75 are affected. The fix ensures that `snap-confine` validates the state of `/tmp/.snap` before performing privileged operations, closing the race window.

## Verification

Confirm the patch is installed and the system is not running an affected configuration:

```bash
# Check installed snapd version
dpkg -l | grep snapd

# Verify the cleanup timer is inactive on server installations
systemctl is-active systemd-tmpfiles-clean.timer

# Inspect /tmp/.snap ownership and permissions
ls -ld /tmp/.snap
```

On a fully patched Ubuntu Desktop 24.04 or 25.10, `dpkg -l` should show the fixed release. If `systemd-tmpfiles-clean.timer` reports `inactive`, the host is not vulnerable via the default vector. If `/tmp/.snap` is present, it should be owned by `root`.

## References

- [Qualys - CVE-2026-3888 Advisory](https://blog.qualys.com/vulnerabilities-threat-research/2026/03/17/cve-2026-3888-important-snap-flaw-enables-local-privilege-escalation-to-root)
- [Ubuntu Security - CVE-2026-3888](https://ubuntu.com/security/CVE-2026-3888)
- [NVD - CVE-2026-3888](https://nvd.nist.gov/vuln/detail/CVE-2026-3888)
- [Hack The Box - Snapshots and Slip-Ups](https://www.hackthebox.com/blog/CVE-2026-27944-CVE-2026-3888)
