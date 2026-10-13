import {chromium} from '@playwright/test'
import {readFile, mkdir} from 'node:fs/promises'
import assert from 'node:assert/strict'
import {traceRecorder} from './support/trace.mjs'

const config = JSON.parse(await readFile(process.argv[2], 'utf8'))
const browser = await chromium.launch({headless: true})
const timer = setTimeout(() => { process.exitCode = 1; browser.close() }, 35_000)
const trace = traceRecorder('destination-picker')
try {
  const context = await browser.newContext({viewport: {width: 1100, height: 700}})
  await trace.attach(context, 'destination-picker')
  await context.addCookies([{name: '_tijara_tides_key', value: config.cookie, url: config.url}])
  const page = await context.newPage()
  page.setDefaultTimeout(10_000)
  await page.goto(config.url + '/play')
  await page.locator('[data-phx-main].phx-connected').waitFor()
  await page.locator(`[phx-click=ship][phx-value-id="${config.ship}"]`).first().click()
  await page.evaluate(() => {
    window.pickerObservations = {emptyGrids: 0, clearedMarkers: 0, busy: 0, busyOverlays: 0, ready: false}
    new MutationObserver(records => {
      const state = window.pickerObservations
      const picker = document.getElementById('destination-picker')
      if (!picker) return
      const table = document.getElementById('destination-matrix')
      if (!table?.querySelector('tbody tr') || !table.querySelector('thead th[id]')) state.emptyGrids++
      if (state.ready && !table?.querySelector('.opportunity-disc')) state.clearedMarkers++
      if (state.ready && !document.getElementById('interaction-busy').hidden) state.busyOverlays++
      state.busy += records.filter(r => r.target.id === 'destination-matrix' &&
        r.attributeName === 'aria-busy' && r.oldValue === 'false').length
    }).observe(document.body, {subtree: true, childList: true, attributes: true, attributeOldValue: true})
  })
  await page.locator('#destination-picker-trigger').click()
  await page.locator('#interaction-busy:not([hidden])').waitFor()
  assert.ok(await page.locator('#destination-matrix tbody tr').count() > 0)
  await page.locator('#destination-matrix[aria-busy=false]').waitFor()
  await page.locator('#interaction-busy').waitFor({state: 'hidden'})
  assert.ok(await page.locator('#destination-matrix .opportunity-disc').count() > 0)
  const labels = page.locator('#destination-cargo-labels')
  assert.ok(await labels.isChecked())
  const labelledWidth = await page.locator('#destination-matrix').evaluate(el => el.offsetWidth)
  await mkdir('cover/browser-contracts', {recursive: true})
  await page.screenshot({path: 'cover/browser-contracts/destination-picker-labels.png'})
  await labels.uncheck()
  await page.locator('#destination-matrix.destination-matrix-icons').waitFor()
  assert.equal(await page.locator('.destination-cargo-label').count(), 0)
  const compactWidth = await page.locator('#destination-matrix').evaluate(el => el.offsetWidth)
  assert.ok(compactWidth < labelledWidth, JSON.stringify({labelledWidth, compactWidth}))
  const heading = page.locator('.destination-cargo-heading').first()
  const cargoName = await heading.getAttribute('aria-label')
  assert.ok(cargoName)
  assert.equal(await heading.getAttribute('title'), cargoName)
  await heading.hover()
  assert.ok(await heading.locator('.opportunity-tooltip').isVisible())
  await page.screenshot({path: 'cover/browser-contracts/destination-picker-icons.png'})
  await page.locator('#destination-picker-title').hover()
  await heading.focus()
  assert.ok(await heading.locator('.opportunity-tooltip').isVisible())
  await page.evaluate(() => {
    window.pickerObservations.ready = true
    window.pickerTable = document.getElementById('destination-matrix')
    window.pickerRows = [...window.pickerTable.querySelectorAll('tbody tr')]
    window.pickerScroll = document.querySelector('.destination-matrix-scroll')
    window.pickerScroll.scrollTop = 80
    window.pickerScroll.scrollLeft = 60
    window.pickerPosition = [window.pickerScroll.scrollTop, window.pickerScroll.scrollLeft]
    const button = window.pickerRows[1].querySelector('button')
    button.focus({preventScroll: true})
    window.pickerFocused = button
  })
  for (let tick = 1; tick <= 3; tick++) {
    console.log('PICKER_TICK')
    await page.waitForFunction(tick => window.pickerObservations.busy >= tick, tick)
    await page.locator('#destination-matrix[aria-busy=false]').waitFor()
    const state = await page.evaluate(() => ({
      ...window.pickerObservations,
      sameTable: window.pickerTable === document.getElementById('destination-matrix'),
      sameRows: window.pickerRows.every(row => row === document.getElementById(row.id)),
      sameFocus: document.activeElement === window.pickerFocused,
      position: [window.pickerScroll.scrollTop, window.pickerScroll.scrollLeft],
      expectedPosition: window.pickerPosition
    }))
    assert.equal(state.emptyGrids, 0, JSON.stringify(state))
    assert.equal(state.clearedMarkers, 0, JSON.stringify(state))
    assert.equal(state.busyOverlays, 0, JSON.stringify(state))
    assert.ok(state.sameTable && state.sameRows && state.sameFocus, JSON.stringify(state))
    assert.deepEqual(state.position, state.expectedPosition)
    assert.equal(await labels.isChecked(), false)
    assert.equal(await page.locator('.destination-cargo-label').count(), 0)
  }
  await labels.check()
  await page.locator('#destination-matrix:not(.destination-matrix-icons)').waitFor()
  assert.ok(await page.locator('.destination-cargo-label').count() > 0)
  assert.equal(await page.locator('#destination-matrix').evaluate(el => el.offsetWidth), labelledWidth)
  await labels.uncheck()
  await page.locator('#destination-matrix.destination-matrix-icons').waitFor()
  await page.locator('#destination-picker button[phx-click=destination-picker-close]').click()
  await page.locator('#destination-picker').waitFor({state: 'detached'})
  await page.locator('#destination-picker-trigger').click()
  await page.locator('#destination-matrix.destination-matrix-icons').waitFor()
  assert.equal(await labels.isChecked(), false)
  await page.locator('#destination-matrix button[phx-click=preview]').first().click()
  await page.locator('#destination-picker').waitFor({state: 'detached'})
  await trace.close(context)
  console.log('Destination picker browser contracts passed')
} catch (error) {
  await trace.save(error)
  throw error
} finally {
  clearTimeout(timer)
  await browser.close()
}
