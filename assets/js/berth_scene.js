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
  Group, Mesh, MeshStandardMaterial, MeshBasicMaterial, BoxGeometry, CylinderGeometry, Shape, ShapeGeometry, ExtrudeGeometry,
  TorusGeometry, Vector3,
} from "../vendor/three/three.module.js"
import {cargoSlots, cargoLayerHeight, dockCargoZ, cargoTransfer, shipPose, plimsollY, waterlineY,
  tankerManifold, loadingArmBase, loadingArmPose} from "./berth_motion"
export {berthSample} from "./berth_motion"

// All artwork is procedural. No model downloads, textures, or cargo data are needed.
export function createBerthScene(host, liquid) {
  const scene = new Scene()
  scene.background = new Color("#0b1729")
  const camera = new OrthographicCamera(-8, 8, 5, -5, 0.1, 80)
  camera.position.set(11, 10, 14)
  camera.lookAt(0, liquid ? 1.8 : 2.15, -0.6)
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
  const pipe = (parent, radius, color) => mesh(parent,
    new CylinderGeometry(radius, radius, 1, 10), color, 0, 0, 0)
  const start = new Vector3(), end = new Vector3(), direction = new Vector3(), up = new Vector3(0, 1, 0)
  const span = (object, a, b) => {
    start.fromArray(a); end.fromArray(b)
    direction.subVectors(end, start)
    object.position.copy(start).add(end).multiplyScalar(0.5)
    object.scale.y = direction.length()
    object.quaternion.setFromUnitVectors(up, direction.normalize())
  }
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
    const dockStock = new Group()
    dockStock.name = "dock-stock"
    scene.add(dockStock)
    for (let i = 0; i < 6; i++) {
      box(dockStock, 1.35, 0.65, 0.65, i % 2 ? "#407f83" : "#b38350", (liquid ? -5 : -6.5) + (i % 3) * 1.5,
        1.02 + Math.floor(i / 3) * 0.67, -4.3)
    }
    const ship = new Group()
    ship.name = "ship"
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
    crane.name = "cargo-crane"
    scene.add(crane)
    const craneLaneZ = -2.9
    // The gantry runs in a clear lane between the quay edge and pickup stacks.
    if (!liquid) {
      for (const offset of [-0.32, 0.32]) box(scene, 8, 0.06, 0.06, "#a8bdc8", 0.3, 0.73, craneLaneZ + offset)
    }
    for (const x of [-0.75, 1.35]) {
      box(crane, 0.2, 4.6, 0.25, "#d6a958", x, 3.0, craneLaneZ)
      box(crane, 0.65, 0.22, 1.0, "#253444", x, 0.86, craneLaneZ)
    }
    box(crane, 2.6, 0.3, 0.45, "#d6a958", 0.3, 5.25, craneLaneZ)
    box(crane, 0.3, 0.3, 6.4, "#e6bb68", 0.3, 5.25, -1.55)
    box(crane, 0.7, 0.55, 0.7, "#668c9f", 1.35, 4.6, craneLaneZ)
    const trolley = box(crane, 0.65, 0.2, 0.55, "#253444", 0.3, 5.05, dockCargoZ)
    const cable = box(crane, 0.035, 1, 0.035, "#a8bdc8", 0.3, 3.0, dockCargoZ)
    cable.name = "crane-cable"
    const cargo = box(scene, 1.05, 0.48, 1.4, "#c39556", 0.3, 0.89, dockCargoZ)
    cargo.name = "carried-container"
    // Containers approximate hold fullness rather than individual manifest lots.
    const deckCargo = new Group()
    deckCargo.name = "deck-cargo"
    ship.add(deckCargo)
    const dockCargo = new Group()
    dockCargo.name = "dock-cargo"
    scene.add(dockCargo)
    const deckBoxes = []
    const dockBoxes = []
    if (liquid) {
      for (let i = 0; i < 4; i++) {
        mesh(ship, new CylinderGeometry(0.6, 0.6, 0.5, 12), "#b4c8c8", -1.4 + i * 1.05, 1.3, 0)
      }
      // Deck header and branches make the shore connection visibly lead to tanks.
      span(pipe(ship, 0.055, "#738b99"), [-1.6, 1.65, -0.72], [2, 1.65, -0.72])
      for (const x of [-1.4, -0.35, 0.7, 1.75]) {
        span(pipe(ship, 0.045, "#738b99"), [x, 1.65, -0.72], [x, 1.65, 0])
        span(pipe(ship, 0.045, "#738b99"), [x, 1.65, 0], [x, 1.55, 0])
      }
      for (const x of [-1.5, 1.9]) box(ship, 0.045, 0.6, 0.045, "#475569", x, 1.35, -0.72)
      span(pipe(ship, 0.085, "#d6a958"), [0.3, 1.65, -0.72], [0.3, 1.75, -0.72])
      span(pipe(ship, 0.085, "#d6a958"), [0.3, 1.75, -0.72], tankerManifold)
      const flange = mesh(ship, new CylinderGeometry(0.16, 0.16, 0.07, 12),
        "#d6a958", ...tankerManifold)
      flange.rotation.x = Math.PI / 2
      box(ship, 0.85, 0.04, 0.44, "#475569", 0.3, 1.07, -0.68)
    } else {
      for (let layer = 0; layer < 3; layer++) {
        for (const x of cargoSlots) {
          deckBoxes.push(box(deckCargo, 1.05, 0.48, 1.4, "#c39556", x, 1.3 + layer * cargoLayerHeight, 0))
          dockBoxes.push(box(dockCargo, 1.05, 0.48, 1.4, "#c39556", x, 0.89 + layer * cargoLayerHeight, dockCargoZ))
        }
      }
    }
    const terminal = new Group()
    terminal.name = "oil-terminal"
    terminal.visible = liquid
    scene.add(terminal)
    // A compact shore tank and pump skid anchor the complete transfer circuit.
    mesh(terminal, new CylinderGeometry(1.08, 1.08, 0.15, 16), "#253444", 4.8, 0.725, -3.8)
    mesh(terminal, new CylinderGeometry(1, 1, 1.8, 16), "#b4c8c8", 4.8, 1.7, -3.8)
    mesh(terminal, new CylinderGeometry(0.12, 1.02, 0.24, 16), "#738b99", 4.8, 2.72, -3.8)
    mesh(terminal, new CylinderGeometry(0.06, 0.06, 0.22, 8), "#738b99", 4.8, 2.95, -3.8)
    mesh(terminal, new CylinderGeometry(1.008, 1.008, 0.1, 16), "#d6a958", 4.8, 1.45, -3.8)
    const outlet = mesh(terminal, new CylinderGeometry(0.14, 0.14, 0.08, 12),
      "#d6a958", 3.8, 1.08, -3.8)
    outlet.rotation.z = Math.PI / 2
    box(terminal, 1.3, 0.13, 1, "#253444", 3.05, 0.775, -4)
    box(terminal, 0.7, 0.08, 0.5, "#738b99", 3.1, 0.875, -3.8)
    const pump = mesh(terminal, new CylinderGeometry(0.2, 0.2, 0.4, 12),
      "#d6a958", 3.1, 1.08, -3.8)
    pump.rotation.z = Math.PI / 2
    const motor = mesh(terminal, new CylinderGeometry(0.18, 0.18, 0.48, 12),
      "#247b82", 3.1, 1.08, -4.19)
    motor.rotation.x = Math.PI / 2
    box(terminal, 0.4, 0.12, 0.45, "#738b99", 3.1, 0.89, -4.19)
    box(terminal, 0.3, 0.55, 0.28, "#738b99", 2.4, 1.115, -4.15)
    box(terminal, 0.65, 0.16, 0.65, "#253444", 0.3, 0.8, -2.7)
    span(pipe(terminal, 0.15, "#d6a958"), [0.3, 0.88, -2.7], loadingArmBase)
    span(pipe(terminal, 0.09, "#738b99"), [3.8, 1.08, -3.8], [3.3, 1.08, -3.8])
    span(pipe(terminal, 0.09, "#738b99"), [2.9, 1.08, -3.8], [2.7, 1.08, -3.8])
    span(pipe(terminal, 0.09, "#738b99"), [2.7, 1.08, -3.8], [2.7, 0.9, -3.8])
    span(pipe(terminal, 0.09, "#738b99"), [2.7, 0.9, -3.8], [0.3, 0.9, -3.8])
    span(pipe(terminal, 0.09, "#738b99"), [0.3, 0.9, -3.8], [0.3, 0.9, -2.7])
    const inboard = pipe(terminal, 0.09, "#d6a958")
    const outboard = pipe(terminal, 0.09, "#e6bb68")
    inboard.name = "loading-arm-inboard"
    outboard.name = "loading-arm-outboard"
    const balance = pipe(terminal, 0.045, "#738b99")
    const weight = box(terminal, 0.45, 0.38, 0.4, "#253444", 0, 0, 0)
    const swivels = Array.from({length: 3}, () => {
      const joint = mesh(terminal, new CylinderGeometry(0.16, 0.16, 0.23, 12), "#738b99", 0, 0, 0)
      joint.rotation.z = Math.PI / 2
      return joint
    })
    const coupling = mesh(terminal, new CylinderGeometry(0.16, 0.16, 0.09, 12), "#d6a958", 0, 0, 0)
    coupling.rotation.x = Math.PI / 2
    // A shore-side indicator shows pumping without depicting exposed liquid.
    const flow = mesh(terminal, new CylinderGeometry(0.065, 0.065, 0.03, 12), "#65d6bd", 2.4, 1.2, -3.995)
    flow.rotation.x = Math.PI / 2
    flow.name = "pumping-indicator"
    const flowMarkers = new Group()
    flowMarkers.name = "cargo-flow"
    flowMarkers.visible = false
    terminal.add(flowMarkers)
    // Opaque equipment carries a directional overlay, not visible liquid.
    const chevron = new Shape()
    chevron.moveTo(-0.1, -0.075)
    chevron.lineTo(0, 0.025)
    chevron.lineTo(0.1, -0.075)
    chevron.lineTo(0.1, -0.015)
    chevron.lineTo(0, 0.085)
    chevron.lineTo(-0.1, -0.015)
    chevron.closePath()
    const glyph = new ShapeGeometry(chevron)
    glyph.rotateY(Math.PI / 2)
    geometries.add(glyph)
    const glyphMaterial = new MeshBasicMaterial({color: "#65d6bd"})
    materials.set("flow-chevrons", glyphMaterial)
    const arrows = Array.from({length: 4}, () => {
      const arrow = new Mesh(glyph, glyphMaterial)
      arrow.scale.setScalar(1.4)
      flowMarkers.add(arrow)
      return arrow
    })
    crane.visible = !liquid
    host.appendChild(canvas)
    let completedDeck = null
    let completedVolume = null
    const landing = new Vector3()
    const manifold = new Vector3()
    let armWasConnected = false
    let armReturnStart = null
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
        staticCount = 4, cargoVolume, loadFraction = staticCount / 12, unloading, laden,
        reducedMotion = false, paused = false}) {
        deckCargo.visible = transferring || !!laden
        if (!transferring && cargoVolume !== completedVolume) completedDeck = null
        // Keep the completed layout across the server's docked patch. Independent
        // rounding of manifest volume must not make a deposited box disappear.
        deckBoxes.forEach((container, i) => { container.visible = completedDeck ? completedDeck[i] : i < staticCount })
        dockBoxes.forEach((container, i) => { container.visible = i < count })
        const pose = shipPose(seconds, loadFraction)
        ship.position.y = pose.y
        ship.rotation.x = pose.roll
        if (liquid) {
          const connected = transferring && progress < 1
          if (connected || reducedMotion) armReturnStart = null
          else if (armWasConnected) armReturnStart = seconds
          armWasConnected = connected
          const retraction = connected ? 0 : reducedMotion || armReturnStart === null ? 1 : (seconds - armReturnStart) / 1.5
          ship.updateMatrixWorld(true)
          ship.localToWorld(manifold.fromArray(tankerManifold))
          const arm = loadingArmPose(manifold.toArray(), retraction)
          span(inboard, arm.base, arm.elbow)
          span(outboard, arm.elbow, arm.tip)
          span(balance, arm.base, arm.counterweight)
          weight.position.fromArray(arm.counterweight)
          const joints = [arm.base, arm.elbow, arm.tip]
          joints.forEach((point, i) => swivels[i].position.fromArray(point))
          coupling.position.fromArray(arm.tip)
          coupling.rotation.x = Math.PI / 2 + (connected ? ship.rotation.x : 0)
          flowMarkers.visible = connected && handling
          const still = reducedMotion || paused
          arrows.forEach((arrow, i) => {
            arrow.visible = !still || i < 2
            if (!arrow.visible) return
            const phase = still ? (i + 0.5) / 2 : (i / 4 + seconds * 0.25) % 1
            const along = (unloading ? 1 - phase : phase) * 2
            const first = along < 1
            start.fromArray(first ? arm.base : arm.elbow)
            end.fromArray(first ? arm.elbow : arm.tip)
            arrow.position.copy(start).lerp(end, first ? along : along - 1)
            arrow.position.x += 0.18
            arrow.quaternion.copy((first ? inboard : outboard).quaternion)
            if (unloading) arrow.rotateX(Math.PI)
          })
        }
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
          const deckWeight = position.travel
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
          trolley.position.z = dockCargoZ
          cable.position.set(0.3, 3.75, dockCargoZ)
          cable.scale.y = 2.5
        }
        flow.scale.setScalar(1 + Math.sin(seconds * 4) * 0.2)
        renderer.render(scene, camera)
      },
      dispose,
    }
  } catch (error) { dispose(); throw error }
}
