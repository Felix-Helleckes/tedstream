#!/bin/bash
set -euo pipefail

WORKDIR="/home/felix/youtubestream"
OUTDIR="/mnt/fritz_nas/kraken/daily_shorts"
TMPDIR="/tmp/youtube_short"
LOG_UNIT="kraken-bot.service"
DURATION=30   # seconds
WIDTH=1080
HEIGHT=1920
FONT="/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
FONTSIZE=28
SCROLL_SPEED=60  # pixels per second

mkdir -p "$OUTDIR" "$TMPDIR"

# 1) collect last 24h logs
journalctl -u "$LOG_UNIT" --since "24 hours ago" --no-pager > "$TMPDIR/last24_full.txt" || true
# fallback to bot_activity.log if empty
if [ ! -s "$TMPDIR/last24_full.txt" ]; then
  tail -n 200 /home/felix/tradingbot/logs/bot_activity.log > "$TMPDIR/last24_full.txt" || true
fi
# reduce to last 200 lines for readability
tail -n 200 "$TMPDIR/last24_full.txt" > "$TMPDIR/last24.txt" || true
# escape percent signs for ffmpeg drawtext
sed -e 's/%/\\%/g' "$TMPDIR/last24.txt" > "$TMPDIR/last24_esc.txt"

# 2) render vertical video with scrolling text
RAW_VIDEO="$TMPDIR/daily_short_raw.mp4"
ffmpeg -y -f lavfi -i "color=black:s=${WIDTH}x${HEIGHT}:d=${DURATION}" \
  -vf "drawtext=fontfile=${FONT}:textfile=${TMPDIR}/last24_esc.txt:fontsize=${FONTSIZE}:fontcolor=white:x=20:y=h-(t*${SCROLL_SPEED}):box=1:boxcolor=black@0.6:boxborderw=6:line_spacing=6" \
  -c:v libx264 -preset veryfast -crf 22 -pix_fmt yuv420p "$RAW_VIDEO"

# 3) generate click unit (short click + silence)
CLICK_UNIT="$TMPDIR/click_unit.wav"
# short high-frequency burst + silence
ffmpeg -y -f lavfi -i "sine=frequency=8000:duration=0.02" -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100:d=0.13" \
  -filter_complex "[0:a][1:a]concat=n=2:v=0:a=1,volume=0.03" -ar 44100 "$CLICK_UNIT"

# 4) loop click unit to full duration
CLICK_LOOP="$TMPDIR/clicks_loop.wav"
ffmpeg -y -stream_loop -1 -i "$CLICK_UNIT" -t "$DURATION" -c:a pcm_s16le "$CLICK_LOOP"

# 5) mix a very soft ambient tone underneath (gentle sine) for ASMR feel
AMBIENT="$TMPDIR/ambient.wav"
ffmpeg -y -f lavfi -i "sine=frequency=200:duration=${DURATION}" -af "lowpass=f=400,volume=0.02" -ar 44100 "$AMBIENT"

# 6) combine ambient + clicks
AUDIO_FINAL="$TMPDIR/audio_final.wav"
ffmpeg -y -i "$AMBIENT" -i "$CLICK_LOOP" -filter_complex "[0:a][1:a]amix=inputs=2:duration=first:dropout_transition=0,volume=1" -ar 44100 "$AUDIO_FINAL"

# 7) mux audio + video
OUTFILE="$OUTDIR/daily_short_$(date +%F).mp4"
ffmpeg -y -i "$RAW_VIDEO" -i "$AUDIO_FINAL" -c:v copy -c:a aac -b:a 128k -shortest "$OUTFILE"

# 8) make file readable and print path
chmod 644 "$OUTFILE"
echo "$OUTFILE"
