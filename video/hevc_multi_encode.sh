#!/bin/bash

INPUT="$1"
if [ -z "$INPUT" ] || [ ! -f "$INPUT" ]; then
  echo "❌ Usage: $0 <video_file>"
  exit 1
fi

DIR=$(dirname "$INPUT")
FILENAME=$(basename "$INPUT")
BASENAME="${FILENAME%.*}"

# 🎯 Target resolutions
RES_NAMES=("1080p" "720p" "480p")
RES_WIDTHS=(1920 1280 854)

# Get input width and codec
INPUT_WIDTH=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$INPUT")
INPUT_CODEC_RAW=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$INPUT")

# Normalize codec
if [[ "$INPUT_CODEC_RAW" == *265 || "$INPUT_CODEC_RAW" == "hevc" ]]; then
  INPUT_CODEC="hevc"
else
  INPUT_CODEC="other"
fi

echo "🎞️ Input codec: $INPUT_CODEC_RAW | normalized: $INPUT_CODEC | width: $INPUT_WIDTH px"

# Detect encoder
detect_encoder() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "hevc_videotoolbox"
  elif command -v nvidia-smi &>/dev/null; then
    echo "hevc_nvenc"
  elif ffmpeg -hide_banner -encoders 2>/dev/null | grep -q hevc_qsv; then
    echo "hevc_qsv"
  elif ffmpeg -hide_banner -encoders 2>/dev/null | grep -q hevc_vaapi; then
    echo "hevc_vaapi"
  else
    echo "libx265"
  fi
}

ENCODER=$(detect_encoder)
echo "🧠 Detected encoder: $ENCODER"

# Process each resolution
for i in "${!RES_NAMES[@]}"; do
  RES="${RES_NAMES[$i]}"
  WIDTH="${RES_WIDTHS[$i]}"
  OUTPUT="$DIR/${BASENAME} - ${RES} HEVC.mkv"

  # Skip up-scaling
  if [[ "$WIDTH" -gt "$INPUT_WIDTH" ]]; then
    echo "⏭️ Skipping $RES – resolution higher than source."
    continue
  fi

  # Smart skip: Check if output exists and is already HEVC of the same resolution
  if [[ -f "$OUTPUT" ]]; then
    OUT_WIDTH=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$OUTPUT" 2>/dev/null)
    OUT_CODEC=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$OUTPUT" 2>/dev/null)

    if [[ "$OUT_CODEC" == "hevc" && "$OUT_WIDTH" -eq "$WIDTH" ]]; then
      echo "⏭️ Skipping $RES – output already exists and is valid HEVC at target resolution."
      continue
    fi
  fi

  echo "🎬 Encoding $RES to $OUTPUT..."

  ffmpeg -hide_banner -y -i "$INPUT" \
    -vf "scale=$WIDTH:-2" \
    -map 0 \
    -c:v "$ENCODER" \
    -q:v 30 \
    -tag:v hvc1 \
    -c:a aac -b:a 96k \
    -c:s copy \
    -movflags +faststart \
    -progress pipe:1 \
    "$OUTPUT"

  echo "✅ Done: $OUTPUT"
done

echo "🎉 All applicable HEVC versions processed!"
