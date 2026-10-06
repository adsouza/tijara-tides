// Failure evidence for the Chromium contracts. Every context records a Playwright
// trace and a page-side step log; both are written to cover/browser-contracts/
// only when the contract fails, and discarded otherwise.
//
// TIJARA_BROWSER_TRACE opts into mutation tracing, which patches DOM APIs and is
// therefore off by default. Entries are separated by `;`:
//   <selector>@<attribute>   record writes with stacks, e.g. [data-berth-toggle]@hidden
//   media=<query>            record change events, e.g. media=(prefers-reduced-motion: reduce)
import {mkdir, writeFile} from 'node:fs/promises'

const dir = 'cover/browser-contracts'

export function parseSpec(text) {
  const watch = []
  const media = []
  for (const entry of text.split(';').map(part => part.trim()).filter(Boolean)) {
    if (entry.startsWith('media=')) {
      media.push(entry.slice('media='.length))
      continue
    }
    const at = entry.lastIndexOf('@')
    if (at <= 0 || at === entry.length - 1) throw new Error(`TIJARA_BROWSER_TRACE entry needs selector@attribute: ${entry}`)
    watch.push({selector: entry.slice(0, at), attribute: entry.slice(at + 1).toLowerCase()})
  }
  return {watch, media}
}

// Runs in the page before any application script.
function pageTrace({watch, media}) {
  const log = window.__tijaraTrace = []
  const now = () => Math.round(performance.now())
  window.__tijaraStep = step => log.push({t: now(), step})
  if (!watch.length && !media.length) return
  // Init-script frames are anonymous; keep the application's callers.
  const stack = () => new Error().stack.split('\n').slice(1).map(line => line.trim())
    .filter(line => !line.includes('<anonymous>')).slice(0, 6).join(' < ')
  const name = el => el.id ? `#${el.id}` :
    `${el.tagName.toLowerCase()} in #${el.parentElement?.closest('[id]')?.id ?? 'document'}`
  const watched = (el, attribute) => el instanceof Element &&
    watch.some(w => w.attribute === attribute && el.matches(w.selector))
  const attributes = [...new Set(watch.map(w => w.attribute))]
  const write = (el, attribute, via, value) => {
    if (watched(el, attribute)) log.push({t: now(), write: attribute, target: name(el), via, value, stack: stack()})
  }
  // Reflected properties such as hidden or ariaPressed bypass setAttribute.
  for (const attribute of attributes) {
    const property = attribute.replace(/-([a-z])/g, (_, c) => c.toUpperCase())
    for (const type of [Element, HTMLElement, HTMLButtonElement, HTMLInputElement, HTMLSelectElement,
      HTMLTextAreaElement, HTMLFormElement, HTMLDetailsElement]) {
      const descriptor = Object.getOwnPropertyDescriptor(type.prototype, property)
      if (!descriptor?.set) continue
      Object.defineProperty(type.prototype, property, {...descriptor, set(value) {
        write(this, attribute, property, value)
        descriptor.set.call(this, value)
      }})
    }
  }
  for (const method of ['setAttribute', 'removeAttribute', 'toggleAttribute', 'setAttributeNS', 'removeAttributeNS']) {
    const original = Element.prototype[method]
    Element.prototype[method] = function(...args) {
      const attribute = String(method.endsWith('NS') ? args[1] : args[0]).toLowerCase()
      write(this, attribute, method, method.startsWith('remove') ? null : args.at(-1))
      return original.apply(this, args)
    }
  }
  // dataset writes reach only this observer, so they carry values but no stack.
  if (attributes.length) {
    new MutationObserver(records => {
      for (const r of records) {
        const value = r.target.getAttribute(r.attributeName)
        if (value !== r.oldValue && watched(r.target, r.attributeName))
          log.push({t: now(), changed: r.attributeName, target: name(r.target), from: r.oldValue, to: value})
      }
    }).observe(document, {subtree: true, attributes: true, attributeOldValue: true, attributeFilter: attributes})
  }
  // Follow events only: polling matches can suppress the change being traced.
  for (const query of media) {
    const list = matchMedia(query)
    log.push({t: now(), media: query, matches: list.matches})
    list.addEventListener('change', event => log.push({t: now(), media: query, matches: event.matches}))
  }
}

export function traceRecorder(name) {
  const spec = parseSpec(process.env.TIJARA_BROWSER_TRACE || '')
  const contexts = new Map()
  return {
    async attach(context, label = name) {
      await context.tracing.start({title: label, screenshots: true, snapshots: true})
      await context.addInitScript(pageTrace, spec)
      contexts.set(context, label)
    },
    step: (page, label) => page.evaluate(step => window.__tijaraStep?.(step), label),
    // Closing a passing context discards its trace.
    async close(context) {
      contexts.delete(context)
      await context.close()
    },
    async save(error) {
      await mkdir(dir, {recursive: true})
      for (const [context, label] of contexts) {
        const pages = []
        for (const page of context.pages()) {
          pages.push({url: page.url(), log: await page.evaluate(() => window.__tijaraTrace).catch(() => null)})
        }
        await writeFile(`${dir}/${label}-log.json`, JSON.stringify({error: String(error?.message ?? error), pages}, null, 1))
        await context.tracing.stop({path: `${dir}/${label}-trace.zip`}).catch(() => {})
        const tail = pages.flatMap(page => page.log || []).slice(-40)
        console.error(`Browser trace ${dir}/${label}-trace.zip; last page events: ${JSON.stringify(tail)}`)
      }
    },
  }
}
