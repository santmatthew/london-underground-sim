#!/bin/bash
# Regenerates every large asset that is not stored in git. Needs: python3, ffmpeg, Blender 5.2 (snap), Godot 4.7, internet.
# Runs the pipelines in order; each step is idempotent and can be run on its own.
set -e
cd "$(dirname "$0")/.."
python3 -m venv build/venv 2>/dev/null || true
build/venv/bin/pip install --quiet numpy pillow scipy piper-tts
echo "== network data (TfL open API)"
python3 tools/fetch_tfl.py && python3 tools/build_network.py
echo "== textures (ambientCG CC0 + procedural)"
python3 tools/fetch_textures.py && build/venv/bin/python tools/gen_textures.py
echo "== MakeHuman/MPFB asset packs + Blender extension, people, trains, props: see docs/ASSETS.md (long-running steps)"
echo "   tools/fetch_mpfb_assets.sh ; blender -b --factory-startup -P tools/blender/people/make_people.py ; ..."
echo "== audio: build/venv/bin/python tools/audio/make_audio.py"
echo "== import into Godot"
godot --headless --path . --import
