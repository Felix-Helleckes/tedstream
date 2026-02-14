#!/bin/bash

# YouTube RTMP Stream - FIXED SETTINGS: 1280x720, 16:9, 1500k, 24fps
# Optimized for stability and bandwidth.
. ./.env
RTMP_URL="$YOUTUBE_RTMP_URL"
STREAM_KEY="$YOUTUBE_STREAM_KEY"
TEMP_DIR="/tmp/youtube_stream"

mkdir -p "$TEMP_DIR"

# STRICT SETTINGS PER USER REQUEST
VIDEO_SIZE="1280x720"
FPS="24"
BITRATE="2000k"
BUF_SIZE="8000k"

# Ensure all files exist
for f in header_main_title.txt status_time.txt status_stats.txt news_marquee.txt portfolio.txt header_balances.txt data_balances.txt header_movers.txt data_movers.txt header_positions.txt data_positions.txt data_risk.txt; do
  touch "$TEMP_DIR/$f"
done

# Start ffmpeg with hardware acceleration (h264_v4l2m2m)
# Increased bufsize to better handle network jitter
ffmpeg -re -f lavfi -i "color=c=black:s=${VIDEO_SIZE}:r=${FPS}" \
  -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 \
  -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:textfile=$TEMP_DIR/header_main_title.txt:reload=1:fontcolor=white:fontsize=20:x=10:y=10, \
       drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf:textfile=$TEMP_DIR/status_time.txt:reload=1:fontcolor=0x00FF00:fontsize=20:box=1:boxcolor=black@0.6:boxborderw=6:x=10:y=35, \
       drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf:textfile=$TEMP_DIR/status_stats.txt:reload=1:fontcolor=white:fontsize=18:x=10:y=60, \
       drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf:textfile=$TEMP_DIR/portfolio.txt:reload=1:fontcolor=0x00FF00:fontsize=16:x=10:y=120, \
       drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:textfile=$TEMP_DIR/header_balances.txt:reload=1:fontcolor=white:fontsize=20:x=950:y=10, \
       drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf:textfile=$TEMP_DIR/data_balances.txt:reload=1:fontcolor=white:fontsize=16:x=950:y=35, \
       drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:textfile=$TEMP_DIR/header_movers.txt:reload=1:fontcolor=white:fontsize=20:x=950:y=240, \
       drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf:textfile=$TEMP_DIR/data_movers.txt:reload=1:fontcolor=white:fontsize=16:x=950:y=265, \
       drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:textfile=$TEMP_DIR/header_positions.txt:reload=1:fontcolor=white:fontsize=20:x=950:y=450, \
       drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf:textfile=$TEMP_DIR/data_positions.txt:reload=1:fontcolor=white:fontsize=16:x=950:y=475, \
       drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf:textfile=$TEMP_DIR/data_risk.txt:reload=1:fontcolor=white:fontsize=14:x=950:y=625, \
       drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf:textfile=$TEMP_DIR/news_marquee_line.txt:reload=1:fontcolor=white:fontsize=18:x=w-mod(max(t*100\\,0)\\,w+text_w):y=695, \
       scale=1280:720" \
  -c:v libx264 -preset ultrafast -tune zerolatency -b:v ${BITRATE} -maxrate ${BITRATE} -bufsize ${BUF_SIZE} -g 48 \
  -pix_fmt yuv420p -c:a aac -b:a 128k -ar 44100 -f flv "${RTMP_URL}/${STREAM_KEY}"
