export const TradeQuantity = {
  mounted() {
    this.sync = event => {
      if (!event.target.matches('input[type="number"], input[type="range"]')) return
      const maximum = Number(this.el.dataset.max)
      const value = maximum < 1 ? 0 : Math.max(1, Math.min(maximum, Math.trunc(Number(event.target.value) || 0)))
      this.el.querySelectorAll('input[type="number"], input[type="range"]').forEach(input => { input.value = value })
    }
    this.el.addEventListener("input", this.sync)
  },
  updated() {
    this.el.querySelectorAll('input[type="number"], input[type="range"]').forEach(input => { input.value = this.el.dataset.quantity })
  },
  destroyed() { this.el.removeEventListener("input", this.sync) },
}
