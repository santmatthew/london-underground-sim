#!/bin/bash
# Records an autopilot journey to an MP4 using Godot's Movie Maker (deterministic fixed timestep, works under xvfb).
# usage: tools/record_video.sh <out.mp4> [seed] [fps] [resolution] [extra game args...]
# Videos are NOT committed to git (see .gitignore); send them out-of-band.
set -e
cd "$(dirname "$0")/.."
OUT=${1:-build/journey.mp4}; SEED=${2:-1}; FPS=${3:-30}; RES=${4:-1280x720}; shift 4 2>/dev/null || shift $# 
AVI="${OUT%.mp4}.avi"
xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --resolution $RES --write-movie "$AVI" --fixed-fps $FPS res://scenes/main.tscn -- --autopilot --seed=$SEED --quit-when-done "$@" 2>&1 | grep -E "RESULT|BOT|ERROR|SCRIPT" | head -80
ffmpeg -y -loglevel error -i "$AVI" -c:v libx264 -preset medium -crf 21 -pix_fmt yuv420p -movflags +faststart "$OUT"
rm -f "$AVI"
ls -la "$OUT"
