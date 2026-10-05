import {berthSample} from "./berth_motion"

export const ShipBerth = {
  mounted() {
    this.host = this.el.querySelector("[data-berth-canvas]")
    this.motion = matchMedia("(prefers-reduced-motion: reduce)")
    this.connected = true
    this.visible = false
    this.paused = false
    this.dead = false
    this.readState = () => {
      const d = this.el.dataset
      const next = {clock: Number(d.clock), complete: Number(d.complete), status: d.status,
        volume: d.volume == null || d.volume === "" ? null : Number(d.volume),
        cargoVolume: Number(d.cargoVolume || 0), capacity: Number(d.capacity || 1),
        queued: d.queued === "true", liquid: d.liquid === "true", laden: d.laden === "true"}
      // Legacy operations without metadata use the first observed world clock.
      // Ordinary ticks, pauses and visibility changes must not restart the batch.
      if (!this.state || next.status !== this.state.status || next.complete !== this.state.complete ||
          next.queued !== this.state.queued) {
        this.transferStart = next.clock
      }
      next.start = d.start == null || d.start === "" ? this.transferStart : Number(d.start)
      if (!this.state || Object.keys(next).some(key => next[key] !== this.state[key])) {
        this.state = next
        this.anchor = performance.now()
      }
    }
    this.stop = () => {
      cancelAnimationFrame(this.frame)
      this.frame = null
      this.host.dataset.animating = "false"
    }
    this.fail = () => {
      this.failed = true
      this.stop()
      this.scene?.canvas.removeEventListener("webglcontextlost", this.onContextLost)
      this.scene?.dispose()
      this.scene = null
      this.host.dataset.renderer = "static"
      this.host.querySelector("[data-berth-fallback]").style.display = ""
      this.el.querySelector("[data-berth-unavailable]").hidden = false
      this.el.querySelector("[data-berth-toggle]").hidden = true
    }
    this.draw = now => {
      this.frame = null
      if (this.dead || !this.scene) return
      const sample = berthSample(this.state, now - this.anchor)
      try {
        const pose = this.paused ? this.frozenPose : {
          seconds: this.motion.matches ? 0 : sample.seconds, progress: sample.progress,
          loadFraction: sample.loadFraction}
        this.lastPose = pose
        this.scene.draw({...sample, ...pose})
      } catch (_) { this.fail(); return }
      if (this.canAnimate() && sample.fresh) {
        this.host.dataset.animating = "true"
        this.frame = requestAnimationFrame(this.draw)
      } else this.host.dataset.animating = "false"
    }
    this.canAnimate = () => this.visible && this.connected && !document.hidden &&
      !this.paused && !this.motion.matches && this.host.clientWidth > 0 && this.host.clientHeight > 0
    this.refresh = () => {
      this.stop()
      if (this.dead || this.failed) return
      const toggle = this.el.querySelector("[data-berth-toggle]")
      toggle.hidden = !this.scene || this.motion.matches
      toggle.setAttribute("aria-pressed", String(this.paused))
      toggle.textContent = this.paused ? toggle.dataset.resumeLabel : toggle.dataset.pauseLabel
      if (this.visible && this.connected && !document.hidden && this.scene) {
        this.scene.resize(this.host.clientWidth, this.host.clientHeight)
        this.draw(performance.now())
      }
    }
    this.load = async () => {
      if (this.loading || this.scene || this.failed || this.dead) return
      this.loading = true
      try {
        const {createBerthScene} = await import(this.el.dataset.sceneSrc)
        if (this.dead) return
        this.scene = createBerthScene(this.host, this.state.liquid)
        this.scene.canvas.addEventListener("webglcontextlost", this.onContextLost)
        this.host.dataset.renderer = "webgl"
        this.host.querySelector("[data-berth-fallback]").style.display = "none"
        this.refresh()
      } catch (_) { if (!this.dead) this.fail() }
      finally { this.loading = false }
    }
    this.onContextLost = event => { event.preventDefault(); this.fail() }
    this.onToggle = event => {
      if (!event.target.closest("[data-berth-toggle]")) return
      this.frozenPose = this.lastPose || {seconds: 0, progress: 0}
      this.paused = !this.paused
      this.refresh()
    }
    this.readState()
    this.intersection = new IntersectionObserver(entries => {
      this.visible = entries.some(entry => entry.isIntersecting)
      if (this.visible) this.load()
      this.refresh()
    })
    this.intersection.observe(this.host)
    this.resize = new ResizeObserver(() => this.refresh())
    this.resize.observe(this.host)
    document.addEventListener("visibilitychange", this.refresh)
    this.motion.addEventListener("change", this.refresh)
    this.el.addEventListener("click", this.onToggle)
  },
  updated() { this.readState(); if (this.failed) this.fail(); else this.refresh() },
  disconnected() { this.connected = false; this.stop() },
  reconnected() { this.connected = true; this.readState(); this.refresh() },
  destroyed() {
    this.dead = true
    this.stop()
    this.intersection.disconnect()
    this.resize.disconnect()
    document.removeEventListener("visibilitychange", this.refresh)
    this.motion.removeEventListener("change", this.refresh)
    this.el.removeEventListener("click", this.onToggle)
    this.scene?.canvas.removeEventListener("webglcontextlost", this.onContextLost)
    this.scene?.dispose()
    this.scene = null
  },
}
