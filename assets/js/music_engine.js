// Streams each piece through an <audio> element routed into Web Audio, so the
// file downloads progressively while fades follow exact gain curves.

export const volumeGain = value => (Math.min(100, Math.max(0, Number(value) || 0)) / 100) ** 2

// Fade-out: from * cos(pi*p/2). Fade-in: from + (1 - from) * sin(pi*p/2).
export function envelopeAt(envelope, t) {
  if (envelope.kind === 'hold') return envelope.value
  const p = envelope.duration > 0 ? Math.min(1, Math.max(0, (t - envelope.start) / envelope.duration)) : 1
  return envelope.kind === 'in'
    ? envelope.from + (1 - envelope.from) * Math.sin(Math.PI * p / 2)
    : envelope.from * Math.cos(Math.PI * p / 2)
}

export function fadeCurve(envelope) {
  const samples = Math.max(2, Math.ceil(envelope.duration * 100) + 1)
  return Float32Array.from({length: samples}, (_, i) =>
    envelopeAt(envelope, envelope.start + envelope.duration * i / (samples - 1)))
}

export const trackUrl = (baseUrl, track) =>
  new URL(`${track.file}?v=${track.output_sha256.slice(0, 12)}`, baseUrl).href

// A curve may not overlap the value set just before it.
const LEAD = 0.01

export function createEngine({context, createAudio, baseUrl, timeoutMs = 10_000,
  setTimer = (fn, ms) => setTimeout(fn, ms), clearTimer = handle => clearTimeout(handle)}) {
  const master = context.createGain()
  master.gain.value = 0
  master.connect(context.destination)

  const timed = (promise, label) => new Promise((resolve, reject) => {
    const timer = setTimer(() => reject(new Error(`${label} timed out`)), timeoutMs)
    promise.then(value => { clearTimer(timer); resolve(value) }, error => { clearTimer(timer); reject(error) })
  })

  function createVoice(track) {
    const element = createAudio()
    element.preload = 'auto'
    const source = context.createMediaElementSource(element)
    const gain = context.createGain()
    gain.gain.value = 0
    source.connect(gain)
    gain.connect(master)
    let disposed = false
    const voice = {
      element,
      track,
      envelope: {kind: 'hold', value: 0},
      get position() { return element.currentTime },
      get duration() { return element.duration },
      get error() { return element.error },
      play: () => timed(Promise.resolve().then(() => element.play()), 'playback'),
      pause() { if (!disposed) element.pause() },
      gain: () => envelopeAt(voice.envelope, context.currentTime),
      fade(kind, duration) {
        const now = context.currentTime
        const from = envelopeAt(voice.envelope, now)
        voice.envelope = {kind, from, start: now + LEAD, duration}
        gain.gain.cancelScheduledValues(0)
        gain.gain.setValueAtTime(from, now)
        gain.gain.setValueCurveAtTime(fadeCurve(voice.envelope), now + LEAD, duration)
      },
      onProgress: fn => element.addEventListener('timeupdate', () => fn()),
      onEnded: fn => element.addEventListener('ended', () => fn()),
      onError: fn => element.addEventListener('error', () => {
        if (!disposed) fn(element.error ?? new Error('audio failed during playback'))
      }),
      dispose() {
        if (disposed) return
        disposed = true
        element.pause()
        element.removeAttribute('src')
        element.load()
        source.disconnect()
        gain.disconnect()
      },
    }
    return voice
  }

  // Resolves once the element can play from `offset` (seconds in the encoded file).
  function prepare(track, offset = 0) {
    const voice = createVoice(track)
    const {element} = voice
    const loaded = new Promise((resolve, reject) => {
      element.addEventListener('error', () => reject(element.error ?? new Error('audio failed to load')), {once: true})
      element.addEventListener('loadedmetadata', () => {
        element.addEventListener(offset > 0 ? 'seeked' : 'canplay', () => resolve(voice), {once: true})
        if (offset > 0) element.currentTime = offset
      }, {once: true})
    })
    element.src = trackUrl(baseUrl, track)
    element.load()
    return timed(loaded, 'loading').catch(error => { voice.dispose(); throw error })
  }

  function setVolume(value) {
    const now = context.currentTime
    const param = master.gain
    param.cancelScheduledValues(0)
    param.setValueAtTime(param.value, now)
    param.linearRampToValueAtTime(volumeGain(value), now + 0.05)
  }

  return {prepare, setVolume, unlock: () => context.resume()}
}
