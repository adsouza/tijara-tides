import {test} from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
const source = readFileSync(new URL('../../assets/js/port_selector.js', import.meta.url), 'utf8')
const {PortSelector} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

test('ticks leave the native selection untouched, while navigation and reconnect synchronize it', () => {
  let value = 'Singapore'
  let writes = 0
  const select = {get value() {return value}, set value(next) {value = next; writes++}}
  const hook = {el: {dataset: {selected: 'Singapore'}, querySelector: () => select}}
  PortSelector.mounted.call(hook)
  for (let i = 0; i < 10; i++) PortSelector.updated.call(hook)
  assert.equal(writes, 0)

  // User changes the native selection before the server acknowledges it.
  value = 'Colombo'
  PortSelector.updated.call(hook)
  assert.equal(value, 'Colombo')
  assert.equal(writes, 0)
  hook.el.dataset.selected = 'Colombo'
  PortSelector.updated.call(hook)
  assert.equal(writes, 0)

  // A map/cargo cross-link selects a different port on the server.
  hook.el.dataset.selected = 'Rotterdam'
  PortSelector.updated.call(hook)
  assert.equal(value, 'Rotterdam')
  assert.equal(writes, 1)

  value = 'Hamburg'
  PortSelector.reconnected.call(hook)
  assert.equal(value, 'Rotterdam')
  assert.equal(writes, 2)
})
