import {chromium, expect} from '@playwright/test';
import {readFile, mkdir, writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';

const config = JSON.parse(await readFile(process.argv[2], 'utf8'));
const browser = await chromium.launch({headless: true});
const timer = setTimeout(() => { console.error('Browser workflow exceeded 60 seconds'); process.exitCode = 1; browser.close(); }, 60_000);
const records = [];
const changes = [];
let submissions = 0;
try {
  const context = await browser.newContext({viewport: {width: 900, height: 1200}});
  await context.addCookies([{name: '_tijara_tides_key', value: config.cookie, url: config.url}]);
  const page = await context.newPage();
  page.setDefaultTimeout(8_000);
  page.on('websocket', socket => socket.on('framesent', ({payload}) => {
    try {
      const frame = JSON.parse(payload);
      if (Array.isArray(frame) && frame[3] === 'event' && frame[4]?.type === 'form') {
        const event = frame[4].event;
        if (event === 'edit-instruction') changes.push({event, fields: [...new URLSearchParams(frame[4].value).keys()].sort()});
        if (['add-instruction', 'exchange'].includes(event)) {
          const fields = [...new URLSearchParams(frame[4].value).keys()].sort();
          if (!fields.includes('_target')) {
            submissions++;
            assert.ok(submissions <= 12, 'command submission budget exceeded');
            records.push({event, fields});
          }
        }
      }
    } catch (error) { if (error.name === 'AssertionError') throw error; }
  }));
  await page.goto(config.url + '/play');
  await page.locator('[data-phx-main].phx-connected').waitFor();
  // Expand disclosures through their actual controls. Tabs are actual workspace buttons.
  if (config.workflow === 'instructions') {
    await page.locator('[data-panel="1"]').click();
    await page.locator(`[phx-click="ship"][phx-value-id="${config.ship}"]`).first().click();
    await page.locator('#destination-picker-trigger').click();
    await page.locator('#destination-picker button[phx-value-destination="Singapore"]').click();
    const form = page.locator(`[id="instruction-form-${config.ship}"]`);
    await page.locator(`[id="instructions-${config.ship}"] > summary`).click();
    await form.locator('[name=side]').selectOption('sell');
    await form.locator('[name=good]').selectOption('lumber');
    await form.locator('[name=quantity]').fill('1');
    assert.equal(await form.locator('[name=budget]').isDisabled(), true);
    assert.equal(await form.locator('[name=freshness_minutes]').isDisabled(), true);
    const request = await form.locator('[name=request_id]').inputValue();
    await form.locator('button[type=submit],button:not([type])').last().click();
    await page.waitForFunction(({ship, request}) => document.querySelector(`[id="instruction-form-${ship}"] input[name=request_id]`)?.value !== request, {ship: config.ship, request});
    const onward = page.locator('form[phx-submit="instruction-onward"]').last();
    await onward.locator('[name=onward]').selectOption('Jakarta');
    const onwardRequest = await onward.locator('[name=request_id]').inputValue();
    await onward.locator('button:not([type]),button[type=submit]').last().click();
    await page.waitForFunction(request => document.querySelector('form[phx-submit="instruction-onward"] input[name=request_id]')?.value !== request, onwardRequest);
    await form.locator('[name=side]').selectOption('buy');
    await expect(form.locator('[name=budget]')).toBeEnabled();
    await form.locator('[name=good]').selectOption('aluminium_scrap');
    await form.locator('[name=quantity]').fill('1');
    await form.locator('[name=limit]').fill('10000');
    await form.locator('[name=budget]').fill('10000');
    const request2 = await form.locator('[name=request_id]').inputValue();
    await form.locator('button[type=submit],button:not([type])').last().click();
    await page.waitForFunction(({ship, request}) => document.querySelector(`[id="instruction-form-${ship}"] input[name=request_id]`)?.value !== request, {ship: config.ship, request: request2});
    assert.equal(records.length, 2);
    assert.ok(changes.some(r => r.fields.includes('_unused_expiry_minutes')), 'untouched expiry change metadata missing');
    assert.ok(records[0].fields.includes('expiry_minutes'), 'blank expiry omitted');
    assert.ok(!records[0].fields.includes('budget'), 'disabled budget serialized');
    assert.ok(records[1].fields.includes('freshness_minutes'), 'blank freshness omitted');
  } else {
    await page.locator('[data-panel="0"]').click();
    await page.locator('#exchange-panel > summary').click();
    await page.locator('#exchange-good-selector select').selectOption('lumber');
    for (const side of ['buy', 'sell']) {
      // Match the good too: until the selection patch lands, the previous good's form is still present.
      const form = page.locator(`form[phx-submit=exchange]:has(input[name=action][value=exchange_place]):has(input[name=good][value=lumber]):has(input[name=side][value=${side}])`);
      await form.locator('[name=quantity]').fill('2');
      await form.locator('[name=price]').fill(side === 'buy' ? '1' : '10000');
      const request = await form.locator('[name=request_id]').inputValue();
      await form.locator('button').click();
      await page.waitForFunction(({side, request}) => document.querySelector(`form[phx-submit=exchange]:has(input[name=side][value=${side}]) input[name=request_id]`)?.value !== request, {side, request});
    }
    await page.locator('#exchange-own-orders > summary').click();
    const amend = page.locator('form[id^="exchange-amend-"]').first();
    await amend.locator('[name=quantity]').fill('1');
    const request = await amend.locator('[name=request_id]').inputValue();
    await amend.locator('button:not([type]),button[type=submit]').click();
    await page.waitForFunction(request => document.querySelector('form[id^="exchange-amend-"] input[name=request_id]')?.value !== request, request);
    for (let remaining = 2; remaining > 0; remaining--) {
      const disclosure = page.locator('#exchange-own-orders');
      if (!await disclosure.evaluate(el => el.open)) await disclosure.locator(':scope > summary').click();
      await page.waitForFunction(() => !document.querySelector('.phx-submit-loading,.phx-click-loading'));
      await page.locator('[phx-value-action="exchange_cancel"]').first().click({force: true});
      await page.waitForFunction(remaining => document.querySelectorAll('[phx-value-action="exchange_cancel"]').length === remaining - 1, remaining);
    }
    assert.equal(records.length, 3);
    assert.ok(records[0].fields.includes('minutes'), 'untouched expiry omitted');
    assert.ok(!records[2].fields.includes('minutes'), 'disabled amendment expiry serialized');
  }
  await mkdir('cover/browser-contracts', {recursive: true});
  await writeFile(`cover/browser-contracts/${config.workflow}.json`, JSON.stringify({schema: 1, runner: 'playwright-1.63.0', records, changes}, null, 2));
  await context.close();
} finally {
  clearTimeout(timer);
  await browser.close();
}
