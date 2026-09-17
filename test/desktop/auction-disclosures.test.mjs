import {test} from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
const source = readFileSync(new URL('../../assets/js/auction_disclosures.js', import.meta.url), 'utf8')
const {AuctionDisclosures} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

test('disclosure choices survive ticks, replacements, regrouping and removed groups', () => {
  let groups = [{id: 'cargo-whisky', open: true}, {id: 'cargo-jewelry', open: false}]
  const hook = {el: {querySelectorAll: () => groups}}
  AuctionDisclosures.mounted.call(hook)
  AuctionDisclosures.beforeUpdate.call(hook)
  groups = [{id: 'cargo-jewelry', open: true}, {id: 'cargo-whisky', open: false}, {id: 'cargo-new', open: false}]
  AuctionDisclosures.updated.call(hook)
  assert.deepEqual(groups.map(d => d.open), [false, true, false])
  groups[1].open = false // user collapses it; next tick must respect that too
  AuctionDisclosures.beforeUpdate.call(hook)
  groups = [{id: 'status-open', open: true}]
  AuctionDisclosures.updated.call(hook)
  assert.equal(groups[0].open, true)
  AuctionDisclosures.beforeUpdate.call(hook)
  groups = [{id: 'cargo-whisky', open: true}]
  AuctionDisclosures.updated.call(hook)
  assert.equal(groups[0].open, false)
})
