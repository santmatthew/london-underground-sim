# Underground Sim — architecture

Godot 4.7 (GDScript) game; Blender 5.2 generates trains, props and people; Python generates textures/audio. Units: metres, Y up.

## Data flow (from network to pixels)
```
TfL API ──tools/fetch_tfl.py──> build/tfl_raw.json ──tools/build_network.py──> data/network.json
                                                                                     │
                       Net (autoload): stations, lines, services, platform ids ("central:Eastbound")
                                                                                     │
Timetable (autoload).build(seed) : runs (train workings) + per-platform sorted departure events + platform-face occupancy
                                                                                     │
StationPlan.for_station(idx)  (pure data, deterministic per station id)
   rooms / escalators / platform modules / gates / street doors + WALKING GRAPH (nodes, edges, walk_points())
        │                                   │
        ▼                                   ▼
Planner (earliest arrival over timetable + walking graph;      Station (Node3D) builds the 3D world from the plan:
 plan_all, plan_tour = exact multi-stop optimum)                 Space, Escalator, PlatformModule, gates, StationSigns,
                                                                 StationProps, StationDecals, TrainService, CrowdManager
```
The planner and the world share the same `StationPlan`, so the "par" time and the world the player walks in always agree.

## Runtime
- `Game` (scenes/main.tscn): menu → journey generation (`Journey`) → briefing → play → result. Owns the Player, HUD, tube map, current `Station`.
- **Trains**: `TrainService` is a pure function of `Clock.now` per platform face: spawns `Train` (Blender cars) as they approach, dwell (doors,
  edge-guard segments, gap plates) and depart. Trains near the player only.
- **Riding**: `Ride` keeps the player's train static and moves the world: origin station slides away → `TunnelRun` endless tunnel → destination
  `Station` (built asynchronously) slides in; the train is then adopted by the destination's `TrainService`. Speed profile solved to match the timetable.
- **Crowds**: `CrowdManager` per station. Data agents follow `StationPlan.walk_points` routes; `PersonModel` + collision body only near the player;
  riders are created lazily per carriage. Time-of-day demand from `Clock.crowd_factor` (weekday/weekend).
- **Audio**: `Sfx` autoload reads `assets/audio/manifest.json`; ambience layers crossfade per location; announcements are queued with subtitles.
- **Autopilot**: `Autopilot` plays the game by following the planner's route (also multi-stop) — end-to-end test and video recorder.

## Conventions
- Station-local frame: hall at y=0; platforms below. `PlatformModule` local frame: x along the track, z across, y=0 at platform level, rail head y=-0.9.
- Faces of a module: face 0 at +z (trains travel +x), face 1 at -z (travel -x). Terminus platforms have two faces (visits alternate).
- Layers: 1 world, 2 people, 3 platform-edge guard (blocks the player only), 4 player.
- Blender models: front = -Z, glTF +Y up. Train cars: X along the train, rail-head origin, doors on ±Z (see `assets/models/train/README.md`).

## Toolchain facts
- Godot: `/usr/bin/godot` 4.7.2 (Forward+, Vulkan). Headless screenshots without opening a window: `xvfb-run -a godot ...` (`tools/shot.sh`).
- Blender is a snap: it cannot see `/tmp` — keep files inside `$HOME` (non-hidden).
- New `class_name` scripts need a `godot --headless --path . --import` before other scripts can use them.
- Packed arrays are value types (`(a[i] as PackedInt64Array).append(x)` appends to a copy).
- The TfL API needs a non-python User-Agent.
