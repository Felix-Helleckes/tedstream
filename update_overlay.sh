#!/bin/bash
# Overlay-Update Optimized - Multi-file output for precise layout and styling
TEMP_DIR="/tmp/youtube_stream"
BOT_DIR="/home/felix/TradingBot"
LOG_FILE="$BOT_DIR/logs/bot_activity.log"
MODE_FILE="$BOT_DIR/mode.txt"
TRADES_FILE="$BOT_DIR/trades.txt"
START_BALANCE=340.00
TARGET_BALANCE=100000.0

mkdir -p "$TEMP_DIR"

# Write Static Headers
echo "KRAKEN BOT - LIVE LOG STREAM" > "$TEMP_DIR/header_main_title.txt"
echo "BALANCES" > "$TEMP_DIR/header_balances.txt"
echo "TOP MOVERS 24H" > "$TEMP_DIR/header_movers.txt"
echo "OPEN POSITIONS" > "$TEMP_DIR/header_positions.txt"
echo "RISK HUD" > "$TEMP_DIR/header_risk.txt"

last_news_update=0
last_movers_update=0
last_heavy_update=0
last_second=""

while true; do
  current_second=$(date +%S)
  
  # 1. HEADER (Fast)
  if [ "$current_second" != "$last_second" ]; then
    NOW_EUR=$(grep -i '^TOTAL' /home/felix/youtubestream/balances.txt | awk '{print $(NF-1)}' 2>/dev/null || echo 0)
    [ -z "$NOW_EUR" ] || [ "$NOW_EUR" = "0" ] && NOW_EUR=$(grep "Bal:" "$LOG_FILE" 2>/dev/null | tail -1 | sed -E 's/.*Bal: ([0-9.]+)EUR.*/\1/' || echo 0)
    NOW_EUR=$(printf "%.2f" "$NOW_EUR")
    PNL=$(awk -v n="$NOW_EUR" -v s="$START_BALANCE" 'BEGIN{printf("%.2f", n - s)}')
    PCT=$(awk -v n="$NOW_EUR" -v s="$START_BALANCE" 'BEGIN{if(s>0) printf("%.2f", ((n/s)-1)*100); else printf("0.00")}')
    [ $(echo "$PNL >= 0" | bc -l) -eq 1 ] && LABEL="Profit" || LABEL="Loss"

    echo "$(date '+%Y-%m-%d %H:%M:%S')" > "$TEMP_DIR/status_time.txt.tmp" && mv "$TEMP_DIR/status_time.txt.tmp" "$TEMP_DIR/status_time.txt"
    printf "Start: %.2fEUR | Now: %.2fEUR | %s: %.2fEUR (%s pct) | Target: %.1fEUR\n" "$START_BALANCE" "$NOW_EUR" "$LABEL" "$PNL" "$PCT" "$TARGET_BALANCE" > "$TEMP_DIR/status_stats.txt"
    
    last_second=$current_second
  fi

  # 2. DATA UPDATES (Heavy)
  now=$(date +%s)
  if [ $((now - last_heavy_update)) -ge 2 ]; then
    # Logs
    if [ -f "$LOG_FILE" ]; then
      PORT_TMP="/tmp/portfolio.$$"
      {
        printf "LAST TRADE:\n"
        LAST_T=$(grep -E "BUY|SELL" "$LOG_FILE" | tail -1 | sed -E 's/.*INFO - //' | sed -E 's/ \| RISK.*$//')
        printf "%s\n----------\n" "${LAST_T:-None}"
        grep -vE "Validated trading pairs|Configuration loaded successfully" "$LOG_FILE" | tail -25 2>/dev/null | sed -E 's/ \| RISK.*$//' | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2} ([0-9]{2}:[0-9]{2}:[0-9]{2}),[0-9]{3}/\1/' | tac
      } > "$PORT_TMP"
      sed -i 's/%/\\%/g' "$PORT_TMP"
      mv "$PORT_TMP" "$TEMP_DIR/portfolio.txt"
    fi

    # Balances List (Compact to avoid clipping on right edge)
    if [ -s "/home/felix/youtubestream/balances.txt" ]; then
      BAL_TMP="/tmp/bal_list.$$"
      grep -v '^TOTAL' "/home/felix/youtubestream/balances.txt" | grep -v '^$' | while read -r line; do
        asset=$(echo "$line" | cut -d: -f1)
        val_str=$(echo "$line" | cut -d: -f2- | sed 's/^[ \t]*//')
        if [[ "$val_str" == *" - "* ]]; then
           qty=$(echo "$val_str" | cut -d' ' -f1)
           eur=$(echo "$val_str" | cut -d'-' -f2 | sed 's/EUR//;s/[ \t]*//')
           printf "%-5s: %.2f - %.2f Euro\n" "$asset" "$qty" "$eur"
        else
           printf "%-5s: %.2f Euro\n" "$asset" "$val_str"
        fi
      done > "$BAL_TMP"
      T_VAL=$(grep '^TOTAL' "/home/felix/youtubestream/balances.txt" | awk '{print $(NF-1)}')
      printf "TOTAL: %.2f Euro\n" "$T_VAL" >> "$BAL_TMP"
      sed -i 's/%/\\%/g' "$BAL_TMP"
      mv "$BAL_TMP" "$TEMP_DIR/data_balances.txt"
    fi

    # Movers
    if [ -s "$TEMP_DIR/top_movers.txt" ]; then
      sed 's/%/\\%/g' "$TEMP_DIR/top_movers.txt" > "$TEMP_DIR/data_movers.txt"
    fi

    # Positions
    POS_TMP="/tmp/pos_list.$$"
    if [ -s "/home/felix/youtubestream/balances.txt" ]; then
      grep ' - ' "/home/felix/youtubestream/balances.txt" 2>/dev/null | grep -v ': 0.00000000 -' | awk -F'[: ]+' '{printf "%sEUR: %.2f\n", $1, $2}' > "$POS_TMP"
    fi
    sed -i 's/%/\\%/g' "$POS_TMP"
    mv "$POS_TMP" "$TEMP_DIR/data_positions.txt"

    # Risk HUD
    RISK_TMP="/tmp/risk_list.$$"
    MODE=$(grep "|" "$LOG_FILE" 2>/dev/null | grep -E 'RISK' | tail -1 | awk -F'|' '{print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//' || echo "UNKNOWN")
    TRADES=$(grep -oE 'Trades: [0-9]+' "$LOG_FILE" 2>/dev/null | tail -1 | awk -F': ' '{print $2}' || echo 0)
    printf "Mode: %s\nTrades: %s\n" "$MODE" "$TRADES" > "$RISK_TMP"
    sed -i 's/%/\\%/g' "$RISK_TMP"
    mv "$RISK_TMP" "$TEMP_DIR/data_risk.txt"

    last_heavy_update=$now
  fi

  # 3. BACKGROUND FETCH
  if [ $((now - last_movers_update)) -ge 120 ]; then
    ( VENV_PY="$BOT_DIR/venv/bin/python3"
      [ -x "$VENV_PY" ] && "$VENV_PY" /home/felix/youtubestream/get_top_movers.py 2>/dev/null > "$TEMP_DIR/data_movers.txt.tmp" && sed -i 's/%/\\%/g' "$TEMP_DIR/data_movers.txt.tmp" && mv "$TEMP_DIR/data_movers.txt.tmp" "$TEMP_DIR/data_movers.txt"
    ) &
    last_movers_update=$now
  fi
  if [ $((now - last_news_update)) -ge 180 ]; then
    (
      M_LINE=""
      declare -A FEEDS=(
        [CoinDesk]="https://www.coindesk.com/arc/outboundfeeds/rss/"
        [Cointelegraph]="https://cointelegraph.com/rss"
        [Decrypt]="https://decrypt.co/feed"
        [TheDefiant]="https://thedefiant.io/feed"
        [BitcoinMag]="https://bitcoinmagazine.com/feed"
        [CryptoSlate]="https://cryptoslate.com/feed/"
        [NewsBTC]="https://www.newsbtc.com/feed/"
        [BTC-ECHO]="https://www.btc-echo.de/feed/"
        [Bitcoin2Go]="https://bitcoin2go.de/feed/"
      )
      
      for name in "CoinDesk" "Cointelegraph" "Decrypt" "TheDefiant" "BitcoinMag" "CryptoSlate" "NewsBTC" "BTC-ECHO" "Bitcoin2Go"; do
        url="${FEEDS[$name]}"
        titles=$(curl -fsS "$url" 2>/dev/null | sed -n 's/<title>\(.*\)<\/title>/\1/p' | sed 's/^[ \t]*//;s/[ \t]*$//' | sed '/^$/d' | sed 1d | head -n 3)
        if [ -n "$titles" ]; then
          block="$name: "
          first=1
          while read -r line; do
            if [ -n "$line" ]; then
              if [ $first -eq 1 ]; then block="$block$line"; first=0; else block="$block   ***   $line"; fi
            fi
          done <<< "$titles"
          if [ -z "$M_LINE" ]; then M_LINE="$block"; else M_LINE="$M_LINE   ***   $block"; fi
        fi
      done
      echo "${M_LINE:-Market Monitoring Active}" | sed 's/%/\\%/g' > "$TEMP_DIR/news_marquee.txt"
    ) &
    last_news_update=$now
  fi
  sleep 0.1
done
