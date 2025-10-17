#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: prepare_loop.sh [input-file] [options]

If no input file is provided, processes all video files in Blankie/Assets/AnimatedArtwork
that don't already have .mov and .jpg versions.

Options:
  -o, --output-dir DIR   Directory for the generated files (default: same as input)
  -n, --name NAME        Base name for outputs (default: input file name without extension)
  -w, --width PIXELS     Output width in pixels (default: 1080)
  -h, --height PIXELS    Output height in pixels (default: 1440, 3:4 aspect ratio)
      --crf VALUE        Constant Rate Factor (default: 20)
      --anchor POS       Crop anchor: center, top, bottom, left, right,
                         bottom-center, top-center (default: center)
      --help             Show this help and exit

The script crops the input to a 3:4 portrait aspect ratio (for iPhone lock screens),
scales to the requested size, encodes to the chosen codec, and writes:
  <NAME>.mov        (loop video)
  <NAME>.jpg        (first-frame preview, 3:4 portrait)
  <NAME>Square.jpg  (first-frame preview, 1:1 square)
USAGE
}

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "❌ ffmpeg is required but not found in PATH" >&2
  exit 1
fi

to_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

INPUT=""
OUTPUT_DIR=""
NAME=""
WIDTH=1080
HEIGHT=1440
CRF="20"
ANCHOR="center"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output-dir)
      OUTPUT_DIR="$2"; shift 2;;
    -n|--name)
      NAME="$2"; shift 2;;
    -w|--width)
      WIDTH="$2"; shift 2;;
    -h|--height)
      HEIGHT="$2"; shift 2;;
    --crf)
      CRF="$2"; shift 2;;
    --anchor)
      ANCHOR="$(to_lower "$2")"; shift 2;;
    --help)
      usage; exit 0;;
    -*)
      echo "Unknown option: $1" >&2
      usage; exit 1;;
    *)
      if [[ -z "$INPUT" ]]; then
        INPUT="$1"; shift
      else
        echo "Only one input file may be specified." >&2
        usage; exit 1
      fi;;
  esac
done

# If no input provided, process all unprocessed files in AnimatedArtwork
if [[ -z "$INPUT" ]]; then
  SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  PROJECT_DIR=$(dirname "$SCRIPT_DIR")
  ARTWORK_DIR="$PROJECT_DIR/Blankie/Assets/AnimatedArtwork"

  if [[ ! -d "$ARTWORK_DIR" ]]; then
    echo "❌ AnimatedArtwork directory not found: $ARTWORK_DIR" >&2
    exit 1
  fi

  # Find all video files that don't have all three outputs (.mov, .jpg, and Square.jpg)
  # Only use .mp4 files as source (skip .mov files - they are outputs)
  FILES_TO_PROCESS=()
  while IFS= read -r -d '' file; do
    basename=$(basename "$file")
    name="${basename%.*}"
    ext="${basename##*.}"

    # Only process .mp4 files (and other source formats), skip .mov files
    if [[ "$ext" == "mov" ]]; then
      continue
    fi

    # Check if all three outputs exist
    if [[ ! -f "$ARTWORK_DIR/$name.mov" ]] || [[ ! -f "$ARTWORK_DIR/$name.jpg" ]] || [[ ! -f "$ARTWORK_DIR/${name}Square.jpg" ]]; then
      FILES_TO_PROCESS+=("$file")
    fi
  done < <(find "$ARTWORK_DIR" -type f \( -name "*.mp4" -o -name "*.avi" -o -name "*.mkv" \) ! -name ".*" -print0 | sort -z)

  if [[ ${#FILES_TO_PROCESS[@]} -eq 0 ]]; then
    echo "✅ All files in $ARTWORK_DIR already have .mov, .jpg, and Square.jpg versions"
    exit 0
  fi

  echo "🎬 Found ${#FILES_TO_PROCESS[@]} file(s) to process:"
  for f in "${FILES_TO_PROCESS[@]}"; do
    echo "   - $(basename "$f")"
  done
  echo ""

  # Process each file
  for file in "${FILES_TO_PROCESS[@]}"; do
    basename=$(basename "$file")
    name="${basename%.*}"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📹 Processing: $basename"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Recursively call this script with the file as input
    "$0" "$file" -w "$WIDTH" -h "$HEIGHT" --crf "$CRF" --anchor "$ANCHOR"

    echo ""
  done

  echo "🎉 Batch processing complete!"
  exit 0
fi

if [[ ! -f "$INPUT" ]]; then
  echo "❌ Input file not found: $INPUT" >&2
  exit 1
fi

INPUT=$(realpath "$INPUT")
INPUT_DIR=$(dirname "$INPUT")

if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="$INPUT_DIR"
else
  mkdir -p "$OUTPUT_DIR"
fi

OUTPUT_DIR=$(realpath "$OUTPUT_DIR")

if [[ -z "$NAME" ]]; then
  NAME=$(basename "$INPUT")
  NAME="${NAME%.*}"
fi

# H.264 only for maximum compatibility
VCODEC="libx264"
TAG="avc1"
CODEC_PARAMS=(-x264-params "keyint=60:min-keyint=60:scenecut=0")

case "$ANCHOR" in
  center|top|bottom|left|right|top-center|bottom-center) ;;
  *)
    echo "❌ Unsupported anchor: $ANCHOR (use center, top, bottom, left, right)" >&2
    exit 1
    ;;
esac

# Calculate 3:4 crop dimensions (portrait)
# crop_w = min(iw, ih * 3/4)
# crop_h = crop_w * 4/3
CROP_W="min(iw\\,ih*3/4)"
CROP_H="(${CROP_W})*4/3"

# Default center positioning
base_x="((iw-${CROP_W})/2)"
base_y="((ih-${CROP_H})/2)"

anchor_x="$base_x"
anchor_y="$base_y"

case "$ANCHOR" in
  left)
    anchor_x="0" ;;
  right)
    anchor_x="(iw-${CROP_W})" ;;
  top)
    anchor_y="0" ;;
  bottom)
    anchor_y="(ih-${CROP_H})" ;;
  top-center)
    anchor_y="((ih-${CROP_H})/4)" ;;
  bottom-center)
    anchor_y="(3*(ih-${CROP_H})/4)" ;;
esac

LOOP_PATH="$OUTPUT_DIR/${NAME}.mov"
PREVIEW_PATH="$OUTPUT_DIR/${NAME}.jpg"
SQUARE_PREVIEW_PATH="$OUTPUT_DIR/${NAME}Square.jpg"

FILTER="crop=${CROP_W}:${CROP_H}:${anchor_x}:${anchor_y},scale=${WIDTH}:${HEIGHT},setsar=1"

echo "🎞️  Encoding loop → $LOOP_PATH"
ffmpeg -hide_banner -y \
  -i "$INPUT" \
  -vf "$FILTER" \
  -an \
  -c:v "$VCODEC" \
  -preset medium \
  -crf "$CRF" \
  "${CODEC_PARAMS[@]}" \
  -pix_fmt yuv420p \
  -tag:v "$TAG" \
  -movflags +faststart \
  "$LOOP_PATH"

echo "🖼️  Extracting preview → $PREVIEW_PATH"
ffmpeg -hide_banner -y \
  -i "$LOOP_PATH" \
  -vf "select=eq(n\\,0)" \
  -frames:v 1 \
  -update 1 \
  "$PREVIEW_PATH"

# Calculate square crop dimensions (1:1 aspect ratio)
SQUARE_SIZE="min(iw\\,ih)"
SQUARE_X="((iw-${SQUARE_SIZE})/2)"
SQUARE_Y="((ih-${SQUARE_SIZE})/2)"
SQUARE_FILTER="crop=${SQUARE_SIZE}:${SQUARE_SIZE}:${SQUARE_X}:${SQUARE_Y},scale=${WIDTH}:${WIDTH},setsar=1"

echo "🔲 Extracting square preview → $SQUARE_PREVIEW_PATH"
ffmpeg -hide_banner -y \
  -i "$INPUT" \
  -vf "${SQUARE_FILTER},select=eq(n\\,0)" \
  -frames:v 1 \
  -update 1 \
  "$SQUARE_PREVIEW_PATH"

echo "✅ Done. Generated:"
echo "   $LOOP_PATH"
echo "   $PREVIEW_PATH"
echo "   $SQUARE_PREVIEW_PATH"
