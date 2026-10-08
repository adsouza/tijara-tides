import {test} from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import {Box3, Vector3} from '../../assets/vendor/three/three.module.js'

const motion = readFileSync(new URL('../../assets/js/berth_motion.js', import.meta.url), 'utf8')
const motionUrl = `data:text/javascript;base64,${Buffer.from(motion).toString('base64')}`
const {tankerManifold} = await import(motionUrl)
// Keep real Three.js geometry and transforms; replace only the GPU/DOM surface.
const renderer = `class WebGLRenderer {
  constructor({canvas}) { this.domElement = canvas }
  setPixelRatio() {} setSize() {} dispose() {} forceContextLoss() {}
  render(scene, camera) {
    this.domElement.scene = scene; this.domElement.camera = camera
    scene.updateMatrixWorld(true); camera.updateMatrixWorld(true)
  }
}`
const source = readFileSync(new URL('../../assets/js/berth_scene.js', import.meta.url), 'utf8')
  .replace('WebGLRenderer, ', '')
  .replace('"../vendor/three/three.module.js"', JSON.stringify(new URL('../../assets/vendor/three/three.module.js', import.meta.url).href))
  .replaceAll('"./berth_motion"', JSON.stringify(motionUrl))
  .replace('// All artwork is procedural.', `${renderer}\n// All artwork is procedural.`)
const {createBerthScene} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

function withScene(liquid, check) {
  const previousDocument = globalThis.document, previousWindow = globalThis.window
  globalThis.document = {createElement: () => ({style: {}, getContext: () => ({}), remove() {}})}
  globalThis.window = {devicePixelRatio: 1}
  const scene = createBerthScene({appendChild() {}}, liquid)
  try { check(scene) }
  finally {
    scene.dispose()
    globalThis.document = previousDocument
    globalThis.window = previousWindow
  }
}

const sample = {seconds: 0, handling: true, transferring: true, progress: 0,
  loadFraction: 0, unloading: false, laden: true}
const tip = scene => scene.getObjectByName('loading-arm-outboard').localToWorld(new Vector3(0, 0.5, 0))

test('freighter gantry clears cargo throughout loading and unloading all three layers', () => {
  withScene(false, view => {
    for (const unloading of [false, true]) {
      for (const count of [1, 4, 8, 12]) {
        for (const baseCount of new Set([0, 12 - count])) {
          for (let frame = 0; frame <= 240; frame++) {
            const progress = frame / 240
            view.draw({...sample, count, baseCount, unloading, seconds: progress * 30,
              progress, handling: progress < 1, loadFraction: (baseCount + count *
                (unloading ? 1 - progress : progress)) / 12})
            const scene = view.canvas.scene
            const containers = ['dock-stock', 'dock-cargo', 'deck-cargo']
              .flatMap(name => scene.getObjectByName(name).children)
              .concat(scene.getObjectByName('carried-container'))
              .filter(container => container.visible)
              .map(container => new Box3().setFromObject(container))
            // The cable intentionally meets the lifted container's top face.
            for (const part of scene.getObjectByName('cargo-crane').children) {
              if (part.name === 'crane-cable') continue
              const bounds = new Box3().setFromObject(part)
              assert.ok(containers.every(container => !bounds.intersectsBox(container)),
                `gantry intersects cargo: unloading=${unloading}, count=${count}, base=${baseCount}, frame=${frame}`)
            }
          }
        }
      }
    }
  })
})

test('rendered arm follows the actual ship transform and retracts after the deadline', () => {
  withScene(true, view => {
    for (const unloading of [false, true]) {
      for (let frame = 0; frame < 100; frame++) {
        const progress = frame / 100
        view.draw({...sample, unloading, seconds: progress * 30, progress,
          loadFraction: unloading ? 1 - progress : progress})
        const scene = view.canvas.scene
        const manifold = scene.getObjectByName('ship').localToWorld(new Vector3(...tankerManifold))
        assert.ok(tip(scene).distanceTo(manifold) < 1e-12, 'pipe end must meet the moving flange')
      }
      const end = {...sample, seconds: 30, progress: 1, handling: false, loadFraction: unloading ? 0 : 1}
      view.draw(end)
      const departing = tip(view.canvas.scene)
      const manifold = view.canvas.scene.getObjectByName('ship').localToWorld(new Vector3(...tankerManifold))
      assert.ok(departing.distanceTo(manifold) < 1e-12, 'disconnect must not jump')
      view.draw({...end, seconds: 30.75})
      const halfway = tip(view.canvas.scene)
      assert.ok(halfway.y > departing.y && halfway.z < departing.z, 'arm must lift and move toward shore')
      view.draw({...end, seconds: 31.5})
      const parked = tip(view.canvas.scene)
      assert.ok(parked.z < -1.95)
      view.draw({...end, seconds: 33, transferring: false, progress: 0})
      assert.ok(tip(view.canvas.scene).distanceTo(parked) < 1e-12, 'docked patch must preserve the parked pose')
    }
  })
})

test('reduced motion parks the completed arm immediately and idle berths show no pumping', () => {
  withScene(true, view => {
    view.draw({...sample, reducedMotion: true})
    assert.equal(view.canvas.scene.getObjectByName('pumping-indicator').visible, true)
    view.draw({...sample, handling: false, progress: 1, reducedMotion: true})
    assert.ok(tip(view.canvas.scene).z < -1.95)
    assert.equal(view.canvas.scene.getObjectByName('pumping-indicator').visible, false)
    view.draw({...sample, transferring: false, handling: false})
    assert.ok(tip(view.canvas.scene).z < -1.95)
  })
  withScene(false, view => {
    view.draw(sample)
    assert.equal(view.canvas.scene.getObjectByName('oil-terminal').visible, false)
  })
})

test('flow chevrons move and point toward the ship when loading and shore when unloading', () => {
  withScene(true, view => {
    for (const unloading of [false, true]) {
      view.draw({...sample, seconds: 0.8, unloading})
      const scene = view.canvas.scene
      const markers = scene.getObjectByName('cargo-flow')
      assert.equal(markers.visible, true)
      assert.equal(markers.children.filter(arrow => arrow.visible).length, 4)
      const arrow = markers.children[0]
      const before = arrow.position.clone()
      const base = new Vector3(0, -0.5, 0)
      const end = new Vector3(0, 0.5, 0)
      const pipe = scene.getObjectByName(unloading ? 'loading-arm-outboard' : 'loading-arm-inboard')
      const path = pipe.localToWorld(end).sub(pipe.localToWorld(base)).normalize()
      const facing = new Vector3(0, 1, 0).applyQuaternion(arrow.quaternion)
      assert.ok(facing.dot(path) * (unloading ? -1 : 1) > 0.999)
      view.draw({...sample, seconds: 0.9, unloading})
      assert.ok(arrow.position.clone().sub(before).dot(facing) > 0.05, 'chevron must travel in its pointed direction')
    }
    for (const inactive of [
      {transferring: false, handling: false}, // docked or queued
      {handling: false}, // stale snapshot
      {progress: 1, handling: false}, // handling deadline
    ]) {
      view.draw({...sample, ...inactive})
      assert.equal(view.canvas.scene.getObjectByName('cargo-flow').visible, false)
    }
  })
})

test('paused and reduced-motion scenes retain two stationary directional arrows', () => {
  withScene(true, view => {
    for (const mode of [{paused: true}, {reducedMotion: true}]) {
      for (const unloading of [false, true]) {
        view.draw({...sample, seconds: 1, unloading, ...mode})
        const markers = view.canvas.scene.getObjectByName('cargo-flow')
        const visible = markers.children.filter(arrow => arrow.visible)
        assert.equal(visible.length, 2)
        const positions = visible.map(arrow => arrow.position.clone())
        view.draw({...sample, seconds: 1.1, unloading, ...mode})
        // Ship motion can move a fixed marker slightly, but flow must not travel
        // along the rigid pipe. Its distance from the pipe midpoint stays fixed.
        visible.forEach((arrow, i) => {
          const pipe = view.canvas.scene.getObjectByName(unloading === (i === 0) ?
            'loading-arm-outboard' : 'loading-arm-inboard')
          assert.ok(Math.abs(arrow.position.y - pipe.position.y) < 1e-12)
          assert.ok(Math.abs(arrow.position.z - pipe.position.z) < 1e-12)
          assert.ok(arrow.position.distanceTo(positions[i]) < 0.01)
        })
      }
    }
  })
})

test('orbiting camera keeps the whole hull in shot while its view direction turns', () => {
  for (const liquid of [false, true]) {
    withScene(liquid, view => {
      view.resize(448, 256) // A typical sm:h-64 ship panel; wider strips crop the keel at rest.
      const directions = []
      for (let seconds = 0; seconds <= 48; seconds += 0.5) {
        view.draw({...sample, seconds})
        const {scene, camera} = view.canvas
        scene.getObjectByName('ship').traverse(part => {
          const points = part.geometry?.attributes.position
          for (let i = 0; i < (points?.count || 0); i++) {
            const point = part.localToWorld(new Vector3().fromBufferAttribute(points, i)).project(camera)
            assert.ok(Math.abs(point.x) < 1 && Math.abs(point.y) < 1, `hull leaves the frame at ${seconds}s`)
          }
        })
        directions.push(camera.getWorldDirection(new Vector3()))
      }
      assert.ok(Math.min(...directions.map(d => d.dot(directions[0]))) < Math.cos(0.25),
        'camera must arc around the ship rather than stay fixed')
    })
  }
})
