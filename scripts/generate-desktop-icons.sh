#!/usr/bin/env bash
# Generate only the icons consumed by our macOS and Linux desktop packages.
set -euo pipefail
cd "$(dirname "$0")/.."
task_icons=$(mktemp -d)
trap 'rm -rf "$task_icons"' EXIT
source_icon=src-tauri/icons/cargo-ship-v2/source.png
node_modules/.bin/tauri icon "$source_icon" --output "$task_icons"
node_modules/.bin/tauri icon "$source_icon" --output "$task_icons" --png 256 --png 1024
for icon in 32x32.png 128x128.png 128x128@2x.png 256x256.png icon.png 1024x1024.png icon.icns; do
  cp "$task_icons/$icon" "src-tauri/icons/$icon"
done
