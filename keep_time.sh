#!/bin/bash
# Keep the overlay clock updated every second
OUT=/tmp/youtube_stream/status_time.txt
TMP=${OUT}.tmp
mkdir -p /tmp/youtube_stream
while true; do
  date '+%Y-%m-%d %H:%M:%S' > "$TMP" && mv "$TMP" "$OUT"
  sleep 1
done
