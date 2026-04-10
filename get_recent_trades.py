#!/usr/bin/env python3
import sys
from pathlib import Path
from dotenv import load_dotenv
import os
sys.path.insert(0, '/home/felix/tradingbot')
try:
    from kraken_interface import KrakenAPI
except Exception as e:
    print(f"Error: cannot import KrakenAPI: {e}")
    sys.exit(1)

# load environment from TradingBot .env if present
env_path='/home/felix/tradingbot/.env'
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
    trades_dict = api.get_trade_history(fetch_all=False)
    if not trades_dict:
        print("No recent trades")
        sys.exit(0)
    # trades_dict is mapping txid -> trade info; sort by time
    trades = []
    for txid, info in trades_dict.items():
        trades.append((info.get('time',0), txid, info))
    trades.sort(reverse=True)
    from datetime import datetime
    for t in trades[:3]:
        info = t[2]
        pair = info.get('pair', '')
        typ = info.get('type', '')
        vol = info.get('vol', '')
        timestamp = info.get('time', 0)
        # format timestamp
        dt_str = datetime.utcfromtimestamp(timestamp).strftime('%Y-%m-%d %H:%M:%S')
        try:
            volf = float(vol)
            vol_s = f"{volf:.2f}"
        except Exception:
            vol_s = vol
        typ_s = (typ or '').lower()
        pair_s = (pair or '').lower()
        paren = ''
        descr = info.get('descr', '')
        try:
            if isinstance(descr, dict):
                order_txt = descr.get('order', '')
            else:
                order_txt = str(descr)
            import re as _re
            m_paren = _re.search(r"(\([^)]*\))", order_txt)
            if m_paren:
                paren = ' ' + m_paren.group(0)
        except Exception:
            paren = ''
        print(f"{dt_str} {typ_s} {vol_s} {pair_s}{paren}")
except Exception as e:
    print(f"Error fetching trades: {e}")
    sys.exit(1)
