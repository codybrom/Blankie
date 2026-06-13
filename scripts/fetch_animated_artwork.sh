#!/usr/bin/env bash
#
# fetch_animated_artwork.sh
#
# Downloads the animated-artwork .mov files that back the app's On-Demand
# Resources. These binaries are NOT stored in git. They live as assets on a
# GitHub Release so cloning the repo doesn't burn LFS bandwidth. The build
# (and ODR archiving) needs them present at:
#
#     Blankie/Resources/AnimatedArtwork/<Name>/<Name>.mov
#
# The script is idempotent: a file already on disk with the expected SHA-256 is
# left untouched, so re-running it (or wiring it into an Xcode build phase) is
# cheap. Integrity is verified against scripts/animated-artwork.manifest.
#
# Usage:
#   scripts/fetch_animated_artwork.sh            # fetch missing/corrupt assets
#   scripts/fetch_animated_artwork.sh --force    # re-download everything
#   TAG=artwork-assets-v2 scripts/fetch_animated_artwork.sh   # override release tag
#
set -euo pipefail

REPO="${REPO:-codybrom/blankie}"
TAG="${TAG:-artwork-assets-v1}"
FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$SCRIPT_DIR/animated-artwork.manifest"
DEST_ROOT="$ROOT_DIR/Blankie/Resources/AnimatedArtwork"
BASE_URL="https://github.com/$REPO/releases/download/$TAG"

[ -f "$MANIFEST" ] || { echo "error: manifest not found at $MANIFEST" >&2; exit 1; }

# SHA-256 helper that works with either shasum (macOS) or sha256sum (Linux CI).
sha256() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else sha256sum "$1" | cut -d' ' -f1; fi
}

fetched=0 skipped=0 failed=0
while read -r name want_sha want_bytes; do
  case "$name" in ''|\#*) continue ;; esac   # skip blanks and comments

  dest="$DEST_ROOT/$name/$name.mov"
  if [ "$FORCE" -eq 0 ] && [ -f "$dest" ] && [ "$(sha256 "$dest")" = "$want_sha" ]; then
    skipped=$((skipped+1))
    continue
  fi

  echo "↓ $name.mov ($((want_bytes/1024/1024)) MB)"
  mkdir -p "$(dirname "$dest")"
  tmp="$dest.download"
  if ! curl -fsSL --retry 3 --retry-delay 2 -o "$tmp" "$BASE_URL/$name.mov"; then
    echo "  ✗ download failed for $name" >&2
    rm -f "$tmp"; failed=$((failed+1)); continue
  fi

  got_sha="$(sha256 "$tmp")"
  if [ "$got_sha" != "$want_sha" ]; then
    echo "  ✗ checksum mismatch for $name (got $got_sha)" >&2
    rm -f "$tmp"; failed=$((failed+1)); continue
  fi

  mv "$tmp" "$dest"
  fetched=$((fetched+1))
done < "$MANIFEST"

echo "Animated artwork: $fetched fetched, $skipped up-to-date, $failed failed (tag $TAG)"
[ "$failed" -eq 0 ]
