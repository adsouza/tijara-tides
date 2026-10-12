import {readContext, identity, choosePiece} from "./music_policy"
import {createEngine} from "./music_engine"
import {createDirector} from "./music_transitions"

const ENABLED_KEY = 'tijara.music.enabled'
const VOLUME_KEY = 'tijara.music.volume'
const CREDIT_MS = 8000
export const DEFAULTS = Object.freeze({enabled: true, volume: 30})

const storage = () => { try { return globalThis.localStorage } catch { return null } }

export function readSettings(store) {
  const settings = {...DEFAULTS}
  try {
    const enabled = store?.getItem(ENABLED_KEY)
    if (enabled === 'true' || enabled === 'false') settings.enabled = enabled === 'true'
    const volume = Number(store?.getItem(VOLUME_KEY) ?? NaN)
    if (Number.isInteger(volume) && volume >= 0 && volume <= 100) settings.volume = volume
  } catch { /* storage unavailable: defaults apply for this visit */ }
  return settings
}

export function saveSettings(store, {enabled, volume}) {
  try {
    store?.setItem(ENABLED_KEY, String(enabled))
    store?.setItem(VOLUME_KEY, String(volume))
  } catch { /* storage unavailable: settings last for this visit */ }
}

export const creditText = (template, track) =>
  template.replace('%{title}', () => track.title).replace('%{artists}', () => track.artists.join(', '))

const supported = () => typeof globalThis.AudioContext === 'function' && typeof globalThis.Audio === 'function' &&
  new Audio().canPlayType('audio/ogg; codecs=opus') !== ''

const isForeground = () => !document.hidden && (document.hasFocus?.() ?? true)

export const Music = {
  async mounted() {
    this.controls = this.el.querySelector('#music-controls')
    this.toggle = this.el.querySelector('#music-toggle')
    this.volume = this.el.querySelector('#music-volume')
    this.credit = this.el.querySelector('#music-credit')
    if (this.el.dataset.music !== 'available' || !supported()) { this.controls.hidden = true; return }
    this.settings = readSettings(storage())
    this.started = []
    this.render()
    // Listeners are registered before the manifest await so a click, key press,
    // toggle or slider change made while it loads is neither lost nor deferred.
    // Every handler tolerates the engine and director not existing yet; both are
    // built from the current settings once the manifest arrives.
    this.onToggle = () => {
      this.settings.enabled = !this.settings.enabled
      saveSettings(storage(), this.settings)
      this.render()
      this.director?.setEnabled(this.settings.enabled)
    }
    this.onVolume = () => {
      this.settings.volume = Number(this.volume.value)
      saveSettings(storage(), this.settings)
      this.engine?.setVolume(this.settings.volume)
    }
    this.onFocus = () => this.director?.setForeground(isForeground())
    this.onGesture = () => {
      document.removeEventListener('pointerdown', this.onGesture, true)
      document.removeEventListener('keydown', this.onGesture, true)
      this.gestured = true
      this.unlockAudio()
    }
    this.toggle.addEventListener('click', this.onToggle)
    this.volume.addEventListener('input', this.onVolume)
    document.addEventListener('visibilitychange', this.onFocus)
    window.addEventListener('focus', this.onFocus)
    window.addEventListener('blur', this.onFocus)
    document.addEventListener('pointerdown', this.onGesture, true)
    document.addEventListener('keydown', this.onGesture, true)
    let manifest
    try {
      const response = await fetch(this.el.dataset.manifest)
      if (!response.ok) throw new Error(`manifest HTTP ${response.status}`)
      manifest = await response.json()
    } catch (error) {
      console.warn('Background music manifest unavailable:', error)
      this.controls.hidden = true
      return
    }
    if (this.gone) return
    this.context = new AudioContext()
    const baseUrl = new URL('.', new URL(this.el.dataset.manifest, location.href)).href
    this.engine = createEngine({context: this.context, createAudio: () => new Audio(), baseUrl})
    this.engine.setVolume(this.settings.volume)
    this.director = createDirector({manifest, engine: this.engine, policy: {identity, choosePiece},
      now: () => performance.now() / 1000,
      setTimer: (fn, ms) => setTimeout(fn, ms), clearTimer: handle => clearTimeout(handle),
      onStart: (track, slug) => this.showCredit(track, slug)})
    this.director.setEnabled(this.settings.enabled)
    this.director.setForeground(isForeground())
    this.director.setContext(readContext(this.el.dataset))
    if (this.gestured) this.unlockAudio()
  },
  unlockAudio() {
    if (this.gone || !this.engine) return
    this.engine.unlock().then(() => { if (!this.gone) this.director?.unlock() },
      error => console.warn('Audio unlock failed:', error))
  },
  updated() { this.director?.setContext(readContext(this.el.dataset)) },
  destroyed() {
    this.gone = true
    this.toggle?.removeEventListener('click', this.onToggle)
    this.volume?.removeEventListener('input', this.onVolume)
    document.removeEventListener('visibilitychange', this.onFocus)
    window.removeEventListener('focus', this.onFocus)
    window.removeEventListener('blur', this.onFocus)
    document.removeEventListener('pointerdown', this.onGesture, true)
    document.removeEventListener('keydown', this.onGesture, true)
    clearTimeout(this.creditTimer)
    this.director?.destroy()
    this.context?.close()
  },
  render() {
    const {enabled, volume} = this.settings
    this.toggle.setAttribute('aria-pressed', enabled)
    this.toggle.setAttribute('aria-label', enabled ? this.el.dataset.labelOff : this.el.dataset.labelOn)
    this.toggle.textContent = enabled ? '🔊' : '🔇'
    this.volume.value = String(volume)
  },
  showCredit(track, slug) {
    this.credit.textContent = creditText(this.el.dataset.nowPlaying, track)
    this.credit.href = track.source_url
    this.credit.hidden = false
    this.started.push(slug)
    this.credit.dataset.started = this.started.join(' ')
    clearTimeout(this.creditTimer)
    this.creditTimer = setTimeout(() => { this.credit.hidden = true }, CREDIT_MS)
  },
}
