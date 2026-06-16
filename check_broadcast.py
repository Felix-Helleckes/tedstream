import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ENV_FILE = Path("/home/felix/youtubestream/.env")
if ENV_FILE.exists():
    with open(ENV_FILE, "r") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                key = key.strip()
                value = value.strip().strip('"\'')
                os.environ[key] = value

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

if not all([client_id, client_secret, refresh_token]):
    print("Missing credentials")
    sys.exit(1)

def http_json(method, url, headers=None, data=None):
    req = urllib.request.Request(url, method=method, headers=headers or {})
    if data is not None:
        req.data = data
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = resp.read().decode("utf-8")
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as e:
        print(f"HTTP error: {e.code} {e.read().decode('utf-8', errors='replace')}")
        raise

token_data = urllib.parse.urlencode({
    "client_id": client_id,
    "client_secret": client_secret,
    "refresh_token": refresh_token,
    "grant_type": "refresh_token",
}).encode("utf-8")
token_resp = http_json("POST", token_uri, headers={"Content-Type": "application/x-www-form-urlencoded"}, data=token_data)
access_token = token_resp["access_token"]
print("Got access token")

base = "https://www.googleapis.com/youtube/v3"
headers = {"Authorization": f"Bearer {access_token}"}

# Get active broadcast
resp = http_json(
    "GET",
    f"{base}/liveBroadcasts?part=snippet,contentDetails&broadcastStatus=active",
    headers=headers,
)
print(json.dumps(resp, indent=2))
