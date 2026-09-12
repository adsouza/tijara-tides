export const Locale = {
  mounted() { this.updated() },
  updated() {
    document.documentElement.lang = this.el.dataset.locale
    document.documentElement.dir = this.el.dataset.direction
    const title = document.querySelector("title")
    const brand = this.el.dataset.gameTitle
    if (title && brand) {
      const suffix = title.dataset.suffix || ""
      const current = title.textContent
      const page = suffix && current.endsWith(suffix) ? current.slice(0, -suffix.length) : current
      title.textContent = current === title.dataset.default ? brand : page + " · " + brand
      title.dataset.default = brand
      title.dataset.suffix = " · " + brand
    }
  },
}
