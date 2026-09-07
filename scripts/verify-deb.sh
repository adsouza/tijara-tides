#!/usr/bin/env bash
set -euo pipefail
[[ $# == 1 && -f "$1" ]] || { echo "Usage: $0 package.deb" >&2; exit 1; }
task_stage=$(mktemp -d)
trap 'rm -rf "$task_stage"' EXIT
dpkg-deb -x "$1" "$task_stage"
test -x "$task_stage/usr/bin/tijara-tides"
desktop="$task_stage/usr/share/applications/Tijara Tides.desktop"
desktop-file-validate "$desktop"
grep -Eq '^Exec=tijara-tides( |$)' "$desktop"
grep -qx 'Icon=tijara-tides' "$desktop"
test -s "$task_stage/usr/share/icons/hicolor/scalable/apps/tijara-tides.svg"
appstreamcli validate --no-net "$task_stage/usr/share/metainfo/io.github.adsouza.tijara-tides.metainfo.xml"
"$(dirname "$0")/check-appstream-launcher.py" \
  "$task_stage/usr/share/metainfo/io.github.adsouza.tijara-tides.metainfo.xml" \
  "$(basename "$desktop")"
# This client must never acquire Armchair Metropolist's local BEAM sidecar.
test "$(find "$task_stage/usr/bin" -maxdepth 1 -type f | wc -l)" -eq 1
ldd "$task_stage/usr/bin/tijara-tides" > "$task_stage/ldd.txt"
cat "$task_stage/ldd.txt"
if grep -q 'not found' "$task_stage/ldd.txt"; then exit 1; fi
echo '.deb contents and dynamic libraries verified.'
