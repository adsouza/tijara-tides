import {test} from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
const source = readFileSync(new URL('../../assets/js/music_engine.js', import.meta.url), 'utf8')
const engineModule = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)
const {volumeGain, envelopeAt, fadeCurve, trackUrl, createEngine} = engineModule
const flush = () => new Promise(resolve => setImmediate(resolve))
const close = (a, b) => assert.ok(Math.abs(a - b) < 1e-6, `${a} ≈ ${b}`)

function param() {
  const p = {value: 0, calls: []}
  for (const name of ['cancelScheduledValues', 'setValueAtTime', 'setValueCurveAtTime', 'linearRampToValueAtTime'])
    p[name] = (...args) => p.calls.push([name, ...args])
  return p
}
function fakeContext() {
  const context = {currentTime: 0, destination: {}, gains: [], resumed: 0,
    createGain() { const node = {gain: param(), connect() {}, disconnect() { node.disconnected = true }}; context.gains.push(node); return node },
    createMediaElementSource: element => ({element, connect() {}, disconnect() {}}),
    resume() { context.resumed++; return Promise.resolve() }}
  return context
}
function fakeAudio() {
  const listeners = new Map()
  const audio = {currentTime: 0, duration: 120, paused: true, attributes: {}, playResult: Promise.resolve(),
    addEventListener(type, fn) { listeners.set(type, [...(listeners.get(type) ?? []), fn]) },
    removeEventListener() {},
    dispatch(type) { const fns = listeners.get(type) ?? []; listeners.set(type, []); fns.forEach(fn => fn()) },
    set src(value) { audio.attributes.src = value }, get src() { return audio.attributes.src },
    removeAttribute(name) { delete audio.attributes[name] }, load() { audio.loads = (audio.loads ?? 0) + 1 },
    play() { audio.paused = false; return audio.playResult }, pause() { audio.paused = true }}
  return audio
}
function timers() {
  const pending = []
  return {pending, setTimer: (fn, ms) => { const h = {fn, ms}; pending.push(h); return h },
    clearTimer: h => { const i = pending.indexOf(h); if (i >= 0) pending.splice(i, 1) },
    fire() { pending.splice(0).forEach(h => h.fn()) }}
}
const track = {file: 'a.ogg', output_sha256: '0123456789abcdef', title: 'A', artists: ['X']}

test('volume maps to the square of the slider fraction', () => {
  assert.equal(volumeGain(0), 0)
  close(volumeGain(30), 0.09)
  assert.equal(volumeGain(100), 1)
  assert.equal(volumeGain(140), 1)
  assert.equal(volumeGain(-5), 0)
})

test('fades follow cosine out from the current gain and sine in', () => {
  const out = {kind: 'out', from: 0.8, start: 10, duration: 5}
  close(envelopeAt(out, 10), 0.8)
  close(envelopeAt(out, 12.5), 0.8 * Math.cos(Math.PI / 4))
  close(envelopeAt(out, 15), 0)
  const fadeIn = {kind: 'in', from: 0, start: 3, duration: 2}
  close(envelopeAt(fadeIn, 4), Math.sin(Math.PI / 4))
  close(envelopeAt(fadeIn, 9), 1)
  const curve = fadeCurve(fadeIn)
  assert.equal(curve.length, 201)
  close(curve[0], 0)
  close(curve[100], Math.sin(Math.PI / 4))
  close(curve[200], 1)
})

test('track URLs are versioned by output hash', () => {
  assert.equal(trackUrl('https://h.test/audio/', track), 'https://h.test/audio/a.ogg?v=0123456789ab')
})

test('prepare seeks to the entry before resolving and schedules exact curves', async () => {
  const context = fakeContext(), audio = fakeAudio(), clock = timers()
  const engine = createEngine({context, createAudio: () => audio, baseUrl: 'https://h.test/audio/', ...clock})
  let voice
  engine.prepare(track, 7.5).then(v => { voice = v })
  audio.dispatch('loadedmetadata')
  assert.equal(audio.currentTime, 7.5)
  await flush()
  assert.equal(voice, undefined)
  audio.dispatch('seeked')
  await flush()
  assert.equal(voice.track, track)
  const gain = context.gains[1].gain
  context.currentTime = 2
  voice.fade('in', 2)
  const [, , [, curve, start, duration]] = gain.calls
  assert.deepEqual(gain.calls[0], ['cancelScheduledValues', 0])
  assert.deepEqual(gain.calls[1], ['setValueAtTime', 0, 2])
  close(start, 2.01)
  assert.equal(duration, 2)
  close(curve[0], 0)
  context.currentTime = 3.01
  close(voice.gain(), Math.sin(Math.PI / 4))
  voice.fade('out', 5)
  const last = gain.calls.at(-1)
  close(last[1][0], Math.sin(Math.PI / 4))
  close(last[1].at(-1), 0)
})

test('load errors and timeouts reject and dispose the element', async () => {
  const context = fakeContext(), clock = timers()
  const failing = fakeAudio()
  const engine = createEngine({context, createAudio: () => failing, baseUrl: 'https://h.test/', ...clock})
  const rejected = engine.prepare(track, 0)
  failing.dispatch('error')
  await assert.rejects(rejected)
  assert.equal(failing.src, undefined)
  const slow = fakeAudio()
  const engine2 = createEngine({context, createAudio: () => slow, baseUrl: 'https://h.test/', ...clock})
  const timedOut = engine2.prepare(track, 0)
  clock.fire()
  await assert.rejects(timedOut, /loading timed out/)
})

test('play times out separately from loading', async () => {
  const context = fakeContext(), audio = fakeAudio(), clock = timers()
  audio.playResult = new Promise(() => {})
  const engine = createEngine({context, createAudio: () => audio, baseUrl: 'https://h.test/', ...clock})
  const ready = engine.prepare(track, 0)
  audio.dispatch('loadedmetadata'); audio.dispatch('canplay')
  const voice = await ready
  assert.equal(clock.pending.length, 0)
  const playing = voice.play()
  await flush()
  clock.fire()
  await assert.rejects(playing, /playback timed out/)
})

test('volume ramps over 50 ms and unlock resumes the context', async () => {
  const context = fakeContext(), clock = timers()
  const engine = createEngine({context, createAudio: fakeAudio, baseUrl: 'https://h.test/', ...clock})
  context.currentTime = 1
  engine.setVolume(30)
  const master = context.gains[0].gain
  const ramp = master.calls.at(-1)
  assert.equal(ramp[0], 'linearRampToValueAtTime')
  close(ramp[1], 0.09)
  close(ramp[2], 1.05)
  await engine.unlock()
  assert.equal(context.resumed, 1)
})
