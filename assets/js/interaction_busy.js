// LiveView sets loading refs before sending an event and removes them after its
// reply. Watching them also works while the server cannot send a busy message.
export function installInteractionBusy(doc = document, options = {}) {
  const overlay = doc.getElementById('interaction-busy')
  if (!overlay) return () => {}
  const schedule = options.setTimeout || setTimeout
  const cancel = options.clearTimeout || clearTimeout
  const Observer = options.MutationObserver || MutationObserver
  let timer = null
  let disposed = false
  let busyRoot = null

  const pendingRoot = () => {
    const root = doc.querySelector('[data-phx-main]')
    return root?.classList.contains('phx-connected') &&
      root.querySelector('[data-phx-ref-loading]') ? root : null
  }
  const hide = () => {
    if (timer !== null) cancel(timer)
    timer = null
    overlay.hidden = true
    busyRoot?.removeAttribute('aria-busy')
    busyRoot = null
  }
  const refresh = () => {
    if (disposed) return
    const root = pendingRoot()
    if (!root) return hide()
    if (!overlay.hidden || timer !== null) return
    timer = schedule(() => {
      timer = null
      busyRoot = pendingRoot()
      if (!busyRoot || disposed) return
      overlay.hidden = false
      busyRoot.setAttribute('aria-busy', 'true')
    }, 300)
  }
  const observer = new Observer(refresh)
  observer.observe(doc.body, {
    subtree: true, childList: true, attributes: true,
    attributeFilter: ['data-phx-ref-loading', 'class'],
  })
  refresh()
  return () => { disposed = true; observer.disconnect(); hide() }
}
