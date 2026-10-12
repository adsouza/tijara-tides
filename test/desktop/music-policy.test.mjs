import {test} from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
const source = readFileSync(new URL('../../assets/js/music_policy.js', import.meta.url), 'utf8')
const policy = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

const manifest = {
  palettes: [
    {id: 'east', ports: ['Shanghai', 'Busan'], port: ['east-port'], voyage: ['east-voyage']},
    {id: 'west', ports: ['Tangier', 'Valencia'], port: ['west-a', 'west-b'], voyage: ['west-voyage']},
  ],
}
const port = p => ({kind: 'port', port: p})
const voyage = (origin, destination, progress) => ({kind: 'voyage', ship: 's', origin, destination, progress})

test('ports in one palette share an identity; voyages are palette pairs', () => {
  assert.equal(policy.identity(manifest, port('Tangier')), policy.identity(manifest, port('Valencia')))
  assert.notEqual(policy.identity(manifest, port('Tangier')), policy.identity(manifest, port('Shanghai')))
  assert.equal(policy.identity(manifest, voyage('Busan', 'Tangier', 0.1)),
    policy.identity(manifest, voyage('Shanghai', 'Valencia', 0.9)))
  assert.equal(policy.identity(manifest, voyage('Busan', 'Tangier', 0)), 'voyage:east>west')
})

test('unknown ports have no identity and no piece', () => {
  assert.equal(policy.identity(manifest, port('Atlantis')), null)
  assert.equal(policy.identity(manifest, voyage('Busan', 'Atlantis', 0.5)), null)
  assert.equal(policy.identity(manifest, null), null)
  assert.equal(policy.choosePiece(manifest, port('Atlantis'), null, () => 0), null)
})

test('progress 0 always chooses the origin and progress 1 the destination', () => {
  for (const r of [0, 0.25, 0.5, 0.999]) {
    assert.equal(policy.choosePiece(manifest, voyage('Busan', 'Tangier', 0), null, () => r), 'east-voyage')
    assert.equal(policy.choosePiece(manifest, voyage('Busan', 'Tangier', 1), null, () => r), 'west-voyage')
  }
  assert.equal(policy.choosePiece(manifest, voyage('Busan', 'Shanghai', 0.5), null, () => 0.9), 'east-voyage')
})

test('no immediate repeat when the pool offers another piece', () => {
  for (const r of [0, 0.5, 0.99]) assert.equal(policy.choosePiece(manifest, port('Tangier'), 'west-a', () => r), 'west-b')
  assert.equal(policy.choosePiece(manifest, port('Busan'), 'east-port', () => 0.5), 'east-port')
})

test('reads the server context from data attributes', () => {
  assert.deepEqual(policy.readContext({context: 'port', port: 'Tangier'}), port('Tangier'))
  assert.deepEqual(policy.readContext({context: 'voyage', ship: 's', origin: 'Busan', destination: 'Tangier', progress: '1.5'}),
    voyage('Busan', 'Tangier', 1))
  assert.equal(policy.readContext({context: 'voyage', origin: 'Busan', progress: 'x'}), null)
  assert.equal(policy.readContext({}), null)
})
