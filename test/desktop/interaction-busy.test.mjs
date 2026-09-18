import {test} from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
const source = readFileSync(new URL('../../assets/js/interaction_busy.js', import.meta.url), 'utf8')
const {installInteractionBusy} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

function setup() {
  let connected = true, pending = 0, callback, now = 0, nextId = 0
  const timers = new Map(), attrs = new Map(), overlay = {hidden: true}
  const root = {
    classList: {contains: () => connected},
    querySelector: () => pending > 0 ? {} : null,
    setAttribute: (key, value) => attrs.set(key, value),
    removeAttribute: key => attrs.delete(key),
  }
  const doc = {body: {}, getElementById: () => overlay, querySelector: () => root}
  const stop = installInteractionBusy(doc, {
    setTimeout: (fn, delay) => { const id = ++nextId; timers.set(id, {fn, at: now + delay}); return id },
    clearTimeout: id => timers.delete(id),
    MutationObserver: class {
      constructor(fn) { callback = fn }
      observe() {}
      disconnect() { callback = () => {} }
    },
  })
  return {
    overlay, attrs, stop,
    pending(n) { pending = n; callback() },
    connected(value) { connected = value; callback() },
    advance(ms) {
      now += ms
      for (const [id, timer] of timers) if (timer.at <= now) { timers.delete(id); timer.fn() }
    },
  }
}

test('fast interactions and background patches never flash an overlay', () => {
  const s = setup()
  s.pending(0); s.advance(1000)
  assert.equal(s.overlay.hidden, true)
  s.pending(1); s.advance(299)
  assert.equal(s.overlay.hidden, true)
  s.pending(0); s.advance(1000)
  assert.equal(s.overlay.hidden, true)
})

test('slow overlapping interactions remain visible until the last response', () => {
  const s = setup()
  s.pending(1); s.advance(300)
  assert.equal(s.overlay.hidden, false)
  assert.equal(s.attrs.get('aria-busy'), 'true')
  s.pending(2); s.pending(1)
  assert.equal(s.overlay.hidden, false)
  s.pending(0)
  assert.equal(s.overlay.hidden, true)
  assert.equal(s.attrs.has('aria-busy'), false)
})

test('disconnects, removed pending elements, and teardown clear feedback', () => {
  const s = setup()
  s.pending(1); s.advance(300); s.connected(false)
  assert.equal(s.overlay.hidden, true)
  s.pending(0); s.connected(true); s.pending(1); s.advance(300)
  assert.equal(s.overlay.hidden, false)
  s.pending(0)
  assert.equal(s.overlay.hidden, true)
  s.pending(1); s.stop(); s.advance(500)
  assert.equal(s.overlay.hidden, true)
})
