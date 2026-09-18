// Keep user edits across live market patches, without freezing hidden request
// IDs or server-provided options. Context-specific form IDs isolate drafts.
export const ExchangeDraft = {
  mounted() {
    this.draft = new Map()
    if (this.handleEvent) this.handleEvent("draft-reset", ({id}) => {
      if (id !== this.el.id) return
      this.draft.clear()
      this.el.reset()
    })
    this.syncExpiry = () => {
      const checkbox = this.el.querySelector('[name="clear_expiry"]')
      const minutes = this.el.querySelector('[name="minutes"]')
      if (checkbox && minutes) minutes.disabled = checkbox.checked
    }
    this.remember = ({target}) => {
      if (!target.name || !target.matches('input:not([type="hidden"]), select')) return
      this.draft.set(target.name, target.type === 'checkbox' ? target.checked : target.value)
      this.syncExpiry()
    }
    this.el.addEventListener('input', this.remember)
    this.el.addEventListener('change', this.remember)
    this.syncExpiry()
  },
  updated() {
    for (const input of this.el.querySelectorAll('input:not([type="hidden"]), select')) {
      if (!this.draft.has(input.name)) continue
      const value = this.draft.get(input.name)
      if (input.tagName === 'SELECT' && !Array.from(input.options).some(option => option.value === value)) {
        this.draft.delete(input.name)
      } else if (input.type === 'checkbox') {
        input.checked = value
      } else {
        input.value = value
      }
    }
    this.syncExpiry()
  },
  destroyed() {
    this.el.removeEventListener('input', this.remember)
    this.el.removeEventListener('change', this.remember)
  },
}
