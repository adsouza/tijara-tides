import {test} from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
const load = name => import(`data:text/javascript;base64,${Buffer.from(
  readFileSync(new URL(`../../assets/js/${name}.js`, import.meta.url), 'utf8')).toString('base64')}`)
const {createDirector} = await load('music_transitions')
const {identity, choosePiece} = await load('music_policy')
const flush = () => new Promise(resolve => setImmediate(resolve))

const track = (slug, entry = 0) => ({file: `${slug}.ogg`, title: slug, artists: ['X'], duration_s: 120, entry_s: entry})
const manifest = {
  palettes: [
    {id: 'east', ports: ['Shanghai', 'Busan'], port: ['east-port'], voyage: ['east-voyage']},
    {id: 'west', ports: ['Tangier', 'Valencia'], port: ['west-a', 'west-b'], voyage: ['west-voyage']},
  ],
  tracks: {'east-port': track('east-port'), 'east-voyage': track('east-voyage', 16),
    'west-a': track('west-a', 2), 'west-b': track('west-b'), 'west-voyage': track('west-voyage', 8)},
}
const port = p => ({kind: 'port', port: p})
const voyage = (origin, destination, progress) => ({kind: 'voyage', ship: 's', origin, destination, progress})

function harness() {
  let t = 0
  const timers = []
  const prepared = []
  const starts = []
  const clock = {
    now: () => t,
    setTimer: (fn, ms) => { const h = {at: t + ms / 1000, fn}; timers.push(h); return h },
    clearTimer: h => { const i = timers.indexOf(h); if (i >= 0) timers.splice(i, 1) },
  }
  const voiceFor = (trackValue, offset) => {
    // Media time advances with the elapsed clock only while playback runs.
    let position = offset, playingAt = null
    const voice = {track: trackValue, offset, fades: [], plays: [], duration: 120,
      disposed: false, paused: false, progressFns: [], endedFns: [], errorFns: [], error: null,
      play() { return new Promise((resolve, reject) => voice.plays.push({at: t,
        resolve() { position = voice.position; playingAt = t; voice.paused = false; resolve() }, reject})) },
      get position() { return position + (playingAt === null ? 0 : t - playingAt) },
      set position(value) { position = value; if (playingAt !== null) playingAt = t },
      pause() { position = voice.position; playingAt = null; voice.paused = true },
      fade(kind, duration) { voice.fades.push([kind, t, duration]) },
      onProgress(fn) { voice.progressFns.push(fn) }, onEnded(fn) { voice.endedFns.push(fn) },
      onError(fn) { voice.errorFns.push(fn) },
      fail() { voice.error = new Error('stream failed'); voice.errorFns.forEach(fn => fn(voice.error)) },
      progress(position) { voice.position = position; voice.progressFns.forEach(fn => fn()) },
      end() { voice.pause(); voice.endedFns.forEach(fn => fn()) },
      dispose() { voice.pause(); voice.disposed = true }}
    return voice
  }
  const engine = {
    prepare(trackValue, offset) {
      return new Promise((resolve, reject) => {
        const voice = voiceFor(trackValue, offset)
        prepared.push({track: trackValue, offset, voice, at: t,
          resolve: async () => { resolve(voice); await flush() },
          reject: async () => { reject(new Error('load')); await flush() }})
      })
    },
  }
  const director = createDirector({manifest, engine, policy: {identity, choosePiece}, ...clock,
    random: () => 0, onStart: (trackValue, slug) => starts.push([slug, t])})
  const advance = async to => {
    for (;;) {
      timers.sort((a, b) => a.at - b.at)
      const next = timers[0]
      if (!next || next.at > to + 1e-9) break
      timers.shift()
      t = next.at
      next.fn()
      await flush()
    }
    t = to
    await flush()
  }
  return {director, prepared, starts, advance, last: () => prepared.at(-1)}
}

// Starts east-port playing at t = 0 and returns its voice.
async function playing(h, context = port('Shanghai')) {
  h.director.setContext(context)
  h.director.unlock()
  await h.last().resolve()
  const voice = h.last().voice
  voice.plays[0].resolve()
  await flush()
  return voice
}

test('a stable selection fades out over 0–5 s and in over 3–5 s', async () => {
  const h = harness()
  const east = await playing(h)
  assert.deepEqual(east.fades, [['in', 0, 2]])
  await h.advance(10)
  h.director.setContext(port('Tangier'))
  assert.deepEqual(east.fades.at(-1), ['out', 10, 5])
  assert.equal(h.last().offset, 2)
  await h.last().resolve()
  const west = h.last().voice
  await h.advance(12.99)
  assert.equal(west.plays.length, 0)
  await h.advance(13)
  assert.equal(west.plays[0].at, 13)
  assert.deepEqual(h.starts.at(-1), ['east-port', 0])
  west.plays[0].resolve(); await flush()
  assert.deepEqual(west.fades, [['in', 13, 2]])
  assert.deepEqual(h.starts.at(-1), ['west-a', 13])
  await h.advance(15)
  assert.ok(east.paused && east.disposed)
})

test('a reselection at 2 s is silent at 5 s and fades in from 6 to 8 s', async () => {
  const h = harness()
  const east = await playing(h)
  await h.advance(10)
  h.director.setContext(port('Tangier'))
  const westPending = h.last()
  await h.advance(12)
  h.director.setContext(voyage('Busan', 'Tangier', 0))
  await westPending.resolve()
  assert.ok(westPending.voice.disposed)
  assert.equal(h.last().offset, 16)
  await h.last().resolve()
  const next = h.last().voice
  await h.advance(15.99)
  assert.equal(next.plays.length, 0)
  assert.equal(east.fades.filter(([kind]) => kind === 'out').length, 1)
  await h.advance(16)
  next.plays[0].resolve(); await flush()
  assert.deepEqual(next.fades, [['in', 16, 2]])
})

test('a change while silent restarts the three-second wait even when ready', async () => {
  const h = harness()
  await playing(h)
  await h.advance(10)
  h.director.setContext(port('Tangier'))
  await h.advance(11)
  h.director.setContext(voyage('Busan', 'Tangier', 0))
  await h.last().resolve()
  await h.advance(15.5)
  h.director.setContext(port('Busan'))
  await h.last().resolve()
  const latest = h.last().voice
  await h.advance(18.49)
  assert.equal(latest.plays.length, 0)
  await h.advance(18.5)
  assert.equal(latest.plays[0].at, 18.5)
})

test('a change during a fade-in fades all audible music from current gains', async () => {
  const h = harness()
  const east = await playing(h)
  await h.advance(10)
  h.director.setContext(port('Tangier'))
  await h.last().resolve()
  await h.advance(13)
  const west = h.last().voice
  west.plays[0].resolve(); await flush()
  await h.advance(14)
  h.director.setContext(voyage('Busan', 'Tangier', 0))
  assert.deepEqual(east.fades.at(-1), ['out', 14, 5])
  assert.deepEqual(west.fades.at(-1), ['out', 14, 5])
  await h.last().resolve()
  await h.advance(16.99)
  assert.equal(h.last().voice.plays.length, 0)
  await h.advance(17)
  assert.equal(h.last().voice.plays.length, 1)
})

test('an unchanged identity changes nothing, including pending transitions', async () => {
  const h = harness()
  const east = await playing(h)
  h.director.setContext(port('Busan'))
  assert.equal(h.prepared.length, 1)
  assert.deepEqual(east.fades, [['in', 0, 2]])
  await h.advance(10)
  h.director.setContext(port('Tangier'))
  await h.last().resolve()
  await h.advance(11)
  h.director.setContext(port('Valencia'))
  assert.equal(h.prepared.length, 2)
  await h.advance(13)
  assert.equal(h.last().voice.plays[0].at, 13)
})

test('progress updates within a voyage change nothing', async () => {
  const h = harness()
  const voice = await playing(h, voyage('Busan', 'Tangier', 0.2))
  h.director.setContext(voyage('Shanghai', 'Valencia', 0.3))
  h.director.setContext(voyage('Busan', 'Tangier', 0.9))
  assert.equal(h.prepared.length, 1)
  assert.deepEqual(voice.fades, [['in', 0, 2]])
})

test('late audio gets a full fade from its actual start and no early credit', async () => {
  const h = harness()
  await playing(h)
  await h.advance(10)
  h.director.setContext(port('Tangier'))
  await h.advance(14.5)
  await h.last().resolve()
  const west = h.last().voice
  assert.equal(west.plays[0].at, 14.5)
  assert.equal(h.starts.length, 1)
  await h.advance(15.2)
  west.plays[0].resolve(); await flush()
  assert.deepEqual(west.fades, [['in', 15.2, 2]])
  assert.deepEqual(h.starts.at(-1), ['west-a', 15.2])
})

test('a superseded play() is paused and disposed without fade or credit', async () => {
  const h = harness()
  await playing(h)
  await h.advance(10)
  h.director.setContext(port('Tangier'))
  await h.last().resolve()
  await h.advance(13)
  const west = h.last().voice
  await h.advance(13.5)
  h.director.setContext(voyage('Busan', 'Tangier', 0))
  west.plays[0].resolve(); await flush()
  assert.ok(west.paused && west.disposed)
  assert.deepEqual(west.fades, [])
  assert.equal(h.starts.length, 1)
})

test('a superseded play() that rejects is disposed without credit or failure', async () => {
  const h = harness()
  await playing(h)
  await h.advance(10)
  h.director.setContext(port('Tangier'))
  await h.last().resolve()
  await h.advance(13)
  const west = h.last().voice
  await h.advance(13.5)
  h.director.setContext(voyage('Busan', 'Tangier', 0))
  const count = h.prepared.length
  west.plays[0].reject(new Error('timeout')); await flush()
  assert.ok(west.paused && west.disposed)
  assert.deepEqual(west.fades, [])
  assert.equal(h.prepared.length, count)
  assert.equal(h.starts.length, 1)
})

test('a play() that rejects after destroy is disposed without credit or failure', async () => {
  const h = harness()
  await playing(h)
  await h.advance(10)
  h.director.setContext(port('Tangier'))
  await h.last().resolve()
  await h.advance(13)
  const west = h.last().voice
  h.director.destroy()
  const count = h.prepared.length
  west.plays[0].reject(new Error('timeout')); await flush()
  assert.ok(west.disposed)
  assert.equal(h.prepared.length, count)
  assert.equal(h.starts.length, 1)
})

test('selection just before track end preserves its deadline and suppresses automatic starts', async () => {
  const h = harness()
  const east = await playing(h)
  await h.advance(10)
  east.position = 119
  h.director.setContext(port('Tangier'))
  await h.last().resolve()
  const count = h.prepared.length
  east.progress(119.5)
  await h.advance(11)
  east.end()
  assert.ok(east.disposed)
  assert.equal(h.prepared.length, count)
  await h.advance(13)
  assert.equal(h.last().voice.plays[0].at, 13)
})

test('pieces are prepared ten seconds before the end and crossfade over the last two', async () => {
  const h = harness()
  const a = await playing(h, port('Tangier'))
  await h.advance(100)
  a.progress(111)
  assert.equal(h.prepared.length, 2)
  assert.equal(h.last().track, manifest.tracks['west-b'])
  assert.equal(h.last().offset, 0)
  await h.last().resolve()
  const b = h.last().voice
  assert.equal(b.plays.length, 0)
  await h.advance(107)
  assert.equal(b.plays[0].at, 107)
  b.plays[0].resolve(); await flush()
  assert.deepEqual(a.fades.at(-1), ['out', 107, 2])
  assert.deepEqual(b.fades, [['in', 107, 2]])
  assert.deepEqual(h.starts.at(-1), ['west-b', 107])
})

test('a selection during an automatic crossfade fades both pieces', async () => {
  const h = harness()
  const a = await playing(h, port('Tangier'))
  a.progress(118)
  await h.last().resolve()
  const b = h.last().voice
  b.plays[0].resolve(); await flush()
  await h.advance(1)
  h.director.setContext(port('Shanghai'))
  assert.deepEqual(a.fades.at(-1), ['out', 1, 5])
  assert.deepEqual(b.fades.at(-1), ['out', 1, 5])
})

test('turning off cancels every pending start; context changes while off cannot play', async () => {
  const h = harness()
  const east = await playing(h)
  await h.advance(10)
  h.director.setContext(port('Tangier'))
  const west = h.last()
  await h.advance(11)
  h.director.setEnabled(false)
  assert.deepEqual(east.fades.at(-1), ['out', 11, 1])
  await west.resolve()
  assert.ok(west.voice.disposed)
  h.director.setContext(voyage('Busan', 'Tangier', 0))
  await h.advance(20)
  assert.equal(h.prepared.length, 2)
  h.director.setEnabled(true)
  assert.equal(h.last().offset, 16)
  await h.last().resolve()
  assert.equal(h.last().voice.plays[0].at, 20)
})

test('turning off during an automatic crossfade fades both and starts nothing', async () => {
  const h = harness()
  const a = await playing(h, port('Tangier'))
  a.progress(118)
  await h.last().resolve()
  const b = h.last().voice
  b.plays[0].resolve(); await flush()
  h.director.setEnabled(false)
  assert.deepEqual(a.fades.at(-1), ['out', 0, 1])
  assert.deepEqual(b.fades.at(-1), ['out', 0, 1])
  await h.advance(5)
  assert.ok(a.disposed && b.disposed)
})

test('toggling back on during the off-fade starts one fresh piece', async () => {
  const h = harness()
  const east = await playing(h)
  await h.advance(10)
  h.director.setEnabled(false)
  await h.advance(10.5)
  h.director.setEnabled(true)
  await h.last().resolve()
  const fresh = h.last().voice
  assert.notEqual(fresh, east)
  fresh.plays[0].resolve(); await flush()
  await h.advance(11)
  assert.ok(east.disposed)
  assert.equal(h.prepared.length, 2)
})

test('switching away pauses port music for resume and repicks voyages', async () => {
  const h = harness()
  const port1 = await playing(h, port('Tangier'))
  await h.advance(20)
  h.director.setForeground(false)
  assert.deepEqual(port1.fades.at(-1), ['out', 20, 1])
  await h.advance(21)
  assert.ok(port1.paused && !port1.disposed)
  await h.advance(30)
  h.director.setForeground(true)
  assert.equal(h.prepared.length, 1)
  assert.equal(port1.plays.length, 2)
  port1.plays[1].resolve(); await flush()
  assert.deepEqual(port1.fades.at(-1), ['in', 30, 2])
  assert.deepEqual(h.starts.at(-1), ['west-a', 30])

  const v = harness()
  const sailing = await playing(v, voyage('Busan', 'Tangier', 0))
  v.director.setForeground(false)
  await v.advance(2)
  assert.ok(sailing.disposed)
  v.director.setForeground(true)
  assert.equal(v.prepared.length, 2)
  assert.equal(v.last().offset, 16)
})

test('switching away during a port crossfade resumes the incoming port piece', async () => {
  const h = harness()
  const a = await playing(h, port('Tangier'))
  a.progress(118)
  await h.last().resolve()
  const b = h.last().voice
  b.plays[0].resolve(); await flush()
  await h.advance(1)
  b.position = 42
  h.director.setForeground(false)
  await h.advance(2)
  assert.ok(a.disposed && b.paused && !b.disposed)
  const position = b.position
  assert.equal(position, 43)
  await h.advance(4)
  h.director.setForeground(true)
  assert.equal(h.prepared.length, 2)
  assert.equal(b.plays.length, 2)
  b.plays[1].resolve(); await flush()
  assert.equal(b.position, position)
  assert.deepEqual(b.fades.at(-1), ['in', 4, 2])
  assert.deepEqual(h.starts.at(-1), ['west-b', 4])
})

test('switching away during a selection overlap resumes the current port piece', async () => {
  const h = harness()
  const a = await playing(h)
  await h.advance(10)
  h.director.setContext(port('Tangier'))
  await h.last().resolve()
  await h.advance(13)
  const b = h.last().voice
  b.plays[0].resolve(); await flush()
  await h.advance(14)
  h.director.setForeground(false)
  await h.advance(15)
  assert.ok(a.disposed && b.paused && !b.disposed)
  const position = b.position
  await h.advance(20)
  h.director.setForeground(true)
  assert.equal(h.prepared.length, 2)
  assert.equal(b.plays.length, 2)
  b.plays[1].resolve(); await flush()
  assert.equal(b.position, position)
})

test('a port piece that ends during the hide fade is not replayed on return', async () => {
  const h = harness()
  const a = await playing(h, port('Tangier'))
  await h.advance(20)
  h.director.setForeground(false)
  await h.advance(20.5)
  a.end()
  await h.advance(25)
  h.director.setForeground(true)
  assert.equal(a.plays.length, 1)
  assert.equal(h.prepared.length, 2)
  assert.equal(h.last().track, manifest.tracks['west-a'])
  assert.equal(h.last().offset, 2)
  // No failure was counted: two more failures still leave a third attempt.
  await h.last().reject()
  await h.last().reject()
  assert.equal(h.prepared.length, 4)
  await h.last().resolve()
  h.last().voice.plays[0].resolve(); await flush()
  assert.deepEqual(h.starts.at(-1), ['west-a', 25])
})

test('waits for foreground before starting', async () => {
  const h = harness()
  h.director.setForeground(false)
  h.director.setContext(port('Shanghai'))
  h.director.unlock()
  assert.equal(h.prepared.length, 0)
  h.director.setForeground(true)
  assert.equal(h.prepared.length, 1)
})

test('nothing starts before the first gesture unlocks audio', async () => {
  const h = harness()
  h.director.setContext(port('Shanghai'))
  await h.advance(30)
  assert.equal(h.prepared.length, 0)
  h.director.unlock()
  assert.equal(h.prepared.length, 1)
})

test('an unknown port fades to silence without a pending piece', async () => {
  const h = harness()
  const east = await playing(h)
  await h.advance(10)
  h.director.setContext(port('Atlantis'))
  assert.deepEqual(east.fades.at(-1), ['out', 10, 5])
  assert.equal(h.prepared.length, 1)
  await h.advance(30)
  assert.equal(h.starts.length, 1)
})

test('three consecutive failures stop music until the identity changes', async () => {
  const h = harness()
  h.director.setContext(port('Tangier'))
  h.director.unlock()
  await h.last().reject()
  await h.last().reject()
  await h.last().reject()
  assert.equal(h.prepared.length, 3)
  await h.advance(30)
  assert.equal(h.prepared.length, 3)
  h.director.setForeground(false)
  h.director.setEnabled(false)
  h.director.setContext(port('Valencia')) // unchanged palette cannot clear the lock
  h.director.setEnabled(true)
  h.director.setForeground(true)
  h.director.unlock()
  assert.equal(h.prepared.length, 3)
  assert.equal(h.starts.length, 0)
  h.director.setContext(port('Shanghai'))
  assert.equal(h.prepared.length, 4)
})

test('automatic failures stop audible music and cannot retry on progress or focus', async () => {
  const h = harness()
  const a = await playing(h)
  a.progress(111)
  await h.last().reject()
  await h.last().reject()
  await h.last().reject()
  assert.equal(h.prepared.length, 4) // current piece and three failed candidates
  assert.deepEqual(a.fades.at(-1), ['out', 0, 1])
  a.progress(112)
  await h.advance(1)
  assert.ok(a.paused && a.disposed)
  h.director.setForeground(false)
  h.director.setForeground(true)
  h.director.setEnabled(false)
  h.director.setEnabled(true)
  assert.equal(h.prepared.length, 4)
  assert.equal(h.starts.length, 1)
  h.director.setContext(port('Tangier'))
  assert.equal(h.prepared.length, 5)
})

test('an identity change while disabled or away releases the failure lock', async () => {
  for (const setting of ['setEnabled', 'setForeground']) {
    const h = harness()
    h.director.setContext(port('Tangier'))
    h.director.unlock()
    await h.last().reject()
    await h.last().reject()
    await h.last().reject()
    h.director[setting](false)
    h.director.setContext(port('Shanghai'))
    assert.equal(h.prepared.length, 3)
    h.director[setting](true)
    assert.equal(h.prepared.length, 4)
    await h.last().resolve()
    h.last().voice.plays[0].resolve(); await flush()
    assert.deepEqual(h.starts, [['east-port', 0]])
  }
})

test('a rejected play counts as a failure and is replaced', async () => {
  const h = harness()
  h.director.setContext(port('Tangier'))
  h.director.unlock()
  await h.last().resolve()
  h.last().voice.plays[0].reject(new Error('blocked')); await flush()
  assert.equal(h.prepared.length, 2)
  assert.equal(h.last().track, manifest.tracks['west-b'])
})

test('a retry uses the latest ship progress without restarting the selection deadline', async () => {
  const h = harness()
  await playing(h)
  await h.advance(10)
  h.director.setContext(voyage('Busan', 'Tangier', 0))
  assert.equal(h.last().track, manifest.tracks['east-voyage'])
  await h.advance(11)
  h.director.setContext({...voyage('Busan', 'Tangier', 1), ship: 'new-ship'})
  await h.last().reject()
  assert.equal(h.last().track, manifest.tracks['west-voyage'])
  assert.equal(h.last().offset, 8)
  await h.last().resolve()
  await h.advance(12.99)
  assert.equal(h.last().voice.plays.length, 0)
  await h.advance(13)
  assert.equal(h.last().voice.plays[0].at, 13)
})

test('a streaming failure replaces the current piece and keeps the failure limit', async () => {
  const h = harness()
  const first = await playing(h, port('Tangier'))
  first.fail()
  assert.ok(first.disposed)
  assert.equal(h.last().track, manifest.tracks['west-b'])
  assert.equal(h.last().offset, 0, 'a replacement within one context starts at the recording beginning')
  await h.last().reject()
  await h.last().reject()
  assert.equal(h.prepared.length, 3)
  h.director.setForeground(false)
  h.director.setForeground(true)
  h.director.setEnabled(false)
  h.director.setEnabled(true)
  assert.equal(h.prepared.length, 3, 'three failures remain locked across toggles and focus')
  h.director.setContext(port('Shanghai'))
  assert.equal(h.prepared.length, 4)
})

test('a streaming failure keeps an already prepared automatic successor', async () => {
  const h = harness()
  const first = await playing(h, port('Tangier'))
  first.progress(111)
  await h.last().resolve()
  const next = h.last().voice
  assert.equal(next.plays.length, 0)
  first.fail()
  assert.ok(first.disposed)
  assert.equal(h.prepared.length, 2)
  assert.equal(next.plays.length, 1, 'the healthy successor starts without waiting for the failed track end')
  next.plays[0].resolve(); await flush()
  assert.deepEqual(h.starts.at(-1), ['west-b', 0])
})

test('errors after readiness and during pending play recover only once', async () => {
  for (const phase of ['ready', 'playing']) {
    const h = harness()
    await playing(h)
    h.director.setContext(port('Tangier'))
    await h.last().resolve()
    const failed = h.last().voice
    if (phase === 'playing') await h.advance(3)
    failed.fail()
    assert.ok(failed.disposed)
    assert.equal(h.last().track, manifest.tracks['west-b'])
    failed.fail()
    if (phase === 'playing') { failed.plays[0].reject(new Error('aborted')); await flush() }
    assert.equal(h.prepared.length, 3)
    assert.equal(h.starts.length, 1)
    await h.last().resolve()
    await h.advance(3)
    h.last().voice.plays[0].resolve(); await flush()
    assert.deepEqual(h.starts.at(-1), ['west-b', 3])
  }
})

test('an error between media readiness and its callback cannot start the failed voice', async () => {
  const h = harness()
  h.director.setContext(port('Tangier'))
  h.director.unlock()
  const failed = h.last().voice
  failed.fail()
  await h.last().resolve()
  assert.ok(failed.disposed)
  assert.equal(failed.plays.length, 0)
  assert.equal(h.last().track, manifest.tracks['west-b'])
})

test('errors from outgoing, hidden or destroyed voices never replace the latest context', async () => {
  for (const phase of ['outgoing', 'hidden', 'destroyed']) {
    const h = harness()
    const first = await playing(h)
    if (phase === 'outgoing') h.director.setContext(port('Tangier'))
    if (phase === 'hidden') h.director.setForeground(false)
    if (phase === 'destroyed') h.director.destroy()
    const count = h.prepared.length
    first.fail()
    assert.ok(first.disposed)
    assert.equal(h.prepared.length, count)
    if (phase === 'hidden') {
      await h.advance(2)
      h.director.setForeground(true)
      assert.equal(first.plays.length, 1, 'a failed paused port piece cannot resume')
      assert.equal(h.prepared.length, count + 1)
    }
  }
})

test('destroy disposes everything and ignores late callbacks', async () => {
  const h = harness()
  const east = await playing(h)
  h.director.setContext(port('Tangier'))
  const pending = h.last()
  h.director.destroy()
  assert.ok(east.disposed)
  await pending.resolve()
  assert.ok(pending.voice.disposed)
})
