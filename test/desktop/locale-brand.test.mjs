import {test} from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
const source = readFileSync(new URL('../../assets/js/locale.js', import.meta.url), 'utf8')
const {Locale} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

test('locale updates replace the title brand without duplicating suffixes', t => {
  const previous = globalThis.document
  t.after(() => { globalThis.document = previous })
  const title = {textContent: 'Company · Tijara Tides', dataset: {default: 'Tijara Tides', suffix: ' · Tijara Tides'}}
  globalThis.document = {documentElement: {}, querySelector: () => title}
  const context = {el: {dataset: {locale: 'ar', direction: 'rtl', gameTitle: 'أمواج التجارة'}}}
  Locale.updated.call(context)
  Locale.updated.call(context)
  assert.equal(title.textContent, 'Company · أمواج التجارة')
  assert.equal(title.dataset.default, 'أمواج التجارة')
  assert.equal(document.documentElement.dir, 'rtl')
  context.el.dataset = {locale: 'en', direction: 'ltr', gameTitle: 'Tijara Tides'}
  Locale.updated.call(context)
  assert.equal(title.textContent, 'Company · Tijara Tides')
  title.textContent = 'Tijara Tides'
  context.el.dataset = {locale: 'ar', direction: 'rtl', gameTitle: 'أمواج التجارة'}
  Locale.updated.call(context)
  assert.equal(title.textContent, 'أمواج التجارة')
})
