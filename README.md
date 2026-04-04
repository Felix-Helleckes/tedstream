# 📺 Kraken Trading Bot — 24/7 YouTube Live Stream

> A Raspberry Pi-powered live stream that displays a Kraken crypto trading bot in real time — built with ffmpeg, bash, and Python.

🔴 **Watch live:** [youtube.com/@TheEfficientDev](https://www.youtube.com/@TheEfficientDev)

---

## What is this?

This project turns a Kraken algorithmic trading bot into a 24/7 YouTube livestream. The stream shows live portfolio balances, open positions, recent trades, top crypto movers, and a scrolling news ticker — all updated automatically every 2 minutes directly from the Kraken API.

No OBS. No GUI. Just ffmpeg, bash, and a Raspberry Pi.

---

## Stream Layout

```
┌─────────────────────────────────────────────────────┐
│ KRAKEN BOT - LIVE LOG STREAM          BALANCES      │
│ 2026-04-04 09:00:00                   EUR : 278 EUR  │
│ Balance: 319.56 EUR                   ETH : 0.02     │
│                                       TOTAL: 319 EUR │
│ LAST TRADES:                                         │
│   sell 0.22 soleur                    TOP MOVERS 24H │
│ ----------                            BTC  +2.4%     │
│ 09:00:01 [1] ETH:HOLD SOL:HOLD ...   ETH  -1.1%     │
│ ...                                                  │
│                                       OPEN POSITIONS  │
│                                       ...            │
│ ── CoinDesk: Bitcoin hits new high ── Cointelegraph  │
└─────────────────────────────────────────────────────┘
```

---

## Architecture

| Component | Role |
|---|---|
| `stream.sh` | ffmpeg process — renders overlay text onto a black canvas and streams to YouTube via RTMP |
| `update_overlay.sh` | Loop that writes data to `/tmp/youtube_stream/*.txt` files every 2 minutes |
| `get_kraken_balance.py` | Fetches live balances from Kraken API |
| `get_recent_trades.py` | Fetches last 3 trades from Kraken API |
| `get_top_movers.py` | Fetches 24h price changes for major pairs |
| `fetch_balances.sh` | Wrapper to call `get_kraken_balance.py` safely |
| `fetch_news.sh` | Hourly news fetch from crypto RSS feeds (CoinDesk, Cointelegraph, etc.) |
| `youtube-stream.service` | systemd service — auto-restarts stream on crash or reboot |
| `youtube-overlay.service` | systemd service — runs the overlay updater continuously |
| `fetch-news.timer` | systemd timer — triggers news fetch every hour |

---

## Requirements

- Raspberry Pi (or any Linux machine)
- `ffmpeg` with `libx264` and `drawtext` support
- Python 3 + `krakenex`, `python-dotenv`, `toml`
- A Kraken account with API key (read-only permissions sufficient for display)
- A YouTube channel with live streaming enabled

---

## Setup

### 1. Clone the repo
```bash
git clone https://github.com/irgendwasmitfelix/tedstream.git
cd tedstream
```

### 2. Create your `.env` file
```bash
cp .env.example .env
```
Edit `.env` with your credentials:
```env
KRAKEN_API_KEY=your_key_here
KRAKEN_API_SECRET=your_secret_here
YOUTUBE_RTMP_URL=rtmp://a.rtmp.youtube.com/live2
YOUTUBE_STREAM_KEY=your_stream_key_here
```

### 3. Install Python dependencies
```bash
python3 -m venv /path/to/your/tradingbot/venv
/path/to/your/tradingbot/venv/bin/pip install krakenex python-dotenv toml
```

### 4. Install systemd services
```bash
sudo cp youtube-stream.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now youtube-stream
sudo systemctl enable --now youtube-overlay
sudo systemctl enable --now fetch-news.timer
```

---

## Service Management

```bash
# Stream
sudo systemctl start youtube-stream
sudo systemctl stop youtube-stream
sudo systemctl status youtube-stream

# Overlay updater
sudo systemctl restart youtube-overlay

# Live logs
sudo journalctl -u youtube-stream -f
sudo journalctl -u youtube-overlay -f
```

---

## Security

- **Never commit your `.env`** — it is listed in `.gitignore`
- Use a Kraken API key with **read-only** permissions where possible
- The stream key should be treated like a password

---

## Tech Stack

- **ffmpeg** — video rendering and RTMP streaming
- **bash** — orchestration and data pipeline
- **Python 3** — Kraken API integration
- **krakenex** — Kraken API client
- **systemd** — process management and scheduling
- **Raspberry Pi** — always-on hardware

---

## 📺 Watch the stream

**[youtube.com/@TheEfficientDev](https://www.youtube.com/@TheEfficientDev)**
