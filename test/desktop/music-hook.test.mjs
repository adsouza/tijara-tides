import {test, afterEach} from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
const uri = source => `data:text/javascript;base64,${Buffer.from(source).toString('base64')}`
const read = name => readFileSync(new URL(`../../assets/js/${name}.js`, import.meta.url), 'utf8')
const hookSource = read('music')
  .replace('"./music_policy"', JSON.stringify(uri(read('music_policy'))))
  .replace('"./music_engine"', JSON.stringify(uri(read('music_engine'))))
  .replace('"./music_transitions"', JSON.stringify(uri(read('music_transitions'))))
const {Music, readSettings, saveSettings, creditText, DEFAULTS} = await import(uri(hookSource))
const flush = () => new Promise(resolve => setImmediate(resolve))

function storage(initial = {}) {
  const values = {...initial}
  return {values, getItem: key => values[key] ?? null, setItem: (key, value) => { values[key] = value }}
}

test('first launch is enabled at 30; saved settings persist; bad storage is tolerated', () => {
  assert.deepEqual(readSettings(storage()), {enabled: true, volume: 30})
  assert.deepEqual(DEFAULTS, {enabled: true, volume: 30})
  assert.deepEqual(readSettings(storage({'tijara.music.enabled': 'false', 'tijara.music.volume': '72'})),
    {enabled: false, volume: 72})
  assert.deepEqual(readSettings(storage({'tijara.music.volume': '999'})), {enabled: true, volume: 30})
  const throwing = {getItem() { throw new Error('denied') }, setItem() { throw new Error('denied') }}
  assert.deepEqual(readSettings(throwing), DEFAULTS)
  saveSettings(throwing, {enabled: false, volume: 10})
  const s = storage()
  saveSettings(s, {enabled: false, volume: 10})
  assert.deepEqual(s.values, {'tijara.music.enabled': 'false', 'tijara.music.volume': '10'})
})

test('credit text fills named placeholders literally', () => {
  assert.equal(creditText('Now playing: %{title} by %{artists}', {title: 'A $& B', artists: ['X', 'Y']}),
    'Now playing: A $& B by X, Y')
})

const restores = []
afterEach(() => { while (restores.length) restores.pop()() })

function element(id) {
  const listeners = {}
  return {id, hidden: false, textContent: '', dataset: {}, attributes: {}, value: '30', href: '', listeners,
    setAttribute(name, value) { this.attributes[name] = String(value) },
    addEventListener(type, fn) { listeners[type] = fn }, removeEventListener(type) { delete listeners[type] },
    fire(type) { listeners[type]?.({}) }}
}

// A target whose listeners can be inspected and fired, keyed by type and capture flag.
function eventTarget(extra = {}) {
  const listeners = []
  return {...extra, listeners,
    addEventListener(type, fn, capture = false) { listeners.push({type, fn, capture: capture === true}) },
    removeEventListener(type, fn, capture = false) {
      const at = listeners.findIndex(l => l.type === type && l.fn === fn && l.capture === (capture === true))
      if (at >= 0) listeners.splice(at, 1)
    },
    fire(type) { for (const l of [...listeners]) if (l.type === type) l.fn({}) }}
}

function mountHook({music = 'available', fetchResult, deferFetch = false} = {}) {
  const nodes = Object.fromEntries(['music-controls', 'music-toggle', 'music-volume', 'music-credit'].map(id => [id, element(id)]))
  const el = {dataset: {music, manifest: '/audio/fixtures/music.json', context: 'port', port: 'Tangier',
    nowPlaying: 'Now playing: %{title} by %{artists}'},
    querySelector: selector => nodes[selector.slice(1)]}
  const local = storage()
  const timeouts = []
  const contexts = []
  const fetches = []
  let resolveFetch
  const deferred = deferFetch ? new Promise(resolve => { resolveFetch = resolve }) : null
  const saved = {setTimeout: globalThis.setTimeout, clearTimeout: globalThis.clearTimeout}
  restores.push(() => Object.assign(globalThis, saved))
  Object.assign(globalThis, {
    localStorage: local,
    location: {href: 'https://h.test/play'},
    performance: {now: () => 0},
    setTimeout: (fn, ms) => { timeouts.push({fn, ms}); return timeouts.length },
    clearTimeout: () => {},
    document: eventTarget({hidden: false, hasFocus: () => true}),
    window: eventTarget(),
    Audio: class { canPlayType() { return 'probably' } },
    AudioContext: class {
      constructor() { this.currentTime = 0; this.destination = {}; this.resumes = 0; contexts.push(this) }
      createGain() { return {gain: {value: 0, cancelScheduledValues() {}, setValueAtTime() {}, linearRampToValueAtTime() {}, setValueCurveAtTime() {}}, connect() {}, disconnect() {}} }
      createMediaElementSource() { return {connect() {}, disconnect() {}} }
      resume() { this.resumes += 1; return Promise.resolve() }
      close() { return Promise.resolve() }
    },
    fetch: async url => { fetches.push(url); return deferred ? deferred : fetchResult ?? {ok: true, json: async () => ({palettes: [], tracks: {}})} },
  })
  const hook = {...Music, el}
  const ok = {ok: true, json: async () => ({palettes: [], tracks: {}})}
  return {hook, nodes, local, timeouts, contexts, fetches, resolveManifest: () => resolveFetch(ok)}
}

test('toggle and volume persist and update the control', async () => {
  const {hook, nodes, local} = mountHook()
  await Music.mounted.call(hook)
  assert.equal(nodes['music-controls'].hidden, false)
  assert.equal(nodes['music-toggle'].attributes['aria-pressed'], 'true')
  nodes['music-toggle'].fire('click')
  assert.equal(local.values['tijara.music.enabled'], 'false')
  assert.equal(nodes['music-toggle'].attributes['aria-pressed'], 'false')
  // The server-rendered label names the control; aria-pressed alone carries its state.
  assert.equal(nodes['music-toggle'].attributes['aria-label'], undefined)
  nodes['music-volume'].value = '55'
  nodes['music-volume'].fire('input')
  assert.equal(local.values['tijara.music.volume'], '55')
  Music.destroyed.call(hook)
})

test('the credit names the piece, links its source and hides after eight seconds', async () => {
  const {hook, nodes, timeouts} = mountHook()
  await Music.mounted.call(hook)
  hook.showCredit({title: 'Shenyang', artists: ['Kevin MacLeod'], source_url: 'https://s.test'}, 'shenyang')
  const credit = nodes['music-credit']
  assert.equal(credit.textContent, 'Now playing: Shenyang by Kevin MacLeod')
  assert.equal(credit.href, 'https://s.test')
  assert.equal(credit.hidden, false)
  assert.equal(nodes['music-credit'].dataset.started, 'shenyang')
  const hide = timeouts.find(t => t.ms === 8000)
  hide.fn()
  assert.equal(credit.hidden, true)
  Music.destroyed.call(hook)
})

test('the started log keeps only the ten most recent pieces', async () => {
  const {hook, nodes} = mountHook()
  await Music.mounted.call(hook)
  for (let i = 0; i < 12; i++) hook.showCredit({title: `T${i}`, artists: ['A'], source_url: 'https://s.test'}, `s${i}`)
  assert.equal(nodes['music-credit'].dataset.started, 's2 s3 s4 s5 s6 s7 s8 s9 s10 s11')
  Music.destroyed.call(hook)
})

test('hides controls when music is unavailable or the browser cannot play Opus', async () => {
  const off = mountHook({music: 'unavailable'})
  await Music.mounted.call(off.hook)
  await flush()
  assert.equal(off.nodes['music-controls'].hidden, true)
  // The disabled path does nothing else: no manifest request, no audio graph
  // and no listener on the document, window or controls.
  assert.deepEqual(off.fetches, [])
  assert.equal(off.contexts.length, 0)
  assert.deepEqual(document.listeners, [])
  assert.deepEqual(window.listeners, [])
  assert.deepEqual(Object.keys(off.nodes['music-toggle'].listeners), [])
  assert.deepEqual(Object.keys(off.nodes['music-volume'].listeners), [])
  assert.equal(off.local.values['tijara.music.enabled'], undefined)
  const noOpus = mountHook()
  globalThis.Audio = class { canPlayType() { return '' } }
  await Music.mounted.call(noOpus.hook)
  assert.equal(noOpus.nodes['music-controls'].hidden, true)
})

test('hides controls when the manifest cannot load', async () => {
  const broken = mountHook({fetchResult: {ok: true, json: async () => { throw new SyntaxError('bad') }}})
  await Music.mounted.call(broken.hook)
  assert.equal(broken.nodes['music-controls'].hidden, true)
  const missing = mountHook({fetchResult: {ok: false, json: async () => ({})}})
  await Music.mounted.call(missing.hook)
  assert.equal(missing.nodes['music-controls'].hidden, true)
  await flush()
})

test('a gesture, toggle and volume change made while the manifest loads are not lost', async () => {
  const {hook, nodes, local, contexts, resolveManifest} = mountHook({deferFetch: true})
  const mounting = Music.mounted.call(hook)
  document.fire('pointerdown')
  nodes['music-toggle'].fire('click')
  nodes['music-volume'].value = '12'
  nodes['music-volume'].fire('input')
  assert.equal(contexts.length, 0, 'no AudioContext before the manifest arrives')
  resolveManifest()
  await mounting
  await flush()
  assert.equal(contexts.length, 1)
  assert.equal(contexts[0].resumes, 1, 'the early gesture unlocked audio once the engine existed')
  assert.deepEqual(hook.settings, {enabled: false, volume: 12})
  assert.deepEqual(local.values, {'tijara.music.enabled': 'false', 'tijara.music.volume': '12'})
  assert.equal(document.listeners.some(l => l.type === 'pointerdown' || l.type === 'keydown'), false)
  Music.destroyed.call(hook)
})

test('a gesture after the engine exists unlocks it once and stops listening', async () => {
  const {hook, contexts} = mountHook()
  await Music.mounted.call(hook)
  assert.equal(contexts[0].resumes, 0)
  document.fire('keydown')
  document.fire('pointerdown')
  await flush()
  assert.equal(contexts[0].resumes, 1)
  Music.destroyed.call(hook)
})

test('switching away and back reaches the director through each foreground signal', async () => {
  const {hook} = mountHook()
  await Music.mounted.call(hook)
  const seen = []
  hook.director.setForeground = visible => seen.push(visible)
  document.hidden = true
  document.fire('visibilitychange')
  document.hidden = false
  document.fire('visibilitychange')
  document.hasFocus = () => false
  window.fire('blur')
  document.hasFocus = () => true
  window.fire('focus')
  assert.deepEqual(seen, [false, true, false, true])
  Music.destroyed.call(hook)
  assert.equal(document.listeners.length + window.listeners.length, 0)
})

test('destroying before the manifest resolves builds nothing and leaves no listeners', async () => {
  const {hook, nodes, contexts, resolveManifest} = mountHook({deferFetch: true})
  const mounting = Music.mounted.call(hook)
  assert.ok(document.listeners.length > 0 && window.listeners.length > 0)
  Music.destroyed.call(hook)
  assert.equal(document.listeners.length + window.listeners.length, 0)
  document.fire('pointerdown')
  resolveManifest()
  await mounting
  await flush()
  assert.equal(contexts.length, 0)
  assert.equal(hook.engine, undefined)
  assert.equal(nodes['music-controls'].hidden, false)
})
