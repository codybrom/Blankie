#!/usr/bin/env bash
#
# package_animated_artwork.sh
#
# Fetches the animated-artwork source videos and packages them into Apple-hosted
# Managed Background Assets asset packs (.aar) — one pack per artwork. These
# archives upload to App Store Connect (Transporter / altool / the App Store
# Connect API) independently of the app build; they are NOT bundled into the app.
#
# The .mov sources are NOT stored in git: they live on a GitHub Release (so
# cloning stays cheap) and are downloaded here on demand, verified against
# scripts/animated-artwork.manifest (SHA-256), then packaged. Fetching is
# idempotent — a video already on disk with the expected checksum is reused.
#
# Each pack mirrors what the app expects at runtime (see BackgroundResourceManager):
#   assetPackID    = <Name>              the artwork id (e.g. "RainLoop")
#   file           = <Name>/<Name>.mov   matches relativeVideoPath(for:)
#   downloadPolicy = onDemand            downloaded only when a user picks it
#   platforms      = iOS                 animated artwork is an iOS-only feature
#
# Each clip ships two variants because iPhone and iPad lock screens advertise
# different artwork keys: a 3:4 portrait master (pack "<Name>", file
# "<Name>/<Name>.mov") and a 1:1 square crop for iPad (pack "<Name>Square", file
# "<Name>/<Name>Square.mov"). Both files live in the base clip's folder, which is
# why a square pack maps to "<Name>/<Name>Square.mov" — matching
# BackgroundResourceManager.relativeVideoPath(for:). All sources (both variants)
# live together on one release, so there is no per-entry tag.
#
# Output: build/AssetPacks/<Name>.aar  (git-ignored)
#
# Usage:
#   scripts/package_animated_artwork.sh                  # fetch + package all
#   scripts/package_animated_artwork.sh RainLoop Beach   # only these artwork ids
#   scripts/package_animated_artwork.sh --force          # re-download, then package
#   TAG=artwork-assets-v3 scripts/package_animated_artwork.sh   # override release tag
#
set -euo pipefail

REPO="${REPO:-codybrom/blankie}"
TAG="${TAG:-artwork-assets-v1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$SCRIPT_DIR/animated-artwork.manifest"
ARTWORK_DIR="$ROOT_DIR/Blankie/Resources/AnimatedArtwork"
OUT_DIR="$ROOT_DIR/build/AssetPacks"
BASE_URL="https://github.com/$REPO/releases/download/$TAG"

# Parse args: --force plus an optional list of artwork ids to limit to.
FORCE=0
FILTER=""
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -*) echo "error: unknown option $arg" >&2; exit 1 ;;
    *) FILTER="$FILTER $arg " ;;
  esac
done

[ -f "$MANIFEST" ] || { echo "error: manifest not found at $MANIFEST" >&2; exit 1; }
xcrun --find ba-package >/dev/null 2>&1 || {
  echo "error: ba-package not found — needs Xcode 26 or later" >&2
  exit 1
}

# SHA-256 helper that works with either shasum (macOS) or sha256sum (Linux CI).
sha256() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else sha256sum "$1" | cut -d' ' -f1; fi
}

# Load manifest entries up front so per-item commands can't consume its stdin.
entries=()
while read -r name want_sha want_bytes; do
  case "$name" in '' | \#*) continue ;; esac
  entries+=("$name $want_sha $want_bytes")
done <"$MANIFEST"

mkdir -p "$OUT_DIR"

fetched=0 reused=0 packaged=0 failed=0
for entry in "${entries[@]}"; do
  read -r name want_sha want_bytes <<<"$entry"
  # Honor an optional id filter.
  if [ -n "$FILTER" ] && [[ "$FILTER" != *" $name "* ]]; then continue; fi

  # Both variants of a clip share the base clip's folder, so a "<Name>Square"
  # pack reads from "<Name>/<Name>Square.mov".
  folder="$name"
  [[ "$name" == *Square ]] && folder="${name%Square}"
  dest="$ARTWORK_DIR/$folder/$name.mov"

  # 1) Ensure the source video is present and matches the manifest checksum.
  if [ "$FORCE" -eq 0 ] && [ -f "$dest" ] && [ "$(sha256 "$dest")" = "$want_sha" ]; then
    reused=$((reused + 1))
  else
    echo "↓ $name.mov ($((want_bytes / 1024 / 1024)) MB)"
    mkdir -p "$(dirname "$dest")"
    tmp="$dest.download"
    if ! curl -fsSL --retry 3 --retry-delay 2 -o "$tmp" "$BASE_URL/$name.mov"; then
      echo "  ✗ download failed for $name" >&2
      rm -f "$tmp"
      failed=$((failed + 1))
      continue
    fi
    if [ "$(sha256 "$tmp")" != "$want_sha" ]; then
      echo "  ✗ checksum mismatch for $name" >&2
      rm -f "$tmp"
      failed=$((failed + 1))
      continue
    fi
    mv "$tmp" "$dest"
    fetched=$((fetched + 1))
  fi

  # 2) Package the video into an Apple-hosted on-demand asset pack. ba-package
  #    requires the manifest to have a .json extension, so write it in a temp dir.
  tmp_dir="$(mktemp -d)"
  cat >"$tmp_dir/$name.json" <<JSON
{
  "assetPackID": "$name",
  "downloadPolicy": { "onDemand": {} },
  "fileSelectors": [ { "file": "$folder/$name.mov" } ],
  "platforms": [ "iOS" ]
}
JSON
  echo "📦 $name.aar"
  # ba-package refuses to overwrite, so clear any prior archive first (keeps
  # re-runs and artwork updates idempotent).
  rm -f "$OUT_DIR/$name.aar"
  # File-selector paths resolve against the current directory, so package from
  # the AnimatedArtwork root to get a "<Name>/<Name>.mov" pack entry.
  if (cd "$ARTWORK_DIR" && xcrun ba-package "$tmp_dir/$name.json" -o "$OUT_DIR/$name.aar"); then
    packaged=$((packaged + 1))
  else
    echo "  ✗ packaging failed for $name" >&2
    failed=$((failed + 1))
  fi
  rm -rf "$tmp_dir"
done

echo "Animated artwork: $fetched fetched, $reused reused, $packaged packaged, $failed failed → $OUT_DIR (tag $TAG)"
[ "$failed" -eq 0 ]
