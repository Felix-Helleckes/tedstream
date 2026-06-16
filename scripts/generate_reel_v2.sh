#!/bin/bash
set -euo pipefail

OUTDIR="/mnt/fritz_nas/kraken/daily_shorts"
TMP="/tmp/youtube_reel_v2"
OVERLAY_DIR="/tmp/youtube_stream"
FONT="/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
WIDTH=1080
HEIGHT=1920
TITLE_DUR=2
HIGHLIGHT_DUR=1.5
SUMMARY_DUR=3
CTA_DUR=2
MAX_HIGHLIGHTS=12

mkdir -p "$OUTDIR" "$TMP"
rm -rf "$TMP"/*

# collect source text
SRC="$OVERLAY_DIR/portfolio.txt"
if [ ! -f "$SRC" ]; then
  echo "No overlay portfolio file at $SRC" >&2
  exit 1
fi

# extract PnL/Bal/Trades
PNL=$(grep -E -o 'TotalPnL:[[:space:]]*-?[0-9]+(\.[0-9]+)?' "$SRC" | tail -n1 || true)
BAL=$(grep -E -o 'Bal:[[:space:]]*-?[0-9]+(\.[0-9]+)?' "$SRC" | tail -n1 || true)
TRADES=$(grep -E -o 'Trades:[[:space:]]*[0-9]+' "$SRC" | tail -n1 || true)
PNL_DISPLAY=${PNL:-TotalPnL: N/A}
BAL_DISPLAY=${BAL:-Bal: N/A}
TRADES_DISPLAY=${TRADES:-Trades: N/A}

# TITLE card (big PnL) - write textfile
cat > "$TMP/title.txt" <<EOF
$PNL_DISPLAY
$BAL_DISPLAY
$TRADES_DISPLAY
EOF
TITLE="$TMP/title.mp4"
ffmpeg -y -f lavfi -i "color=black:s=${WIDTH}x${HEIGHT}:d=${TITLE_DUR}" \
  -vf "drawtext=fontfile=${FONT}:textfile=$TMP/title.txt:fontsize=220:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/3:box=1:boxcolor=black@0.6:boxborderw=18" \
  -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p "$TITLE"

# HIGHLIGHTS: grep important actions and normalize
grep -E 'BUY|SELL|TotalPnL|Take-Profit|Stop-Loss|BUY skipped|SELL skipped' "$SRC" | tail -n 100 > "$TMP/high_candidates.txt" || true
if [ ! -s "$TMP/high_candidates.txt" ]; then
  tail -n 200 "$SRC" > "$TMP/high_candidates.txt" || true
fi

# select top lines containing BUY or SELL first
grep -Ei 'BUY|SELL' "$TMP/high_candidates.txt" | tail -n $MAX_HIGHLIGHTS > "$TMP/high_selected.txt" || true
# fill with other lines if not enough
if [ $(wc -l < "$TMP/high_selected.txt" | tr -d ' ') -lt $MAX_HIGHLIGHTS ]; then
  tail -n $MAX_HIGHLIGHTS "$TMP/high_candidates.txt" > "$TMP/high_selected.txt" || true
fi

# create highlight clips
IDX=0
HIGHLISTS=()
while IFS= read -r LINE && [ $IDX -lt $MAX_HIGHLIGHTS ]; do
  # sanitize percent signs
  LINESCAPED=$(echo "$LINE" | sed 's/%/%%/g')
  # choose color
  COLOR=white
  if echo "$LINE" | grep -Ei 'BUY'; then COLOR=lime; fi
  if echo "$LINE" | grep -Ei 'SELL'; then COLOR=red; fi
  TEXTFILE="$TMP/high_${IDX}.txt"
  echo "$LINESCAPED" > "$TEXTFILE"
  OUT="$TMP/high_${IDX}.mp4"
  ffmpeg -y -f lavfi -i "color=black:s=${WIDTH}x${HEIGHT}:d=${HIGHLIGHT_DUR}" \
    -vf "drawtext=fontfile=${FONT}:textfile=${TEXTFILE}:fontsize=64:fontcolor=$COLOR:x=80:y=(h-text_h)/2:box=1:boxcolor=black@0.6:boxborderw=8" \
    -c:v libx264 -preset veryfast -crf 22 -pix_fmt yuv420p "$OUT"
  HIGHLISTS+=("$OUT")
  IDX=$((IDX+1))
done < "$TMP/high_selected.txt"

# SUMMARY card (short sparkline placeholder) - use short list of PnL-like lines
WINRATE=$(grep -E -o 'Winrate:[[:space:]]*[0-9]+(\.[0-9]+)?' "$SRC" | tail -n1 || echo 'Winrate: N/A')
cat > "$TMP/summary.txt" <<EOF
Day Summary
$PNL_DISPLAY | $BAL_DISPLAY
$WINRATE
EOF
SUMMARY="$TMP/summary.mp4"
ffmpeg -y -f lavfi -i "color=black:s=${WIDTH}x${HEIGHT}:d=${SUMMARY_DUR}" \
  -vf "drawtext=fontfile=${FONT}:textfile=$TMP/summary.txt:fontsize=64:fontcolor=white:x=80:y=(h-text_h)/3:box=1:boxcolor=black@0.6:boxborderw=10" \
  -c:v libx264 -preset veryfast -crf 22 -pix_fmt yuv420p "$SUMMARY"

# CTA
echo "Follow for daily recaps" > "$TMP/cta.txt"
CTA="$TMP/cta.mp4"
ffmpeg -y -f lavfi -i "color=black:s=${WIDTH}x${HEIGHT}:d=${CTA_DUR}" \
  -vf "drawtext=fontfile=${FONT}:textfile=$TMP/cta.txt:fontsize=56:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2:box=1:boxcolor=black@0.6:boxborderw=8" \
  -c:v libx264 -preset veryfast -crf 22 -pix_fmt yuv420p "$CTA"

# concat list
LIST="$TMP/concat.txt"
> "$LIST"
echo "file '$TITLE'" >> "$LIST"
for f in "${HIGHLISTS[@]}"; do echo "file '$f'" >> "$LIST"; done
echo "file '$SUMMARY'" >> "$LIST"
echo "file '$CTA'" >> "$LIST"
FINAL_RAW="$TMP/final_raw.mp4"
ffmpeg -y -f concat -safe 0 -i "$LIST" -c copy "$FINAL_RAW"

# audio: soft clicks looped to duration
DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$FINAL_RAW" | awk '{print int($1+0.5)}')
CLICK="$TMP/click_unit.wav"
ffmpeg -y -f lavfi -i "sine=frequency=8000:duration=0.02" -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100:d=0.13" -filter_complex "[0:a][1:a]concat=n=2:v=0:a=1,volume=0.03" -ar 44100 "$CLICK"
CLICK_LOOP="$TMP/clicks_loop.wav"
ffmpeg -y -stream_loop -1 -i "$CLICK" -t "$DURATION" -c:a pcm_s16le "$CLICK_LOOP" || true
AMBI="$TMP/ambient.wav"
ffmpeg -y -f lavfi -i "sine=frequency=200:duration=$DURATION" -af "lowpass=f=400,volume=0.02" -ar 44100 "$AMBI"
AUDIO="$TMP/audio_final.wav"
ffmpeg -y -i "$AMBI" -i "$CLICK_LOOP" -filter_complex "[0:a][1:a]amix=inputs=2:duration=first:dropout_transition=0,volume=1" -ar 44100 "$AUDIO" || true

OUTFILE="$OUTDIR/reel_v2_$(date +%F).mp4"
ffmpeg -y -i "$FINAL_RAW" -i "$AUDIO" -c:v copy -c:a aac -b:a 128k -shortest "$OUTFILE"
chmod 644 "$OUTFILE" || true

echo "$OUTFILE"
