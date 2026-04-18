import tailwind from "bun-plugin-tailwind"

const SOURCE_DIR = "./src"
const NOT_FOUND = `${SOURCE_DIR}/404.html`

function isSafePath(pathname: string) {
  return (
    pathname.startsWith("/") &&
    !pathname.includes("\0") &&
    !pathname.includes("..") &&
    !pathname.includes("\\")
  )
}

function resolvePathnameToFile(pathname: string) {
  if (pathname.endsWith("/")) return `${SOURCE_DIR}${pathname}index.html`

  const direct = `${SOURCE_DIR}${pathname}`
  return direct
}

async function fileResponse(filePath: string) {
  const file = Bun.file(filePath)
  if (!(await file.exists())) return null

  return new Response(file, {
    headers: {
      "Content-Type": file.type || "application/octet-stream"
    }
  })
}

async function compiledCssResponse(entrypoint: string) {
  const entryFile = Bun.file(entrypoint)
  if (!(await entryFile.exists())) return null

  const result = await Bun.build({
    entrypoints: [entrypoint],
    outdir: "./.bun",
    naming: {
      entry: "index.css",
      asset: "[name].[ext]"
    },
    minify: false,
    plugins: [tailwind]
  })

  if (!result.success) {
    const messages = result.logs
      .map((l) => `${l.level.toUpperCase()}: ${l.message}`)
      .join("\n")
    return new Response(messages, { status: 500 })
  }

  const out = Bun.file("./.bun/index.css")
  if (!(await out.exists()))
    return new Response("CSS build failed", { status: 500 })

  const text = await out.text()
  return new Response(text, {
    headers: { "Content-Type": "text/css; charset=utf-8" }
  })
}

const server = Bun.serve({
  port: 5000,
  async fetch(req) {
    const url = new URL(req.url)
    const pathname = decodeURIComponent(url.pathname)

    if (!isSafePath(pathname)) {
      return new Response("Bad Request", { status: 400 })
    }

    if (pathname === "/style.css" || pathname === "/post.css") {
      const entry =
        pathname === "/post.css"
          ? `${SOURCE_DIR}/post.css`
          : `${SOURCE_DIR}/style.css`
      const css = await compiledCssResponse(entry)
      if (css) return css
    }

    if (pathname === "/") {
      const home = await fileResponse(`${SOURCE_DIR}/index.html`)
      if (home) return home
    }

    const mapped = resolvePathnameToFile(pathname)
    const resp = await fileResponse(mapped)
    if (resp) return resp

    const asDirIndex = await fileResponse(`${SOURCE_DIR}${pathname}/index.html`)
    if (asDirIndex) return asDirIndex

    const notFound = await fileResponse(NOT_FOUND)
    return notFound ?? new Response("Not Found", { status: 404 })
  }
})

console.log(`Server running at http://localhost:${server.port}`)
