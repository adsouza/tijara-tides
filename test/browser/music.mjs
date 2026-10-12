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
  await page.goto(config.url + '/play')
  await page.locator('[data-phx-main].phx-connected').waitFor()
  await page.locator('#music[data-music="available"]').waitFor({state: 'attached'})
  return {context, page}
}

async function gestureAndEast(page) {
  await page.locator('.game-tagline').click()
  await page.waitForFunction(() => document.querySelector('#music-credit').dataset.started?.includes('east-port'))
}

function delayWest(page, ms) {
  return page.route('**/audio/fixtures/west-port.ogg*', async route => { await sleep(ms); await route.continue() })
}

try {
  {
    const {context, page} = await open('music-timing')
    await sleep(1_500)
    assert.deepEqual(await started(page), [], 'nothing plays before the first gesture')
    await gestureAndEast(page)
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
    assert.equal(await credit.textContent(), 'Now playing: West Harbour Tone by Fixture Composer')
    await trace.close(context)
  }
  {
    const {context, page} = await open('music-superseded')
    await gestureAndEast(page)
    await delayWest(page, 6_000)
    await page.selectOption('#port-selector select', 'Tangier')
    await sleep(1_000)
    await page.selectOption('#port-selector select', 'Guangzhou')
    await sleep(12_000)
    const log = await started(page)
    assert.ok(!log.includes('west-port'), `superseded piece played: ${log}`)
    assert.equal(log.at(-1), 'east-port')
    await trace.close(context)
  }
  {
    const {context, page} = await open('music-disabled')
    await gestureAndEast(page)
    await delayWest(page, 6_000)
    await page.selectOption('#port-selector select', 'Tangier')
    await sleep(1_000)
    await page.locator('#music-toggle').click()
    await sleep(9_000)
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
