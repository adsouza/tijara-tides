#!/usr/bin/env bash
# Run on Linux, after building the .deb and installing GNOME 50 Platform + SDK.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# != 1 || ! -f "$1" ]]; then
  echo "Usage: $0 path/to/tijara-tides.deb" >&2
  exit 1
fi
if [[ $(dpkg-deb -f "$1" Architecture) != "$(dpkg --print-architecture)" ]]; then
  echo "Build the Flatpak on the same architecture as its .deb." >&2
  exit 1
fi
cp "$1" packaging/flatpak/app.deb
mkdir -p dist
flatpak-builder --user --disable-rofiles-fuse --force-clean \
  --repo=dist/flatpak-repo dist/flatpak-build \
  packaging/flatpak/io.github.adsouza.tijara-tides.yml
flatpak build-bundle --runtime-repo=https://flathub.org/repo/flathub.flatpakrepo \
  dist/flatpak-repo "dist/tijara-tides-$(flatpak --default-arch).flatpak" \
  io.github.adsouza.tijara-tides
