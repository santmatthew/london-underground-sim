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

## Tube map (M)
`TubeMap` has two views: the **diagram** (default; the Beck-style schematic with lines at 0/45/90 degrees, parallel lines on shared track, ticks and interchange
capsules, the Thames) and the **geographic** map; G or the button top right switches. The diagram is generated offline from the real network by
`tools/build_diagram.py` (needs numpy + scipy; `--png` needs matplotlib): warp the real positions to magnify the centre, optimise edge angles, anneal the stations
on a grid so almost every edge is exactly octilinear with no crossings, route the few remaining edges as two-part doglegs, place labels, warp the river with the
layout -> `data/tube_diagram.json` (~42 KB). The layout is cached in `build/diagram/G.npy` (`--relayout` recomputes; ~2 min). Labels are culled by priority in the game.

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
- Platform tunnels: the running tunnel on the room side of a module is short (`tun_w`) and ends in a dark cap; rooms never overlap a tunnel
  (`LayoutCompiler._check_overlaps`, `route_audit_test` asserts the length). Never add a room in line with a platform without lengthening the passage.
- Every station must have a free path: `tests/route_audit_test.gd` sweeps the real capsule along every street door <-> platform, platform <-> platform and
  start-spot route of all 272 stations (gates open, static, ~1 min for the whole network); an empty planner path is a failure, not a pass.
- `Autopilot` stuck recovery is per waypoint (`_wp_sides`): a re-route from the nearest visible node after 3 stuck events at the same waypoint.
- `Autopilot` also: boards early when the doors are open and it is on the platform; steps back out if a boarding passenger pushes it into a standing
  train; never dodges a person into a train; picks the exit door by walking time (as the planner does), not by node count.

## Signage
Every sign is tagged (`meta "sign"`, `meta "size"`), hung through `StationSigns.hang_room / hang_blade / mount_wall` and fitted by
`PlatformModule.ceiling_at / fit_blade` (roof arch, walls, columns, headroom `HEAD` = 2.15 m). `tests/sign_audit_test.gd` checks every sign of
a list of stations against the real colliders and the analytic roof. Real Tube proportions: blades/indicators ~1-2.6 m wide on short stems,
roundels and names flat on the tile wall. On platform walls the station name is the TfL roundel (name in the blue bar across the red ring, every ~13 m on the
track-side wall and behind the platform); deep-tube platform walls also carry the white name fascia (see Station character) and, at the stations that have it, the tile lettering.

## Station dressing
What fills a station (ticket-hall furniture, shops, posters, benches, clocks) is placed by `StationDressing.gd` after the architecture and signs are built.
Rules come from real-station research (private photos/specs under `build/refs_dress/`, never committed): halls have no bins or benches, ticket machines sit
in wall bays, platforms carry an ad run across the track between roundel plates, deep-tube platforms get perforated-steel benches and sub-surface ones timber.
* **Nothing may block a walking route.** `DressMap` samples every route `route_audit_test` sweeps (door<->platform, platform<->platform, start spots) into grid cells;
  `StationDressing.floor_prop/floor_node/kit_prop` refuse a footprint on a route cell, on the gateline band or on anything already placed. Wall items claim free wall
  (`wall_slot`: openings and signs excluded). Footprints are read from each prop's collision shapes.
* **Props:** Blender glbs (`tools/blender/props`, `assets/models/props`, e.g. ticket machines, gates, stands) plus procedural ones in `PropKit.gd` (benches, bin hoops,
  ceiling speaker clusters, ticket bay surround) and `ShopKit.gd` (kiosks, generic names). Posters go through `PosterKit.gd`: real formats (4/6/16/48-sheet, Double/Quad
  Royal), one merged mesh per surface, a per-station `Picker` bounds the texture count. Art: `tools/gen_posters3.py` (invented brands) -> `assets/textures/props/posters2`.
* **Live displays:** analogue clocks are driven by `StationClocks` (hands from `Clock.now`), platform indicators show two trains + a seconds clock. Do not place a prop
  whose texture has a time baked in (CID totem, departure_board_dm) without making the time live.
* Tests after any change: `route_audit_test --all`, `sign_audit_test`, `wall_audit_test` (ghost counts vs baseline), `tools/hub_walks.sh`; `station_test` prints draw calls.

## Station character
Each deep-tube platform module gets its finishes from `StationCharacter.platform(station, line, kind)` (data: `data/station_character.json`; textures: `tools/gen_char_textures.py` +
`tools/char_motifs.py` -> `assets/textures/char/`). Authored from reference photos (private, `build/refs_dress/platforms`): Covent Garden, Caledonian Road, Tufnell Park, Chalk Farm,
Goodge Street, Archway, Warren Street (Northern), Edgware Road (Bakerloo), Baker Street (Bakerloo). Every other deep platform takes its line default (Bakerloo cream + brown, Piccadilly,
Northern grey dado, Central black/blue, Victoria 150 mm grey tile, Jubilee Line Extension panels). Sub-surface and surface stations keep the older seeded schemes.
* Tile scheme: `wall` material + `stripes` ([y0, y1, colour, tile?] on both platform walls), optional `ribs` (tile bands ringed over the vault), `pilasters` (vertical tile bands on the
  platform wall), `frame` (tiled surround of the cross-passages), `giant` (tile lettering of the name, RGBA with the tile joints cut through it; benches stand under it).
* Name fascia (`StationDressing._frieze`): 0.30 m white enamel strip at 1.99-2.30 m on the platform wall, the name on 3 m panels, a line-colour keyline, a black "Way out" patch after every
  second panel; it stops at the cross-passages. Roundels, info frames and clocks sit below it.
* Victoria line seat recesses (`PlatformModule._recess`): 2 x 1.75 m niches in the platform wall every 10 m beyond the spine, with the station's tile motif on the back, stainless trim and a
  timber slab carrying two `seat` markers (E to sit). Motifs are simplified redrawings of the original subjects (Brixton bricks, Stockwell swan ...), keyed by station in the data file.
* Materials for these quads come from `StationCharacter.material("char:<path>|<w>|<h>|<alpha>")`; `PosterKit.finish` and `PlatformModule.build` resolve `char:` and `flat:` keys.
* Ticket halls (`StationCharacter.hall`, data `hall_types` / `halls`): an era type sets the Space wall / floor / ceiling materials and a list of bands (`Space._band_at`): Holden (buff brick,
  green dado, cream floor tile; Brent Cross chequer), Leslie Green (cream tile, terracotta quarry), 1970s-90s refit (cream tile, line-neutral band; Green Park blue, Kentish Town maroon),
  large-format stone (King's Cross, North Greenwich, Waterloo, Canary Wharf) and 2020s Idiom (white panels, slate floor, metal ceiling). Unlisted stations keep the default hall.
  Platforms without an authored scheme (sub-surface and surface lines) get the generic one: white tile, dark skirt, one band in the line's colour.
* Platform floors (`floor` key): Edgware Road lozenge, Bank Central grey diamonds, Waterloo Northern black/cream, 600 mm slabs (Victoria line, Stockwell, Lancaster Gate), pale stone (JLE).
  Oxford Circus Central has its braided-ribbon wall tile (`tools/gen_textures.py oxford`); era light colours come from the `light` key. The glass doors at each way-out show a street by the
  time of day (`Station._street_material`, `tools/gen_street.py`).
* Platform edge doors (`PlatformDoors.gd`, `peds` key of the `jubilee_ext` default): the eight Jubilee Line Extension stations with doors in reality (Westminster, Waterloo, Southwark, London
  Bridge, Bermondsey, Canada Water, Canary Wharf, North Greenwich) get a stainless head casing, fixed tinted glass with the yellow band, and a sliding leaf pair at each of the train's doors
  (`Train.door_positions_for`). `PlatformModule.set_edge_open` (called per door by `TrainService._edge_guard`) opens the matching pair together with the invisible edge guard, so the
  player can only board where a door is open. No yellow line / MIND THE GAP stencil there (the doors are the boundary). Test: `ped_test`.
* `tools/char_sheet.sh out.png <view> "Station" ...` renders a contact sheet; `station_test --view=pwall --x= --dx= --fov=` looks across the platform at its wall.

## Tests worth knowing
`walkbot_test` (real capsule along routes; `--reverse`, `--rot=180`, `--trace`), `walk_test` (floor audit), `spine_wall_test`, `sign_audit_test`,
`tools/hub_walks.sh` (walkbot on every authored hub, all halls + reverse, in parallel) and `tools/hub_journeys.sh [file]` (autopilot journeys between hubs in parallel; flags falls, stuck events, missed trains),
`route_audit_test` (`--all` or `--stations=..`: free path everywhere), `wall_audit_test` (visible surfaces without a collider, `--range=a,b`), `tube_map_test` / `map_toggle_test`, `person_bag_test`,
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
