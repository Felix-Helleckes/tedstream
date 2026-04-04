#!/bin/bash
# Runs get_kraken_balance.py using TradingBot virtualenv to avoid system pip issues
cd /home/felix/youtubestream || exit 1
VENV_PY="/home/felix/tradingbot/venv/bin/python3"
if [ -x "$VENV_PY" ]; then
  "$VENV_PY" get_kraken_balance.py > balances.txt.tmp 2>/dev/null && mv balances.txt.tmp balances.txt || rm -f balances.txt.tmp
else
  python3 get_kraken_balance.py > balances.txt.tmp 2>/dev/null && mv balances.txt.tmp balances.txt || rm -f balances.txt.tmp
fi
