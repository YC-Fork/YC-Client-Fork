# YC-Client-Fork (v2.00.001)

A feature-packed client for playing music, videos, radio stations, and live streams in Minecraft using [ComputerCraft: Tweaked](https://tweaked.cc/).

Works together with [YC-Server-Fork](https://github.com/YC-Fork/YC-Server-Fork).

---

## What's New in Version 2.00.001

- **Marquee Scrolling**: Long track titles and metadata (Artist, Views, Likes) automatically scroll as a smooth ticker.
- **Improved Reconnect Screen**: Shows `SERVER UNREACHABLE` or `CONNECTION TO SERVER LOST` with a 5-second retry countdown and an `[ Exit (Q) ]` button to quit anytime.
- **Dashboard Remote Control**: Full support for seeking, volume adjustments, skip, stop, and restart directly from the server's web dashboard.
- **Zero-Delay Audio Seeking**: Seek forward or backward without audio cutouts or freezing.
- **Live Stream Badge**: Pulsing `🔴 LIVE STREAM` indicator for YouTube/Twitch streams and radio stations.

---

## Installation

Run this command on your ComputerCraft computer or monitor:

```lua
wget run https://raw.githubusercontent.com/YC-Fork/YC-Client-Fork/main/installer.lua
```

---

## How to Use

```bash
yc-fork-client [options] [URL or search term...]
```

### Quick Commands / Hotkeys
- **Q**: Stop playing or exit reconnect screen
- **D**: Skip song
- **A**: Previous song (Back)
- **R**: Restart current song from start
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
To host your own server or use the web dashboard, visit:
https://github.com/YC-Fork/YC-Server-Fork
