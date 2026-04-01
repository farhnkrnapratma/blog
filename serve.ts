import NotFound from "./src/404.html"
import Home from "./src/index.html"

const server = Bun.serve({
  port: 5000,
  routes: {
    "/": Home,
    "/404": NotFound
  },
  fetch() {
    return Response.redirect("/404")
  }
})

console.log(`Server running at http://localhost:${server.port}`)
