#!/usr/bin/env python3
"""
Update the YouTube live stream title with a day counter.
Requires a YouTube Data API v3 OAuth token (token.json) in this directory.
If credentials are missing, exits cleanly without error.
"""
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

TOKEN_FILE = Path(__file__).parent / "token.json"
STREAM_START_FILE = Path(__file__).parent / "stream_start_date.txt"

# Determine stream start date
if STREAM_START_FILE.exists():
    try:
        start_str = STREAM_START_FILE.read_text().strip()
        stream_start = datetime.fromisoformat(start_str).replace(tzinfo=timezone.utc)
    except ValueError:
        stream_start = datetime.now(tz=timezone.utc)
        STREAM_START_FILE.write_text(stream_start.date().isoformat())
else:
    stream_start = datetime.now(tz=timezone.utc)
    STREAM_START_FILE.write_text(stream_start.date().isoformat())

day_number = (datetime.now(tz=timezone.utc).date() - stream_start.date()).days + 1
new_title = f"🤖 Kraken Trading Bot Live – Tag {day_number} | KI-Bot handelt Bitcoin, ETH & Co."

if not TOKEN_FILE.exists():
    print(f"[title-updater] No token.json found – skipping title update (would set: \"{new_title}\")")
    sys.exit(0)

try:
    from google.oauth2.credentials import Credentials
    from googleapiclient.discovery import build
    from google.auth.transport.requests import Request
except ImportError:
    print("[title-updater] google-api-python-client not installed – skipping title update")
    sys.exit(0)

try:
    creds = Credentials.from_authorized_user_file(str(TOKEN_FILE))
    if creds.expired and creds.refresh_token:
        creds.refresh(Request())
        TOKEN_FILE.write_text(creds.to_json())

    youtube = build("youtube", "v3", credentials=creds)

    # Find the active live broadcast
    broadcasts = youtube.liveBroadcasts().list(
        part="id,snippet",
        broadcastStatus="active",
        broadcastType="all",
    ).execute()

    if not broadcasts.get("items"):
        print("[title-updater] No active broadcasts found")
        sys.exit(0)

    broadcast_id = broadcasts["items"][0]["id"]
    youtube.liveBroadcasts().update(
        part="snippet",
        body={
            "id": broadcast_id,
            "snippet": {
                "title": new_title,
                "scheduledStartTime": broadcasts["items"][0]["snippet"]["scheduledStartTime"],
            },
        },
    ).execute()

    print(f"[title-updater] Title updated to: \"{new_title}\"")

except Exception as e:
    print(f"[title-updater] Error updating title: {e}")
    sys.exit(1)
