export const SystemNotifications = {
  mounted() {
    this.button = this.el.querySelector('button')
    this.updatePermission = () => {
      const permission = globalThis.Notification?.permission
      this.button.disabled = permission !== 'default'
      this.button.textContent = permission === 'granted' ? this.el.dataset.enabled :
        permission === 'default' ? this.el.dataset.enable : this.el.dataset.unavailable
    }
    this.enable = async () => {
      try { await Notification.requestPermission() }
      catch (error) { console.warn('Notification permission request failed:', error) }
      this.updatePermission()
    }
    this.button.addEventListener('click', this.enable)
    this.handleEvent('system-notification', ({title, body, tag}) => {
      if (globalThis.Notification?.permission !== 'granted') return
      try {
        const notification = new Notification(title, {body, tag, icon: '/favicon.ico'})
        notification.onclick = () => { window.focus(); notification.close() }
      } catch (error) { console.warn('System notification failed:', error) }
    })
    this.updatePermission()
  },
  updated() { this.updatePermission() },
  destroyed() { this.button.removeEventListener('click', this.enable) },
}
