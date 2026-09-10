// Both menus start below the summary, even when its contents or the header wrap.
export const PopupAnchor = {
  mounted() {
    this.positionPopups = () => {
      const anchor = this.el.querySelector(".company-summary") || this.el.querySelector(".game-header")
      if (anchor) this.el.style.setProperty("--popup-top", `${anchor.getBoundingClientRect().bottom}px`)
    }
    this.observeAnchor = () => {
      this.observer.disconnect()
      this.el.querySelectorAll(".game-header, .company-summary").forEach(el => this.observer.observe(el))
      this.positionPopups()
    }
    this.observer = new ResizeObserver(this.positionPopups)
    window.addEventListener("resize", this.positionPopups)
    window.addEventListener("scroll", this.positionPopups, true)
    this.observeAnchor()
  },
  updated() { this.observeAnchor() },
  destroyed() {
    this.observer.disconnect()
    window.removeEventListener("resize", this.positionPopups)
    window.removeEventListener("scroll", this.positionPopups, true)
  },
}
