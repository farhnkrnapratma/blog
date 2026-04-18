import { Glob } from "bun"
import tailwind from "bun-plugin-tailwind"

const glob = new Glob("**/*.html")

const htmlEntrypoints = Array.from(glob.scanSync({ cwd: "./src" })).map(
  (file) => `./src/${file}`
)

await Bun.build({
  entrypoints: htmlEntrypoints,
  outdir: "./build",
  naming: {
    entry: "[dir]/[name].[ext]",
    asset: "[dir]/[name].[ext]",
    chunk: "[dir]/[name].[ext]"
  },
  minify: true,
  plugins: [tailwind]
})

for (const file of ["rss.xml", "robots.txt", "sitemap.xml"]) {
  const src = Bun.file(`./src/${file}`)
  if (await src.exists()) {
    await Bun.write(`./build/${file}`, src)
  }
}
