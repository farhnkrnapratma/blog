window.addEventListener("scroll", (): void => {
  const progressBar = document.getElementById(
    "scroll-progress"
  ) as HTMLElement | null

  if (progressBar) {
    const winScroll: number =
      document.body.scrollTop || document.documentElement.scrollTop
    const height: number =
      document.documentElement.scrollHeight -
      document.documentElement.clientHeight

    if (height > 0) {
      const scrolled: number = (winScroll / height) * 100
      progressBar.style.width = `${scrolled}%`
    }
  }
})

const codeBlocks = document.querySelectorAll<HTMLPreElement>("pre")

codeBlocks.forEach((pre: HTMLPreElement): void => {
  const btn = document.createElement("button") as HTMLButtonElement
  btn.className = "copy-btn"

  const copyIcon: string =
    '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path></svg>'
  const checkIcon: string =
    '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>'

  btn.innerHTML = copyIcon

  btn.onclick = async (): Promise<void> => {
    const codeElement = pre.querySelector("code")
    if (!codeElement) return

    try {
      await navigator.clipboard.writeText(codeElement.innerText)
      btn.innerHTML = checkIcon
      setTimeout((): void => {
        btn.innerHTML = copyIcon
      }, 5000)
    } catch (err) {
      console.error("Failed to copy text: ", err)
    }
  }

  pre.appendChild(btn)
})
