# Underground Sim

A first-person simulation of riding the **London Underground**, built with Godot 4.7 (GDScript) and Blender 5.2.
You start at a random point inside a random station, are given a destination (or several), and must reach the street exit as fast
as you can. Time of day (crowds and train frequency), the real train timetable, and the route you take through each station all matter.

## What's in it
- **Real network**: 272 stations, 11 lines, real routes/branches/zones/coordinates from the TfL open API; deterministic timetable with
  time-of-day and weekday/weekend frequencies, per-platform regulation (no two trains ever overlap) and 1–2 faces at termini.
- **Journey planner**: earliest-arrival routing over the timetable *and* each station's walking graph gives the optimal ("par") time; an exact
  Held-Karp tour optimiser gives the par for multi-stop games (computed on a worker thread).
- **Procedural stations** (deterministic per station): street passages, ticket hall with gate lines (real gate models), escalator banks,
  landings, corridors, and three platform styles: deep-tube twin tunnels, sub-surface box halls with columns, and glass-roofed surface halls.
  Wayfinding modelled on real Tube signage (white enamel panels with line-coloured rules, black/yellow "Way out", fascia name boards, roundels,
  tile-lettering panels, live dot-matrix indicators driven by the timetable).
- **Trains**: Blender-built deep-tube and sub-surface cars (interiors, moquette, poles, sliding doors, line diagrams, destination displays)
  that approach, stop, open doors and depart on the timetable. **Ride** them: the world scrolls past as tunnel while the next station is built
  and slides in; announcements, ambience and sway included.
- **People**: 36 MakeHuman-based characters (clothes, hair, skins, bags) animated with retargeted CMU mocap; crowd flows follow the same routes
  the planner uses (gates, escalators — standing on the right — platforms, boarding and alighting), scaled by time of day; riders fill the carriages.
- **Audio**: 1300+ generated clips: station/line announcements in a British voice (keyed by station and line/destination), ambience layers
  that crossfade by location, door/gate/escalator/train sounds, footsteps.
- **Game modes**: single destination and multi-stop (visit 3–5 stations in any order), route hints, tube map with Thames, scoring against par.
- **Tooling**: an autopilot bot that plays whole journeys (used for testing and for recording videos), walkability audits, video recorder.

## Run
```
tools/setup_assets.sh      # once: fetch/generate the large assets that are not stored in git (see docs/ASSETS.md; some steps take a while)
godot --path .             # or open the project in Godot 4.7 and press F5
```
Jump straight to a journey (handy for the authored stations): `godot --path . -- --start=Victoria --dest=Bank --spot=street_entrance --hour=8.5 --auto-start`
(station names with underscores for spaces; `--spot=platform` or `street_entrance`; `--seed=N`).
Controls: **WASD** move · **Shift** hurry (stamina) · **E** sit down on a free seat (train seat or platform bench; move or press E again to stand) · **M** tube map (**G** switches between the classic diagram and the geographic map) · **H** route hint · **Tab** skip time (when standing still or riding) ·
**F3** performance overlay · **F11** (or Alt+Enter) full screen · **Esc** pause/menu. Settings (graphics quality, crowd density, volume, mouse sensitivity) are on the main menu.

Tests: `tools/run_tests.sh` (quick) or `tools/run_tests.sh --full`. Video: `tools/record_video.sh out.mp4 [seed]` (not committed to git).

## Layout
See `docs/ARCHITECTURE.md` and `docs/ASSETS.md`. Code: `scripts/autoload` (Net, Clock, Timetable, Sfx), `scripts/sim` (Planner),
`scripts/world` (station generator, trains, crowds, signs, props), `scripts/game` (game loop, ride, HUD, map, autopilot), `scripts/people`.

## Known issues / roadmap
- Surface (outer-zone) stations are glass-roofed halls; rides between them still show a tunnel rather than open-air scenery.
- 19 major stations have layouts authored from TfL's station diagrams (Oxford Circus, King's Cross, Bank, Waterloo, Victoria, ... see docs/REAL_LAYOUTS.md); the rest are procedural per station (stable between runs) but use the real exit numbers, platform numbers and depths.
- The autopilot's multi-stop mode is slower than the planner's par (85-90%) and can wander into the wrong platform strip in crowds; it recovers by re-routing.
- Escalators use a simple shader for treads; no lifts or fixed stairs yet; buskers are audio-only.
- Performance was measured on an RTX 3050 Ti laptop under a virtual display only; use F3 and the Graphics setting to tune on your machine.
- Real-station specifics (tile patterns, exact layouts) are generic; only names, lines, zones, depth class and line colours are per-station.

## Credits
See `CREDITS.md`. Uses TfL open data, ambientCG (CC0) textures, MakeHuman/MPFB assets (CC0/CC-BY), CMU motion capture, Google Fonts (OFL),
Piper TTS voices. Not affiliated with Transport for London.
