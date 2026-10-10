import {chromium, expect} from '@playwright/test'
import {readFile} from 'node:fs/promises'
import assert from 'node:assert/strict'
import {traceRecorder} from './support/trace.mjs'

const config = JSON.parse(await readFile(process.argv[2], 'utf8'))
const browser = await chromium.launch({headless: true})
const trace = traceRecorder('first-ship')
try {
  const context = await browser.newContext({viewport: {width: 900, height: 1200}})
  await trace.attach(context)
  await context.addCookies([{name: '_tijara_tides_key', value: config.cookie, url: config.url}])
  const page = await context.newPage()
  page.setDefaultTimeout(8_000)
  await page.goto(config.url + '/play')
  await page.locator('[data-phx-main].phx-connected').waitFor()
  const picker = page.locator('#first-ship-port-select')
  await expect(picker).toBeVisible()
  await expect(picker).toHaveValue('')
  await expect(page.locator('#shipyard')).toHaveCount(0)
  const options = await picker.locator('option').evaluateAll(nodes => nodes.map(node => ({value: node.value, text: node.textContent.trim()})))
  assert.deepEqual(options.map(option => option.value), ['', 'Guangzhou', 'Busan', 'Shanghai', 'Colombo', 'Abu Dhabi', 'Ho Chi Minh City', 'Mumbai', 'Rotterdam', 'Manila', 'Tokyo'])
  assert.equal(options[1].text, 'Guangzhou (Small freighter, Freighter, Bulk, Reefer, Tanker)')
  await picker.selectOption('Guangzhou')
  await expect(picker).toHaveCount(0)
  await expect(page.locator('#shipyard-purchase')).toBeVisible()
  await expect(page.locator('#shipyard-purchase button[name=class]')).toHaveCount(5)
  await expect(page.locator('#port-selector select')).toHaveValue('Guangzhou')

  await page.locator('.workspace-tabs [data-panel="2"]').click()
  await page.locator('#port-selector select').selectOption('Jakarta')
  await expect(page.locator('#shipyard')).toHaveCount(0)
  await page.locator('.workspace-tabs [data-panel="0"]').click()
  await expect(picker).toBeVisible()
  await expect(picker).toHaveValue('')
  await picker.selectOption('Tokyo')
  await expect(picker).toHaveCount(0)
  await expect(page.locator('#port-selector select')).toHaveValue('Tokyo')
  await expect(page.locator('#shipyard-purchase')).toBeVisible()
  await expect(page.locator('#shipyard-purchase button[name=class]')).toHaveCount(1)
  await expect(page.locator('#shipyard-purchase button[name=class]')).toHaveAttribute('value', 'bulk')
  await trace.close(context)
  console.log('First ship chooser contracts passed')
} catch (error) {
  await trace.save(error)
  throw error
} finally {
  await browser.close()
}
