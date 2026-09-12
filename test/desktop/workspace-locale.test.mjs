import {test} from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
const source = readFileSync(new URL('../../assets/js/workspace.js', import.meta.url), 'utf8')
const {Workspace} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

for (const dir of ['ltr', 'rtl']) {
  test(`portrait navigation and keyboard arrows respect ${dir}`, t => {
    const media = globalThis.matchMedia
    const observer = globalThis.ResizeObserver
    globalThis.matchMedia = () => ({matches: true})
    globalThis.ResizeObserver = class { observe() {} disconnect() {} }
    t.after(() => { globalThis.matchMedia = media; globalThis.ResizeObserver = observer })
    const track = {
      clientWidth: 390, scrollLeft: 0,
      scrollTo({left}) { this.scrollLeft = left },
      addEventListener() {}, removeEventListener() {},
    }
    const buttons = [0, 1, 2].map(index => ({
      dataset: {panel: String(index)}, attributes: {},
      setAttribute(key, value) { this.attributes[key] = value },
      matches: () => true, focus() {},
    }))
    const panels = [{}, {}, {}]
    const el = {
      dataset: {}, ownerDocument: {documentElement: {dir}},
      querySelector: selector => selector === '.workspace-panels' ? track : null,
      querySelectorAll: selector => selector === '[data-panel]' ? buttons : panels,
      closest: () => null, addEventListener() {}, removeEventListener() {},
    }
    const hook = {el, handleEvent() {}}
    Workspace.mounted.call(hook)
    const sign = dir === 'rtl' ? -1 : 1
    assert.equal(track.scrollLeft, sign * 390)
    hook.selectPanel(2)
    assert.equal(track.scrollLeft, sign * 780)
    hook.onScroll()
    assert.equal(hook.activePanel, 2)
    assert.equal(panels[2].inert, false)
    assert.equal(panels[0].inert, true)
    hook.onKey({target: buttons[1], key: 'ArrowLeft', preventDefault() {}})
    assert.equal(hook.activePanel, dir === 'rtl' ? 2 : 0)
    hook.onKey({target: buttons[2], key: dir === 'rtl' ? 'ArrowLeft' : 'ArrowRight', preventDefault() {}})
    assert.equal(hook.activePanel, 2)
    Workspace.destroyed.call(hook)
  })
}
