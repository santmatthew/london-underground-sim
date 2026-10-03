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

## Curves: rides that turn, platforms that bend (2026-10-03)
The real track is not straight. `tools/fetch_line_geometry.py` + `tools/build_line_geometry.py` turn the OpenStreetMap route relations of every line (raw geometry under `build/geom`, never shipped) into
`data/line_geometry.json`: for each pair of consecutive stops the track length and its heading every 20 m, and for each platform the heading change across it (110 m, + = left in the travel direction). Overpass is slow
and rate limited: relations are fetched one at a time inside the London bounding box, failures are skipped and retried on the next run.
- **Rides turn.** `TrackPath` is the track between two stops in the frame of the train that sets off (cells of 12 m, constant curvature each, so a pose at any distance is closed form). The real profile is
  held straight near both stations (`fade_in/out`: the platform and the hand-over stretches), and the exact curves of curved platforms at either end are laid over it (`head` / `tail`). `Ride` keeps the
  *player's car* fixed in the world and places everything else on that path: the origin station, the destination station (`dest_p`, so it arrives rotated to meet the track), the tunnel scenery (`TunnelRun`:
  a ring of 22 cells, each a mesh bent to its curvature class, built by worker threads) and the other cars (`Train.follow_path`: each car sits between its two bogies, so a car swings out at its ends
  and in at its middle). The real track length replaces the 1.15 x straight-line estimate when the data has it (702 hops, 650 covered; the Elizabeth line's core tunnels and a few
  Piccadilly / Metropolitan branches ride straight). `UG_CURVE=<class>` bends every ride (tests).
- **Platforms bend.** A module is *designed* straight (plan, rooms, walking graph, crowd, dressing all live in "design space") and `Bend` wraps it round an arc afterwards: the part with the spine and the
  cross-passages stays straight, the platform beyond follows the curve, the running tunnel carries on straight at the final heading. `PlatformCurve.for_module` decides (average of both faces; >= 5 degrees across
  the platform; radius not under 150 m; the mirror image if the real direction would hit another module or room at the same level, `_conflicts`; else straight). The mesh is cut into 3 m slabs and
  bent (`MeshKit.bend`, on a worker thread), colliders become rotated pieces, lights/signs/props are set down on the curve (`PlatformModule.bend_children`), posters are bent where they are made
  (`PosterKit.finish`), the occluders follow (`StationOcclusion`). `UG_BEND=<radius>` bends every deep-tube module (tests).
- **Two spaces.** Anything that reasons about the plan stays in design space; anything physical (the player, rays, node positions) is in the curved world. `Station.to_phys / to_design / phys_yaw`
  convert, `PlatformModule.design_local(world)` gives a module-local point, `Station.platform_point` is physical and `platform_point_design` is not. The crowd walks in design space and `_sync` puts
  the people on the curve; the autopilot's waypoints are mapped (with intermediate points, a chord would cut the corner); trains come from `Train.place(x)` (`design_x`), doors from `Train.slot_global`.
- Gotchas: a straight line in design space is not a straight line in the world (audits sweep `to_phys` of each sample); shared statics read by plan-building worker threads need a mutex
  (`PlatformCurve`, `TrackPath.data`); `WorkerThreadPool` tasks must be waited for (`wait_for_task_completion`) or the engine corrupts memory at exit.
- Tests: `bend_test` (maths), `ride_curve_test` (forced curve), `curved_platform_test` (Bank: floor, edge guard, walls, cars, gap, crowd), `curved_ride_test` (Bank -> Liverpool Street, real geometry),
  `bend_list_test` (every curved platform of the network), `ride_speed_test` (real lengths vs timetable), `tunnel_view_test --curve=7 --at=100` (screenshot).

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
* Open-air platforms (`PlatformOpen.gd`): surface stations (and the open-cutting sub-surface ones listed in `open_sub`) are no longer a closed box: a canopy over the island (slab with deep
  fascia, white valanced boards, or timber soffit), columns where the box hall's steel columns stood (square Holden, flared round 1950s, slim cast iron; same collision), ballast, buff tactile
  edge, a brick retaining wall with coping and a palisade fence across each track, a sky dome (`shaders/sky_dome.gdshader`: gradient, noise clouds, stars) and two backdrop strips (trees,
  house backs) that follow the simulated clock, with daylight omni lights. Styles (`open_styles`, `surface_lines`, `surface_overrides` in the data file) are by line and era; Station.build adds
  `spec.nb` (sides that have another module close by, whose backdrop would cut through it). Textures: `tools/gen_open_textures.py`. Reference photos of 70-odd surface stations are fetched to
  the private `build/refs_dress/surface` by `tools/fetch_surface_refs.py`; `tools/ref_sheet.py` makes contact sheets. `UG_OFF=scenery,openwall,valance` isolate parts.
* Photo-authored surface stations (2026-10-02): a station may have an `open_styles` entry named after it (mapped in `surface_overrides`), authored from private reference photos (notes in
  `build/refs_dress/surface/SPEC_four.md`; only what the photos show). Style keys are listed at the top of `PlatformOpen.gd`: `canopy` slab / valanced / timber / `gable` (pitched, rafters, rooflight
  strips, `valance` scallop / saw / none) / `mushroom` (concrete umbrellas on a column row down the centre line, a smooth `MeshKit.lathe`), `roof_h`, `spans` (fractions of the length the roof covers),
  `col` / `col_main` / `col_band` / `col_ring`, `pitch`, `front`, and extras: `bridge` (the Kew Gardens footbridge: arched white concrete girders with blind panels), `lamps`, `planters`, `roundel_post`
  (`PropKit`, placed by `StationDressing._open_extras` in the gaps between roofs). Done: Loughton (umbrellas), Kew Gardens (separate white canopy sections, footbridge, planters, lamps),
  Boston Manor (long pitched roof, saw-tooth valance, rooflights, black columns with yellow rings), Northwick Park (two short dark shelters on maroon posts, brick planters, CCTV poles, name board on a post).
  Everything that hangs from a roof asks `PlatformOpen.soffit_y` / `snap_x` / `covered` (what is overhead where): hung boards, crown clusters, lights, the occluder (`StationOcclusion`); clocks and help
  points are mounted on columns (an open island has no wall); roofs that do not reach the way in get a flat entry roof over the cross-passages (the centre line is the walkway: no column on it there).
  Test: `open_style_test`; route / sign audits pass on all four. `station_test --mcam=x,y,z --mlook=x,y,z --mi=<module>` places the camera in a module's frame.
* `tools/char_sheet.sh out.png <view> "Station" ...` renders a contact sheet; `station_test --view=pwall --x= --dx= --fov=` looks across the platform at its wall.

## Branch junctions
Where a line splits, one platform per direction is not enough: at Camden Town, Euston and Kennington (Northern line) and Finchley Central the branches have their own platforms with their real
numbers. `data/junctions.json` lists them (one entry per station, direction and branch: the `via` station that tells a service's branch, the platform `number`, a `module` = island);
`tools/junctions.py` (called by `build_network.py`, or run alone on `data/network.json`) renames the platform ids at those stations to `northern:Northbound~edgware` etc., sets `branch`, `number`
and a per-branch `group` (`northern.a`), and moves every service stop of the matching branch onto its platform. Everything downstream is keyed by platform id, so timetable, planner, indicators
and signs follow; `StationPlan.dir_text(pid)` gives "Northbound via Bank" for signs; the generator and layout builder make one platform module per branch group (`BASE_DEPTH` and measured
depths use the part before the dot). Euston's layout was edited by hand, Kennington's rebuilt from its brief. Test: `junction_test` (numbers, and every train on a platform belongs to its branch).
* Camden Town: northbound 1 = Edgware branch, 3 = High Barnet branch; southbound 2 = via Charing Cross, 4 = via Bank (live TfL data; the Wikipedia article's "by origin branch" wording does not match it).
  Euston: 1/2 = Charing Cross branch, 3/6 = Bank branch. Kennington: northbound 1 = via Charing Cross, 3 = via Bank; southbound 2 = via Charing Cross, 4 = via Bank.
  Finchley Central: northbound 1 = Mill Hill East branch, 2 = High Barnet branch, southbound 3 shared.
* The other junctions (Acton Town, Earl's Court, Turnham Green, Leytonstone, Woodford, North Acton, Harrow-on-the-Hill, Moor Park, Chalfont & Latimer, Rayners Lane) are not split: the live
  platform data (`tools/fetch_platform_dests.py` -> `data/platform_destinations.json`) show shared or mixed platforms there, so a split would invent structure.
* Which platforms form an island is the simulator's choice; the sources give numbers and branches only.

## Frame rate
`tools/fps_experiment.sh [secs] [WxH]` runs a ladder of progressively heavier scenes (`tests/fps_experiment.tscn`: empty scene, architecture, + dressing, + signs, + trains, + crowd, an open-air
station, the whole game on autopilot), each for `secs` seconds (default 300) on a REAL display with a scripted walk, logging every frame (`FrameLog`: frame ms, GPU ms, render CPU ms, draws, VRAM ...)
beside a once-a-second system sampler (`tools/sys_sampler.py`: GPU clocks / power / temperature / throttle bits, CPU frequency / temperature / load); `tools/fps_report.py` makes the report and plots.
In game, F4 starts / stops the same log (user://fps_<time>.csv) and `--fps-log=<file> [--fps-secs=N] [--fps-quit]` does it from the command line. `UG_HITCH=1` prints every frame over 100 ms with the
node count and crowd stats. A virtual display (xvfb) has no real present path (about 55 ms per 1080p frame), so measure on the real one; with vsync on and the session locked the window is throttled to 1 Hz.
What it found (2026-10-02): (1) every station with a wall map re-recorded the whole 2000 x 1600 Tube diagram each frame (`TubeMap._process` queued a redraw while visible): about 22 ms of main-thread
time per frame, 42 fps in any dressed station, fixed; (2) the first appearance of each of the 36 characters cost about 130 ms and filling a train with riders in one frame 150 ms to 1 s: `CrowdWarmup`
draws every character once off screen behind the menu, riders appear 5 per frame (`CrowdManager._fill_pending`, flushed by `finish_riders` before a ride hand-over); (3) the first train of each kind
loaded its car model synchronously (about 0.8 s each): `Train.preload_async` at start-up. After the fixes a static station is GPU-bound (7.5 ms at 1080p, about 131 fps, 1% lows within 15 % of the median);
the empty scene already costs 4.3 ms at 1080p (the full-screen passes of the Balanced tier at the GPU's throttled clock). The laptop's GPU spends the runs in "software power cap" / "software thermal
slowdown" (SM clock mean about 740 MHz of 2100) and its CPU package idles near 100 C with the fans at maximum while a VM, k3s and Chrome run in the background.

### The Elizabeth line (2026-10-03)
Twelfth line of the network, all 41 stops of the TfL API (Reading, Twyford, Maidenhead, Taplow, Burnham, Slough, Langley, Iver, West Drayton, Hayes & Harlington, Southall, Hanwell, West Ealing, Ealing Broadway, Acton Main Line, Paddington, Bond Street,
Tottenham Court Road, Farringdon, Liverpool Street, Whitechapel, Canary Wharf, Custom House, Woolwich, Abbey Wood, Stratford, Maryland ... Shenfield, Heathrow Terminals 2 & 3, 4 and 5): 301 stations in all.
* **Network** (`tools/fetch_tfl.py elizabeth`, `tools/build_network.py`): the API's 910G... ids; the ones that are platforms of an Underground station's complex (`tools/elizabeth_ids.py`: Paddington, Bond Street, Tottenham Court Road, Farringdon, Liverpool Street, Whitechapel,
  Stratford, Canary Wharf, Ealing Broadway, Heathrow 2 & 3, 4, 5) join that node (one plan, interchange inside it; the station's `lines` gain "elizabeth", its platforms `elizabeth:Eastbound/Westbound`), the other 29 are stations of their own. Ten services (the API's eight through
  routes without the main-line Liverpool Street stub, plus Abbey Wood - Paddington and Shenfield - Paddington, which carry the core), zone None counts as 9, the line name is "Elizabeth" ("... line" is added everywhere). `Timetable.TPH/WEIGHTS`: 24 trains an hour in the core at the peaks.
  Trains are the 18 m sub-surface cars, eleven to a train (205 m), `Train.kind_of_line`, `StationPlan.CARS`.
* **Stations**: the 29 new ones come from the generator (rail-station open-air platforms, styles `rail_valanced`, `rail_modern`; Woolwich a deep box; the Heathrow ones covered); the 8 authored interchange layouts get an Elizabeth line level by `tools/layouts/add_elizabeth.py` (a landing at the
  depth of `data/elizabeth_depths.json`, reached by a bank that leaves the EAST wall of the easternmost hall: every other bank goes south and a module runs east at its landing's lane, so a landing east of the hall has nothing in its way; terminal platforms get both faces; re-run it after regenerating a layout),
  Stratford, Ealing Broadway and Heathrow 2 & 3 and 5 are generated (`RealData` merges the depths). `StationCharacter.platform_is_box/platform_roof`: the nine central stations (`elizabeth_core`) have full-height edge doors (smoked glass, black and white striped band: `PlatformDoors el`), Bond Street, Tottenham Court Road,
  Farringdon, Liverpool Street and Whitechapel the cream perforated vault (`el_panel`, an arch module), Paddington, Canary Wharf, Custom House and Woolwich dark panels and a concrete soffit (`el_dark`, a box); the roundels have a purple ring (`Signs.ring_color`). Reference: Commons photographs, private under build/elizabeth/refs.
* **Data**: `tools/build_elizabeth_depths.py` (depths from tubedepths), `tools/fetch_station_real.py --missing` (TfL record and OSM for the new stations; the rail record has no counts, so lifts are set to 2 because every station is step-free), `tools/fetch_platform_numbers.py` (the arrivals give "Platform 4" without a direction:
  `el_direction` from the destination), `tools/build_step_free.py`, `tools/gen_cvd_palettes.py` (twelve lines), `tools/build_diagram.py --add` (the Tube diagram keeps every old station where it was and places the new ones), speech (`tools/audio/make_audio.py --only speech`, "an Elizabeth line train").
* **Tests**: `el_timetable_test`, `plan_faces_test` (every platform of the network has a face in its plan), `route_audit_test` over `$(cat build/el_stations.txt)`, `tools/check_layout.sh` for the eight authored stations, `bot_test --start=Romford --dest=Bond_Street --spot=platform`.
* **Known gaps**: rides between the surface stations still show the dark bore; the outer stations share three generic platform styles (no photo-authored ones); Whitechapel's and Paddington's branches share one platform per direction (no junction split); Heathrow's Elizabeth line platforms are covered white-tile placeholders.

### Measuring on this machine: which GPU is rendering? (2026-10-03)
Check the F3 overlay ("... on <adapter>") or the first lines of a Godot run (`Vulkan ... Using Device #0: ...`) before trusting any frame time. An unattended apt upgrade (2026-10-03 09:08) replaced the NVIDIA user-space libraries
(595.84 -> 595.91) under the still-loaded 595.84 kernel module: `nvidia-smi` says "Driver/library version mismatch", the NVIDIA Vulkan ICD fails and Godot silently renders on the Intel Iris Xe iGPU (the empty scene went from
4.3 ms to 14.8 ms at 1080p, the static station from 7.5 ms to 30 ms). A reboot (or reloading the nvidia modules) fixes it; no code change does. The tunnel detail costs about 13 draw calls and 12k triangles in a platform view (`UG_OFF=tunnel_detail` / `tunnel_lights` switch it off for an A/B).

### Z-fighting (2026-10-03)
`tests/zfight_audit_test.gd` (`--stations="A|B"`, `--range=a,b`, `--all`, `--sep=` metres) flattens every ArrayMesh of a built station to world triangles, groups them by plane and reports pairs of *different materials* that lie in the same plane (within 0.6 mm), face the same way
and overlap: they are drawn at the same depth and flicker. Found: pilasters stood on the dado at the same offset (`_band` now takes an `off`: pilasters 10 mm, their edge strips 14 mm, the dado 4 mm), cable trays of the running tunnel had a face in the plane of the spine's wall
(`MeshKit.box(..., skip_z)` leaves the wall-side face out), cables of equal height overlapped.

### Crowd and the player (2026-10-03)
`CrowdManager._step_walk`: from `AVOID_R` (2.8 m) a walker heading for the player bears off to the side the player is not on (the nearer, the harder; dead ahead each person keeps a side chosen by their seed), slows a little head-on and never comes closer than
`KEEP_OFF` (0.66 m; the bodies touch at 0.52), so the crowd goes round the player instead of pushing. Test: `crowd_avoid_test` (a player standing in the main flow at Oxford Circus in the morning peak: closest approach 0.01 m before, 0.66 m after).

### Explore mode (2026-10-02)
`ExplorePanel` (setup screen: station search / random, start spot labelled by `ExplorePanel.spot_label`, day, time slider) -> `Game.start_explore(cfg)` (tears the world down with `_teardown_world`, rebuilds the timetable for the chosen day, builds the station, puts the player on the chosen start spot and goes straight to play, no briefing).
`journey["mode"] == "explore"` (`Game._exploring()`): no destination, par, score or result panel; the street exit only turns the player back, the end of service does not fail the session (a toast says the network has closed), the HUD shows "Exploring", the hint (H) explains there is no destination, the pause panel offers "Start somewhere else"
(the setup screen over the pause panel). Riding, arrival and boarding work as in a journey. Test: `explore_test` (CLI start `--explore=...`, search, restart elsewhere, a ride to the next station); viewer `explore_shot_test`.

### Starting a journey (loading hitches, 2026-10-02)
Measured with `UG_ON=loadtime` (a line per stage of start-up and per stretch of the station build over 60 ms) and `--fps-log`; `--menu-secs=N` makes the autopilot wait at the menu like a person. Before, choosing
a journey froze the window for up to 9 s in stretches of 1 to 2 s; now nothing after "Start" is longer than about 0.3 s. What moved where: the 36 characters' files (and shaders, textures, animations) load on
worker threads (`PersonModel.preload_async`) and `CrowdWarmup` then creates 3 per frame behind the menu; every station's plan and walk-time cache are built by a worker group at start-up
(`StationPlan.warm_all_async`, 1.7 s of work on one core, 0.25 s on all; `warm_all()` hands them to the cache and waits if they are not done); the prop models load on workers (`StationProps.preload_async`);
`Timetable.build_async` and the journey pick run on worker threads while the loading label keeps drawing (nothing may read the timetable meanwhile: the menu has freed the old station;
quitting waits for the workers, `_exit_tree`); the station build is time-sliced: `Station._slice()` (also in `DressMap.build`, `StationSigns.place`, `StationDressing.run`) breaks for a frame only when 25 ms of work
have run since the last break, so a warm build has no stretch over 85 ms. What is left is first-use cost of a run: the first platform module (about 0.3 s: shaders, textures) and escalator (0.15 s).
`tests/build_chunks_test.gd` (`--station=`, `--preload`) shows the cold and the warm build's longest stretches; `tests/plan_warm_test.gd` checks the threaded builds against the synchronous ones.
Waiting for the briefing in a test must use the wall clock, not a frame count (headless frames are much faster than the workers).

### GPU cost at a 4K target (2026-10-02, RTX 3050 Ti Mobile, static hall, Auto scale = FSR 1 at 54 %)
Measured with `tests/fps_experiment.gd --vp=3840x2160 --cycle=<json>` (configs rotated inside one process in a shuffled order, a 60 s warm-up and 8 rounds, because the GPU's clock drifts
with temperature and one-after-another runs are not comparable). Floor (empty scene) 4.2 ms; the static station adds about 3.5 ms (lighting and materials; the lights cost about 1.7 ms *as soon as there
are any*: shorter ranges or distance fade did not help); ambient occlusion +2.6 ms (its quality knob changes nothing), TAA +2.4 ms, glow +1.3 ms (bilinear upscale / fewer levels change nothing),
colour adjustment and fog about 0, FXAA about 0. Balanced + TAA 13.3 ms, + FXAA 11.7, Fast + TAA 9.3, Fast + FXAA 7.8, High (light bounce + reflections) 19.0, FSR 2 24 (vs FSR 1 11).
`RenderSettings.apply` holds the settings (tier, AA, upscaler, scale) for both the game and the experiment; `AdaptiveScale` moves the Auto scale along a ladder (ceiling = the size-based Auto value,
floor 0.40, steps of 12 %) from one-second medians of the GPU time: two slow seconds step down, four fast seconds step up if the next step is predicted to fit; a crowd run at the 4K target went from
13.5 ms / 45 fps fixed to 11.8 ms / 50 fps adaptive. `--no-adaptive` switches it off; a fixed scale in the menu does too.

## Settings, controls, audio and accessibility (2026-10-02)
* `Settings` (autoload): audio / access / controls sections with defaults, saved in `user://settings.cfg` next to the display ones; `get_v` / `set_v` / `changed`; `UG_SETTINGS=<path>` redirects the file (tools/gtest.sh and shot.sh do, so tests never change the player's settings); `--colour-vision=` overrides one run.
  `SettingsPanel` (Sound, Accessibility, Controls tabs) opens from the main menu and the pause panel. Volumes drive the buses (`Sfx._apply_buses`); the HUD scales its text (`Hud.apply_text_scale`: HUD text size and subtitle size).
* Input: every control is an InputMap action defined in `InputBindings` (keyboard + gamepad; movement is analogue, so the left stick and WASD are one `Input.get_vector`; the right stick looks; triggers zoom the map). The player can rebind keys and pad
  buttons (a key already in use is swapped, saved in `controls/bindings`); prompts and the help line show the key or the button depending on the last device used. Never use `Input.is_key_pressed` in game code; use actions (F-keys and Alt+Enter are fixed).
* Audio: the clips already existed (generated, `tools/audio`); `PlatformAnnouncer` (ticked from `Game._update_audio_zone`) uses them: on a platform "The next train is a ... line train to ... Due in N minutes" for the first train that has not arrived yet, safety messages now and then (their own
  setting "Extra PA messages"), the push of air out of the tunnel mouth 9-15 s before a train (tunnel stations only), distant train rumbles; the escalator "stand on the right", a greeting once per journey, "mind the gap" when the player's train opens its doors, at a terminus "ready to depart", in a crowd "move right down", the driver
  holding a train that waits long. Open-air platforms have their own beds (`outdoor_day_loop` / `outdoor_night_loop`, zone "platform_open", chosen by the simulated daylight). `Sfx.say(keys, priority, chatter)` queues, subtitles, ignores repeats within 8 s and honours the settings. Test: `announcer_test`.
* Colour vision: `Net.line_color` goes through `Palette` (data/line_palettes.json from `tools/gen_cvd_palettes.py`: dichromacy simulation, every pair of lines at least ~26 CIELAB units apart as that player sees them, brand colours moved as little as that allows). The live map changes at once, signs / trains / wall maps from the next station build. Test: `palette_test`.

* Lifts (all play): a station with lifts in reality (TfL facility record `lifts > 0`: 85 stations; `plan.lifts_real`) gets a lift housing beside the mouth of every escalator / stair bank, built by `Station._build_lifts` and usable by the player (E at the door, `Game._ride_lift`);
  the walking graph the player and the planner use (`StationPlan.adj_lift`, on when `StationPlan.lifts_enabled`, Game sets it) has the lift edges next to the escalator ones, so par and the autopilot take a lift when it is quicker; the crowd always walks `adj`
  (escalators and stairs only, never lifts). One lift per bank is an approximation of the real count and position.
  Lift-only stations (data/vertical_access.json `lift_only`: Borough, Covent Garden, Hampstead, Goodge Street, Russell Square) have no escalator-type banks at all: `_apply_lift_only` marks them `removed`, closes their openings and drops their edges, and the lifts stand where the openings were (paired housings in a wide bank)
  and are in the crowd's graph too (crowd "hop" state, `stats["lift_rides"]`). The fixed stair flights stay. The other lift-only stations of the record (Belsize Park, Caledonian Road, Chalk Farm, Holloway Road, Lambeth North, Regent's Park, Tufnell Park ...) still show escalators standing in for their lifts.
* Running tunnels (the bore between stations, 170 m beyond each platform end and the scenery that scrolls past while riding): bare dark cast-iron segmental lining (`tunnel_lining`, tools/gen_tunnel_textures.py), cable trays and cables on both walls, brackets, junction boxes, refuge niches, a lamp only every ~20-24 m
  (some out); `TunnelDetail.add` builds the detail, `PlatformModule._run_detail` for the stretches beyond each platform end (after `RUN_IN` = 4 m of the platform's own tiling), `TunnelRun` for the ride (segments chosen by absolute cell, so nothing pops as they are recycled). Viewer: `tests/tunnel_view_test.tscn`.
* Spiral emergency stairs (`vertical_access.json` `spiral`, the five stations above; step count only where a source gives it: Covent Garden 193, Hampstead 320, Russell Square 171, Goodge Street 136; Borough's is derived from the depth at an 0.18 m riser and not announced): `StationPlan._add_spirals` finds a free stretch of wall in the ticket hall
  (paid side of the gateline) and in the deepest landing for a door each (`_wall_spot`, `_attach_node`: a door front hangs on the room's graph by a straight line cleared against the housings), and puts a tower (`SpiralStair`: a real helix, 17 steps a turn, a smooth ramp collider, newel, wall, rails, doors) 60 m east of everything. The doors are portals, like the lifts: `Station._build_spirals`
  (anchors in group "stair_door", meta end top/bot/top_tower/bot_tower, to, to_dir), E at a door -> `Game._use_stair_door` (a fade, out at the other side facing out), and the stair is walked on foot, slowed to the pace of the steps by `Player.terrain_mult` (`SpiralStair.PACE_DOWN/UP`: about 0.38 s a step down, 0.65 up; 193 steps take
  about 70 s down and 2 minutes up). The planner never routes through it (its edges are only in `adj_spiral`, the graph of `StationPlan.spiral_mode`, off in play; par times are the lifts'); `bot_test --spiral` / `route_audit_test --spiral` turn it on, the bot takes the doors (`Autopilot._use_spiral`) and the audit sweeps the helix with the capsule.
  Tests: `spiral_plan_test`, `spiral_ride_test`, `route_audit_test --spiral`, `bot_test --start=Covent_Garden --dest=Holborn --spot=ticket_hall --spiral`; viewers `spiral_view_test`, `station_test --view=stair_top|stair_bot|tower_top|tower_bot`.
* Step-free journeys (optional; Settings > Accessibility, `--step-free`; off by default): `tools/build_step_free.py` turns TfL's step-free pathway graph (build/tfl_topology GTFS) into data/step_free.json (platform reachable from the street by lifts and level routes only; 217 of the 272 stations have data, 68 can be used step-free
  (every platform needs the data AND every escalator / stair bank a lift); a station with no entry counts as not step-free). `StepFree.platform_ok / station_ok`. In this mode `StationPlan.step_free_mode` is on (Game sets it before it plans or builds): the planner boards, alights and changes only at step-free platforms,
  the journey picker draws starts, destinations and multi-stop targets from the step-free stations, walking queries (`walk_time`, `path`, `dijkstra`) use `adj_sf` (no escalator or stair edges; lift edges with a 20 s wait + 0.9 m/s + doors; `adj` never contains lifts, so normal play is unchanged),
  gates use the wide lanes. `StationPlan._add_lifts` puts a lift housing beside the mouth of every bank at both ends (`plan.lifts`, validated against the room, its openings and the other lifts; all 272 stations fit), `Station._build_lifts` builds them (`PropKit.lift_housing`) with a door anchor
  per door (group "lift_door") and a barrier across each bank mouth (collision layer 3: stops the player, not the crowd). Riding: E at a door -> `Game._ride_lift` (fade, the clock runs 8x for the ride, out at the other door facing out). Routes with a lift are walked in segments (`StationPlan.path_segments`; DressMap,
  route audit `--sf`, autopilot kind "lift"). The crowd always uses the normal graph. Tests: `lift_plan_test`, `step_free_plan_test`, `lift_ride_test`, `route_audit_test --all --sf`, `bot_test --step-free`.

## Display
F11 / Alt+Enter / the menu toggle borderless full screen (`Game.set_fullscreen`, remembered in `user://settings.cfg`; `--fullscreen` / `--windowed` override). `tools/upscale_shots.sh` renders 4K comparisons of native,
FSR 1 and FSR 2 for `tools/upscale_sheet.py`; Godot has no DLSS (it needs NVIDIA's proprietary SDK linked into the renderer), so FSR 2 at the DLSS-equivalent scales is only a stand-in.

## Tests worth knowing
`walkbot_test` (real capsule along routes; `--reverse`, `--rot=180`, `--trace`), `walk_test` (floor audit), `spine_wall_test`, `sign_audit_test`,
`tools/hub_walks.sh` (walkbot on every authored hub, all halls + reverse, in parallel) and `tools/hub_journeys.sh [file]` (autopilot journeys between hubs in parallel; flags falls, stuck events, missed trains),
`route_audit_test` (`--all` or `--stations=..`: free path everywhere), `wall_audit_test` (visible surfaces without a collider, `--range=a,b`), `tube_map_test` / `map_toggle_test`, `person_bag_test`,
`layouts_test` (every data/layouts file maps to a station and compiles), `module_dump_test` (`--station`: modules with their bends, rooms, faces), `plan_dump_test` (`--station`, optional `--from/--to`: platform ids, rooms, modules, waypoints of a route),
`ray_probe_test` (what is at a point), `esc_edge_test` (real capsule pinned on every escalator lane, incl. `--crowd` = the station's real crowd at 08:50; fails if the player climbs a
balustrade or leaves the shaft), `bot_test` (autopilot journey; `--seed`, `--multi=N`, `--start/--dest/--spot/--hour`, `--every`, `--frames`; prints DROP/TRAIL diagnostics
when the player falls), `shots_test` (autopilot journey with screenshots), `overlap_test`, `plan_warm_test` (threaded plan / timetable builds equal the synchronous ones), `build_chunks_test` (longest uninterrupted stretch of a station build, cold and warm).

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
