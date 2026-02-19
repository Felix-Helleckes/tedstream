#!/usr/bin/env python3
from pathlib import Path
import re
src = Path('/home/felix/youtubestream/balances.txt')
out_dir = Path('/tmp/youtube_stream')
out_dir.mkdir(parents=True, exist_ok=True)
if not src.exists():
    print('balances.txt missing')
    raise SystemExit(1)
lines = src.read_text().strip().splitlines()
bal_lines = []
pos_lines = []
for line in lines:
    if not line.strip():
        continue
    if line.upper().startswith('TOTAL'):
        # Will handle later
        total_line = line
        continue
    # Example: ETH: 0.06698957 - 117.86EUR
    m = re.match(r"^([^:]+):\s*(.+)$", line)
    if not m:
        continue
    asset = m.group(1).strip()
    rest = m.group(2).strip()
    if ' - ' in rest:
        parts = rest.split(' - ')
        qty = parts[0].strip()
        eur = parts[1].replace('EUR','').strip()
        try:
            qtyf = float(qty)
        except:
            qtyf = 0.0
        try:
            eurf = float(eur)
        except:
            eurf = 0.0
        bal_lines.append(f"{asset}: {qtyf:.2f} - {eurf:.2f}EUR")
        pos_lines.append(f"{asset} EUR: {qtyf:.2f}")
    else:
        # e.g. EUR: 88.45
        try:
            valf = float(rest.replace('EUR','').strip())
        except:
            valf = 0.0
        bal_lines.append(f"{asset}: {valf:.2f}")
# total
if 'total_line' in locals():
    m = re.search(r"([0-9]+\.?[0-9]*)", total_line)
    if m:
        total = float(m.group(1))
    else:
        total = 0.0
else:
    total = 0.0

# write outputs
with open(out_dir / 'data_balances.txt', 'w') as f:
    for l in bal_lines:
        f.write(l + "\n")
    f.write('\n')
    f.write(f"TOTAL: {total:.2f} EUR\n")

with open(out_dir / 'data_positions.txt', 'w') as f:
    for l in pos_lines:
        f.write(l + "\n")
