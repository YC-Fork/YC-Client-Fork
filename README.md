# YC-Client-Fork (v2.01.002)

A feature-packed client for playing music, videos, radio stations, and live streams in Minecraft using [ComputerCraft: Tweaked](https://tweaked.cc/).

Pairs with [YC-Server-Fork](https://github.com/YC-Fork/YC-Server-Fork).

---

## Features & Improvements

- **Marquee Title Ticker**: Long track titles and metadata (Artist, Views, Likes) automatically scroll smoothly across the screen.
- **Smart Audio-Only Detection**: Seamlessly detects audio-only tracks and avoids unnecessary video chunk requests.
- **Paced Buffer Streaming**: Optimized WebSocket buffer streaming for 100% smooth, stutter-free playback.
- **Enhanced Reconnect Interface**: Interactive reconnection screen showing status (`SERVER UNREACHABLE` / `CONNECTION LOST`), automatic 60-second retry timer, manual retry cooldown, and `[ Exit (Q) ]` option.
- **Full Dashboard Integration**: Remote seeking, volume control (0-300%), skip, stop, restart, and queueing driven from the web dashboard.
- **Instant Audio Seeking**: Seek forward or backward anywhere in a track without audio cutouts or freezing.
- **Live Stream Indicator**: Pulsing `🔴 LIVE STREAM` badge for live broadcasts and online radio stations.

---

## Installation

Run this command on your ComputerCraft computer or monitor:

```lua
wget run https://raw.githubusercontent.com/YC-Fork/YC-Client-Fork/main/installer.lua
```

---

## Usage

```bash
yc-fork-client [options] [URL or search term...]
```

### Hotkeys & Controls
- **Q** / **X**: Stop playing or exit reconnect screen
- **D**: Skip song
- **A**: Previous song (Back)
- **R**: Restart current song from `0:00`
- **Mouse / Touch Screen**: Click UI buttons to adjust volume, skip, stop, restart, or seek.

### CLI Options
- `-v`, `--verbose`: Show debug logs.
- `-V`, `--volume <0-300>`: Set starting volume (default: 100).
- `-s`, `--server <address>`: Connect to a custom server (e.g. `ycfork.beltboys.nl`).
- `--nv`, `--no-video`: Audio-only mode (saves bandwidth).
- `--na`, `--no-audio`: Video-only mode.
- `--sh`, `--shuffle`: Shuffle playlist.
- `-l`, `--loop`: Loop current song.
- `--lp`, `--loop-playlist`: Loop full playlist.
- `--fps <number>`: Set target video frame rate.

---

## Server Setup

To host your own backend server or access the web admin dashboard, visit:  
👉 [https://github.com/YC-Fork/YC-Server-Fork](https://github.com/YC-Fork/YC-Server-Fork)
