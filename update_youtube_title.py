#!/usr/bin/env python3
"""
Update the YouTube live stream title with a day counter.
Credentials are read from .env (YOUTUBE_CLIENT_ID, YOUTUBE_CLIENT_SECRET,
YOUTUBE_REFRESH_TOKEN, YOUTUBE_TOKEN_URI) — no token.json needed.
"""
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

from dotenv import load_dotenv

ENV_FILE = Path(__file__).parent / ".env"
STREAM_START_FILE = Path(__file__).parent / "stream_start_date.txt"

load_dotenv(ENV_FILE)

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

client_id = os.getenv("YOUTUBE_CLIENT_ID")
client_secret = os.getenv("YOUTUBE_CLIENT_SECRET")
refresh_token = os.getenv("YOUTUBE_REFRESH_TOKEN")
token_uri = os.getenv("YOUTUBE_TOKEN_URI", "https://oauth2.googleapis.com/token")

if not all([client_id, client_secret, refresh_token]):
    print(f"[title-updater] YOUTUBE_CLIENT_ID/SECRET/REFRESH_TOKEN not set in .env – skipping (would set: \"{new_title}\")")
    sys.exit(0)

try:
    from google.oauth2.credentials import Credentials
    from googleapiclient.discovery import build
    from google.auth.transport.requests import Request
except ImportError:
    print("[title-updater] google-api-python-client not installed – skipping title update")
    sys.exit(0)

try:
    creds = Credentials(
        token=None,
        refresh_token=refresh_token,
        token_uri=token_uri,
        client_id=client_id,
        client_secret=client_secret,
        scopes=["https://www.googleapis.com/auth/youtube"],
    )
    creds.refresh(Request())

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
