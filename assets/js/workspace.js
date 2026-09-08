// Native scroll snapping handles touch swipes; tabs also work with a keyboard.
export const Workspace = {
  mounted() {
    this.track = this.el.querySelector(".workspace-panels")
    this.buttons = [...this.el.querySelectorAll("[data-panel]")]
    this.activePanel = 1
    this.mapExpanded = false
    this.portrait = () => matchMedia("(orientation: portrait)").matches
    this.sizeMapLabels = () => {
      const svg = this.el.querySelector("#world-map")
      const matrix = svg?.getScreenCTM()
      if (!matrix || !matrix.a) return
      const unit = 1 / Math.abs(matrix.a)
      svg.querySelectorAll("[data-port-label]").forEach(label => {
        label.setAttribute("font-size", 12 * unit)
        label.setAttribute("stroke-width", 3 * unit)
        label.setAttribute("x", Number(label.dataset.labelX) + Number(label.dataset.labelDx) * unit)
        label.setAttribute("y", Number(label.dataset.labelY) + Number(label.dataset.labelDy) * unit)
      })
    }
    this.markPanel = () => {
      if (this.portrait()) this.mapExpanded = false
      this.el.dataset.mapExpanded = String(this.mapExpanded)
      this.el.querySelector("#map-expand")?.setAttribute("aria-expanded", String(this.mapExpanded))
      this.el.closest(".game-screen")?.querySelectorAll(".game-header, .company-summary, .company-menu, #ships-panel > .panel-content, #ships-panel > .panel-title").forEach(el => { el.inert = this.mapExpanded })
      this.buttons.forEach((button, index) => button.setAttribute("aria-current", String(index === this.activePanel)))
      this.el.querySelectorAll(".workspace-panel").forEach((panel, index) => {
        panel.inert = (this.mapExpanded && index !== 1) || (this.portrait() && index !== this.activePanel)
      })
      this.sizeMapLabels()
    }
    this.selectPanel = index => {
      this.activePanel = index
      this.markPanel()
      if (this.portrait()) this.track.scrollTo({left: index * this.track.clientWidth, behavior: "instant"})
    }
    this.onClick = event => {
      if (event.target.closest("[data-map-expand]")) {
        this.mapExpanded = !this.mapExpanded && !this.portrait()
        this.markPanel()
        return
      }
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
      if (event.key === "Escape" && this.mapExpanded) {
        event.preventDefault()
        this.mapExpanded = false
        this.markPanel()
        this.el.querySelector("#map-expand").focus()
        return
      }
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
