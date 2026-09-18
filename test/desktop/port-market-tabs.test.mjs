import {test} from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
const source = readFileSync(new URL('../../assets/js/port_market_tabs.js', import.meta.url), 'utf8')
const {PortMarketTabs} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

test('tabs switch before a server reply and preserve the latest choice through stale patches', () => {
  const panels = ['buy', 'sell'].map(side => ({dataset: {marketPanel: side}, hidden: side === 'sell', draft: 17}))
  const buttons = ['buy', 'sell'].map(side => ({dataset: {marketSide: side}, attrs: {},
    setAttribute(k, v) { this.attrs[k] = v }, classList: {toggle() {}}}))
  let listener
  const el = {dataset: {side: 'buy'}, contains: b => buttons.includes(b),
    querySelectorAll: selector => selector === '[data-market-panel]' ? panels : buttons,
    addEventListener: (_, fn) => { listener = fn }, removeEventListener: (_, fn) => assert.equal(fn, listener)}
  let select
  const hook = {...PortMarketTabs, el, handleEvent: (_, fn) => { select = fn }}
  hook.mounted()
  listener({target: {closest: () => buttons[1]}})
  assert.deepEqual(panels.map(p => p.hidden), [true, false])
  assert.equal(buttons[1].attrs['aria-pressed'], 'true')
  // An old buy-side server patch must not undo the click, or replace the forms.
  panels[0].hidden = false
  panels[1].hidden = true
  hook.updated()
  assert.deepEqual(panels.map(p => p.hidden), [true, false])
  assert.deepEqual(panels.map(p => p.draft), [17, 17])
  listener({target: {closest: () => buttons[0]}})
  el.dataset.side = 'sell'
  hook.updated()
  assert.deepEqual(panels.map(p => p.hidden), [false, true])
  select({side: 'sell'})
  assert.deepEqual(panels.map(p => p.hidden), [true, false])
  select({side: 'buy'}) // Selecting a destination intentionally returns to purchases.
  assert.deepEqual(panels.map(p => p.hidden), [false, true])
  hook.destroyed()
})
