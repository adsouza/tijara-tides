// Owns every change in what is audible: selection transitions, automatic
// crossfades between pieces, silent waits, disabling, hiding and resuming.
// Timing follows DESIGN.md's Background music section. Every asynchronous
// result is checked against the current generation and pending piece, so a
// superseded load or play never becomes audible or earns a credit.

export const TIMING = {settle: 3, fadeOut: 5, fadeIn: 2, silence: 1, crossfade: 2, prepareAhead: 10, quickFade: 1}
const MAX_FAILURES = 3

export function createDirector({manifest, engine, policy, now, setTimer, clearTimer,
  random = Math.random, onStart = () => {}}) {
  let desired = {context: null, id: null}
  let enabled = true, foreground = true, unlocked = false, destroyed = false
  let generation = 0
  let mode = 'idle'            // idle: may start at once; playing; stopped after failures
  let current = null           // {voice, id, slug}
  const voices = new Set()     // voices whose gain may be above zero
  let transition = null        // {outgoingEndsAt, deadline}
  let pending = null           // the one incoming piece
  let paused = null            // {voice, id, slug} kept while away
  let failures = 0
  let failureLocked = false    // cleared only by a musical identity change
  let wake = null

  const remaining = voice => {
    const left = voice.duration - voice.position
    return Number.isFinite(left) ? left : Infinity
  }

  function retire(voice, seconds, keep = false) {
    voice.role = 'outgoing'
    voice.fade('out', seconds)
    const token = voice.retiring = {}
    setTimer(() => {
      if (voice.retiring !== token) return
      voices.delete(voice)
      voice.pause()
      if (!keep) voice.dispose()
    }, seconds * 1000)
  }

  function choose(context, previous, automatic) {
    const slug = policy.choosePiece(manifest, context, previous, random)
    if (!slug) return null
    const track = manifest.tracks[slug]
    return {id: policy.identity(manifest, context), context, slug, track, automatic,
      offset: automatic ? 0 : track.entry_s ?? 0, voice: null, ready: false, starting: false, notBefore: now()}
  }

  function discardPending() {
    if (pending?.voice && !pending.starting) pending.voice.dispose()
    pending = null
  }

  function prepare(next) {
    if (destroyed || failureLocked) { next?.voice?.dispose(); return }
    pending = next
    if (!next) return
    if (next.ready) { pump(); return }
    engine.prepare(next.track, next.offset).then(voice => {
      if (pending !== next || destroyed) { voice.dispose(); return }
      next.voice = voice
      voice.onError(() => mediaFailed(voice))
      // An error can arrive after readiness, before this promise callback runs.
      if (voice.error) { mediaFailed(voice); return }
      next.ready = true
      pump()
    }, () => { if (pending === next) fail(next) })
  }

  function fail(failed) {
    failed.voice?.dispose()
    voices.delete(failed.voice)
    if (current?.voice === failed.voice) current = null
    if (pending === failed) pending = null
    failures += 1
    if (failures >= MAX_FAILURES) {
      failureLocked = true
      silence(TIMING.quickFade, false)
      mode = 'stopped'
      return
    }
    // A failed playing piece may already have a healthy successor loading.
    if (pending) { pump(); return }
    const next = choose(desired.context, failed.slug, failed.automatic)
    if (next) next.notBefore = failed.notBefore
    prepare(next)
  }

  function mediaFailed(voice) {
    if (destroyed) return
    if (pending?.voice === voice) { fail(pending); return }
    if (current?.voice === voice) {
      fail({...current, automatic: true, notBefore: now()})
      return
    }
    // An outgoing or paused voice cannot replace a newer selection or resume.
    if (paused?.voice === voice) paused = null
    voices.delete(voice)
    voice.dispose()
  }

  function pump() {
    if (wake) { clearTimer(wake); wake = null }
    if (destroyed || failureLocked || !enabled || !foreground || !unlocked) return
    if (!pending?.ready || pending.starting) return
    const t = now()
    const due = transition ? transition.deadline
      : pending.automatic && current ? t + Math.max(0, remaining(current.voice) - TIMING.crossfade)
      : pending.notBefore
    if (due > t) { wake = setTimer(() => { wake = null; pump() }, (due - t) * 1000); return }
    start(pending)
  }

  function start(next) {
    next.starting = true
    const voice = next.voice
    const gen = generation
    voice.play().then(() => {
      if (gen !== generation || pending !== next || destroyed) { voice.pause(); voice.dispose(); return }
      pending = null
      transition = null
      failures = 0
      mode = 'playing'
      if (next.automatic && current && current.voice !== voice) retire(current.voice, TIMING.crossfade)
      voice.retiring = null
      voice.role = 'current'
      voices.add(voice)
      voice.fade('in', TIMING.fadeIn)
      current = next
      watch(voice)
      onStart(next.track, next.slug)
    }, () => {
      // A superseded rejection is not a failure, but its element must still go.
      if (gen === generation && pending === next) fail(next)
      else { voice.pause(); voice.dispose() }
    })
  }

  function watch(voice) {
    if (voice.watched) return
    voice.watched = true
    voice.onProgress(() => {
      if (current?.voice !== voice || transition || failureLocked || !enabled || !foreground) return
      if (!pending && remaining(voice) <= TIMING.prepareAhead) prepare(choose(desired.context, current.slug, true))
      pump()
    })
    voice.onEnded(() => {
      voices.delete(voice)
      voice.dispose()
      // A port piece that ends during the hide fade has nothing left to resume.
      if (paused?.voice === voice) paused = null
      if (current?.voice === voice) { current = null; pump() }
    })
  }

  function select() {
    const t = now()
    generation += 1
    failures = 0
    discardPending()
    const incoming = [...voices].some(voice => voice.role !== 'outgoing')
    if (incoming) {
      for (const voice of [...voices]) retire(voice, TIMING.fadeOut)
      transition = {outgoingEndsAt: t + TIMING.fadeOut, deadline: t + TIMING.settle}
    } else if (transition && t < transition.outgoingEndsAt) {
      transition.deadline = transition.outgoingEndsAt + TIMING.silence
    } else if (transition || mode !== 'idle') {
      transition = {outgoingEndsAt: transition?.outgoingEndsAt ?? t, deadline: t + TIMING.settle}
    }
    current = null
    if (mode === 'stopped') mode = 'playing'
    prepare(desired.id ? choose(desired.context, null, false) : null)
  }

  // Keep the current port piece even if an outgoing voice still overlaps it.
  function silence(seconds, keepPort) {
    generation += 1
    if (wake) { clearTimer(wake); wake = null }
    discardPending()
    transition = null
    const kept = keepPort && !failureLocked && current?.id?.startsWith('port:') ? current : null
    for (const voice of [...voices]) retire(voice, seconds, voice === kept?.voice)
    current = null
    mode = 'idle'
    if (paused && paused.voice !== kept?.voice) paused.voice.dispose()
    paused = kept
  }

  function begin() {
    if (destroyed || failureLocked || !enabled || !foreground || !unlocked || !desired.id || pending) return
    generation += 1
    if (paused && paused.id === desired.id) {
      const {voice, id, slug} = paused
      paused = null
      prepare({id, context: desired.context, slug, track: voice.track, automatic: false, offset: 0,
        voice, ready: true, starting: false, notBefore: now()})
      return
    }
    paused?.voice.dispose()
    paused = null
    prepare(choose(desired.context, null, false))
  }

  return {
    setContext(context) {
      const id = policy.identity(manifest, context)
      const changed = id !== desired.id
      desired = {context, id}
      if (changed) { failureLocked = false; failures = 0 }
      if (!changed || destroyed || !enabled || !foreground || !unlocked) return
      if (mode === 'idle' && voices.size === 0 && !transition) { discardPending(); begin(); return }
      select()
    },
    setEnabled(on) {
      if (on === enabled || destroyed) return
      enabled = on
      if (on) { begin(); return }
      silence(TIMING.quickFade, false)
      paused?.voice.dispose()
      paused = null
    },
    setForeground(visible) {
      if (visible === foreground || destroyed) return
      foreground = visible
      if (visible) begin()
      else silence(TIMING.quickFade, true)
    },
    unlock() {
      unlocked = true
      if (mode === 'idle' && !pending && voices.size === 0) begin()
    },
    destroy() {
      destroyed = true
      generation += 1
      if (wake) clearTimer(wake)
      discardPending()
      for (const voice of voices) voice.dispose()
      voices.clear()
      paused?.voice.dispose()
      paused = null
    },
  }
}
