#!/bin/bash
set -euo pipefail

# Reel v3: vertical timelapse of green console logs (bottom), top current values updating,
# bottom lower-third with channel name THEEFFICIENTDEV

OUTDIR="/mnt/fritz_nas/kraken/daily_shorts"
TMP="/tmp/youtube_reel_anim_v3"
OVERLAY_DIR="/tmp/youtube_stream"
FONT_MONO="/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
FONT_SANS="/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
WIDTH=1080
HEIGHT=1920
DURATION=15
PAGESIZE=10
MAX_PAGES=12
LOWERTHIRD_H=160
TOP_H=240

mkdir -p "$OUTDIR" "$TMP"
rm -rf "$TMP"/*

SRC="$OVERLAY_DIR/portfolio.txt"
if [ ! -f "$SRC" ]; then
  echo "No overlay portfolio file at $SRC" >&2
  exit 1
fi

# extract summary values for top area (use latest occurrences)
PNL=$(grep -E -o 'TotalPnL:[[:space:]]*-?[0-9]+(\.[0-9]+)?' "$SRC" | tail -n1 || true)
BAL=$(grep -E -o 'Bal:[[:space:]]*-?[0-9]+(\.[0-9]+)?' "$SRC" | tail -n1 || true)
START=$(grep -E -o 'Start:[[:space:]]*[0-9]+(\.[0-9]+)? EUR' "$SRC" | tail -n1 || true)
PCT=$(grep -E -o '-?[0-9]+\.[0-9]+%|-[0-9]+%|\+[0-9]+\.[0-9]+%|\+[0-9]+%' "$SRC" | tail -n1 || true)
TRADES=$(grep -E -o 'Trades:[[:space:]]*[0-9]+' "$SRC" | tail -n1 || true)

PNL_DISPLAY=${PNL:-TotalPnL: N/A}
BAL_DISPLAY=${BAL:-Bal: N/A}
START_DISPLAY=${START:-Start: N/A}
PCT_DISPLAY=${PCT:-N/A}
TRADES_DISPLAY=${TRADES:-Trades: N/A}

# prepare log lines for timelapse
# take last 120 lines as default
tail -n 240 "$SRC" > "$TMP/log_lines.txt" || true

# split into pages of PAGESIZE lines
split -l $PAGESIZE -d --additional-suffix=.page "$TMP/log_lines.txt" "$TMP/page_"
PAGES=( $TMP/page_*.page )
# cap pages to MAX_PAGES (keep newest pages)
TOTAL_PAGES=${#PAGES[@]}
if [ $TOTAL_PAGES -eq 0 ]; then
  echo "No pages found; aborting" >&2
  exit 1
fi
if [ $TOTAL_PAGES -gt $MAX_PAGES ]; then
  # keep last MAX_PAGES
  STARTIDX=$((TOTAL_PAGES-MAX_PAGES))
  PAGES=( "${PAGES[@]:$STARTIDX:$MAX_PAGES}" )
fi

# compute per-page duration
N=${#PAGES[@]}
PER_PAGE_MS=$(( (DURATION*1000) / N ))
PER_PAGE_SEC=$(awk "BEGIN{printf \"%.3f\", $DURATION/$N}")

# render each page to a clip
i=0
PARTS=()
for p in "${PAGES[@]}"; do
  PAGE_TEXT="$TMP/page_text_$i.txt"
  # convert page file to a single text block with \n escapes for ffmpeg textfile
  # but ffmpeg drawtext supports textfile containing newlines
  cp "$p" "$PAGE_TEXT"

  # top values update slightly: rotate through same values but append page index timestamp
  TOPFILE="$TMP/top_$i.txt"
  echo "$START_DISPLAY | Aktuell: ${BAL_DISPLAY#Bal: } | ${PCT_DISPLAY} | ${TRADES_DISPLAY#Trades: } trades" > "$TOPFILE"

  OUT="$TMP/part_$i.mp4"
  # build ffmpeg drawtext: top (white), log block (mono green) placed below center, lower-third white
  ffmpeg -y -f lavfi -i "color=black:s=${WIDTH}x${HEIGHT}:d=${PER_PAGE_SEC}" \
    -vf "drawtext=fontfile=${FONT_SANS}:textfile=${TOPFILE}:fontsize=52:fontcolor=white:x=(w-text_w)/2:y=40:box=1:boxcolor=black@0.6:boxborderw=6,\
         drawtext=fontfile=${FONT_MONO}:textfile=${PAGE_TEXT}:fontsize=36:fontcolor=#00ff66:x=60:y=${TOP_H}:box=0:line_spacing=6,\
         drawbox=x=0:y=${HEIGHT}-${LOWERTHIRD_H}:w=iw:h=${LOWERTHIRD_H}:color=black@0.6:t=fill,\
         drawtext=fontfile=${FONT_SANS}:text='THEEFFICIENTDEV':fontsize=48:fontcolor=white:x=(w-text_w)/2:y=${HEIGHT}-${LOWERTHIRD_H}+40:box=0" \
    -c:v libx264 -preset veryfast -crf 22 -pix_fmt yuv420p "$OUT"
  PARTS+=("$OUT")
  i=$((i+1))
done

# concat parts
CONCAT="$TMP/concat.txt"
> "$CONCAT"
for f in "${PARTS[@]}"; do echo "file '$f'" >> "$CONCAT"; done
FINAL_RAW="$TMP/final_raw.mp4"
ffmpeg -y -f concat -safe 0 -i "$CONCAT" -c copy "$FINAL_RAW"

OUTFILE="$OUTDIR/reel_anim_v3_$(date +%F).mp4"
ffmpeg -y -i "$FINAL_RAW" -c:v copy -c:a aac -b:a 128k -shortest "$OUTFILE"
chmod 644 "$OUTFILE" || true

echo "$OUTFILE"
