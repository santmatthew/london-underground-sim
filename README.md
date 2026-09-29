# Underground Sim

A first-person simulation of riding the **London Underground**, built with Godot 4.7 (GDScript) and Blender 5.2.
You start at a random point inside a random station, are given a destination, and must get to its street exit as fast as you can.
Time of day (crowds and train frequency), the real train timetable, and the route you take through each station all matter.

## Status
Playable vertical slice: real network data (272 stations, 11 lines from the TfL open API), a deterministic timetable with platform
regulation, a journey planner (par time), procedurally generated stations (ticket hall, gates, escalators, corridors, tiled platforms,
wayfinding signs modelled on real Tube signage), animated trains, riding between stations, HUD, tube map, scoring.
In progress: crowds of realistic people, sub-surface/surface station styles, audio, props, multi-stop mode.

## Run
```
tools/setup_assets.sh      # once: fetch/generate the large assets that are not in git
godot --path .             # or open the project in the Godot 4.7 editor and press F5
```
Controls: WASD move · Shift hurry (uses stamina) · M tube map · H route hint · Tab skip time (standing still / riding) · Esc menu.

## Layout
See `docs/ARCHITECTURE.md`. Code: `scripts/` (autoloads `Net`, `Clock`, `Timetable`; `sim/Planner`; `world/*` station generator;
`game/*` game loop). Asset pipelines: `tools/`.

## Credits
See `CREDITS.md`. Uses TfL open data, ambientCG (CC0) textures, MakeHuman/MPFB assets (CC0/CC-BY), CMU motion capture, Google Fonts (OFL).
Not affiliated with Transport for London.
