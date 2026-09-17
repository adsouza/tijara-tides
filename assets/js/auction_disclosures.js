// Keep disclosure choices by group identity, including when auction groups are
// inserted, reordered, or temporarily disappear as their last listing expires.
export const AuctionDisclosures = {
  mounted() { this.expanded = new Map() },
  beforeUpdate() {
    for (const details of this.el.querySelectorAll(':scope > details[id]')) {
      this.expanded.set(details.id, details.open)
    }
  },
  updated() {
    for (const details of this.el.querySelectorAll(':scope > details[id]')) {
      if (this.expanded.has(details.id) && details.open !== this.expanded.get(details.id)) {
        details.open = this.expanded.get(details.id)
      }
    }
  },
}
