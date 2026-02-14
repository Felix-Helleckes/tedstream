#!/bin/bash
# Fetch top 5 headlines from configured RSS feeds and write to news_marquee.txt
# Runs once per hour via systemd user timer.
set -euo pipefail
TEMP_DIR="/tmp/youtube_stream"
mkdir -p "$TEMP_DIR"
OUT_TMP="/tmp/news_marquee.$$"
OUT_FILE="$TEMP_DIR/news_marquee.txt"
# Feed list (English sources). Each entry: "DisplayName|URL"
FEEDS=(
  "CoinDesk|https://www.coindesk.com/arc/outboundfeeds/rss/"
  "Cointelegraph|https://cointelegraph.com/rss"
  "Decrypt|https://decrypt.co/feed"
  "TheDefiant|https://thedefiant.io/feed/"
  "BitcoinMag|https://bitcoinmagazine.com/feed"
  "CryptoSlate|https://cryptoslate.com/feed/"
  "NewsBTC|https://www.newsbtc.com/feed/"
  "Bitcoinist|https://bitcoinist.com/feed/"
  "BeInCrypto|https://www.beincrypto.com/feed/"
)
# Number of headlines per feed
N=5
# Curl timeout (seconds)
CURL_TIMEOUT=8
# User-Agent to reduce 403s
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36"
: > "$OUT_TMP"
for entry in "${FEEDS[@]}"; do
  name="${entry%%|*}"
  url="${entry#*|}"
  echo "${name}:" >> "$OUT_TMP"
  # fetch feed (max time) and extract titles; skip the first <title> (feed title)
  # try to ensure UTF-8 output; if iconv available, normalize
  if curl -fsS -m $CURL_TIMEOUT -A "$UA" --compressed "$url" -o /tmp/news_feed.$$; then
    # extract title tags (skip feed title), trim whitespace
    sed -n 's/<title>\(.*\)<\/title>/\1/p' /tmp/news_feed.$$ | sed '1d' | sed 's/^[ \t]*//;s/[ \t]*$//' | head -n $N | \
      python3 -c "import sys,html;print('\n'.join(html.unescape(l.rstrip()) for l in sys.stdin))" >> "$OUT_TMP" || true
    rm -f /tmp/news_feed.$$
  else
    echo "  (failed to fetch)" >> "$OUT_TMP"
  fi
  echo "" >> "$OUT_TMP"
done
# Ensure UTF-8 (attempt conversion if necessary)
if command -v iconv >/dev/null 2>&1; then
  iconv -f utf-8 -t utf-8 -c "$OUT_TMP" > "$OUT_TMP".utf8 || cat "$OUT_TMP" > "$OUT_TMP".utf8
  mv "$OUT_TMP".utf8 "$OUT_TMP"
fi
# Atomic move
mv "$OUT_TMP" "$OUT_FILE"
chmod 644 "$OUT_FILE"
# done
exit 0
