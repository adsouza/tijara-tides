// The last slider stop is the exact credit ceiling, even between $10,000 steps.
export const LoanAmount = {
  mounted() {
    this.amount = Number(this.el.querySelector('input[type="number"]').value)
    this.sync = event => {
      if (event.target.type === "range") this.amount = Number(event.target.value) * 10000
      else if (event.target.type === "number") this.amount = Number(event.target.value)
      else return
      this.renderAmount()
    }
    this.renderAmount = () => {
      const maximum = Number(this.el.dataset.max)
      this.amount = maximum < 1 ? 0 : Math.max(1, Math.min(maximum, Math.trunc(this.amount) || 0))
      this.el.querySelector('input[type="number"]').value = this.amount
      const slider = this.el.querySelector('input[type="range"]')
      slider.value = this.amount === maximum ? Math.ceil(maximum / 10000) : Math.round(this.amount / 10000)
      slider.setAttribute("aria-valuetext", `$${this.amount.toLocaleString("en-US")}`)
    }
    this.el.addEventListener("input", this.sync)
    this.renderAmount()
  },
  updated() { this.renderAmount() },
  destroyed() { this.el.removeEventListener("input", this.sync) },
}
