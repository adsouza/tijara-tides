import {chromium} from '@playwright/test'
import {readFile} from 'node:fs/promises'
import assert from 'node:assert/strict'
import {traceRecorder} from './support/trace.mjs'

// Visitors and players both see the workspace fit one viewport, with each panel
// scrolling on its own rather than the page growing to the tallest panel.
const config = JSON.parse(await readFile(process.argv[2], 'utf8'))
const browser = await chromium.launch({headless: true})
const timer = setTimeout(() => { process.exitCode = 1; browser.close() }, 30_000)
const trace = traceRecorder('layout')
try {
  for (const [who, cookie] of [['visitor', null], ['player', config.cookie]]) {
    for (const viewport of [{width: 1100, height: 600}, {width: 375, height: 700}]) {
      const label = `${who} ${viewport.width}x${viewport.height}`
      const context = await browser.newContext({viewport})
      await trace.attach(context, `layout-${who}-${viewport.width}`)
      if (cookie) await context.addCookies([{name: '_tijara_tides_key', value: cookie, url: config.url}])
      const page = await context.newPage()
      page.setDefaultTimeout(8_000)
      await page.goto(config.url + '/play')
      await page.locator('[data-phx-main].phx-connected').waitFor()
      assert.equal(await page.locator('#game-screen.game-screen-playing').count(), who === 'player' ? 1 : 0, label)
      await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight))
      const layout = await page.evaluate(() => ({
        workspace: document.getElementById('game-workspace').getBoundingClientRect().toJSON(),
        panels: [...document.querySelectorAll('.panel-content')].map(p => ({
          id: p.parentElement.id, client: p.clientHeight, scroll: p.scrollHeight
        }))
      }))
      assert.ok(layout.workspace.top >= 0 && layout.workspace.bottom <= viewport.height,
        `${label}: workspace must fit the viewport ${JSON.stringify(layout.workspace)}`)
      assert.ok(layout.panels.every(p => p.client > 200), `${label}: panels must stay usable ${JSON.stringify(layout.panels)}`)
      assert.ok(layout.panels.some(p => p.scroll > p.client), `${label}: some panel must scroll ${JSON.stringify(layout.panels)}`)
      await trace.close(context)
    }
  }
  // A visitor's page scrolls past the onboarding cards, so a panel with nothing
  // left to scroll must hand the wheel to the page rather than swallow it.
  const viewport = {width: 1600, height: 1400}
  const context = await browser.newContext({viewport})
  await trace.attach(context, 'layout-visitor-wheel')
  const page = await context.newPage()
  page.setDefaultTimeout(8_000)
  await page.goto(config.url + '/play')
  await page.locator('[data-phx-main].phx-connected').waitFor()
  const panels = await page.evaluate(() =>
    [...document.querySelectorAll('.panel-content')].map(p => ({id: p.parentElement.id, fits: p.scrollHeight <= p.clientHeight})))
  assert.ok(panels.some(p => p.fits), `a panel must fit to exercise wheel chaining ${JSON.stringify(panels)}`)
  for (const {id} of panels) {
    await page.evaluate(() => { window.scrollTo(0, 0); document.querySelectorAll('.panel-content').forEach(p => { p.scrollTop = 0 }) })
    const box = await page.locator(`#${id} .panel-content`).boundingBox()
    await page.mouse.move(box.x + box.width / 2, box.y + 20)
    await page.mouse.wheel(0, 300)
    await page.waitForFunction(id => window.scrollY > 0 || document.querySelector(`#${id} .panel-content`).scrollTop > 0, id)
      .catch(() => assert.fail(`wheel over #${id} must scroll the panel or the page ${JSON.stringify(panels)}`))
  }
  await trace.close(context)
  console.log('Workspace layout contracts passed')
} catch (error) {
  await trace.save(error)
  throw error
} finally {
  clearTimeout(timer)
  await browser.close()
}
