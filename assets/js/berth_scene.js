/*!
 * Three.js 0.186.1
 * The MIT License
 *
 * Copyright © 2010-2026 three.js authors
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */
import {
  Scene, Color, OrthographicCamera, WebGLRenderer, HemisphereLight, DirectionalLight,
  Group, Mesh, MeshStandardMaterial, BoxGeometry, CylinderGeometry, Shape, ExtrudeGeometry,
  TorusGeometry, Vector3, CatmullRomCurve3, TubeGeometry,
} from "../vendor/three/three.module.js"
import {cargoSlots, cargoLayerHeight, cargoTransfer, shipPose, plimsollY, waterlineY} from "./berth_motion"
export {berthSample} from "./berth_motion"

// All artwork is procedural. No model downloads, textures, or cargo data are needed.
export function createBerthScene(host, liquid) {
  const scene = new Scene()
  scene.background = new Color("#0b1729")
  const camera = new OrthographicCamera(-8, 8, 5, -5, 0.1, 80)
  camera.position.set(11, 10, 14)
  camera.lookAt(0, 1.8, -0.6)
  const canvas = document.createElement("canvas")
  const context = canvas.getContext("webgl2", {antialias: true, alpha: false})
  if (!context) throw new Error("WebGL2 unavailable")
  const renderer = new WebGLRenderer({canvas, context, antialias: true})
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.5))
  renderer.domElement.style.cssText = "display:block;width:100%;height:100%"
  const geometries = new Set()
  const materials = new Map()
  let disposed = false
  const material = color => {
    if (!materials.has(color)) materials.set(color, new MeshStandardMaterial({color, roughness: 0.85, flatShading: true}))
    return materials.get(color)
  }
  const mesh = (parent, geometry, color, x, y, z) => {
    geometries.add(geometry)
    const object = new Mesh(geometry, material(color))
    object.position.set(x, y, z)
    parent.add(object)
    return object
  }
  const box = (parent, w, h, d, color, x, y, z) => mesh(parent, new BoxGeometry(w, h, d), color, x, y, z)
  const dispose = () => {
    if (disposed) return
    disposed = true
    geometries.forEach(geometry => geometry.dispose())
    materials.forEach(value => value.dispose())
    renderer.dispose()
    renderer.forceContextLoss()
    canvas.remove()
  }
  try {
    scene.add(new HemisphereLight(0xc2e8ef, 0x233047, 2.4))
    const sun = new DirectionalLight(0xffe4ad, 3)
    sun.position.set(-3, 9, 5)
    scene.add(sun)
    box(scene, 17, 0.25, 11, "#164456", 0, waterlineY - 0.125, 0)
    const ripples = []
    for (let i = 0; i < 16; i++) {
      ripples.push(box(scene, 0.4 + (i % 4) * 0.28, 0.015, 0.045, "#2a6573",
        -7 + (i % 8) * 1.85, -0.21, 2.6 + Math.floor(i / 8) * 1.8))
    }
    box(scene, 15, 0.9, 3.3, "#475569", 0, 0.2, -3.5)
    box(scene, 15, 0.12, 0.22, "#94a3b8", 0, 0.71, -1.95)
    for (let x = -6; x <= 6; x += 2) {
      box(scene, 0.5, 0.6, 0.2, "#172333", x, 0.1, -1.8)
      mesh(scene, new CylinderGeometry(0.09, 0.14, 0.28, 8), "#d6a958", x, 0.83, -2.2)
    }
    for (let i = 0; i < 6; i++) {
      box(scene, 1.35, 0.65, 0.65, i % 2 ? "#407f83" : "#b38350", -5 + (i % 3) * 1.5,
        1.02 + Math.floor(i / 3) * 0.67, -4.3)
    }
    const ship = new Group()
    ship.position.z = 0.55
    scene.add(ship)
    const outline = new Shape()
    outline.moveTo(-4.2, -0.95)
    outline.lineTo(2.9, -0.95)
    outline.lineTo(4.4, 0)
    outline.lineTo(2.9, 0.95)
    outline.lineTo(-4.2, 0.95)
    outline.lineTo(-4.4, 0.5)
    outline.lineTo(-4.4, -0.5)
    outline.closePath()
    const lowerHull = mesh(ship, new ExtrudeGeometry(outline, {depth: 0.62, bevelEnabled: true,
      bevelSize: 0.1, bevelThickness: 0.1, bevelSegments: 1, steps: 1}), "#a64e43", 0, 0.12, 0)
    lowerHull.rotation.x = Math.PI / 2
    const hull = mesh(ship, new ExtrudeGeometry(outline, {depth: 0.9, bevelEnabled: true,
      bevelSize: 0.12, bevelThickness: 0.12, bevelSegments: 1, steps: 1}), "#247b82", 0, 0.85, 0)
    hull.rotation.x = Math.PI / 2
    for (const z of [-1.075, 1.075]) {
      mesh(ship, new TorusGeometry(0.09, 0.014, 6, 20), "#e4edf0", 1.9, plimsollY, z)
      box(ship, 0.42, 0.022, 0.022, "#e4edf0", 1.9, plimsollY, z)
    }
    box(ship, 6.8, 0.12, 1.72, "#b4c8c8", -0.35, 0.98, 0)
    box(ship, 1.35, 1.1, 1.45, "#d5e3e6", -3.25, 1.6, 0)
    box(ship, 1.65, 0.55, 1.65, "#e4edf0", -3.1, 2.4, 0)
    box(ship, 1.35, 0.18, 1.7, "#29465b", -3.1, 2.37, 0)
    box(ship, 0.3, 0.8, 0.4, "#c39556", -3.6, 2.85, 0)
    box(ship, 0.08, 0.95, 0.08, "#a8bdc8", -2.8, 3.05, 0)
    for (const x of [-2.1, 2.8]) {
      for (const z of [-0.96, 0.96]) {
        const ring = mesh(ship, new TorusGeometry(0.15, 0.04, 4, 8), "#d6a958", x, 0.65, z)
        ring.rotation.y = Math.PI / 2
      }
    }
    const crane = new Group()
    scene.add(crane)
    for (const x of [-0.75, 1.35]) {
      box(crane, 0.2, 4.6, 0.25, "#d6a958", x, 3.0, -2.7)
      box(crane, 0.65, 0.22, 1.0, "#253444", x, 0.86, -2.7)
    }
    box(crane, 2.6, 0.3, 0.45, "#d6a958", 0.3, 5.25, -2.7)
    box(crane, 0.3, 0.3, 6.0, "#e6bb68", 0.3, 5.25, -1.35)
    box(crane, 0.7, 0.55, 0.7, "#668c9f", 1.0, 4.6, -2.7)
    const trolley = box(crane, 0.65, 0.2, 0.55, "#253444", 0.3, 5.05, -3.1)
    const cable = box(crane, 0.035, 1, 0.035, "#a8bdc8", 0.3, 3.0, -3.1)
    const cargo = box(scene, 1.05, 0.48, 1.4, "#c39556", 0.3, 0.89, -3.1)
    // Containers approximate hold fullness rather than individual manifest lots.
    const deckCargo = new Group()
    ship.add(deckCargo)
    const deckBoxes = []
    const dockBoxes = []
    if (liquid) {
      for (let i = 0; i < 4; i++) {
        mesh(ship, new CylinderGeometry(0.6, 0.6, 0.5, 12), "#b4c8c8", -1.4 + i * 1.05, 1.3, 0)
      }
    } else {
      for (let layer = 0; layer < 3; layer++) {
        for (const x of cargoSlots) {
          deckBoxes.push(box(deckCargo, 1.05, 0.48, 1.4, "#c39556", x, 1.3 + layer * cargoLayerHeight, 0))
          dockBoxes.push(box(scene, 1.05, 0.48, 1.4, "#c39556", x, 0.89 + layer * cargoLayerHeight, -3.1))
        }
      }
    }
    const hose = mesh(scene, new TubeGeometry(new CatmullRomCurve3([
      new Vector3(0.3, 0.8, -3), new Vector3(0.3, 1.7, -2),
      new Vector3(0.3, 1.8, -0.5), new Vector3(0.3, 1.2, 0.55),
    ]), 16, 0.09, 6, false), "#253444", 0, 0, 0)
    const flow = mesh(scene, new CylinderGeometry(0.15, 0.15, 0.32, 8), "#65d6bd", 0.3, 1.7, -1.2)
    crane.visible = !liquid
    hose.visible = liquid
    host.appendChild(canvas)
    let completedDeck = null
    let completedVolume = null
    const landing = new Vector3()
    return {
      canvas,
      resize(width, height) {
        if (!width || !height || disposed) return
        const aspect = width / height
        camera.left = -7.8
        camera.right = 7.8
        camera.top = 7.8 / aspect
        camera.bottom = -7.8 / aspect
        camera.updateProjectionMatrix()
        renderer.setSize(width, height, false)
      },
      draw({seconds, handling, transferring = handling, progress = 0, count = 4, baseCount = 0,
        staticCount = 4, cargoVolume, loadFraction = staticCount / 12, unloading, laden}) {
        deckCargo.visible = transferring || !!laden
        if (!transferring && cargoVolume !== completedVolume) completedDeck = null
        // Keep the completed layout across the server's docked patch. Independent
        // rounding of manifest volume must not make a deposited box disappear.
        deckBoxes.forEach((container, i) => { container.visible = completedDeck ? completedDeck[i] : i < staticCount })
        dockBoxes.forEach((container, i) => { container.visible = i < count })
        const pose = shipPose(seconds, loadFraction)
        ship.position.y = pose.y
        ship.rotation.x = pose.roll
        ripples.forEach((ripple, i) => { ripple.scale.x = 1 + Math.sin(seconds * 0.7 + i) * 0.2 })
        cargo.visible = handling && !liquid
        flow.visible = handling && liquid
        if (transferring && !liquid) {
          const position = cargoTransfer(progress, unloading, count, baseCount)
          completedDeck = Array.from({length: 12}, (_, i) => i < baseCount + (unloading ? 0 : count))
          completedVolume = cargoVolume
          deckBoxes.forEach((container, i) => { container.visible = position.deck[i] })
          dockBoxes.forEach((container, i) => { container.visible = position.dock[i] })
          // Match the moving ship at the landing point so release has no jump.
          ship.updateMatrixWorld(true)
          const deckY = 1.3 + position.deckLayer * cargoLayerHeight
          ship.localToWorld(landing.set(position.x, deckY, 0))
          const deckWeight = (position.z + 3.1) / 3.65
          const y = position.y + deckWeight * (landing.y - deckY)
          const z = position.z + deckWeight * (landing.z - 0.55)
          cargo.visible = position.carrying
          cargo.position.set(position.x, y, z)
          cargo.rotation.x = deckWeight * ship.rotation.x
          crane.position.x = position.x - 0.3
          trolley.position.z = z
          cable.position.set(0.3, (5 + y + 0.24) / 2, z)
          cable.scale.y = 5 - y - 0.24
        } else {
          crane.position.x = 0
          trolley.position.z = -3.1
          cable.position.set(0.3, 3.75, -3.1)
          cable.scale.y = 2.5
        }
        flow.scale.setScalar(1 + Math.sin(seconds * 4) * 0.2)
        renderer.render(scene, camera)
      },
      dispose,
    }
  } catch (error) { dispose(); throw error }
}
