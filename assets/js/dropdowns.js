// Native menus can close when LiveView patches surrounding layout. Defer only
// background display refreshes while choosing; commands and simulation still run.
export function watchDropdowns(root, notify) {
  let active = false
  let menuCheck
  const stopCheck = () => { clearInterval(menuCheck); menuCheck = undefined }
  const setActive = value => {
    if (!value) stopCheck()
    if (value !== active) { active = value; notify(value) }
  }
  const isSelect = event => event.target?.tagName === 'SELECT'
  const start = event => {
    if (!isSelect(event)) return
    setActive(true)
    stopCheck()
    // Native menus may swallow Escape without dispatching a DOM key event.
    // Observe visibility; never impose a timeout on an open menu.
    menuCheck = setInterval(() => {
      try { if (!event.target.matches(':open')) setActive(false) }
      catch { stopCheck() } // Older browsers resume on change/focusout instead.
    }, 100)
  }
  const finish = event => { if (isSelect(event)) setActive(false) }
  const key = event => {
    if (!isSelect(event)) return
    if (event.key === 'Escape' || event.key === 'Tab') setActive(false)
    else if (['ArrowDown', 'ArrowUp', ' ', 'Enter'].includes(event.key)) start(event)
  }
  const pointer = event => { if (isSelect(event)) start(event); else setActive(false) }
  const listeners = {focusin: start, focusout: finish, change: finish, pointerdown: pointer, keydown: key}
  for (const [name, fn] of Object.entries(listeners)) root.addEventListener(name, fn, true)
  return () => {
    stopCheck()
    for (const [name, fn] of Object.entries(listeners)) root.removeEventListener(name, fn, true)
  }
}
