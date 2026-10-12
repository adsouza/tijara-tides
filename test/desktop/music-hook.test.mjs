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
  return {id, hidden: false, textContent: '', dataset: {}, attributes: {}, value: '30', href: '',
    setAttribute(name, value) { this.attributes[name] = String(value) },
    addEventListener(type, fn) { listeners[type] = fn }, removeEventListener(type) { delete listeners[type] },
    fire(type) { listeners[type]?.({}) }}
}

function mountHook({music = 'available', fetchResult} = {}) {
  const nodes = Object.fromEntries(['music-controls', 'music-toggle', 'music-volume', 'music-credit'].map(id => [id, element(id)]))
  const el = {dataset: {music, manifest: '/audio/fixtures/music.json', context: 'port', port: 'Tangier',
    nowPlaying: 'Now playing: %{title} by %{artists}', labelOn: 'Turn music on', labelOff: 'Turn music off'},
    querySelector: selector => nodes[selector.slice(1)]}
  const local = storage()
  const timeouts = []
  const saved = {setTimeout: globalThis.setTimeout, clearTimeout: globalThis.clearTimeout}
  restores.push(() => Object.assign(globalThis, saved))
  Object.assign(globalThis, {
    localStorage: local,
    location: {href: 'https://h.test/play'},
    performance: {now: () => 0},
    setTimeout: (fn, ms) => { timeouts.push({fn, ms}); return timeouts.length },
    clearTimeout: () => {},
    document: {hidden: false, hasFocus: () => true, addEventListener() {}, removeEventListener() {}},
    window: {addEventListener() {}, removeEventListener() {}},
    Audio: class { canPlayType() { return 'probably' } },
    AudioContext: class {
      constructor() { this.currentTime = 0; this.destination = {} }
      createGain() { return {gain: {value: 0, cancelScheduledValues() {}, setValueAtTime() {}, linearRampToValueAtTime() {}, setValueCurveAtTime() {}}, connect() {}, disconnect() {}} }
      createMediaElementSource() { return {connect() {}, disconnect() {}} }
      resume() { return Promise.resolve() }
      close() { return Promise.resolve() }
    },
    fetch: async () => fetchResult ?? {ok: true, json: async () => ({palettes: [], tracks: {}})},
  })
  const hook = {...Music, el}
  return {hook, nodes, local, timeouts}
}

test('toggle and volume persist and update the control', async () => {
  const {hook, nodes, local} = mountHook()
  await Music.mounted.call(hook)
  assert.equal(nodes['music-controls'].hidden, false)
  assert.equal(nodes['music-toggle'].attributes['aria-pressed'], 'true')
  nodes['music-toggle'].fire('click')
  assert.equal(local.values['tijara.music.enabled'], 'false')
  assert.equal(nodes['music-toggle'].attributes['aria-pressed'], 'false')
  assert.equal(nodes['music-toggle'].attributes['aria-label'], 'Turn music on')
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

test('hides controls when music is unavailable or the browser cannot play Opus', async () => {
  const off = mountHook({music: 'unavailable'})
  await Music.mounted.call(off.hook)
  assert.equal(off.nodes['music-controls'].hidden, true)
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
