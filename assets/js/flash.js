// Live updates must not restart the countdown for an unchanged notification.
export const Flash = {
  mounted() {
    this.message = this.el.dataset.message
    this.scheduleDismissal()
  },
  updated() {
    if (this.message !== this.el.dataset.message) {
      this.message = this.el.dataset.message
      this.scheduleDismissal()
    }
  },
  scheduleDismissal() {
    clearTimeout(this.dismissTimer)
    this.dismissTimer = setTimeout(() => {
      this.pushEvent("lv:clear-flash", {key: this.el.dataset.kind})
    }, 10000)
  },
  destroyed() {
    clearTimeout(this.dismissTimer)
  },
}
