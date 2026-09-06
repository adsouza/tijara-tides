#!/usr/bin/env bash
# Installs the supplied bundle in the current user's Flatpak installation.
set -euo pipefail
[[ $# == 1 && -f "$1" ]] || { echo "Usage: $0 package.flatpak" >&2; exit 1; }
if [[ -z ${DBUS_SESSION_BUS_ADDRESS:-} ]]; then
  exec dbus-run-session -- "$0" "$@"
fi
app_id=io.github.adsouza.tijara-tides
flatpak install --user --noninteractive --assumeyes "$1"
flatpak info --user --show-permissions "$app_id" > /tmp/tijara-flatpak-permissions.txt
grep -Eq '^shared=.*network' /tmp/tijara-flatpak-permissions.txt
if grep -Eq '^filesystems=|^sockets=.*system-bus' /tmp/tijara-flatpak-permissions.txt; then
  echo 'Unexpected filesystem or system bus access' >&2; exit 1
fi
flatpak run --command=sh "$app_id" -c '
  set -eu
  ldd /app/bin/tijara-tides > /tmp/ldd.txt
  cat /tmp/ldd.txt
  ! grep -q "not found" /tmp/ldd.txt
'
# A successful export alone does not prove that WebKit can open a window.
# The single-quoted script expands its variables in the child shell.
# shellcheck disable=SC2016
dbus-run-session -- xvfb-run -a bash -c '
  set -euo pipefail
  flatpak run --socket=x11 io.github.adsouza.tijara-tides > /tmp/tijara-flatpak-launch.log 2>&1 &
  app_pid=$!
  trap '\''flatpak kill io.github.adsouza.tijara-tides 2>/dev/null || true'\'' EXIT
  if ! timeout 30s xdotool search --sync --onlyvisible --name "^Tijara Tides$"; then
    cat /tmp/tijara-flatpak-launch.log
    exit 1
  fi
  kill -0 "$app_pid"
'
echo 'Flatpak permissions, libraries, and native window verified.'
