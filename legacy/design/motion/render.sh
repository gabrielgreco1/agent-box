#!/bin/bash
# Re-render the two silent design assets. Requires motion-designer, Playwright and ffmpeg.
set -euo pipefail
MOTION_DIR="$(cd "$(dirname "$0")" && pwd)"
RENDERER="${1:-/Users/gabrielgreco/.codex/skills/motion-designer/scripts/render.py}"
FRAME_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/racky-motion.XXXXXX")"
trap 'rm -rf "$FRAME_ROOT"' EXIT
render_asset() {
  local page="$1" size="$2" name="$3"
  nice -n 15 python3 "$RENDERER" "$MOTION_DIR/$page" --ar "$size" --sweep 10
  nice -n 15 python3 "$RENDERER" "$MOTION_DIR/$page" --ar "$size" --fps 240 --workers 3 --out "$FRAME_ROOT/$name"
  nice -n 15 ffmpeg -y -loglevel error -threads 3 -framerate 240 -i "$FRAME_ROOT/$name/%05d.jpg" \
    -vf "tmix=frames=4:weights='1 1 1 1',fps=60,format=yuv420p" \
    -c:v libx264 -preset slow -crf 17 -movflags +faststart -an "$MOTION_DIR/$name.mp4"
}
render_asset box-loop.html 512x512 box-loop
render_asset timeline.html 1920x1200 racky-walkthrough
