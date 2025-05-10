#!/bin/bash

# 🎬 Usage: ./hevc_multi_encode_smart.sh <video_file> [quality]
INPUT="$1"
QUALITY="${2:-30}"  # Optional quality override, default to 30

if [ -z "$INPUT" ] || [ ! -f "$INPUT" ]; then
  echo "❌ Usage: $0 <video_file> [quality]"
  exit 1
fi

# 📁 Path and name extraction
DIR=$(dirname "$INPUT")
FILENAME=$(basename "$INPUT")
BASENAME="${FILENAME%.*}"

# 🎯 Target resolutions
RES_NAMES=("1080p" "720p" "480p")
RES_WIDTHS=(1920 1280 854)

# 📊 Get input resolution and codec
INPUT_WIDTH=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$INPUT")
INPUT_CODEC_RAW=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$INPUT")

# 🧠 Normalize codec name
if [[ "$INPUT_CODEC_RAW" == *265 || "$INPUT_CODEC_RAW" == "hevc" ]]; then
  INPUT_CODEC="hevc"
else
  INPUT_CODEC="other"
fi

echo "🎞️ Input codec: $INPUT_CODEC_RAW | normalized: $INPUT_CODEC | width: $INPUT_WIDTH px"

# 🔍 Detect vaapi card
detect_vaapi_card() {
  for card in /dev/dri/card*; do
    if ffmpeg -hide_banner -init_hw_device vaapi=va:$card -filter_hw_device va \
       -f lavfi -i nullsrc -t 1 \
       -vf "format=nv12,hwupload,scale_vaapi=w=640:h=360" \
       -f null - 2>/dev/null; then
      echo "$card"
      return
    fi
  done
  echo "renderD128"
}

# 🔍 Detect encoder
detect_encoder() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "hevc_videotoolbox"
  elif command -v nvidia-smi &>/dev/null; then
    echo "hevc_nvenc"
  elif ffmpeg -hide_banner -encoders 2>/dev/null | grep -q hevc_amf; then
    echo "hevc_amf"
  elif ffmpeg -hide_banner -encoders | grep -q hevc_qsv && ffmpeg -init_hw_device qsv=hw:0 2>/dev/null; then
    echo "hevc_qsv"
  elif ffmpeg -hide_banner -encoders 2>/dev/null | grep -q hevc_vaapi; then
    echo "hevc_vaapi"
  else
    echo "libx265"
  fi
}

ENCODER=$(detect_encoder)
echo "🧠 Using encoder: $ENCODER (quality: $QUALITY)"

# 🔁 Loop through target resolutions
for i in "${!RES_NAMES[@]}"; do
  RES="${RES_NAMES[$i]}"
  WIDTH="${RES_WIDTHS[$i]}"
  OUTPUT="$DIR/${BASENAME} - ${RES} HEVC.mkv"
  VIDEO_FORMAT="scale=$WIDTH:-2"
  ENCODER_MODIFIER=()

  if [[ "$ENCODER" == "hevc_vaapi" ]]; then
    ENCODER_DEVICE=$(detect_vaapi_card)
    VIDEO_FORMAT="format=nv12,hwupload,scale_vaapi=w=$WIDTH:h=-2"
    ENCODER_MODIFIER=(-init_hw_device vaapi=va:$ENCODER_DEVICE -filter_hw_device va)
  fi

  # Skip upscaling
  if [[ "$WIDTH" -gt "$INPUT_WIDTH" ]]; then
    echo "⏭️ Skipping $RES – resolution is higher than input."
    continue
  fi

  # Smart skip: file exists and matches resolution & HEVC
  if [[ -f "$OUTPUT" ]]; then
    OUT_WIDTH=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$OUTPUT" 2>/dev/null)
    OUT_CODEC=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$OUTPUT" 2>/dev/null)

    if [[ "$OUT_CODEC" == "hevc" && "$OUT_WIDTH" -eq "$WIDTH" ]]; then
      echo "⏭️ Skipping $RES – output already exists and is valid HEVC."
      continue
    fi
  fi

  echo "🎬 Encoding $RES to $OUTPUT"

  if [[ ! "$OUTPUT" =~ \.mkv$ ]]; then
    echo "❌ OUTPUT does not look like a valid .mkv file: '$OUTPUT'"
    exit 1
  fi


  ffmpeg -hide_banner -y \
    "${ENCODER_MODIFIER[@]}" \
    -i "$INPUT" \
    -vf "$VIDEO_FORMAT" \
    -map 0 \
    -c:v "$ENCODER" \
    -q:v "$QUALITY" \
    -tag:v hvc1 \
    -c:a aac -b:a 96k \
    -c:s copy \
    -movflags +faststart \
    "$OUTPUT"

  echo "✅ Done: $OUTPUT"
done

echo "🎉 All applicable HEVC versions processed!"
