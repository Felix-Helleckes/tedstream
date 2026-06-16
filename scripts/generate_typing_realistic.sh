#!/bin/bash
set -euo pipefail

# generate_typing_realistic.sh (fixed)
# Creates a more realistic mechanical keyboard typing bed
# Usage: generate_typing_realistic.sh DURATION CLICKS
DURATION=${1:-22}
CLICKS=${2:-80}
OUT="/tmp/typing_realistic.wav"
TMPDIR="/tmp/typing_samples_$$"
mkdir -p "$TMPDIR"

# create small samples (mono)
ffmpeg -y -f lavfi -i "sine=frequency=1800:duration=0.06" -f lavfi -i "anoisesrc=color=white:duration=0.06" -filter_complex \
  "[0:a]volume=0.9,highpass=f=700,lowpass=f=8000[ton];[1:a]volume=0.25,highpass=f=1000[noi];[ton][noi]amix=inputs=2,volume=1,afade=t=out:st=0.045:d=0.01" \
  -c:a pcm_s16le "$TMPDIR/soft_key.wav"

ffmpeg -y -f lavfi -i "sine=frequency=2600:duration=0.08" -f lavfi -i "anoisesrc=color=white:duration=0.08" -filter_complex \
  "[0:a]volume=1.0,highpass=f=800,lowpass=f=10000[ton];[1:a]volume=0.5,highpass=f=1200[noi];[ton][noi]amix=inputs=2,volume=1.1,afade=t=out:st=0.065:d=0.01" \
  -c:a pcm_s16le "$TMPDIR/hard_key.wav"

# spacebar: lower thud
ffmpeg -y -f lavfi -i "sine=frequency=140:duration=0.12" -filter_complex "[0:a]volume=1.0,lowpass=f=600,afade=t=out:st=0.09:d=0.02" -c:a pcm_s16le "$TMPDIR/space.wav"

# enter: two hard_key instances with short delay -> mix
ffmpeg -y -i "$TMPDIR/hard_key.wav" -i "$TMPDIR/hard_key.wav" -filter_complex "[1]adelay=80|80[a1];[0][a1]amix=inputs=2,volume=1" -c:a pcm_s16le "$TMPDIR/enter.wav" || cp "$TMPDIR/hard_key.wav" "$TMPDIR/enter.wav"

# silent base (stereo)
ffmpeg -y -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 -t "$DURATION" -c:a pcm_s16le "$TMPDIR/silent_base.wav"

# generate delayed files
rm -f "$TMPDIR"/delayed_*.wav
for i in $(seq 1 $CLICKS); do
  ms=$((RANDOM % (DURATION*1000 + 1)))
  # pick sample type: soft (70%), hard (18%), space(6%), enter(6%)
  r=$((RANDOM % 100 + 1))
  if [ $r -le 70 ]; then
    sample="$TMPDIR/soft_key.wav"
    vol=0.9
  elif [ $r -le 88 ]; then
    sample="$TMPDIR/hard_key.wav"
    vol=1.0
  elif [ $r -le 94 ]; then
    sample="$TMPDIR/space.wav"
    vol=0.95
  else
    sample="$TMPDIR/enter.wav"
    vol=0.95
  fi
  out="$TMPDIR/delayed_${i}.wav"
  # simple stereo duplicate with slight random volume
  rv=$(awk "BEGIN{printf \"%.2f\", (0.85 + (srand()+$i)%150/1000)}") || rv=0.95
  ffmpeg -y -i "$sample" -af "adelay=${ms}|${ms},volume=${vol}" -t "$DURATION" -c:a pcm_s16le "$out"
done

# mix all into final wav
inputs=("$TMPDIR/silent_base.wav")
for f in "$TMPDIR"/delayed_*.wav; do inputs+=("$f"); done
cmd=(ffmpeg -y -i "${inputs[0]}")
for ((j=1;j<${#inputs[@]};j++)); do cmd+=( -i "${inputs[j]}" ); done
ninputs=${#inputs[@]}
cmd+=( -filter_complex "amix=inputs=${ninputs}:duration=first:dropout_transition=2,volume=1.2" -c:a pcm_s16le "$OUT")

"${cmd[@]}"

# normalize
ffmpeg -y -i "$OUT" -filter:a loudnorm -c:a pcm_s16le "${OUT}.tmp.wav"
mv "${OUT}.tmp.wav" "$OUT"

# cleanup
rm -rf "$TMPDIR"

echo "TYPING_REALISTIC=$OUT"
chmod 644 "$OUT" || true
