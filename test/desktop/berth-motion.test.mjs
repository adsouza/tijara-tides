import {test} from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
const source = readFileSync(new URL('../../assets/js/berth_motion.js', import.meta.url), 'utf8')
const {berthSample, cargoPosition, cargoTransfer, cargoCount} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)
const state = {clock: 120_000, start: 120_000, complete: 125_000, status: 'loading',
  queued: false, liquid: false, capacity: 900_000, volume: 450_000, cargoVolume: 600_000}

// Independently check that a stacked box is supported by the box below it.
function supported(boxes) {
  boxes.forEach((occupied, i) => { if (occupied && i >= 4) assert.equal(boxes[i - 4], true) })
}

test('handling never starts in a queue or extends beyond the committed deadline', () => {
  assert.equal(berthSample(state, 0).handling, true)
  assert.equal(berthSample(state, 4999).handling, true)
  assert.equal(berthSample(state, 5000).handling, false)
  assert.equal(berthSample({...state, queued: true}, 0).transferring, false)
  for (const status of ['docked', 'sailing', undefined]) {
    assert.equal(berthSample({...state, status}, 0).transferring, false)
  }
  assert.equal(berthSample({...state, complete: null}, 0).transferring, false)
})

test('stalled snapshots bound animation while preserving the in-progress stack', () => {
  const long = {...state, clock: 0, start: 0, complete: 60_000, status: 'unloading', liquid: true}
  assert.equal(berthSample(long, 9999).handling, true)
  const stopped = berthSample(long, 10_000)
  assert.equal(stopped.handling, false)
  assert.equal(stopped.transferring, true)
  assert.equal(stopped.fresh, false)
  assert.equal(stopped.progress, 1 / 6)
  assert.equal(berthSample(long, 90_000).seconds, 10)
  assert.equal(berthSample(long, -1).seconds, 0)
  assert.equal(berthSample(long, 0).liquid, true)
  assert.equal(berthSample(long, 0).unloading, true)
})

test('box count scales with transferred volume, not total manifest or operation duration', () => {
  for (const [volume, count] of [[0, 0], [1, 1], [225_000, 3], [450_000, 6], [900_000, 12], [2_000_000, 12]]) {
    assert.equal(cargoCount(volume, 900_000), count)
  }
  assert.equal(cargoCount(null, 900_000), 1)
  assert.equal(cargoCount(100, 0), 0)
  const loading = berthSample(state, 0)
  assert.equal(loading.count, 6)
  assert.equal(loading.baseCount, 2)
  const unloading = berthSample({...state, status: 'unloading', cargoVolume: 150_000}, 0)
  assert.equal(unloading.count, loading.count)
  assert.equal(unloading.baseCount, loading.baseCount)
  assert.equal(berthSample({...state, complete: 300_000}, 0).count, 6)
  const legacyFull = berthSample({...state, volume: null, cargoVolume: 900_000}, 0)
  assert.equal(legacyFull.count, 1)
  assert.equal(legacyFull.baseCount, 11)
})

test('the last container lands at the actual deadline for short, long and resumed operations', () => {
  for (const duration of [1000, 5000, 32_000, 180_000]) {
    for (const count of [1, 3, 6, 12]) {
      for (const unloading of [false, true]) {
        const job = {...state, start: 100_000, complete: 100_000 + duration,
          status: unloading ? 'unloading' : 'loading', volume: count * 75_000, cargoVolume: unloading ? 0 : count * 75_000}
        const sample = clock => berthSample({...job, clock}, 0)
        const before = sample(job.complete - 1)
        assert.equal(before.handling, true)
        const moving = cargoTransfer(before.progress, unloading, before.count)
        assert.equal(moving.carrying, true)
        assert.equal((unloading ? moving.dock : moving.deck).filter(Boolean).length, count - 1)
        const end = sample(job.complete)
        const placed = cargoTransfer(end.progress, unloading, end.count)
        assert.equal(end.handling, false)
        assert.equal(end.progress, 1)
        assert.equal(placed.carrying, false)
        assert.equal((unloading ? placed.dock : placed.deck).filter(Boolean).length, count)
        assert.equal((unloading ? placed.deck : placed.dock).filter(Boolean).length, 0)
        const halfway = sample(job.start + duration / 2)
        assert.equal(halfway.progress, 0.5, 'a fresh view at the same world clock must show the same progress')
        assert.equal(cargoTransfer(halfway.progress, unloading, count).deck.length, 12)
      }
    }
  }
})

test('three-layer transfers retain existing cargo, remain supported, and conserve boxes', () => {
  for (let count = 1; count <= 12; count++) {
    for (const baseCount of [0, 12 - count]) {
      for (const unloading of [false, true]) {
        for (let frame = 0; frame <= 200; frame++) {
          const position = cargoTransfer(frame / 200, unloading, count, baseCount)
          assert.equal(position.deck.length, 12)
          assert.equal(position.dock.length, 12)
          assert.deepEqual(position.deck.slice(0, baseCount), Array(baseCount).fill(true))
          assert.equal(position.deck.filter(Boolean).length + position.dock.filter(Boolean).length + Number(position.carrying), baseCount + count)
          supported(position.deck)
          supported(position.dock)
          assert.ok(position.y >= 0.89 && position.y <= 4.05)
          assert.ok(position.deckLayer < 3)
        }
      }
    }
  }
  const empty = cargoTransfer(0, false, 0, 4)
  assert.equal(empty.carrying, false)
  assert.equal(empty.deck.filter(Boolean).length, 4)
})

test('cargo lifts clear of all layers and releases without changing its landing height', () => {
  assert.equal(cargoPosition(0, false).z, -3.1)
  assert.equal(cargoPosition(5.2, false, 2, 2).y, 2.3)
  assert.equal(cargoPosition(0, true, 2, 2).y, 2.3)
  assert.ok(Math.abs(cargoPosition(5.2, true, 2, 2).y - 1.89) < 1e-9)
  assert.equal(cargoPosition(1.6, false, 2, 2).y, 4.05)
  assert.equal(cargoPosition(1.6, false).z, -3.1)
  assert.equal(cargoPosition(8, false).carrying, false)
})
