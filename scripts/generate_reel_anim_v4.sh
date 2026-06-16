#!/bin/bash
set -euo pipefail

# generate_reel_anim_v4.sh (patched)
# - PnL intro (2s) using textfile to avoid ffmpeg quoting issues
# - timelapse parts from overlay logs (configurable duration)
# - lower-third with channel name "TheefficientDev"
# - accepts arg: DURATION (total seconds)
# - retention: keep last RETAIN mp4s in OUTDIR

OUTDIR="/mnt/fritz_nas/kraken/daily_shorts"
TMP="/tmp/youtube_reel_anim_v4"
OVERLAY_DIR="/tmp/youtube_stream"
SRC="$OVERLAY_DIR/portfolio.txt"

# defaults
DURATION=${1:-15}
FONT_MONO=${FONT_MONO:-/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf}
FONT_SANS=${FONT_SANS:-/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf}
RETAIN=${RETAIN:-7}
WIDTH=1080
HEIGHT=1920
LOWERTHIRD_H=160
TOP_H=220
PAGESIZE=10
MAX_PAGES=12

mkdir -p "$OUTDIR" "$TMP"
rm -rf "$TMP"/*

if [ ! -f "$SRC" ]; then
  echo "No overlay portfolio file at $SRC" >&2
  exit 1
fi

# Robust extraction using awk (portable)
PNL_DISPLAY=$(awk '/TotalPnL/ {for(i=1;i<=NF;i++) if($i~/TotalPnL/){print $(i+1); exit}}' "$SRC" || true)
BAL_DISPLAY=$(awk '/Bal:/ {for(i=1;i<=NF;i++) if($i~/Bal:/){print $(i+1); exit}}' "$SRC" || true)
START_DISPLAY=$(awk '/Start:/ {for(i=1;i<=NF;i++) if($i~/Start:/){print $(i+1) " " $(i+2); exit}}' "$SRC" || true)
PCT_DISPLAY=$(awk '/%/ {for(i=1;i<=NF;i++) if($i~/[%]/){print $i}} END{ if(!found) print "N/A" }' "$SRC" | tail -n1 || true)
TRADES_DISPLAY=$(awk '/Trades:/ {for(i=1;i<=NF;i++) if($i~/Trades:/){print $(i+1); exit}}' "$SRC" || true)

PNL_DISPLAY=${PNL_DISPLAY:-N/A}
BAL_DISPLAY=${BAL_DISPLAY:-N/A}
START_DISPLAY=${START_DISPLAY:-N/A}
PCT_DISPLAY=${PCT_DISPLAY:-N/A}
TRADES_DISPLAY=${TRADES_DISPLAY:-N/A}

# Prepare log lines
tail -n 240 "$SRC" > "$TMP/log_lines.txt" || true

# Split into pages
split -l $PAGESIZE -d --additional-suffix=.page "$TMP/log_lines.txt" "$TMP/page_"
PAGES=( $TMP/page_*.page )
TOTAL_PAGES=${#PAGES[@]}
if [ $TOTAL_PAGES -eq 0 ]; then
  echo "No log lines to render" >&2
  exit 1
fi
if [ $TOTAL_PAGES -gt $MAX_PAGES ]; then
  STARTIDX=$((TOTAL_PAGES-MAX_PAGES))
  PAGES=( "${PAGES[@]:$STARTIDX:$MAX_PAGES}" )
fi
N=${#PAGES[@]}
PER_PAGE_SEC=$(awk "BEGIN{printf \"%.3f\", $DURATION/$N}")

# Create textfiles for intro to avoid ffmpeg quoting problems
echo "Tagessaldo: ${PNL_DISPLAY}" > "$TMP/intro_top.txt"
echo "Aktuell: ${BAL_DISPLAY}" > "$TMP/intro_sub.txt"

# Create PnL intro (2s)
INTRO_OUT="$TMP/intro.mp4"
INTRO_DUR=2
ffmpeg -y -f lavfi -i "color=black:s=${WIDTH}x${HEIGHT}:d=${INTRO_DUR}" \
  -vf "drawtext=fontfile=${FONT_SANS}:textfile=${TMP}/intro_top.txt:fontsize=110:fontcolor=white:x=(w-text_w)/2:y=h/2-90:box=1:boxcolor=black@0.6:boxborderw=12,\
        drawtext=fontfile=${FONT_SANS}:textfile=${TMP}/intro_sub.txt:fontsize=54:fontcolor=#00ff66:x=(w-text_w)/2:y=h/2-10:box=0" \
  -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p "$INTRO_OUT"

# Render each page
i=0
PARTS=()
for p in "${PAGES[@]}"; do
  PAGE_TEXT="$TMP/page_text_$i.txt"
  # sanitize and ensure UTF-8
  awk '{gsub(/\r/,""); print}' "$p" > "$PAGE_TEXT"

  TOPFILE="$TMP/top_$i.txt"
  echo "Start: ${START_DISPLAY} | Aktuell: ${BAL_DISPLAY} | ${PCT_DISPLAY} | ${TRADES_DISPLAY} trades" > "$TOPFILE"

  OUT="$TMP/part_$i.mp4"
  ffmpeg -y -f lavfi -i "color=black:s=${WIDTH}x${HEIGHT}:d=${PER_PAGE_SEC}" \
    -vf "drawtext=fontfile=${FONT_SANS}:textfile=${TOPFILE}:fontsize=48:fontcolor=white:x=(w-text_w)/2:y=28:box=1:boxcolor=black@0.6:boxborderw=8,\
         drawtext=fontfile=${FONT_MONO}:textfile=${PAGE_TEXT}:fontsize=34:fontcolor=#00ff66:x=60:y=${TOP_H}:box=0:line_spacing=6,\
         drawbox=x=0:y=${HEIGHT}-${LOWERTHIRD_H}:w=iw:h=${LOWERTHIRD_H}:color=black@0.6:t=fill,\
         drawtext=fontfile=${FONT_SANS}:text='TheefficientDev':fontsize=46:fontcolor=white:x=(w-text_w)/2:y=${HEIGHT}-${LOWERTHIRD_H}+42:box=0" \
    -c:v libx264 -preset veryfast -crf 22 -pix_fmt yuv420p "$OUT"
  PARTS+=("$OUT")
  i=$((i+1))
done

# Concat intro + parts
CONCAT="$TMP/concat.txt"
> "$CONCAT"
echo "file '$INTRO_OUT'" >> "$CONCAT"
for f in "${PARTS[@]}"; do echo "file '$f'" >> "$CONCAT"; done
FINAL_RAW="$TMP/final_raw.mp4"
ffmpeg -y -f concat -safe 0 -i "$CONCAT" -c copy "$FINAL_RAW"

OUTFILE="$OUTDIR/reel_anim_v4_$(date +%F).mp4"
ffmpeg -y -i "$FINAL_RAW" -c:v copy -c:a aac -b:a 128k -shortest "$OUTFILE"
chmod 644 "$OUTFILE" || true

echo "WROTE $OUTFILE"

# Retention: keep last $RETAIN mp4s in OUTDIR (matching reel_anim_v4_*)
cd "$OUTDIR"
ls -1t reel_anim_v4_*.mp4 2>/dev/null | tail -n +$((RETAIN+1)) | xargs -r rm -v || true

# Also keep generic reel files under a limit: keep last RETAIN files matching reel_anim_*
ls -1t reel_anim_* 2>/dev/null | tail -n +$((RETAIN+1)) | xargs -r rm -v || true

# Clean tmp
rm -rf "$TMP"

exit 0
