#!/usr/bin/env python3
import sys
import re

def extract_order_from_descr(line):
    # match patterns like "'descr': {'order': 'sell 0.21968 SOLEUR @ market with 2:1 leverage'}"
    m = re.search(r"descr\s*:\s*\{\s*['"]order['"]\s*:\s*['"]([^'"]+)['"]", line)
    if m:
        order = m.group(1).strip()
        # trim after '@ market' if present
        m2 = re.search(r"(@\s*market)", order, re.IGNORECASE)
        if m2:
            idx = m2.end()
            return order[:idx]
        # otherwise remove "with ..." suffix if present
        order = re.sub(r"\s+with\s+.*$", "", order, flags=re.IGNORECASE)
        return order
    return None


def format_line(line):
    # redact txid values
    line = re.sub(r"'txid'\s*:\s*\[[^\]]*\]", "'txid': [REDACTED]", line)
    # try to extract order from descr
    order = extract_order_from_descr(line)
    if order:
        # keep single quotes around order key like 'order': '...'
        return "'order': '" + order + "'"
    # fallback: try to find inline order text like "sell 0.21968 SOLEUR @ market"
    m = re.search(r"(buy|sell)[^
]{0,80}\@\s*market", line, re.IGNORECASE)
    if m:
        candidate = m.group(0).strip()
        # normalize spacing
        candidate = re.sub(r"\s+", " ", candidate)
        return "'order': '" + candidate + "'"
    # fallback: find buy/sell and first numeric volume and pair
    m2 = re.search(r"(buy|sell)\s*([0-9]+(?:\.[0-9]+)?)\s*([A-Za-z/]+)", line, re.IGNORECASE)
    if m2:
        typ = m2.group(1).lower()
        vol = m2.group(2)
        pair = m2.group(3).lower()
        try:
            volf = float(vol)
            vol_s = f"{volf:.2f}"
        except Exception:
            vol_s = vol
        return f"'order': '{typ} {vol_s} {pair}'"
    # otherwise, remove descr blocks and txid and return trimmed line
    line = re.sub(r"descr\s*:\s*\{[^}]*\}", "", line)
    line = re.sub(r"\s+", " ", line).strip()
    return line

if __name__=='__main__':
    for raw in sys.stdin:
        raw = raw.rstrip('
')
        if not raw:
            continue
        out = format_line(raw)
        print(out)
