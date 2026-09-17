import {test} from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
const source = readFileSync(new URL('../../assets/js/dropdowns.js', import.meta.url), 'utf8')
const {watchDropdowns} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

test('dropdown interaction defers refreshes until selection, dismissal or focus leaves', () => {
  const listeners = {}
  const updates = []
  const root = {
    addEventListener(name, fn) { listeners[name] = fn },
    removeEventListener(name, fn) { assert.equal(listeners[name], fn); delete listeners[name] },
  }
  const stop = watchDropdowns(root, active => updates.push(active))
  const select = {target: {tagName: 'SELECT'}}
  listeners.pointerdown(select)
  listeners.focusin(select)
  assert.deepEqual(updates, [true])
  listeners.change(select)
  assert.deepEqual(updates, [true, false])
  listeners.pointerdown(select) // reopen while still focused
  listeners.keydown({...select, key: 'Escape'})
  listeners.keydown({...select, key: 'ArrowDown'})
  listeners.focusout(select)
  listeners.focusin(select)
  listeners.pointerdown({target: {tagName: 'BUTTON'}})
  assert.deepEqual(updates, [true, false, true, false, true, false, true, false])
  stop()
  assert.deepEqual(listeners, {})
})

test('native cancellation resumes updates without imposing a menu timeout', t => {
  const previous = {setInterval, clearInterval}
  let check
  globalThis.setInterval = fn => { check = fn; return 1 }
  globalThis.clearInterval = () => {}
  t.after(() => Object.assign(globalThis, previous))
  const listeners = {}
  const updates = []
  const root = {addEventListener(name, fn) { listeners[name] = fn }, removeEventListener() {}}
  const stop = watchDropdowns(root, active => updates.push(active))
  let open = true
  listeners.pointerdown({target: {tagName: 'SELECT', matches: () => open}})
  for (let tick = 0; tick < 1000; tick++) check()
  assert.deepEqual(updates, [true])
  open = false // Escape handled by the OS; no change or keydown event arrives.
  check()
  assert.deepEqual(updates, [true, false])
  stop()
})
