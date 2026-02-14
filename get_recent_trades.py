#!/usr/bin/env python3
import sys
from pathlib import Path
from dotenv import load_dotenv
import os
sys.path.insert(0, '/home/felix/TradingBot')
try:
    from kraken_interface import KrakenAPI
except Exception as e:
    print(f"Error: cannot import KrakenAPI: {e}")
    sys.exit(1)

# load environment from TradingBot .env if present
env_path='/home/felix/TradingBot/.env'
if Path(env_path).exists():
    load_dotenv(env_path)

api_key=os.getenv('KRAKEN_API_KEY')
api_secret=os.getenv('KRAKEN_API_SECRET')
try:
    api = KrakenAPI(api_key, api_secret)
except Exception as e:
    print(f"Error: creating KrakenAPI: {e}")
    sys.exit(1)

try:
    trades = api.get_recent_trades(limit=3)
    if not trades:
        print("No recent trades")
        sys.exit(0)
    for t in trades:
        ts = t.get('time') or t.get('timestamp') or ''
        sym = t.get('symbol') or t.get('pair') or ''
        typ = t.get('side') or t.get('type') or ''
        price = t.get('price') or t.get('rate') or ''
        vol = t.get('volume') or t.get('amount') or ''
        print(f"{ts} {sym} {typ} {vol}@{price}")
except Exception as e:
    print(f"Error fetching trades: {e}")
    sys.exit(1)
