import {test} from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
const source = readFileSync(new URL('../../assets/js/exchange_draft.js', import.meta.url), 'utf8')
const {ExchangeDraft} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

function setup() {
  const fields = [
    {name: 'price', value: '50'}, {name: 'minutes', value: '', disabled: true},
    {name: 'quantity', value: '1'}, {name: 'clear_expiry', type: 'checkbox', checked: true},
    {name: 'warehouse', tagName: 'SELECT', value: 'a', options: [{value: 'a'}, {value: 'b'}]},
    {name: 'request_id', type: 'hidden', value: 'old'},
  ]
  fields.forEach(field => {field.matches = () => field.type !== 'hidden'})
  const listeners = new Map()
  const hook = {el: {
    querySelector: selector => fields.find(field => selector === `[name="${field.name}"]`),
    querySelectorAll: () => fields.filter(field => field.type !== 'hidden'),
    addEventListener: (event, fn) => listeners.set(event, fn),
    removeEventListener: event => listeners.delete(event),
  }}
  ExchangeDraft.mounted.call(hook)
  return {hook, fields: Object.fromEntries(fields.map(field => [field.name, field])), listeners}
}

test('ticks preserve dirty values and checkbox state while hidden IDs refresh', () => {
  const {hook, fields, listeners} = setup()
  for (const [name, value] of [['price', '123'], ['minutes', '45'], ['quantity', '7'], ['warehouse', 'b']]) {
    fields[name].value = value
    listeners.get('input')({target: fields[name]})
  }
  fields.clear_expiry.checked = false
  listeners.get('change')({target: fields.clear_expiry})
  for (let i = 0; i < 10; i++) {
    fields.price.value = '50'; fields.minutes.value = ''; fields.quantity.value = '1'
    fields.warehouse.value = 'a'; fields.clear_expiry.checked = true
    fields.request_id.value = `request-${i}`
    ExchangeDraft.updated.call(hook)
    assert.equal(fields.price.value, '123')
    assert.equal(fields.minutes.value, '45')
    assert.equal(fields.quantity.value, '7')
    assert.equal(fields.warehouse.value, 'b')
    assert.equal(fields.clear_expiry.checked, false)
    assert.equal(fields.minutes.disabled, false)
    assert.equal(fields.request_id.value, `request-${i}`)
  }
  fields.clear_expiry.checked = true
  listeners.get('change')({target: fields.clear_expiry})
  assert.equal(fields.minutes.disabled, true)
  ExchangeDraft.destroyed.call(hook)
  assert.equal(listeners.size, 0)
})

test('untouched defaults refresh, vanished warehouses are discarded, new forms have fresh drafts', () => {
  const {hook, fields, listeners} = setup()
  fields.price.value = '70'
  ExchangeDraft.updated.call(hook)
  assert.equal(fields.price.value, '70')
  fields.warehouse.value = 'b'
  listeners.get('change')({target: fields.warehouse})
  fields.warehouse.options = [{value: 'a'}]
  fields.warehouse.value = 'a'
  ExchangeDraft.updated.call(hook)
  assert.equal(fields.warehouse.value, 'a')
  assert.equal(hook.draft.has('warehouse'), false)
  assert.equal(setup().hook.draft.size, 0)
})
