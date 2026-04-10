#!/bin/bash
# Overlay-Update Optimized - Multi-file output for precise layout and styling
# Ensure single instance via flock
LOCKFILE="/var/lock/update_overlay.lock"
exec 200>"$LOCKFILE" || exit 1
flock -n 200 || exit 0
TEMP_DIR="/tmp/youtube_stream"
BOT_DIR="/home/felix/tradingbot"
LOG_FILE="$BOT_DIR/logs/bot_activity.log"
MODE_FILE="$BOT_DIR/mode.txt"
TRADES_FILE="$BOT_DIR/trades.txt"
START_BALANCE=100.00
TARGET_BALANCE=100000.0

mkdir -p "$TEMP_DIR"

# Write Static Headers
echo "KRAKEN BOT - LIVE LOG STREAM" > "$TEMP_DIR/header_main_title.txt"
echo "BALANCES" > "$TEMP_DIR/header_balances.txt"
echo "TOP MOVERS 24H" > "$TEMP_DIR/header_movers.txt"
echo "OPEN POSITIONS" > "$TEMP_DIR/header_positions.txt"

last_news_update=0
last_movers_update=0
last_balance_update=0
last_heavy_update=0
last_trades_update=0
last_second=""

while true; do
  current_second=$(date +%S)
  
  # 1. CLOCK (Fast - every second)
  if [ "$current_second" != "$last_second" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S')" > "$TEMP_DIR/status_time.txt.tmp" && mv "$TEMP_DIR/status_time.txt.tmp" "$TEMP_DIR/status_time.txt"
    last_second=$current_second
  fi

  # 2. DATA UPDATES (Heavy)
  now=$(date +%s)
  if [ $((now - last_heavy_update)) -ge 2 ]; then
    # Logs (Showing last 3 trades and then 23 lines of general log)
    if [ -f "$LOG_FILE" ]; then
      PORT_TMP="/tmp/portfolio.$$"
      {
        printf "LAST TRADES:\n"
        # Fetch last 3 trades via API (max every 2 minutes to avoid rate limiting)
        VENV_PY="$BOT_DIR/venv/bin/python3"
        if [ $((now - last_trades_update)) -ge 120 ]; then
          if [ -x "$VENV_PY" ]; then
            "$VENV_PY" /home/felix/youtubestream/get_recent_trades.py > /tmp/recent_trades.$$ 2>/dev/null || true
          else
            /home/felix/youtubestream/get_recent_trades.py > /tmp/recent_trades.$$ 2>/dev/null || true
          fi
          last_trades_update=$now
        fi
        [ -f /tmp/recent_trades.$$ ] && tail -n 3 /tmp/recent_trades.$$ | tac | sed -e 's/^/  /' || printf "  (keine frischen Trades)\n"
        printf -- "----------\n"
        # Show latest bot lines with newest first.
        grep -a -vE "Validated trading pairs|Configuration loaded successfully|Loaded [0-9]+ trades from|Pair normalized:" "$LOG_FILE" | \
          tail -n 20 | \
          tac | \
          sed -E "s/\s*[|] *[Bb]al.*$//" | \
          sed -E "s/'txid': '[^']+'/'txid': [REDACTED]/g" | \
          sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2} ([0-9]{2}:[0-9]{2}:[0-9]{2}),[0-9]{3} - /\1 /'
      } > "$PORT_TMP"
      sed -i 's/%/\\%/g' "$PORT_TMP"
      mv "$PORT_TMP" "$TEMP_DIR/portfolio.txt"
    fi

    # Balances
    if [ -s "/home/felix/youtubestream/balances.txt" ]; then
      BAL_TMP="/tmp/bal_list.$$"
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        case "$line" in
          TOTAL:*|POSITION:*) continue ;;
        esac

        asset="${line%%:*}"
        val_str="${line#*:}"
        val_str="$(printf "%s" "$val_str" | sed 's/^[ \t]*//')"

        if [[ "$val_str" == *" - "* ]]; then
           qty="$(printf "%s" "$val_str" | cut -d' ' -f1)"
           eur="$(printf "%s" "$val_str" | cut -d'-' -f2 | sed 's/EUR//;s/[ \t]*//')"
           # skip zero spot balances
           [ "$(printf "%.4f" "$qty" 2>/dev/null || echo 0)" = "0.0000" ] && continue
           printf "%-5s: %.4f (%.2f EUR)\n" "$asset" "$qty" "$eur"
        else
           # EUR fiat line — only format if numeric
           if printf "%.2f" "$val_str" >/dev/null 2>&1; then
             printf "%-5s: %.2f\n" "$asset" "$val_str"
           fi
        fi
      done < "/home/felix/youtubestream/balances.txt" > "$BAL_TMP"
      T_VAL=$(grep '^TOTAL' "/home/felix/youtubestream/balances.txt" | awk '{print $(NF-1)}')
      printf "\nTOTAL: %.2f EUR\n" "$T_VAL" >> "$BAL_TMP"
      sed -i 's/%/\\%/g' "$BAL_TMP"
      mv "$BAL_TMP" "$TEMP_DIR/data_balances.txt"
      
      # Open Positions Data — show only real margin positions, not spot holdings
      POS_TMP="/tmp/pos_list.$$"
      grep '^POSITION:' "/home/felix/youtubestream/balances.txt" 2>/dev/null | while read -r line; do
        info="${line#POSITION:}"
        printf "%s\n" "$info"
      done > "$POS_TMP"
      [ ! -s "$POS_TMP" ] && echo "(keine offenen Margin-Positionen)" > "$POS_TMP"
      sed -i 's/%/\\%/g' "$POS_TMP"
      mv "$POS_TMP" "$TEMP_DIR/data_positions.txt"
    fi

    # Risk HUD - only show Trades (Mode removed)
    RISK_TMP="/tmp/risk_list.$$"
    NAS_TRADES=$(grep -oE 'Loaded [0-9]+ trades from' "$LOG_FILE" 2>/dev/null | tail -1 | grep -oE '[0-9]+' || echo 0)
[ -z "$NAS_TRADES" ] && NAS_TRADES=0
printf "Trades: %s\n" "$NAS_TRADES" > "$RISK_TMP"
sed -i 's/%/\%/g' "$RISK_TMP"
mv "$RISK_TMP" "$TEMP_DIR/data_risk.txt"

last_heavy_update=$now
  fi

  # 3. BACKGROUND FETCH
  if [ $((now - last_balance_update)) -ge 120 ]; then
    /home/felix/youtubestream/fetch_balances.sh
    NOW_EUR=$(grep -i '^TOTAL' /home/felix/youtubestream/balances.txt | awk '{print $(NF-1)}' 2>/dev/null || echo 0)
    [ -z "$NOW_EUR" ] || [ "$NOW_EUR" = "0" ] && NOW_EUR=$(grep "Bal:" "$LOG_FILE" 2>/dev/null | tail -1 | sed -E 's/.*Bal: ([0-9.]+)EUR.*/\1/' || echo 0)
    NOW_EUR=$(printf "%.2f" "$NOW_EUR")
    PCT=$(awk -v n="$NOW_EUR" -v s="$START_BALANCE" 'BEGIN{if(s>0) printf("%.2f", ((n/s)-1)*100); else printf("0.00")}')
    STATUS_LINE=$(printf "Start: %.2f EUR | Aktuell: %.2f EUR | %+.2f%% | Ziel: %.0f EUR" "$START_BALANCE" "$NOW_EUR" "$PCT" "$TARGET_BALANCE")
    printf "%s\n" "$STATUS_LINE" | sed 's/%/\\%/g' > "$TEMP_DIR/status_stats.txt.tmp" && mv "$TEMP_DIR/status_stats.txt.tmp" "$TEMP_DIR/status_stats.txt"
    last_balance_update=$now
  fi

  if [ $((now - last_movers_update)) -ge 120 ]; then
    ( VENV_PY="$BOT_DIR/venv/bin/python3"
      [ -x "$VENV_PY" ] && "$VENV_PY" /home/felix/youtubestream/get_top_movers.py 2>/dev/null > "$TEMP_DIR/data_movers.txt.tmp" && sed -i 's/%/\\%/g' "$TEMP_DIR/data_movers.txt.tmp" && mv "$TEMP_DIR/data_movers.txt.tmp" "$TEMP_DIR/data_movers.txt"
    ) &
    last_movers_update=$now
  fi
  # News fetched by separate hourly systemd timer (fetch_news.sh)
  # If the news file exists, the fetcher keeps it updated; otherwise keep a placeholder
  if [ -f "$TEMP_DIR/news_marquee.txt" ]; then
    :
  else
    echo "Market Monitoring Active" | sed 's/%/\%/g' > "$TEMP_DIR/news_marquee.txt"
  fi
  sleep 0.1
done
