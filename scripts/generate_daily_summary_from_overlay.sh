#!/bin/bash
set -euo pipefail

# Generates a 16:9 daily summary using the existing overlay files (copied, not modified).
OUTDIR="/mnt/fritz_nas/kraken/daily_shorts"
TMPDIR="/tmp/youtube_summary"
OVERLAY_DIR="/tmp/youtube_stream"
WORKFILE_DIR="$TMPDIR/files"
FONT="/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
PAGESIZE=18
DURATION_PER_PAGE=2
WIDTH=1920
HEIGHT=1080

mkdir -p "$OUTDIR" "$TMPDIR" "$WORKFILE_DIR"
rm -rf "$TMPDIR"/*

# 1) copy overlay files (preserve originals)
cp -a "$OVERLAY_DIR"/* "$WORKFILE_DIR" || true

# 2) prepare summary values from copied files
PNL=$(grep -E -o 'TotalPnL:[[:space:]]*-?[0-9]+(\.[0-9]+)?' "$WORKFILE_DIR/portfolio.txt" 2>/dev/null | tail -n1 || true)
BAL=$(grep -E -o 'Bal:[[:space:]]*-?[0-9]+(\.[0-9]+)?' "$WORKFILE_DIR/portfolio.txt" 2>/dev/null | tail -n1 || true)
TRADES=$(grep -E -o 'Trades:[[:space:]]*[0-9]+' "$WORKFILE_DIR/portfolio.txt" 2>/dev/null | tail -n1 || true)

PNL_DISPLAY=${PNL:-TotalPnL: N/A}
BAL_DISPLAY=${BAL:-Bal: N/A}
TRADES_DISPLAY=${TRADES:-Trades: N/A}

# 3) Title card (use same overlay look) - write textfile to avoid drawtext quoting issues
TITLETXT="$TMPDIR/title.txt"
cat > "$TITLETXT" <<EOF
$(date +%F)
$PNL_DISPLAY
$BAL_DISPLAY
$TRADES_DISPLAY
EOF

TITLEVID="$TMPDIR/title.mp4"
ffmpeg -y -f lavfi -i "color=black:s=${WIDTH}x${HEIGHT}:d=3" \
  -vf "drawtext=fontfile=${FONT}:textfile=${TITLETXT}:fontsize=64:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/4:box=1:boxcolor=black@0.6:boxborderw=8" \
  -c:v libx264 -preset veryfast -crf 22 -pix_fmt yuv420p "$TITLEVID"

# 4) paginate the portfolio (log) text and render pages
tail -n 400 "$WORKFILE_DIR/portfolio.txt" > "$TMPDIR/portfolio_tail.txt" || true
split -l $PAGESIZE -d -a 3 "$TMPDIR/portfolio_tail.txt" "$TMPDIR/page_" || true
PAGE_FILES=("$TMPDIR"/page_*)
if [ ${#PAGE_FILES[@]} -eq 0 ]; then
  echo "(no logs)" > "$TMPDIR/page_000"
  PAGE_FILES=("$TMPDIR"/page_000)
fi
SEGMENTS=()

IDX=0
for PF in "$TMPDIR"/page_*; do
  [ -f "$PF" ] || continue
  PAGE_ESC="$TMPDIR/page_${IDX}_esc.txt"
  sed 's/%/%%/g' "$PF" > "$PAGE_ESC" || cp "$PF" "$PAGE_ESC" || true
  PAGEVID="$TMPDIR/page_${IDX}.mp4"
  ffmpeg -y -f lavfi -i "color=black:s=${WIDTH}x${HEIGHT}:d=${DURATION_PER_PAGE}" \
    -vf "drawtext=fontfile=${FONT}:textfile=${PAGE_ESC}:fontsize=28:fontcolor=white:x=60:y=120:box=1:boxcolor=black@0.6:boxborderw=6:line_spacing=8" \
    -c:v libx264 -preset veryfast -crf 22 -pix_fmt yuv420p "$PAGEVID"
  SEGMENTS+=("$PAGEVID")
  IDX=$((IDX+1))
done

# 5) summary card (wider, 16:9)
SUMMARYTXT="$TMPDIR/summary.txt"
WINRATE=$(grep -E -o 'Winrate:[[:space:]]*[0-9]+(\.[0-9]+)?' "$WORKFILE_DIR/news_marquee.txt" 2>/dev/null | tail -n1 || echo 'Winrate: N/A')
cat > "$SUMMARYTXT" <<EOF
Day Summary
$PNL_DISPLAY | $BAL_DISPLAY | $TRADES_DISPLAY
$WINRATE
EOF
SUMMARYVID="$TMPDIR/summary.mp4"
ffmpeg -y -f lavfi -i "color=black:s=${WIDTH}x${HEIGHT}:d=4" \
  -vf "drawtext=fontfile=${FONT}:textfile=${SUMMARYTXT}:fontsize=44:fontcolor=white:x=80:y=(h-text_h)/3:box=1:boxcolor=black@0.6:boxborderw=10" \
  -c:v libx264 -preset veryfast -crf 22 -pix_fmt yuv420p "$SUMMARYVID"
SEGMENTS+=("$SUMMARYVID")

# 6) CTA
CTATXT="$TMPDIR/cta.txt"
echo "Daily recap - follow for more" > "$CTATXT"
CTAVID="$TMPDIR/cta.mp4"
ffmpeg -y -f lavfi -i "color=black:s=${WIDTH}x${HEIGHT}:d=3" \
  -vf "drawtext=fontfile=${FONT}:textfile=${CTATXT}:fontsize=40:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2:box=1:boxcolor=black@0.6:boxborderw=10" \
  -c:v libx264 -preset veryfast -crf 22 -pix_fmt yuv420p "$CTAVID"
SEGMENTS+=("$CTAVID")

# 7) concat everything
CONCATLIST="$TMPDIR/concat.txt"
> "$CONCATLIST"
# title first
echo "file '$TITLEVID'" >> "$CONCATLIST"
for S in "${SEGMENTS[@]}"; do
  echo "file '$S'" >> "$CONCATLIST"
done
FINALRAW="$TMPDIR/final_raw.mp4"
ffmpeg -y -f concat -safe 0 -i "$CONCATLIST" -c copy "$FINALRAW"

# 8) optional simple ambient audio (short)
AUDIO="$TMPDIR/audio.wav"
ffmpeg -y -f lavfi -i "sine=frequency=220:duration=60" -af "lowpass=f=400,volume=0.02" -ar 44100 "$AUDIO"
OUTFILE="$OUTDIR/daily_summary_$(date +%F)_16-9.mp4"
ffmpeg -y -i "$FINALRAW" -i "$AUDIO" -c:v copy -c:a aac -b:a 128k -shortest "$OUTFILE"
chmod 644 "$OUTFILE" || true

echo "$OUTFILE"
