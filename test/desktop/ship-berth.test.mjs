import {test} from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
const uri = source => `data:text/javascript;base64,${Buffer.from(source).toString('base64')}`
const motion = uri(readFileSync(new URL('../../assets/js/berth_motion.js', import.meta.url), 'utf8'))
const source = readFileSync(new URL('../../assets/js/ship_berth.js', import.meta.url), 'utf8')
const {ShipBerth} = await import(uri(source.replace('"./berth_motion"', JSON.stringify(motion))))
const flush = () => new Promise(resolve => setImmediate(resolve))

function harness({fail = false} = {}) {
  let now = 0
  const frames = new Map()
  const listeners = new Map()
  const mediaListeners = new Map()
  const clicks = new Map()
  let intersect, resize
  let observersStopped = 0
  globalThis.performance = {now: () => now}
  globalThis.document = {hidden: false, addEventListener: (k, v) => listeners.set(k, v),
    removeEventListener: k => listeners.delete(k)}
  const media = {matches: false, addEventListener: (k, v) => mediaListeners.set(k, v),
    removeEventListener: k => mediaListeners.delete(k)}
  globalThis.matchMedia = () => media
  globalThis.requestAnimationFrame = callback => { const id = Symbol(); frames.set(id, callback); return id }
  globalThis.cancelAnimationFrame = id => frames.delete(id)
  globalThis.IntersectionObserver = class {
    constructor(callback) { intersect = callback }
    observe() {}
    disconnect() { observersStopped++ }
  }
  globalThis.ResizeObserver = class {
    constructor(callback) { resize = callback }
    observe() {}
    disconnect() { observersStopped++ }
  }
  const fallback = {style: {}}
  const toggle = {hidden: true, dataset: {pauseLabel: 'Pause', resumeLabel: 'Resume'},
    setAttribute(k, v) { this[k] = v }}
  const unavailable = {hidden: true}
  const host = {dataset: {}, clientWidth: 500, clientHeight: 256, querySelector: () => fallback}
  const scenes = []
  globalThis.berthTestCreate = () => {
    if (fail) throw new Error('GPU unavailable')
    const events = new Map()
    const scene = {samples: [], sizes: [], disposed: 0,
      canvas: {addEventListener: (k, v) => events.set(k, v), removeEventListener: k => events.delete(k)},
      draw(sample) { this.samples.push(sample) }, resize(...size) { this.sizes.push(size) },
      dispose() { this.disposed++ }, events}
    scenes.push(scene)
    return scene
  }
  const el = {dataset: {sceneSrc: uri('export const createBerthScene = () => globalThis.berthTestCreate()'),
    clock: '1000', start: '0', complete: '60000', status: 'loading', queued: 'false', liquid: 'false',
    volume: '450000', capacity: '900000', cargoVolume: '600000', laden: 'true'},
    querySelector: selector => selector === '[data-berth-canvas]' ? host :
      selector === '[data-berth-toggle]' ? toggle : unavailable,
    addEventListener: (k, v) => clicks.set(k, v), removeEventListener: k => clicks.delete(k)}
  const hook = {...ShipBerth, el}
  hook.mounted()
  return {hook, host, scenes, toggle, unavailable, fallback, media, listeners, frames,
    visible(value) { intersect([{isIntersecting: value}]) },
    tick(ms) { now = ms; const callbacks = [...frames.values()]; frames.clear(); callbacks.forEach(cb => cb(now)) },
    togglePause() { clicks.get('click')({target: {closest: () => toggle}}) },
    reduce(value) { media.matches = value; mediaListeners.get('change')() },
    resize, get observersStopped() { return observersStopped },
    get listenerCount() { return listeners.size + clicks.size + mediaListeners.size }}
}

test('one scene survives patches, preserves a pause, and reverses committed handling', async () => {
  const h = harness()
  assert.equal(h.scenes.length, 0, 'invisible scene must not allocate GPU resources')
  h.visible(true)
  await flush()
  assert.equal(h.host.dataset.renderer, 'webgl')
  assert.equal(h.scenes.length, 1)
  h.tick(700)
  const before = h.scenes[0].samples.at(-1).seconds
  const beforeProgress = h.scenes[0].samples.at(-1).progress
  const beforeLoad = h.scenes[0].samples.at(-1).loadFraction
  h.togglePause()
  assert.equal(h.toggle['aria-pressed'], 'true')
  assert.equal(h.scenes[0].samples.at(-1).seconds, before)
  assert.equal(h.scenes[0].samples.at(-1).progress, beforeProgress)
  h.hook.el.dataset.clock = '2000'
  h.hook.el.dataset.status = 'unloading'
  h.hook.updated()
  assert.equal(h.scenes.length, 1)
  assert.equal(h.scenes[0].samples.at(-1).unloading, true)
  assert.equal(h.scenes[0].samples.at(-1).seconds, before)
  assert.equal(h.frames.size, 0)
  assert.equal(h.scenes[0].samples.at(-1).loadFraction, beforeLoad)
  h.togglePause()
  h.hook.el.dataset.queued = 'true'
  h.hook.updated()
  assert.equal(h.scenes[0].samples.at(-1).handling, false)
  h.hook.destroyed()
  assert.equal(h.scenes[0].disposed, 1)
  assert.equal(h.listenerCount, 0)
  assert.equal(h.observersStopped, 2)
  assert.equal(h.frames.size, 0)
})

test('tick patches and reopening midway preserve the committed handling timeline and existing cargo', async () => {
  const h = harness()
  h.visible(true)
  await flush()
  const first = h.scenes[0].samples.at(-1)
  assert.equal(first.count, 6)
  assert.equal(first.baseCount, 2)
  h.hook.el.dataset.clock = '30000'
  h.hook.updated()
  assert.equal(h.scenes[0].samples.at(-1).progress, 0.5)
  h.visible(false)
  h.hook.el.dataset.clock = '45000'
  h.hook.updated()
  h.visible(true)
  assert.equal(h.scenes[0].samples.at(-1).progress, 0.75)
  h.reduce(true)
  assert.equal(h.scenes[0].samples.at(-1).progress, 0.75)
  h.reduce(false)
  h.hook.el.dataset.clock = '60000'
  h.hook.updated()
  assert.equal(h.scenes[0].samples.at(-1).progress, 1)
  assert.equal(h.scenes[0].samples.at(-1).handling, false)
  h.hook.destroyed()

  const reopened = harness()
  reopened.hook.el.dataset.clock = '30000'
  reopened.hook.updated()
  reopened.visible(true)
  await flush()
  assert.equal(reopened.scenes[0].samples.at(-1).progress, 0.5)
  reopened.hook.destroyed()
})

test('legacy operations use the first observed clock, keeping that origin across ticks', async () => {
  const h = harness()
  delete h.hook.el.dataset.start
  delete h.hook.el.dataset.volume
  h.hook.updated()
  h.visible(true)
  await flush()
  assert.equal(h.scenes[0].samples.at(-1).progress, 0)
  assert.equal(h.scenes[0].samples.at(-1).count, 1)
  h.hook.el.dataset.clock = '30500'
  h.hook.updated()
  assert.equal(h.scenes[0].samples.at(-1).progress, 0.5)
  h.hook.destroyed()
})

test('hidden, disconnected, reduced-motion and stale views suspend rendering', async () => {
  const h = harness()
  h.visible(true)
  await flush()
  assert.equal(h.frames.size, 1)
  h.visible(false)
  const count = h.scenes[0].samples.length
  h.tick(100)
  assert.equal(h.scenes[0].samples.length, count)
  h.visible(true)
  h.hook.disconnected()
  h.tick(200)
  assert.equal(h.frames.size, 0)
  h.hook.reconnected()
  assert.equal(h.frames.size, 1)
  document.hidden = true
  h.listeners.get('visibilitychange')()
  assert.equal(h.frames.size, 0)
  document.hidden = false
  h.listeners.get('visibilitychange')()
  h.reduce(true)
  assert.equal(h.frames.size, 0)
  assert.equal(h.toggle.hidden, true)
  assert.equal(h.scenes[0].samples.at(-1).seconds, 0)
  h.reduce(false)
  assert.equal(h.frames.size, 1)
  h.tick(10_001)
  assert.equal(h.frames.size, 0)
  assert.equal(h.scenes[0].samples.at(-1).handling, false)
  h.hook.updated() // An unrelated patch cannot restart a stalled world clock.
  assert.equal(h.frames.size, 0)
  h.hook.el.dataset.clock = '12000'
  h.hook.updated()
  assert.equal(h.frames.size, 1)
  h.hook.destroyed()
})

test('GPU failure and context loss retain a usable static view across patches', async () => {
  for (const fail of [true, false]) {
    const h = harness({fail})
    h.visible(true)
    await flush()
    if (!fail) h.scenes[0].events.get('webglcontextlost')({preventDefault() {}})
    assert.equal(h.host.dataset.renderer, 'static')
    assert.equal(h.fallback.style.display, '')
    assert.equal(h.unavailable.hidden, false)
    assert.equal(h.toggle.hidden, true)
    h.unavailable.hidden = true // A server patch restores the original hidden attribute.
    h.hook.updated()
    assert.equal(h.unavailable.hidden, false)
    if (!fail) assert.equal(h.scenes[0].disposed, 1)
    h.hook.destroyed()
  }
})

test('leaving during the lazy import never creates an orphan renderer', async () => {
  const h = harness()
  h.visible(true)
  h.hook.destroyed()
  await flush()
  assert.equal(h.scenes.length, 0)
  assert.equal(h.listenerCount, 0)
})
