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
START_BALANCE=340.00
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
  
  # 1. HEADER (Fast)
  if [ "$current_second" != "$last_second" ]; then
    NOW_EUR=$(grep -i '^TOTAL' /home/felix/youtubestream/balances.txt | awk '{print $(NF-1)}' 2>/dev/null || echo 0)
    [ -z "$NOW_EUR" ] || [ "$NOW_EUR" = "0" ] && NOW_EUR=$(grep "Bal:" "$LOG_FILE" 2>/dev/null | tail -1 | sed -E 's/.*Bal: ([0-9.]+)EUR.*/\1/' || echo 0)
    NOW_EUR=$(printf "%.2f" "$NOW_EUR")
    PNL=$(awk -v n="$NOW_EUR" -v s="$START_BALANCE" 'BEGIN{printf("%.2f", n - s)}')
    PCT=$(awk -v n="$NOW_EUR" -v s="$START_BALANCE" 'BEGIN{if(s>0) printf("%.2f", ((n/s)-1)*100); else printf("0.00")}')
    [ $(echo "$PNL >= 0" | bc -l) -eq 1 ] && LABEL="Profit" || LABEL="Loss"

    echo "$(date '+%Y-%m-%d %H:%M:%S')" > "$TEMP_DIR/status_time.txt.tmp" && mv "$TEMP_DIR/status_time.txt.tmp" "$TEMP_DIR/status_time.txt"
    printf "Balance: %.2f EUR\n" "$NOW_EUR" > "$TEMP_DIR/status_stats.txt"
    
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
        # Fetch last 3 trades via API (max every 5 minutes to avoid rate limiting)
        VENV_PY="$BOT_DIR/venv/bin/python3"
        if [ $((now - last_trades_update)) -ge 120 ]; then
          if [ -x "$VENV_PY" ]; then
            "$VENV_PY" /home/felix/youtubestream/get_recent_trades.py > /tmp/recent_trades.$$ 2>/dev/null || true
          else
            /home/felix/youtubestream/get_recent_trades.py > /tmp/recent_trades.$$ 2>/dev/null || true
          fi
          last_trades_update=$now
        fi
        [ -f /tmp/recent_trades.$$ ] && tail -n 3 /tmp/recent_trades.$$ | sed -e "s/^/\t/" || true
        printf -- "----------\n"
        # Filter noisy system lines, mask TXIDs, and show last 23 log lines
        grep -vE "Validated trading pairs|Configuration loaded successfully" "$LOG_FILE" | \
        sed -E "s/'txid': '[^']+'/'txid': [REDACTED]/g" | \
        /home/felix/youtubestream/format_trade_line.py | \
        tail -23 2>/dev/null | sed -E 's/ \| RISK.*$//' | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2} ([0-9]{2}:[0-9]{2}:[0-9]{2}),[0-9]{3}/\1/' | tac
      } > "$PORT_TMP"
      sed -i 's/%/\\%/g' "$PORT_TMP"
      mv "$PORT_TMP" "$TEMP_DIR/portfolio.txt"
    fi

    # Balances
    if [ -s "/home/felix/youtubestream/balances.txt" ]; then
      BAL_TMP="/tmp/bal_list.$$"
      grep -v '^TOTAL' "/home/felix/youtubestream/balances.txt" | grep -v '^$' | while read -r line; do
        asset=$(echo "$line" | cut -d: -f1); val_str=$(echo "$line" | cut -d: -f2- | sed 's/^[ \t]*//')
        if [[ "$val_str" == *" - "* ]]; then
           qty=$(echo "$val_str" | cut -d' ' -f1)
           eur=$(echo "$val_str" | cut -d'-' -f2 | sed 's/EUR//;s/[ \t]*//')
           # skip zero positions
           [ "$(printf "%.2f" "$eur" 2>/dev/null || echo 0)" = "0.00" ] && continue
           printf "%-5s: %.4f (%.2f EUR)\n" "$asset" "$qty" "$eur"
        else
           # EUR fiat line — no suffix needed, it's already EUR
           printf "%-5s: %.2f EUR\n" "$asset" "$val_str"
        fi
      done > "$BAL_TMP"
      T_VAL=$(grep '^TOTAL' "/home/felix/youtubestream/balances.txt" | awk '{print $(NF-1)}')
      printf "\nTOTAL: %.2f EUR\n" "$T_VAL" >> "$BAL_TMP"
      sed -i 's/%/\\%/g' "$BAL_TMP"
      mv "$BAL_TMP" "$TEMP_DIR/data_balances.txt"
      
      # Open Positions Data
      POS_TMP="/tmp/pos_list.$$"
      grep ' - ' "/home/felix/youtubestream/balances.txt" 2>/dev/null | grep -v ': 0.00000000 -' | awk -F'[: ]+' '{printf "%sEUR: %.2f\n", $1, $2}' > "$POS_TMP"
      sed -i 's/%/\\%/g' "$POS_TMP"
      mv "$POS_TMP" "$TEMP_DIR/data_positions.txt"
    fi

    # Risk HUD - only show Trades (Mode removed)
    RISK_TMP="/tmp/risk_list.$$"
    TRADES=$(grep -oE 'Trades: [0-9]+' "$LOG_FILE" 2>/dev/null | tail -1 | awk -F': ' '{print $2}' || echo 0)
    printf "Trades: %s
" "$TRADES" > "$RISK_TMP"
    sed -i 's/%/\%/g' "$RISK_TMP"
    mv "$RISK_TMP" "$TEMP_DIR/data_risk.txt"

    last_heavy_update=$now
  fi

  # 3. BACKGROUND FETCH
  if [ $((now - last_balance_update)) -ge 120 ]; then
    /home/felix/youtubestream/fetch_balances.sh &
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
