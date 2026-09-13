import {test} from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
const source = readFileSync(new URL('../../assets/js/system_notifications.js', import.meta.url), 'utf8')
const {SystemNotifications} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

test('requests permission only on click and emits notifications only when granted', async t => {
  const original = globalThis.Notification
  t.after(() => { globalThis.Notification = original })
  const delivered = []
  let requested = 0
  globalThis.Notification = class {
    static permission = 'default'
    static async requestPermission() { requested++; this.permission = 'granted' }
    constructor(title, options) { delivered.push({title, ...options}) }
  }
  const button = {addEventListener() {}, removeEventListener() {}}
  const handlers = {}
  const hook = {el: {dataset: {enabled: 'Enabled', enable: 'Enable', unavailable: 'Blocked'}, querySelector: () => button}, handleEvent(name, fn) { handlers[name] = fn }}
  SystemNotifications.mounted.call(hook)
  assert.equal(requested, 0)
  handlers['system-notification']({title: 'Game', body: 'Finished', tag: 'one'})
  assert.equal(delivered.length, 0)
  await hook.enable()
  assert.equal(requested, 1)
  assert.equal(button.textContent, 'Enabled')
  handlers['system-notification']({title: 'Game', body: 'Finished', tag: 'one'})
  assert.equal(delivered[0].body, 'Finished')
  Notification.permission = 'denied'
  SystemNotifications.updated.call(hook)
  assert.equal(button.textContent, 'Blocked')
  assert.equal(button.disabled, true)
  SystemNotifications.destroyed.call(hook)
})
