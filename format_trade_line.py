#!/usr/bin/env python3
import sys
import re

def format_line(line):
    # Try to find pair, type, vol
    # patterns like "'pair': 'XBTEUR'" or "pair=XBTEUR"
    pair=None
    typ=None
    vol=None
    # search common patterns
    m=re.search(r"['\"]pair['\"]\s*[:=]\s*['\"]?([A-Za-z0-9_/+-]+)['\"]?", line)
    if m:
        pair=m.group(1)
    m=re.search(r"['\"]type['\"]\s*[:=]\s*['\"]?([A-Za-z]+)['\"]?", line)
    if m:
        typ=m.group(1)
    m=re.search(r"['\"]vol['\"]\s*[:=]\s*['\"]?([0-9.]+)['\"]?", line)
    if m:
        vol=m.group(1)
    # fallback: try to find patterns like BUY 0.123 or SELL 1.23
    if not typ:
        m=re.search(r"\b(BUY|SELL|buy|sell)\b", line)
        if m:
            typ=m.group(1)
    if not vol:
        m=re.search(r"\b([0-9]+\.[0-9]+)\b", line)
        if m:
            vol=m.group(1)
    # If we have at least type and vol, print condensed
    if typ and vol and pair:
        try:
            volf=float(vol)
            vols=f"{volf:.2f}"
        except Exception:
            vols=vol
        return f"{typ.lower()} {vols} {pair.lower()}"
    # If only type and pair
    if typ and pair and not vol:
        return f"{typ.lower()} {pair.lower()}"
    # If none matched, try to clean by removing txid and descr blocks and return short remainder
    # redact txid values
    line = re.sub(r"'txid'\s*:\s*'[^']+'", "'txid': [REDACTED]", line)
    # remove large dicts like descr: {...}
    line = re.sub(r"descr\s*:\s*\{[^}]*\}", "", line)
    # collapse whitespace
    line = re.sub(r"\s+", " ", line).strip()
    # strip leading timestamp and INFO - if present
    line = re.sub(r"^\d{4}-\d{2}-\d{2} .*INFO - ", "", line)
    return line

if __name__=='__main__':
    for raw in sys.stdin:
        raw=raw.rstrip('\n')
        if not raw:
            continue
        out=format_line(raw)
        print(out)
