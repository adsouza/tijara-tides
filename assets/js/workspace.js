// Native scroll snapping handles touch swipes; tabs also work with a keyboard.
export const Workspace = {
  mounted() {
    this.track = this.el.querySelector(".workspace-panels")
    this.buttons = [...this.el.querySelectorAll("[data-panel]")]
    this.activePanel = 1
    this.portrait = () => matchMedia("(orientation: portrait)").matches
    this.markPanel = () => {
      this.buttons.forEach((button, index) => button.setAttribute("aria-current", String(index === this.activePanel)))
      this.el.querySelectorAll(".workspace-panel").forEach((panel, index) => {
        panel.inert = this.portrait() && index !== this.activePanel
      })
    }
    this.selectPanel = index => {
      this.activePanel = index
      this.markPanel()
      if (this.portrait()) this.track.scrollTo({left: index * this.track.clientWidth, behavior: "instant"})
    }
    this.onClick = event => {
      const button = event.target.closest("[data-panel]")
      if (button) this.selectPanel(Number(button.dataset.panel))
      const action = event.target.closest("[phx-click]")?.getAttribute("phx-click")
      if (action === "port") this.selectPanel(0)
      if (action === "market-good") {
        this.selectPanel(2)
        this.el.querySelector("#cargo-panel .panel-content").scrollTop = 0
      }
      if (action === "ship" || action === "inspect-ship") this.selectPanel(1)
    }
    this.onKey = event => {
      if (!event.target.matches("[data-panel]")) return
      const index = Number(event.target.dataset.panel)
      const next = {ArrowLeft: Math.max(0, index - 1), ArrowRight: Math.min(2, index + 1), Home: 0, End: 2}[event.key]
      if (next === undefined) return
      event.preventDefault()
      this.selectPanel(next)
      this.buttons[next].focus()
    }
    this.onScroll = () => {
      if (this.portrait() && this.track.clientWidth) {
        this.activePanel = Math.round(this.track.scrollLeft / this.track.clientWidth)
        this.markPanel()
      }
    }
    this.el.addEventListener("click", this.onClick)
    this.el.addEventListener("keydown", this.onKey)
    this.track.addEventListener("scroll", this.onScroll, {passive: true})
    this.resizeObserver = new ResizeObserver(() => this.selectPanel(this.activePanel))
    this.resizeObserver.observe(this.track)
    this.handleEvent("workspace-panel", ({panel}) => {
      this.selectPanel(panel)
      this.el.querySelectorAll(".panel-content")[panel].scrollTop = 0
    })
    this.selectPanel(1)
  },
  updated() { this.markPanel() },
  destroyed() {
    this.resizeObserver.disconnect()
    this.el.removeEventListener("click", this.onClick)
    this.el.removeEventListener("keydown", this.onKey)
    this.track.removeEventListener("scroll", this.onScroll)
  },
}
