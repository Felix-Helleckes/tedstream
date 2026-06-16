#!/bin/bash
# Dual YouTube stream (landscape + portrait) in one ffmpeg process
# Usage: set YOUTUBE_RTMP_URL, YOUTUBE_STREAM_KEY (landscape), YOUTUBE_STREAM_KEY2 (portrait)
# Optional: YOUTUBE_RTMP_URL2 (falls different), BITRATE_L, BITRATE_P

set -euo pipefail
. ./.env

RTMP_URL="${YOUTUBE_RTMP_URL:-rtmp://a.rtmp.youtube.com/live2}"
RTMP_URL2="${YOUTUBE_RTMP_URL2:-$RTMP_URL}"
KEY1="${YOUTUBE_STREAM_KEY:-}"
KEY2="${YOUTUBE_STREAM_KEY2:-}"

if [ -z "$KEY1" ] || [ -z "$KEY2" ]; then
  echo "ERROR: Both YOUTUBE_STREAM_KEY and YOUTUBE_STREAM_KEY2 must be set in .env" >&2
  exit 2
fi

TEMP_DIR="/tmp/youtube_stream"
mkdir -p "$TEMP_DIR"

# defaults
FPS="24"
BITRATE_L="${BITRATE_L:-2000k}"
BITRATE_P="${BITRATE_P:-1500k}"
BUF_L="8000k"
BUF_P="6000k"

# ensure overlay files exist
for f in header_main_title.txt status_time.txt status_stats.txt status_profit.txt status_loss.txt news_marquee.txt news_marquee_line.txt portfolio.txt header_balances.txt data_balances.txt header_movers.txt data_movers.txt header_positions.txt data_positions.txt data_risk.txt; do
  touch "$TEMP_DIR/$f"
done

# Build filter_complex: two separate video sources (color), each gets its own drawtext chain
# Input 0: landscape color 1280x720
# Input 1: portrait color 720x1280
# Input 2: anullsrc audio

FILTERS=""

# landscape drawtext chain (similar to existing stream.sh overlay positions)
FILTERS="$FILTERS [0:v]format=yuv420p,drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:textfile=$TEMP_DIR/header_main_title.txt:reload=1:fontcolor=white:fontsize=20:x=10:y=10,\
 drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf:textfile=$TEMP_DIR/status_time.txt:reload=1:fontcolor=0x00FF00:fontsize=20:box=1:boxcolor=black@0.6:boxborderw=6:x=10:y=35,\
 drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf:textfile=$TEMP_DIR/status_stats.txt:reload=1:fontcolor=white:fontsize=20:x=10:y=68,\
 drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf:textfile=$TEMP_DIR/portfolio.txt:reload=1:fontcolor=0x00FF00:fontsize=16:x=10:y=120:line_spacing=2,\
 drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:textfile=$TEMP_DIR/header_balances.txt:reload=1:fontcolor=white:fontsize=20:x=w-text_w-10:y=10,\
 drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf:textfile=$TEMP_DIR/data_balances.txt:reload=1:fontcolor=white:fontsize=18:x=w-text_w-10:y=35:line_spacing=2,\
 drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:textfile=$TEMP_DIR/header_movers.txt:reload=1:fontcolor=white:fontsize=19:x=w-text_w-10:y=225,\
 drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf:textfile=$TEMP_DIR/data_movers.txt:reload=1:fontcolor=white:fontsize=16:x=w-text_w-10:y=250:line_spacing=2,\
 drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:textfile=$TEMP_DIR/header_positions.txt:reload=1:fontcolor=white:fontsize=19:x=w-text_w-10:y=420,\
 drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf:textfile=$TEMP_DIR/data_positions.txt:reload=1:fontcolor=white:fontsize=16:x=w-text_w-10:y=445:line_spacing=2,\
 drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:textfile=$TEMP_DIR/data_risk.txt:reload=1:fontcolor=white:fontsize=27:x=w-text_w-10:y=610:line_spacing=2,\
 drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf:textfile=$TEMP_DIR/news_marquee_line.txt:reload=1:fontcolor=white:fontsize=18:x=w-mod(max(t*100\\,0)\\,w+text_w):y=695,scale=1280:720[voutL];"

# portrait drawtext chain (simplified layout for 720x1280)
FILTERS="$FILTERS [1:v]format=yuv420p,drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:textfile=$TEMP_DIR/header_main_title.txt:reload=1:fontcolor=white:fontsize=30:x=10:y=10,\
 drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf:textfile=$TEMP_DIR/status_time.txt:reload=1:fontcolor=0x00FF00:fontsize=22:box=1:boxcolor=black@0.6:boxborderw=6:x=10:y=60,\
 drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf:textfile=$TEMP_DIR/portfolio.txt:reload=1:fontcolor=0x00FF00:fontsize=18:x=10:y=120:line_spacing=2,\
 drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf:textfile=$TEMP_DIR/news_marquee_line.txt:reload=1:fontcolor=white:fontsize=20:x=w-mod(max(t*80\\,0)\\,w+text_w):y=h-80,scale=720:1280[voutP];"

# assemble and run ffmpeg
echo "Starting dual stream: $RTMP_URL/$KEY1  and  $RTMP_URL2/$KEY2"

ffmpeg -re \
  -f lavfi -i "color=c=black:s=1280x720:r=$FPS" \
  -f lavfi -i "color=c=black:s=720x1280:r=$FPS" \
  -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 \
  -filter_complex "$FILTERS" \
  -map "[voutL]" -map 2:a -c:v libx264 -preset ultrafast -tune zerolatency -b:v $BITRATE_L -maxrate $BITRATE_L -bufsize $BUF_L -g 48 -pix_fmt yuv420p -c:a aac -b:a 128k -ar 44100 -f flv "${RTMP_URL}/${KEY1}" \
  -map "[voutP]" -map 2:a -c:v libx264 -preset ultrafast -tune zerolatency -b:v $BITRATE_P -maxrate $BITRATE_P -bufsize $BUF_P -g 48 -pix_fmt yuv420p -c:a aac -b:a 128k -ar 44100 -f flv "${RTMP_URL2}/${KEY2}"

EXIT_CODE=$?

echo "ffmpeg exited with $EXIT_CODE" >&2
exit $EXIT_CODE
