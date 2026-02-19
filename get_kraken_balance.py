#!/usr/bin/env python3
import sys
sys.path.insert(0, '/home/felix/TradingBot')
from kraken_interface import KrakenAPI
import os
from dotenv import load_dotenv

# Load environment
load_dotenv('/home/felix/TradingBot/.env')
api_key = os.getenv('KRAKEN_API_KEY')
api_secret = os.getenv('KRAKEN_API_SECRET')

try:
    api = KrakenAPI(api_key, api_secret)
    balance = api.get_account_balance()
    
    # Get EUR balance
    eur = float(balance.get('ZEUR', 0))
    total_value_eur = eur
    
    # Get current prices for each pair
    pairs_to_check = {
        'XXBT': 'XXBTZEUR',  # BTC pair name is different!
        'XETH': 'ETHEUR', 
        'SOL': 'SOLEUR',
        'ADA': 'ADAEUR',
        'DOT': 'DOTEUR',
        'XXRP': 'XRPEUR',
        'LINK': 'LINKEUR'
    }
    
    prices = {}
    for asset, pair in pairs_to_check.items():
        try:
            data = api.get_market_data(pair)
            # The response key might be different from request pair
            for key in data.keys():
                if 'c' in data[key]:
                    prices[asset] = float(data[key]['c'][0])
                    break
        except Exception as e:
            prices[asset] = 0
    
    print(f"EUR: {eur:.2f}")
    
    # Check each crypto and calculate EUR value (High precision for Open Positions)
    btc = float(balance.get('XXBT', 0))
    btc_value = btc * prices.get('XXBT', 0)
    total_value_eur += btc_value
    print(f"BTC: {btc:.2f} - {btc_value:.2f}EUR")

    eth = float(balance.get('XETH', 0))
    eth_value = eth * prices.get('XETH', 0)
    total_value_eur += eth_value
    print(f"ETH: {eth:.2f} - {eth_value:.2f}EUR")

    sol = float(balance.get('SOL', 0))
    sol_value = sol * prices.get('SOL', 0)
    total_value_eur += sol_value
    print(f"SOL: {sol:.2f} - {sol_value:.2f}EUR")

    ada = float(balance.get('ADA', 0))
    ada_value = ada * prices.get('ADA', 0)
    total_value_eur += ada_value
    print(f"ADA: {ada:.2f} - {ada_value:.2f}EUR")

    dot = float(balance.get('DOT', 0))
    dot_value = dot * prices.get('DOT', 0)
    total_value_eur += dot_value
    print(f"DOT: {dot:.2f} - {dot_value:.2f}EUR")

    xrp = float(balance.get('XXRP', 0))
    xrp_value = xrp * prices.get('XXRP', 0)
    total_value_eur += xrp_value
    print(f"XRP: {xrp:.2f} - {xrp_value:.2f}EUR")

    link = float(balance.get('LINK', 0))
    link_value = link * prices.get('LINK', 0)
    total_value_eur += link_value
    print(f"LINK: {link:.2f} - {link_value:.2f}EUR")
        
    print("")
    print(f"TOTAL: {total_value_eur:.2f} EUR")
    
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
