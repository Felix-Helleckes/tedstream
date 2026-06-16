#!/usr/bin/env python3
"""
Update the YouTube live stream title with a day counter.
Credentials are read from .env. Supports common naming variations.
"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ENV_FILE = Path("/home/felix/youtubestream/.env")
DAY_COUNTER_FILE = Path("/home/felix/youtubestream/stream_day_counter.txt")

# The permanent live stream video ID
VIDEO_ID = "M7lc1UVf-VE"

# Manual parsing of .env to avoid dotenv dependency issues and handle variations
if ENV_FILE.exists():
    with open(ENV_FILE, "r") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                key = key.strip()
                value = value.strip().strip('"\'')
                os.environ[key] = value

# Helper to get env var with fallbacks
def get_env(*keys):
    for k in keys:
        val = os.getenv(k)
        if val:
            return val
    return None

client_id = get_env("YOUTUBE_CLIENT_ID", "CLIENT_ID", "YT_CLIENT_ID")
client_secret = get_env("YOUTUBE_CLIENT_SECRET", "CLIENT_SECRET", "YT_CLIENT_SECRET")
refresh_token = get_env("YOUTUBE_REFRESH_TOKEN", "REFRESH_TOKEN", "YT_REFRESH_TOKEN")
token_uri = get_env("YOUTUBE_TOKEN_URI", "TOKEN_URI", "https://oauth2.googleapis.com/token")

# Keep a persistent day counter. Start at 121 as requested.
if DAY_COUNTER_FILE.exists():
    try:
        day_number = int(DAY_COUNTER_FILE.read_text().strip())
    except ValueError:
        day_number = 121
        DAY_COUNTER_FILE.write_text(str(day_number))
else:
    day_number = 121
    DAY_COUNTER_FILE.write_text(str(day_number))

new_title = f"[Day{day_number}] The Efficient Dev – Kraken Trading Bot Live"

if not all([client_id, client_secret, refresh_token]):
    print(f"[title-updater] Missing required credentials in .env. Skipping (would set: \"{new_title}\")")
    sys.exit(0)


def http_json(method, url, headers=None, data=None):
    req = urllib.request.Request(url, method=method, headers=headers or {})
    if data is not None:
        req.data = data
    with urllib.request.urlopen(req, timeout=30) as resp:
        body = resp.read().decode("utf-8")
        return json.loads(body) if body else {}


try:
    token_data = urllib.parse.urlencode({
        "client_id": client_id,
        "client_secret": client_secret,
        "refresh_token": refresh_token,
        "grant_type": "refresh_token",
    }).encode("utf-8")
    token_resp = http_json("POST", token_uri, headers={"Content-Type": "application/x-www-form-urlencoded"}, data=token_data)
    access_token = token_resp["access_token"]

    base = "https://www.googleapis.com/youtube/v3"
    headers = {"Authorization": f"Bearer {access_token}"}

    # Get current snippet to preserve categoryId and other required fields
    resp = http_json(
        "GET",
        f"{base}/videos?part=snippet&id={VIDEO_ID}",
        headers=headers,
    )
    if not resp.get("items"):
        print(f"[title-updater] No items returned for video ID {VIDEO_ID}. Full response: {resp}")
        sys.exit(1)
    current_snippet = resp["items"][0]["snippet"]
    current_title = current_snippet["title"]
    
    # Keep everything after the closing bracket '] ' to preserve the rest of the title
    if "] " in current_title:
        base_title = current_title.split("] ", 1)[1]
    else:
        base_title = current_title # fallback if format is unexpected
        
    new_title = f"[Day{day_number}] {base_title}"
    current_snippet["title"] = new_title

    payload = json.dumps({
        "id": VIDEO_ID,
        "snippet": current_snippet,
    }).encode("utf-8")

    http_json(
        "PUT",
        f"{base}/videos?part=snippet",
        headers={**headers, "Content-Type": "application/json"},
        data=payload,
    )

    # Prepare next day's number for the next nightly run.
    DAY_COUNTER_FILE.write_text(str(day_number + 1))

    print(f"[title-updater] Title updated to: \"{new_title}\" for video {VIDEO_ID}")

except urllib.error.HTTPError as e:
    detail = e.read().decode("utf-8", errors="replace")
    print(f"[title-updater] HTTP error: {e.code} {detail}")
    sys.exit(1)
except Exception as e:
    print(f"[title-updater] Error updating title: {e}")
    sys.exit(1)
