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

## Riding: things that must hold (each was a real bug)
- The player's train is static in the world; stations slide past it. Anything of a *moving* station that could touch the carriage must be inert:
  `Ride` builds the destination **parked at y=-5000 from the first frame**, mutes the colliders of both the origin and the destination while
  they slide (`_mute`/`_unmute`), and only restores them (`_finish`) once the destination has stopped in its final place.
- A service-driven train is only solid while it stands at the platform (`Train.set_solid`, driven by `TrainService`): approaching/departing
  trains pass straight through landings and corridors that share their tunnel line.
- `TrainService.x_at` places a train from the timetable; when a ride ends slightly early/late, `Ride._finish` widens the visit's `arr`/`dep`
  so the player's train is held at the platform instead of teleporting away from under the player.
- World-space assumptions break after a ride (the destination is placed with an arbitrary rotation/offset): use `station.to_global/to_local`
  (e.g. `Station.platform_point` is station-LOCAL), and gate-local coordinates for the gate approach side.
- `Player` has a fall safety net; `Game._respawn_point` only respawns at the last standing position if floor still exists there.
- Escalators/stairs: the balustrade collision is **full shaft height** (`Escalator.GUARD_H`), and crowd riders are **not solid** for the player
  while they ride (`CrowdManager._set_solid`). A rider that is carried into a player who is boxed in by the balustrades can only be resolved
  upwards - onto the rider's head or the rail top - and from there the player slid off the outside edge into the void (Oxford Circus, found
  by a hub journey). `esc_edge_test --crowd` reproduces it.
- `Autopilot` stuck recovery is per waypoint (`_wp_sides`): a re-route from the nearest visible node after 3 stuck events at the same waypoint.
- `Autopilot` also: boards early when the doors are open and it is on the platform; steps back out if a boarding passenger pushes it into a standing
  train; never dodges a person into a train; picks the exit door by walking time (as the planner does), not by node count.

## Signage
Every sign is tagged (`meta "sign"`, `meta "size"`), hung through `StationSigns.hang_room / hang_blade / mount_wall` and fitted by
`PlatformModule.ceiling_at / fit_blade` (roof arch, walls, columns, headroom `HEAD` = 2.15 m). `tests/sign_audit_test.gd` checks every sign of
a list of stations against the real colliders and the analytic roof. Real Tube proportions: blades/indicators ~1-2.6 m wide on short stems,
roundels and names flat on the tile wall.

## Tests worth knowing
`walkbot_test` (real capsule along routes; `--reverse`, `--rot=180`, `--trace`), `walk_test` (floor audit), `spine_wall_test`, `sign_audit_test`,
`tools/hub_walks.sh` (walkbot on every authored hub, all halls + reverse, in parallel) and `tools/hub_journeys.sh [file]` (autopilot journeys between hubs in parallel; flags falls, stuck events, missed trains),
`layouts_test` (every data/layouts file maps to a station and compiles), `plan_dump_test` (`--station`, optional `--from/--to`: platform ids, rooms, modules, waypoints of a route),
`ray_probe_test` (what is at a point), `esc_edge_test` (real capsule pinned on every escalator lane, incl. `--crowd` = the station's real crowd at 08:50; fails if the player climbs a
balustrade or leaves the shaft), `bot_test` (autopilot journey; `--seed`, `--multi=N`, `--start/--dest/--spot/--hour`, `--every`, `--frames`; prints DROP/TRAIL diagnostics
when the player falls), `shots_test` (autopilot journey with screenshots), `overlap_test`.

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
