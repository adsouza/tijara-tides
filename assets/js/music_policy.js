// Pure rules mapping the server's musical context onto the soundtrack manifest.

export function paletteOf(manifest, port) {
  return manifest.palettes.find(palette => palette.ports.includes(port))?.id ?? null
}

export function readContext(dataset) {
  if (dataset.context === 'port') return dataset.port ? {kind: 'port', port: dataset.port} : null
  if (dataset.context !== 'voyage') return null
  const progress = Number(dataset.progress)
  if (!dataset.origin || !dataset.destination || !Number.isFinite(progress)) return null
  return {kind: 'voyage', ship: dataset.ship, origin: dataset.origin, destination: dataset.destination,
    progress: Math.min(1, Math.max(0, progress))}
}

// Two contexts with one identity share music: ports by palette, voyages by
// their pair of origin and destination palettes.
export function identity(manifest, context) {
  if (!context) return null
  if (context.kind === 'port') {
    const palette = paletteOf(manifest, context.port)
    return palette && `port:${palette}`
  }
  const origin = paletteOf(manifest, context.origin)
  const destination = paletteOf(manifest, context.destination)
  return origin && destination ? `voyage:${origin}>${destination}` : null
}

// A voyage draws from the destination palette with probability equal to its
// progress, and avoids repeating the previous piece when the pool allows.
export function choosePiece(manifest, context, previous, random = Math.random) {
  if (!identity(manifest, context)) return null
  const id = context.kind === 'port' ? paletteOf(manifest, context.port)
    : random() < context.progress ? paletteOf(manifest, context.destination) : paletteOf(manifest, context.origin)
  const pool = manifest.palettes.find(palette => palette.id === id)[context.kind === 'port' ? 'port' : 'voyage']
  const candidates = pool.length > 1 ? pool.filter(slug => slug !== previous) : pool
  return candidates[Math.floor(random() * candidates.length)]
}
