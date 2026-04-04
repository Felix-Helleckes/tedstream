#!/usr/bin/env python3
import sys
sys.path.insert(0, '/home/felix/tradingbot')
from kraken_interface import KrakenAPI
import os
from dotenv import load_dotenv

# Load environment
env_path = '/home/felix/tradingbot/.env'
if os.path.exists(env_path):
    load_dotenv(env_path)
else:
    load_dotenv('/home/felix/youtubestream/.env')
api_key = os.getenv('KRAKEN_API_KEY')
api_secret = os.getenv('KRAKEN_API_SECRET')

try:
    api = KrakenAPI(api_key, api_secret)
    pairs = ['ADAEUR', 'XXBTZEUR', 'DOTEUR', 'ETHEUR', 'LINKEUR', 'SOLEUR', 'XRPEUR']
    for pair in pairs:
        try:
            data = api.get_market_data(pair)
            for key in data.keys():
                if 'o' in data[key] and 'c' in data[key]:
                    open_price = float(data[key]['o'])
                    close_price = float(data[key]['c'][0])
                    change = ((close_price - open_price) / open_price) * 100 if open_price else 0
                    asset_name = pair.replace('ZEUR','').replace('EUR','').replace('XRP','XXRP').replace('BTC','XXBT').replace('XX','X')
                    # Standard names for display
                    display_name = pair.replace('ZEUR','').replace('EUR','').replace('XXBT','BTC').replace('XXRP','XRP')
                    print(f"{display_name}: {change:+.2f}pct")
        except:
            continue
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
