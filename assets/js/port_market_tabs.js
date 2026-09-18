// Both sides stay mounted, so switching never waits on a server reply and draft
// quantities survive. Server events still remember the choice for reconnects.
export const PortMarketTabs = {
  mounted() {
    this.side = this.el.dataset.side
    this.onClick = event => {
      const button = event.target.closest('[data-market-side]')
      if (!button || !this.el.contains(button)) return
      this.side = button.dataset.marketSide
      this.paint()
    }
    this.handleEvent('port-market-select', ({side}) => {
      if (side !== 'buy' && side !== 'sell') return
      this.side = side
      this.paint()
    })
    this.el.addEventListener('click', this.onClick)
    this.paint()
  },
  updated() { this.paint() },
  destroyed() { this.el.removeEventListener('click', this.onClick) },
  paint() {
    for (const panel of this.el.querySelectorAll('[data-market-panel]')) {
      panel.hidden = panel.dataset.marketPanel !== this.side
    }
    for (const button of this.el.querySelectorAll('[data-market-side]')) {
      const active = button.dataset.marketSide === this.side
      button.setAttribute('aria-pressed', String(active))
      button.classList.toggle('bg-teal-800', active)
      button.classList.toggle('text-teal-100', active)
      button.classList.toggle('bg-slate-800', !active)
      button.classList.toggle('text-slate-400', !active)
    }
  },
}
