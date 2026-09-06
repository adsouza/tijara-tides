#!/usr/bin/env bash
# Keep the package list here: CI hashes this script to invalidate its .deb cache.
set -euo pipefail

archive_dir="$HOME/apt-archives"
mkdir -p "$archive_dir/partial"
# apt downloads as _apt; hand ownership back so actions/cache can save the files.
restore_ownership() {
  sudo chown -R "$(id -u):$(id -g)" "$archive_dir"
}
trap restore_ownership EXIT
sudo chown -R _apt:root "$archive_dir"
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  -o Dir::Cache::archives="$archive_dir" \
  -o APT::Keep-Downloaded-Packages=true \
  libwebkit2gtk-4.1-dev libgtk-3-dev libdbus-1-dev libayatana-appindicator3-dev \
  librsvg2-dev librsvg2-common patchelf desktop-file-utils appstream \
  flatpak flatpak-builder elfutils xvfb xauth xdotool dbus-x11
find /usr/lib -name libpixbufloader-svg.so -print -quit | grep -q .
command -v eu-strip
