// The port catalogue is static. Preserve the native select/options while a
// market tick patches the page; rewriting options can close an open popup.
export const PortSelector = {
  mounted() {
    this.select = this.el.querySelector('select')
    this.syncSelection = (force = false) => {
      const selected = this.el.dataset.selected
      if (force || selected !== this.lastSelected) {
        if (this.select.value !== selected) this.select.value = selected
        this.lastSelected = selected
      }
    }
    this.syncSelection()
  },
  updated() { this.syncSelection() },
  reconnected() { this.syncSelection(true) },
}
