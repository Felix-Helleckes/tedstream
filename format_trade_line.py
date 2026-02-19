#!/usr/bin/env python3
import sys
import re


def extract_order_from_descr(line):
    # match patterns like "'descr': {'order': 'sell 0.21968 SOLEUR @ market with 2:1 leverage'}"
    m = re.search(r"descr\s*:\s*\{\s*['\"]order['\"]\s*:\s*['\"]([^'\"]+)['\"]", line)
    if m:
        order = m.group(1).strip()
        # trim after '@ market' if present (we'll drop the '@ market' part entirely per request)
        m2 = re.search(r"(@\s*market)", order, re.IGNORECASE)
        if m2:
            # keep only the part before '@' (drop '@ market')
            return order[:m2.start()].strip()
        # otherwise remove "with ..." suffix if present
        order = re.sub(r"\s+with\s+.*$", "", order, flags=re.IGNORECASE)
        return order
    return None


def round_floats_to_2(s: str) -> str:
    # Round any floating-point numbers with more than 2 decimals to 2 decimals
    def _round_match(m):
        try:
            v = float(m.group(0))
            return f"{v:.2f}"
        except Exception:
            return m.group(0)
    return re.sub(r"(?<![0-9.])([0-9]+\.[0-9]{3,})(?![0-9.])", lambda m: _round_match(m), s)


def format_line(line):
    # redact txid values (arrays like ['ABC'])
    line = re.sub(r"'txid'\s*:\s*\[[^\]]*\]", "'txid': [REDACTED]", line)
    # try to extract order from descr
    order = extract_order_from_descr(line)
    if order:
        # Normalize volume to 2 decimals in the extracted order if possible
        m = re.search(r"\b(buy|sell)\b\s*([0-9]+(?:\.[0-9]+)?)\s*([A-Za-z/]+)", order, re.IGNORECASE)
        if m:
            typ = m.group(1).lower()
            vol = m.group(2)
            pair = m.group(3)
            try:
                volf = float(vol)
                vol_s = f"{volf:.2f}"
            except Exception:
                vol_s = vol
            # return without '@ market'
            return f"{typ} {vol_s} {pair}"
        # if it doesn't match, just return the trimmed order
        return round_floats_to_2(order)
    # fallback: try to find inline order text like "sell 0.21968 SOLEUR @ market"
    m = re.search(r"\b(buy|sell)\b[^\n]{0,80}@\s*market", line, re.IGNORECASE)
    if m:
        candidate = m.group(0).strip()
        # normalize spacing
        candidate = re.sub(r"\s+", " ", candidate)
        # normalize volume to 2 decimals if possible
        m2 = re.search(r"\b(buy|sell)\b\s*([0-9]+(?:\.[0-9]+)?)\s*([A-Za-z/]+)", candidate, re.IGNORECASE)
        if m2:
            typ = m2.group(1).lower()
            vol = m2.group(2)
            pair = m2.group(3)
            try:
                volf = float(vol)
                vol_s = f"{volf:.2f}"
            except Exception:
                vol_s = vol
            return f"{typ} {vol_s} {pair}"
        return round_floats_to_2(candidate)
    # fallback: find buy/sell and first numeric volume and pair
    m2 = re.search(r"\b(buy|sell)\b\s*([0-9]+(?:\.[0-9]+)?)\s*([A-Za-z/]+)", line, re.IGNORECASE)
    if m2:
        typ = m2.group(1).lower()
        vol = m2.group(2)
        pair = m2.group(3)
        try:
            volf = float(vol)
            vol_s = f"{volf:.2f}"
        except Exception:
            vol_s = vol
        return f"{typ} {vol_s} {pair}"
    # otherwise, remove descr blocks and return trimmed line without keys
    line = re.sub(r"descr\s*:\s*\{[^}]*\}", "", line)
    line = re.sub(r"\s+", " ", line).strip()
    # round other numeric floats to 2 decimals
    return round_floats_to_2(line)


if __name__ == '__main__':
    for raw in sys.stdin:
        raw = raw.rstrip('\n')
        if not raw:
            continue
        out = format_line(raw)
        print(out)
