# Underground Sim — architecture & conventions

First-person London Underground navigation game. Godot 4.7 (GDScript) + Blender 5.2 (asset generation).
Goal: get from a random spot in a random station to a given destination as fast as possible, with a real
timetable, time-of-day crowds, and photoreal-ish textures/people.

## Toolchain facts (verified)
- Godot: `/usr/bin/godot` (4.7.2). Renders on the NVIDIA RTX 3050 Ti (4 GB VRAM) via Vulkan Forward+.
  Headless screenshots WITHOUT touching the user's desktop: `xvfb-run -a -s "-screen 0 1600x900x24" godot --path <proj> --resolution 1280x720 <scene>`
  then have the scene save `get_viewport().get_texture().get_image().save_png(...)` after a few frames and `get_tree().quit()`.
  (A "No DRI3" warning is harmless.) Import assets with `godot --headless --path <proj> --import` (run again if it errors the first time).
- Blender: `/snap/blender/...` 5.2.2 LTS, run as `blender -b --factory-startup -P script.py`. It is a SNAP: it cannot see `/tmp`.
  **Keep all Blender input/output inside `/home/msant/Projects/Personal/underground-sim/` (non-hidden dirs).**
- MPFB (MakeHuman for Blender) 2.0.17 is installed as extension repo `user_default`; asset packs live in
  `~/.config/blender/5.2/extensions/.user/user_default/mpfb/data/` (clothes, skins, hair, ...). Download progress: `build/fetch_mpfb.log` (`ALL_DONE` at the end).
- No numpy/PIL system-wide for python3 except PIL; use `python3 -m venv build/venv` if you need more.
- CMU mocap BVH files are in `build/mocap/` (public domain / free for all uses). Index of all clips: `build/cmu_index.txt`.
- CC0 PBR textures (ambientCG) in `assets/textures/<Name>/{Color,NormalGL,Roughness,AmbientOcclusion,Metalness}.jpg`.

## Units / axes
- 1 unit = 1 metre. Y up. Godot convention: a model "faces" -Z; glTF export from Blender uses +Y up, so export with `export_yup=True`.
- Track direction is the X axis in station scenes; platforms are at |z| offsets from the track centre-line.

## Layout
```
assets/textures/   ambientCG PBR sets
assets/people/     Blender-generated characters (glb) + animation library + manifest
assets/models/     Blender-generated props, train cars (glb)
assets/audio/      generated ambience + announcements
data/              network.json (from TfL API), timetable params
scripts/           GDScript (autoload singletons in scripts/autoload)
scenes/            .tscn
tools/             python/blender/shell tooling (fetch_*.py, blender/*.py)
tests/             throw-away test scenes
build/             scratch, downloads (not shipped)
docs/              this file
```

## Licences to credit (CREDITS.md at the end)
- TfL Open Data (network/timetable structure), ambientCG (CC0), MakeHuman/MPFB assets (CC0 + some CC-BY packs: shirts02/03, pants02/03, shoes02, hair02/03, suits03, skirts02, equipment02, glasses02),
  CMU Mocap (free for all uses).
