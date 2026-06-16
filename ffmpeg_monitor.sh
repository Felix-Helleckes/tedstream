#!/bin/bash
LOG=/home/felix/youtubestream/ffmpeg_monitor.log
echo "Monitor started $(date -u)" >> $LOG
for i in $(seq 1 30); do
  echo "--- $(date -u +'%Y-%m-%dT%H:%M:%SZ')" >> $LOG
  pgrep -af ffmpeg >> $LOG || echo 'FFMPEG_NOT_RUNNING' >> $LOG
  echo '--- stream.log tail' >> $LOG
  tail -n 5 /home/felix/youtubestream/stream.log >> $LOG 2>&1 || true
  echo '--- update_overlay.log tail' >> $LOG
  tail -n 5 /home/felix/youtubestream/update_overlay.log >> $LOG 2>&1 || true
  sleep 10
done
echo "Monitor finished $(date -u)" >> $LOG
