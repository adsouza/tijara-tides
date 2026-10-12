import {chromium} from '@playwright/test'
import {readFile} from 'node:fs/promises'
import assert from 'node:assert/strict'
import {traceRecorder} from './support/trace.mjs'

// Background music waits for a gesture, follows explicit selections with
// DESIGN.md's timing even when audio arrives late, never lets a superseded
// piece become audible, and keeps its settings across reloads.
const config = JSON.parse(await readFile(process.argv[2], 'utf8'))
const browser = await chromium.launch({headless: true})
const timer = setTimeout(() => { process.exitCode = 1; browser.close() }, 110_000)
const trace = traceRecorder('music')
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms))
const started = page => page.locator('#music-credit').evaluate(el => (el.dataset.started ?? '').split(' ').filter(Boolean))

async function open(label) {
  const context = await browser.newContext()
  await trace.attach(context, label)
  const page = await context.newPage()
  page.setDefaultTimeout(15_000)
  // Network evidence, independent of what the audio stack does with a request.
  const oggs = []
  page.on('request', request => { if (request.url().includes('.ogg')) oggs.push(request.url()) })
  const manifest = page.waitForResponse(response => response.url().includes('/audio/fixtures/music.json'))
  await page.goto(config.url + '/play')
  await page.locator('[data-phx-main].phx-connected').waitFor()
  await page.locator('#music[data-music="available"]').waitFor({state: 'attached'})
  return {context, page, oggs, manifest}
}

async function gestureAndEast(page) {
  await page.locator('.game-tagline').click()
  await page.waitForFunction(() => document.querySelector('#music-credit').dataset.started?.includes('east-port'))
}

// Delays west-port.ogg and reports when the delayed response has reached the
// page, so a test can tell "never played" from "had not arrived yet".
async function delayWest(page, ms) {
  const arrived = page.waitForResponse(response => response.url().includes('/audio/fixtures/west-port.ogg'), {timeout: 20_000})
  arrived.catch(() => {})
  await page.route('**/audio/fixtures/west-port.ogg*', async route => { await sleep(ms); await route.continue() })
  return {arrived}
}

// Time for the arrived element to be decoded and, if it were going to, start.
const DECODE_GRACE_MS = 2_000

try {
  {
    const {context, page, oggs, manifest} = await open('music-timing')
    await manifest
    await sleep(1_500)
    // The manifest is in; if the gesture gate were missing the first piece would
    // already be requested. Network, not silence, proves the gate.
    assert.deepEqual(oggs, [], 'no audio file is requested before the first gesture')
    assert.deepEqual(await started(page), [], 'nothing plays before the first gesture')
    await gestureAndEast(page)
    assert.ok(oggs.length > 0, 'the gesture releases the first audio request')
    const credit = page.locator('#music-credit')
    await credit.waitFor({state: 'visible'})
    assert.equal(await credit.textContent(), 'Now playing: East Harbour Tone by Fixture Composer')
    assert.equal(await credit.getAttribute('href'), 'https://example.test/east-port')

    await delayWest(page, 6_000)
    const t0 = Date.now()
    await page.selectOption('#port-selector select', 'Tangier')
    await page.waitForFunction(() => document.querySelector('#music-credit').dataset.started?.includes('west-port'), null, {timeout: 20_000})
    const elapsed = (Date.now() - t0) / 1000
    assert.ok(elapsed >= 5.5, `late audio must not start before it arrives (${elapsed}s)`)
    // Arrival at 6 s, long past the 3 s settle: a restarted settle would add 3 s.
    assert.ok(elapsed < 9, `late audio starts when it arrives, not after a new settle (${elapsed}s)`)
    assert.equal(await credit.textContent(), 'Now playing: West Harbour Tone by Fixture Composer')
    await trace.close(context)
  }
  {
    const {context, page} = await open('music-superseded')
    await gestureAndEast(page)
    const west = await delayWest(page, 6_000)
    await page.selectOption('#port-selector select', 'Tangier')
    await sleep(1_000)
    await page.selectOption('#port-selector select', 'Guangzhou')
    // East must restart, and the superseded west response must have arrived
    // and had time to start, before its absence means anything.
    await page.waitForFunction(() => document.querySelector('#music-credit').dataset.started === 'east-port east-port', null, {timeout: 20_000})
    await west.arrived
    await sleep(DECODE_GRACE_MS)
    const log = await started(page)
    assert.deepEqual(log, ['east-port', 'east-port'], `superseded piece played: ${log}`)
    await trace.close(context)
  }
  {
    const {context, page} = await open('music-disabled')
    await gestureAndEast(page)
    const west = await delayWest(page, 6_000)
    await page.selectOption('#port-selector select', 'Tangier')
    await sleep(1_000)
    await page.locator('#music-toggle').click()
    await west.arrived
    await sleep(DECODE_GRACE_MS)
    assert.ok(!(await started(page)).includes('west-port'), 'disabled music must not start the delayed piece')
    assert.equal(await page.locator('#music-toggle').getAttribute('aria-pressed'), 'false')
    await page.locator('#music-settings summary').click()
    await page.locator('#music-volume').fill('70')
    await page.reload()
    await page.locator('[data-phx-main].phx-connected').waitFor()
    await page.waitForFunction(() => document.querySelector('#music-toggle').getAttribute('aria-pressed') === 'false')
    assert.equal(await page.locator('#music-volume').inputValue(), '70')
    await trace.close(context)
  }
  console.log('Music browser contracts passed')
} catch (error) {
  console.error(error)
  process.exitCode = 1
} finally {
  clearTimeout(timer)
  await browser.close()
}
