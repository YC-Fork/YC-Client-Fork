# YC-Client-Fork (v2.00.001)

This repository contains the client player and library for **YC-Fork** running on Minecraft [ComputerCraft: Tweaked](https://tweaked.cc/).

## Features

- **Music & Video Playback**: Supports YouTube, Spotify, direct audio/video URLs, and local files.
- **Radio Stations & Live Streams**: Full support for Dutch/International live radio streams and YouTube/Twitch live broadcasts with a pulsing `🔴 LIVE STREAM` indicator.
- **Metadata Marquee Carousel**: Smooth scrolling ticker for long track titles and metadata (`By: Artist | Views: ... | Likes: ...`).
- **Remote Synchronization**: Fully synchronized with the YC-Fork Server Web Dashboard for remote seeking, volume control, skipping, stopping, and restarting.
- **Robust Reconnection UI**: Pixel-perfect connection loss handling showing `[!] SERVER UNREACHABLE` or `[!] CONNECTION TO SERVER LOST` with a 5-second retry countdown and an interactive red `[ Exit (Q) ]` button.
- **Non-Blocking Coroutines**: Event-stealing prevention for 100% responsive UI hotkeys and smooth DFPWM audio chunk streaming.

---

## Installation

Run this command in ComputerCraft:
```lua
wget run https://raw.githubusercontent.com/YC-Fork/YC-Client-Fork/main/installer.lua
```

---

## CLI Usage

```bash
yc-fork-client [options] [URL or search term...]
```

### Arguments:
- `URL or search term` *(optional)*: If omitted, the client enters the **READY TO PLAY!** interactive screen.

### Options:
- `-v`, `--verbose`: Enable verbose debug output.
- `-V`, `--volume <0-300>`: Set initial audio volume (default `100%` / value `1.0`).
- `-s`, `--server <address>`: Connect to a specific YC-Fork server (e.g. `ycfork.beltboys.nl`).
- `--nv`, `--no-video`: Disable video output (Audio-only player mode).
- `--na`, `--no-audio`: Disable audio output (Video-only player mode).
- `--sh`, `--shuffle`: Shuffle playlist before playing.
- `-l`, `--loop`: Loop current media item continuously.
- `--lp`, `--loop-playlist`: Loop the current playlist.
- `--fps <number>`: Force Sanjuuni frame rate for video output.

---

## In-Game Controls & Hotkeys

- **Q**: Stop playback / Exit reconnect screen
- **D**: Skip to next track
- **A**: Previous track (Back)
- **R**: Repeat current track from 0:00
- **Touch / Mouse Click**: Interactive UI buttons for Seek, Volume, Stop, Skip, and Repeat.

---

## Hosting Your Server
For server setup and web admin dashboard configuration, check out the server repository:
https://github.com/YC-Fork/YC-Server-Fork
