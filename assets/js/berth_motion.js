const clamp = n => Math.max(0, Math.min(1, n))
const ease = n => { const t = clamp(n); return t * t * (3 - 2 * t) }
export const cargoSlots = [-1.6, -0.48, 0.64, 1.76]
export const cargoLayerHeight = 0.5

// Twelve illustrative boxes represent a full hold, rounded up for a nonempty load.
export function cargoCount(volume, capacity) {
  if (volume === null) return 1 // Unknown volume on a legacy in-progress operation.
  if (!(capacity > 0) || !(volume > 0)) return 0
  return Math.min(12, Math.ceil(volume / capacity * 12))
}

// Interpolate only a fresh committed snapshot. The server still owns completion.
export function berthSample(state, elapsedMs) {
  const elapsed = Math.max(0, Math.min(elapsedMs, 10_000))
  const now = state.clock + elapsed
  const transferring = !state.queued && ["loading", "unloading"].includes(state.status) &&
    Number.isFinite(state.complete) && state.complete > state.start
  const unloading = state.status === "unloading"
  // The manifest already includes purchases and excludes sales when handling begins.
  const baseVolume = unloading ? state.cargoVolume : Math.max(0, state.cargoVolume - (state.volume || 0))
  const baseCount = Math.min(state.volume === null || state.volume > 0 ? 11 : 12,
    Math.max(baseVolume > 0 ? 1 : 0, Math.floor(baseVolume / state.capacity * 12)))
  const count = Math.min(12 - baseCount, cargoCount(state.volume, state.capacity))
  return {
    seconds: now / 1000,
    fresh: elapsedMs < 10_000,
    transferring,
    handling: transferring && state.complete > now && elapsedMs < 10_000,
    progress: transferring ? clamp((now - state.start) / (state.complete - state.start)) : 0,
    count,
    baseCount,
    staticCount: cargoCount(state.cargoVolume, state.capacity),
    cargoVolume: state.cargoVolume,
    unloading,
    liquid: state.liquid,
    laden: state.laden,
  }
}

export function cargoPosition(seconds, unloading, deckLayer = 0, dockLayer = 0) {
  // Lift clear of every stack, traverse, lower, release, and return the empty hook.
  const cycle = clamp(seconds / 8)
  const returning = cycle >= 0.65
  let travel = returning ? 1 - ease((cycle - 0.8) / 0.15) : ease((cycle - 0.2) / 0.25)
  const lift = cycle < 0.2 ? ease(cycle / 0.2) : cycle < 0.45 ? 1 :
    cycle < 0.65 ? 1 - ease((cycle - 0.45) / 0.2) : cycle < 0.8 ? ease((cycle - 0.65) / 0.15) :
    1 - ease((cycle - 0.95) / 0.05)
  if (unloading) travel = 1 - travel
  const deckY = 1.3 + deckLayer * cargoLayerHeight
  const dockY = 0.89 + dockLayer * cargoLayerHeight
  const low = dockY + travel * (deckY - dockY)
  return {z: -3.1 + travel * 3.65, y: low + lift * (4.05 - low), carrying: !returning, travel}
}

// The last release, rather than an empty return trip, coincides with progress=1.
// Stack bottom-up, take top-down, and keep cargo outside this operation in place.
export function cargoTransfer(progress, unloading, count, baseCount = 0) {
  const time = clamp(progress) * (Math.max(1, count) - 1 + 0.65)
  const finished = progress >= 1 || count === 0
  const index = Math.min(Math.max(0, count - 1), Math.floor(time))
  const phase = finished ? 0.65 : time - index
  const deckIndex = baseCount + (unloading ? count - 1 - index : index)
  const dockIndex = unloading ? index : count - 1 - index
  const deckLayer = Math.floor(deckIndex / cargoSlots.length)
  const dockLayer = Math.floor(dockIndex / cargoSlots.length)
  const position = cargoPosition(phase * 8, unloading, deckLayer, dockLayer)
  const carrying = !finished && position.carrying
  const completed = index + Number(finished || !position.carrying)
  const deckX = cargoSlots[Math.max(0, deckIndex) % cargoSlots.length]
  const dockX = cargoSlots[Math.max(0, dockIndex) % cargoSlots.length]
  const nextIndex = Math.min(index + 1, Math.max(0, count - 1))
  const nextSourceIndex = unloading ? baseCount + count - 1 - nextIndex : count - 1 - nextIndex
  const nextSourceX = cargoSlots[Math.max(0, nextSourceIndex) % cargoSlots.length]
  const returning = !position.carrying && !finished
  const travel = returning ? ease((phase - 0.8) / 0.15) : position.travel
  const x = returning ? (unloading ? dockX : deckX) * (1 - travel) + nextSourceX * travel :
    dockX + (deckX - dockX) * travel
  if (returning && phase >= 0.95) {
    const nextSourceY = (unloading ? 1.3 : 0.89) + Math.floor(nextSourceIndex / cargoSlots.length) * cargoLayerHeight
    position.y = 4.05 + (nextSourceY - 4.05) * ease((phase - 0.95) / 0.05)
  }
  const deck = Array(12).fill(false)
  const dock = Array(12).fill(false)
  for (let i = 0; i < baseCount; i++) deck[i] = true
  for (let i = 0; i < count; i++) {
    const source = i >= completed && !(i === index && carrying)
    const destination = i < completed
    deck[baseCount + (unloading ? count - 1 - i : i)] = unloading ? source : destination
    dock[unloading ? i : count - 1 - i] = unloading ? destination : source
  }
  return {...position, x, carrying, deckLayer, deck, dock}
}
