#!/usr/bin/env bash
# Called by the tag workflow after both native builds and verification succeed.
set -euo pipefail
[[ $# == 2 ]] || { echo "Usage: $0 vX.Y.Z artifact-directory" >&2; exit 1; }
cd "$(dirname "$0")/.."
release_tag=$1
artifact_dir=$2
: "${GH_REPO:?Set GH_REPO to the owner/repository}"
: "${RELEASE_COMMIT:?Set RELEASE_COMMIT to the built commit SHA}"
python3 scripts/check-desktop-versions.py --tag "$release_tag"

# Check every local package before creating or changing a release.
shopt -s nullglob
assets=()
for suffix in deb flatpak dmg app.zip; do
  matches=("$artifact_dir"/*."$suffix")
  if [[ ${#matches[@]} != 1 || ! -f "${matches[0]}" || ! -s "${matches[0]}" ]]; then
    echo "Expected exactly one nonempty .$suffix package in $artifact_dir" >&2
    exit 1
  fi
  assets+=("${matches[0]}")
done

# Resolve both lightweight and annotated tags through GitHub's commit endpoint.
remote_commit=$(gh api "repos/$GH_REPO/commits/$release_tag" --jq .sha)
if [[ "$remote_commit" != "$RELEASE_COMMIT" ]]; then
  echo "Remote release tag no longer points to the built commit" >&2
  exit 1
fi

if is_draft=$(gh release view "$release_tag" --json isDraft --jq .isDraft); then
  if [[ "$is_draft" != true ]]; then
    echo "Release $release_tag is already published; refusing to replace its packages" >&2
    exit 1
  fi
else
  gh release create "$release_tag" --verify-tag --draft --generate-notes \
    --title "Tijara Tides $release_tag"
fi
# Clobber only draft assets, so rerunning a failed upload can resume safely.
gh release upload "$release_tag" "${assets[@]}" --clobber
gh release edit "$release_tag" --draft=false
