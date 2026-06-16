#!/bin/bash
set -euo pipefail

# generate_enhanced_assets.sh
# - creates /tmp/sparkline.png from /tmp/youtube_stream/portfolio.txt
# - creates /tmp/typing.wav (duration configurable)

SRC="/tmp/youtube_stream/portfolio.txt"
SPARK_SVG="/tmp/sparkline.svg"
SPARK_PNG="/tmp/sparkline.png"
CLICK_WAV="/tmp/click.wav"
TYPING_WAV="/tmp/typing.wav"
DURATION=${1:-22}
CLICKS=${2:-60}

if [ ! -f "$SRC" ]; then
  echo "Missing $SRC" >&2
  exit 1
fi

# Extract last numeric values for Bal: or TotalPnL; fallback to any floats
# We'll try to get up to 120 samples
vals=( )
while IFS= read -r line; do
  if [[ "$line" =~ Bal: ]]; then
    # get first number after Bal:
    num=$(echo "$line" | sed -n 's/.*Bal:[[:space:]]*\([-0-9.]*\).*/\1/p')
    if [[ -n "$num" ]]; then vals+=("$num"); fi
  fi
done < "$SRC"

# if not enough, extract any floats
if [ ${#vals[@]} -lt 8 ]; then
  while IFS= read -r line; do
    num=$(echo "$line" | grep -oE "-?[0-9]+\.[0-9]+" | tail -n1 || true)
    if [ -n "$num" ]; then vals+=("$num"); fi
  done < "$SRC"
fi

# If still empty, create dummy
if [ ${#vals[@]} -eq 0 ]; then
  for i in $(seq 0 23); do vals+=("$(printf "%.2f" $(echo "100 + $i*0.1" | bc -l))"); done
fi

# down/up sample to at most 120 points by simple nearest sampling
MAX=120
n=${#vals[@]}
if [ $n -gt $MAX ]; then
  step=$(awk "BEGIN{printf \"%f\", $n/$MAX}")
  newvals=()
  idx=0.0
  for i in $(seq 1 $MAX); do
    j=$(printf "%d" "$(awk "BEGIN{printf \"%f\", ($i-1)*$step+1}")")
    newvals+=("${vals[$((j-1))]}")
  done
  vals=("${newvals[@]}")
  n=${#vals[@]}
fi

# normalize to SVG height
min=$(printf "%s\n" "${vals[@]}" | awk 'BEGIN{min=1e99} {if($1+0<min) min=$1} END{print min}')
max=$(printf "%s\n" "${vals[@]}" | awk 'BEGIN{max=-1e99} {if($1+0>max) max=$1} END{print max}')
range=$(awk "BEGIN{printf \"%f\", $max - $min}")
if awk "BEGIN{exit ($range==0)}"; then
  range=1
fi

W=1200
H=240
pad=10
count=${#vals[@]}

# build polyline points
points=""
for i in "${!vals[@]}"; do
  x=$(awk "BEGIN{printf \"%f\", ($i)/($count-1)*($W-2*$pad)+$pad}")
  v=${vals[$i]}
  y=$(awk "BEGIN{printf \"%f\", ($H-2*$pad)*(1-($v - $min)/$range)+$pad}")
  points+=" ${x},${y}"
done

cat > "$SPARK_SVG" <<EOF
<svg xmlns='http://www.w3.org/2000/svg' width='${W}' height='${H}' viewBox='0 0 ${W} ${H}'>
  <defs>
    <linearGradient id='g' x1='0' x2='1'>
      <stop offset='0' stop-color='#003300' />
      <stop offset='1' stop-color='#001100' />
    </linearGradient>
  </defs>
  <rect width='100%' height='100%' fill='black'/>
  <polyline points='${points}' fill='none' stroke='#00ff66' stroke-width='6' stroke-linecap='round' stroke-linejoin='round' />
  <polyline points='${points}' fill='none' stroke='url(#g)' stroke-width='18' stroke-linecap='round' stroke-linejoin='round' opacity='0.12' />
</svg>
EOF

# convert to PNG (prefer rsvg-convert, else use convert)
if command -v rsvg-convert >/dev/null 2>&1; then
  rsvg-convert -w $W -h $H "$SPARK_SVG" -o "$SPARK_PNG"
else
  if command -v convert >/dev/null 2>&1; then
    convert "$SPARK_SVG" "$SPARK_PNG"
  else
    echo "No SVG renderer found (rsvg-convert or convert)" >&2
    exit 1
  fi
fi

# create click sound (short sine with decay)
ffmpeg -y -f lavfi -i "sine=frequency=3200:duration=0.02" -af "volume=0.8,adelay=0|0" -c:a pcm_s16le -ar 44100 -ac 1 "$CLICK_WAV"

# create silent base
ffmpeg -y -f lavfi -i anullsrc=channel_layout=mono:sample_rate=44100 -t $DURATION -c:a pcm_s16le /tmp/silent_base.wav

# generate randomized delays and delayed click files
rm -f /tmp/delayed_*.wav
for i in $(seq 1 $CLICKS); do
  ms=$(shuf -i 0-$(($DURATION*1000)) -n 1)
  out="/tmp/delayed_${i}.wav"
  ffmpeg -y -i "$CLICK_WAV" -af "adelay=${ms}|${ms}" -t $DURATION -c:a pcm_s16le "$out"
done

# mix all into typing wav
inputs=(/tmp/delayed_*.wav)
filter=""
for i in "${inputs[@]}"; do
  filter+="-i $i "
done

# Build amix command
cmd=(ffmpeg -y -i /tmp/silent_base.wav)
for f in "${inputs[@]}"; do cmd+=( -i "$f" ); done
ninputs=$((${#inputs[@]} + 1))
cmd+=( -filter_complex "amix=inputs=$ninputs:duration=first:dropout_transition=2,volume=2" -c:a pcm_s16le "$TYPING_WAV")

# Run the mix
"${cmd[@]}"

# normalize
ffmpeg -y -i "$TYPING_WAV" -filter:a loudnorm -c:a pcm_s16le "$TYPING_WAV.tmp.wav"
mv "$TYPING_WAV.tmp.wav" "$TYPING_WAV"

# cleanup
rm -f /tmp/delayed_*.wav /tmp/silent_base.wav

echo "SPARK=$SPARK_PNG TYPING=$TYPING_WAV"
