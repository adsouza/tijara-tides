import {test} from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
const source = readFileSync(new URL('../../assets/js/loan_amount.js', import.meta.url), 'utf8')
const {LoanAmount} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

test('loan controls clamp amounts, link slider steps, and follow changing credit', () => {
  const number = {type: 'number', value: '125500'}
  const range = {type: 'range', value: '13', setAttribute(key, value) { this[key] = value }}
  const listeners = new Map()
  const el = {
    dataset: {max: '125500'},
    querySelector: selector => selector.includes('number') ? number : range,
    addEventListener: (name, callback) => listeners.set(name, callback),
    removeEventListener: name => listeners.delete(name),
  }
  const hook = {el}
  LoanAmount.mounted.call(hook)
  assert.equal(range.value, 13)
  number.value = '999999'
  listeners.get('input')({target: number})
  assert.equal(number.value, 125500)
  range.value = '7'
  listeners.get('input')({target: range})
  assert.equal(number.value, 70000)
  assert.equal(range['aria-valuetext'], '$70,000')
  range.value = '13'
  listeners.get('input')({target: range})
  assert.equal(number.value, 125500)
  el.dataset.max = '5200'
  LoanAmount.updated.call(hook)
  assert.equal(number.value, 5200)
  assert.equal(range.value, 1)
  number.value = '-10'
  listeners.get('input')({target: number})
  assert.equal(number.value, 1)
  number.min = '4201'
  number.value = '2'
  listeners.get('input')({target: number})
  assert.equal(number.value, 4201)
  assert.equal(range['aria-valuetext'], '$4,201')
  el.dataset.max = '0'
  LoanAmount.updated.call(hook)
  assert.equal(number.value, 0)
  assert.equal(range.value, 0)
  LoanAmount.destroyed.call(hook)
  assert.equal(listeners.size, 0)
})
