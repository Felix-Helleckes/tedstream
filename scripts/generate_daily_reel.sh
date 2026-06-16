#!/bin/bash
set -euo pipefail

WORKDIR="/home/felix/youtubestream"
OUTDIR="/mnt/fritz_nas/kraken/daily_shorts"
TMPDIR="/tmp/youtube_reel"
LOG_UNIT="kraken-bot.service"
DURATION_PER_PAGE=3
WIDTH=1080
HEIGHT=1920
FONT="/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
PAGESIZE=12  # lines per page

mkdir -p "$OUTDIR" "$TMPDIR"
rm -rf "$TMPDIR"/*

# 1) collect last 24h logs
journalctl -u "$LOG_UNIT" --since "24 hours ago" --no-pager > "$TMPDIR/last24_full.txt" || true
if [ ! -s "$TMPDIR/last24_full.txt" ]; then
  tail -n 400 /home/felix/tradingbot/logs/bot_activity.log > "$TMPDIR/last24_full.txt" || true
fi
# reduce to last 200 lines
tail -n 200 "$TMPDIR/last24_full.txt" > "$TMPDIR/last24.txt" || true

# 2) extract summary (from overlay portfolio if available)
PNL="$(grep -E -o 'TotalPnL:[[:space:]]*-?[0-9]+(\.[0-9]+)?' /tmp/youtube_stream/portfolio.txt 2>/dev/null || true)"
BAL="$(grep -E -o 'Bal:[[:space:]]*-?[0-9]+(\.[0-9]+)?' /tmp/youtube_stream/portfolio.txt 2>/dev/null || true)"
TRADES="$(grep -E -o 'Trades:[[:space:]]*[0-9]+' /tmp/youtube_stream/portfolio.txt 2>/dev/null || true)"
# fallback parsing
if [ -z "$PNL" ]; then
  PNL="$(grep -E -o 'TotalPnL:[[:space:]]*-?[0-9]+(\.[0-9]+)?' "$TMPDIR/last24.txt" 2>/dev/null | tail -n1 || true)"
fi
if [ -z "$TRADES" ]; then
  TRADES="$(grep -E -o 'Trades:[[:space:]]*[0-9]+' "$TMPDIR/last24.txt" 2>/dev/null | tail -n1 || true)"
fi

# Normalize values for display
PNL_DISPLAY="${PNL:-TotalPnL: N/A}"
BAL_DISPLAY="${BAL:-Bal: N/A}"
TRADES_DISPLAY="${TRADES:-Trades: N/A}"

# choose color for PnL (green if +, red if -)
PNL_VAL="$(echo "$PNL_DISPLAY" | grep -E -o '-?[0-9]+(\.[0-9]+)?' || true)"
PNL_COLOR="white"
if [ -n "$PNL_VAL" ]; then
  if awk "BEGIN{exit !($PNL_VAL>0)}"; then
    PNL_COLOR="lime"
  elif awk "BEGIN{exit !($PNL_VAL<0)}"; then
    PNL_COLOR="red"
  fi
fi

# 3) split logs into pages
split -l $PAGESIZE -d -a 3 "$TMPDIR/last24.txt" "$TMPDIR/page_" || true
PAGE_FILES=("$TMPDIR"/page_*)
# if no pages, create empty page
if [ ${#PAGE_FILES[@]} -eq 0 ]; then
  echo "(no logs)" > "$TMPDIR/page_000"
  PAGE_FILES=("$TMPDIR"/page_000)
fi

SEGMENTS=()

# 4) title card (3s) - write to textfile to avoid drawtext parsing issues
TITLE_VID="$TMPDIR/title.mp4"
cat > "$TMPDIR/title.txt" <<EOF
$(date +%F)
$PNL_DISPLAY
$BAL_DISPLAY
$TRADES_DISPLAY
EOF
ffmpeg -y -f lavfi -i "color=black:s=${WIDTH}x${HEIGHT}:d=3" \
  -vf "drawtext=fontfile=${FONT}:textfile=$TMPDIR/title.txt:fontsize=120:fontcolor=$PNL_COLOR:x=(w-text_w)/2:y=(h-text_h)/3:box=1:boxcolor=black@0.6:boxborderw=12" \
  -c:v libx264 -preset veryfast -crf 22 -pix_fmt yuv420p "$TITLE_VID"
SEGMENTS+=("$TITLE_VID")

# 5) render each page as its own clip
IDX=0
for PF in "$TMPDIR"/page_*; do
  [ -f "$PF" ] || continue
  # ensure file is UTF-8 and escape % for drawtext
  PAGE_TEXT_ESC="$TMPDIR/page_${IDX}_esc.txt"
  sed 's/%/%%/g' "$PF" > "$PAGE_TEXT_ESC" || cp "$PF" "$PAGE_TEXT_ESC" || true
  PAGE_VID="$TMPDIR/page_${IDX}.mp4"
  ffmpeg -y -f lavfi -i "color=black:s=${WIDTH}x${HEIGHT}:d=${DURATION_PER_PAGE}" \
    -vf "drawtext=fontfile=${FONT}:textfile=${PAGE_TEXT_ESC}:fontsize=36:fontcolor=white:x=60:y=200:box=1:boxcolor=black@0.6:boxborderw=8:line_spacing=6" \
    -c:v libx264 -preset veryfast -crf 22 -pix_fmt yuv420p "$PAGE_VID"
  SEGMENTS+=("$PAGE_VID")
  IDX=$((IDX+1))
done

# 6) summary card (sparkline placeholder) - write textfile
SUMMARY_VID="$TMPDIR/summary.mp4"
WINRATE="$(grep -E -o 'Winrate:[[:space:]]*[0-9]+(\.[0-9]+)?' "$TMPDIR/last24.txt" 2>/dev/null | tail -n1 || echo 'Winrate: N/A')"
cat > "$TMPDIR/summary.txt" <<EOF
Day Summary
$PNL_DISPLAY | $BAL_DISPLAY | $TRADES_DISPLAY
$WINRATE
EOF
ffmpeg -y -f lavfi -i "color=black:s=${WIDTH}x${HEIGHT}:d=3" \
  -vf "drawtext=fontfile=${FONT}:textfile=$TMPDIR/summary.txt:fontsize=56:fontcolor=white:x=80:y=(h-text_h)/3:box=1:boxcolor=black@0.6:boxborderw=10" \
  -c:v libx264 -preset veryfast -crf 22 -pix_fmt yuv420p "$SUMMARY_VID"
SEGMENTS+=("$SUMMARY_VID")

# 7) CTA card
CTA_VID="$TMPDIR/cta.mp4"
cat > "$TMPDIR/cta.txt" <<EOF
Follow @theefficientdev for daily trading recaps
EOF
ffmpeg -y -f lavfi -i "color=black:s=${WIDTH}x${HEIGHT}:d=3" \
  -vf "drawtext=fontfile=${FONT}:textfile=$TMPDIR/cta.txt:fontsize=48:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2:box=1:boxcolor=black@0.6:boxborderw=10" \
  -c:v libx264 -preset veryfast -crf 22 -pix_fmt yuv420p "$CTA_VID"
SEGMENTS+=("$CTA_VID")

# 8) concat segments using concat demuxer
CONCAT_LIST="$TMPDIR/concat_list.txt"
> "$CONCAT_LIST"
for S in "${SEGMENTS[@]}"; do
  echo "file '$S'" >> "$CONCAT_LIST"
done
FINAL_RAW="$TMPDIR/final_raw.mp4"
ffmpeg -y -f concat -safe 0 -i "$CONCAT_LIST" -c copy "$FINAL_RAW"

# compute total duration for audio loop (title + pages + summary + cta)
NUM_PAGES=0
for pf in "$TMPDIR"/page_*; do [ -f "$pf" ] && NUM_PAGES=$((NUM_PAGES+1)); done
TOTAL_DURATION=$((3 + NUM_PAGES * DURATION_PER_PAGE + 3 + 3))

# 9) generate ASMR clicks + ambient audio (like earlier)
CLICK_UNIT="$TMPDIR/click_unit.wav"
ffmpeg -y -f lavfi -i "sine=frequency=8000:duration=0.02" -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100:d=0.13" \
  -filter_complex "[0:a][1:a]concat=n=2:v=0:a=1,volume=0.03" -ar 44100 "$CLICK_UNIT"
CLICK_LOOP="$TMPDIR/clicks_loop.wav"
ffmpeg -y -stream_loop -1 -i "$CLICK_UNIT" -t "$TOTAL_DURATION" -c:a pcm_s16le "$CLICK_LOOP" || true
AMBIENT="$TMPDIR/ambient.wav"
ffmpeg -y -f lavfi -i "sine=frequency=200:duration=$TOTAL_DURATION" -af "lowpass=f=400,volume=0.02" -ar 44100 "$AMBIENT"
AUDIO_FINAL="$TMPDIR/audio_final.wav"
ffmpeg -y -i "$AMBIENT" -i "$CLICK_LOOP" -filter_complex "[0:a][1:a]amix=inputs=2:duration=first:dropout_transition=0,volume=1" -ar 44100 "$AUDIO_FINAL" || true

# 10) mux audio + video
OUTFILE="$OUTDIR/daily_reel_$(date +%F).mp4"
ffmpeg -y -i "$FINAL_RAW" -i "$AUDIO_FINAL" -c:v copy -c:a aac -b:a 128k -shortest "$OUTFILE"

chmod 644 "$OUTFILE" || true
echo "$OUTFILE"
