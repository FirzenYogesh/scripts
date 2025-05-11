#!/bin/bash

# 🎬 Usage: ./hevc_multi_encode_smart.sh <video_file> [quality]
INPUT="$1"
QUALITY="${2:-30}"  # Optional quality override, default to 30
USER_ENCODER="$3"

if [ -z "$INPUT" ] || [ ! -f "$INPUT" ]; then
  echo "❌ Usage: $0 <video_file> [quality]"
  exit 1
fi

command -v ffmpeg >/dev/null || { echo "❌ ffmpeg not found"; exit 1; }
command -v ffprobe >/dev/null || { echo "❌ ffprobe not found"; exit 1; }

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
INPUT_CODEC="other"
[[ "$INPUT_CODEC_RAW" == *265 || "$INPUT_CODEC_RAW" == "hevc" ]] && INPUT_CODEC="hevc"

echo "🎞️ Input codec: $INPUT_CODEC_RAW | normalized: $INPUT_CODEC | width: $INPUT_WIDTH px"

vaapi_dry_run() {
  local vaapi_driver=$1
  ffmpeg -hide_banner -init_hw_device vaapi=va:$vaapi_driver -filter_hw_device va \
    -f lavfi -i nullsrc -t 1 \
    -vf "format=nv12,hwupload,scale_vaapi=w=640:h=360" -f null - \
    -loglevel error -nostats >/dev/null 2>&1
}

# 🔍 Detect vaapi card
detect_vaapi_card() {
  local default_vaapi="/dev/dri/renderD128"
  if vaapi_dry_run "$default_vaapi"; then
    echo "$default_vaapi"
    return 0
  fi

  for card in /dev/dri/card*; do
    if vaapi_dry_run "$card"; then
      echo "$card"
      return 0
    fi
  done
  return 1
}

check_qsv_available() {
  ffmpeg -hide_banner -init_hw_device qsv=hw:0 -f lavfi -i nullsrc -t 1 \
    -vf 'format=nv12,hwupload=extra_hw_frames=64' -f null - \
    -loglevel error -nostats >/dev/null 2>&1
  return $?
}

# 🔍 Check if encoder exists
check_if_encoder_exists() {
  local short=$1
  if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q "hevc_${short}"; then
    echo "hevc_${short}"
  else
    echo ""
  fi
}

# 🔍 Detect encoder
detect_encoder() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "hevc_videotoolbox"
  elif [[ -n $(check_if_encoder_exists nvenc) ]] && command -v nvidia-smi &>/dev/null; then
    echo "hevc_nvenc"
  elif [[ -n $(check_if_encoder_exists amf) ]]; then
    echo "hevc_amf"
  elif [[ -n $(check_if_encoder_exists qsv) ]] && check_qsv_available; then
    echo "hevc_qsv"
  elif [[ -n $(check_if_encoder_exists vaapi) ]]; then
    echo "hevc_vaapi"
  else
    echo "libx265"
  fi
}

ENCODER=""
set_encoder() {
  if [[ -n "$USER_ENCODER" ]]; then
    ENCODER=$(check_if_encoder_exists "$USER_ENCODER")
  fi
  if [[ -z "$ENCODER" ]]; then
    echo "⚠️ Warning: hevc_$USER_ENCODER not found. Falling back to auto-detected encoder."
    ENCODER=$(detect_encoder)
    echo "🛠️ Fallback encoder: $ENCODER"
  fi

  if [[ "$ENCODER" == "hevc_vaapi" ]]; then
    ENCODER_DEVICE=$(detect_vaapi_card)
    if [[ -z "$ENCODER_DEVICE" ]]; then
      echo "❌ No usable VAAPI device found. Falling back to libx265."
      ENCODER="libx265"
      ENCODER_DEVICE=""
    fi
  fi
}

set_encoder

echo "🧠 Using encoder: $ENCODER (quality: $QUALITY)"
TOTAL_START=$(date +%s)
# 🔁 Loop through target resolutions
for i in "${!RES_NAMES[@]}"; do
  RES="${RES_NAMES[$i]}"
  WIDTH="${RES_WIDTHS[$i]}"
  OUTPUT="$DIR/${BASENAME} - ${RES} HEVC.mkv"
  VIDEO_FORMAT="scale=$WIDTH:-2"
  ENCODER_MODIFIER=()
  VIDEO_QUALITY_ARGUMENT=(-q:v "$QUALITY")

  if [[ "$ENCODER" == "hevc_vaapi" ]] && [[ -n "$ENCODER_DEVICE" ]]; then
    VIDEO_QUALITY_ARGUMENT=(-rc_mode CQP -global_quality "$QUALITY")
    VIDEO_FORMAT="format=nv12,hwupload,scale_vaapi=w=$WIDTH:h=-2"
    ENCODER_MODIFIER=(-init_hw_device vaapi=va:$ENCODER_DEVICE -filter_hw_device va)
  fi

  if [[ "$ENCODER" == "hevc_qsv" ]]; then
    VIDEO_FORMAT="format=nv12,hwupload=extra_hw_frames=64,scale_qsv=w=$WIDTH:h=-2"
  fi

  if [[ "$ENCODER" == "hevc_nvenc" ]]; then
    VIDEO_QUALITY_ARGUMENT=(-cq "$QUALITY" -preset slow)
  fi

  if [[ "$ENCODER" == "libx265" ]]; then
    VIDEO_QUALITY_ARGUMENT=(-crf "$QUALITY" -preset slow)
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

  START_TIME=$(date +%s)

  if ! ffmpeg -hide_banner -y \
    -fflags +genpts -copyts -start_at_zero \
    "${ENCODER_MODIFIER[@]}" \
    -i "$INPUT" \
    -vf "$VIDEO_FORMAT" \
    -map 0 \
    -c:v "$ENCODER" \
    "${VIDEO_QUALITY_ARGUMENT[@]}" \
    -tag:v hvc1 \
    -c:a copy \
    -c:s copy \
    -movflags +faststart \
    "$OUTPUT"; then
    echo "❌ FFmpeg failed to encode $RES. Cleaning up stale output file."
    rm -f "$OUTPUT"
    continue
  fi

  END_TIME=$(date +%s)
  FILESIZE=$(du -h "$OUTPUT" | cut -f1)
  
  echo "⏱️ Encoding time: $((END_TIME - START_TIME)) seconds"
  echo "📦 File size: $FILESIZE"
  echo "✅ Done: $OUTPUT"
done
TOTAL_END=$(date +%s)
echo "⏱️ Total time: $((TOTAL_END - TOTAL_START)) seconds"
echo "🎉 All applicable HEVC versions processed!"
