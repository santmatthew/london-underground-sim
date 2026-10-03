# Underground Sim

A first-person simulation of riding the **London Underground**, built with Godot 4.7 (GDScript) and Blender 5.2.
You start at a random point inside a random station, are given a destination (or several), and must reach the street exit as fast
as you can. Time of day (crowds and train frequency), the real train timetable, and the route you take through each station all matter.

## What's in it
- **Real network**: 301 stations, 12 lines (the 11 Underground lines and the Elizabeth line from Reading and Heathrow to Shenfield and Abbey Wood), real routes/branches/zones/coordinates from the TfL open API; deterministic timetable with
  time-of-day and weekday/weekend frequencies, per-platform regulation (no two trains ever overlap) and 1–2 faces at termini.
- **Journey planner**: earliest-arrival routing over the timetable *and* each station's walking graph gives the optimal ("par") time; an exact
  Held-Karp tour optimiser gives the par for multi-stop games (computed on a worker thread).
- **Procedural stations** (deterministic per station): street passages, ticket hall with gate lines (real gate models), escalator banks,
  landings, corridors, and three platform styles: deep-tube twin tunnels, sub-surface box halls with columns, and glass-roofed surface halls.
  Wayfinding modelled on real Tube signage (white enamel panels with line-coloured rules, black/yellow "Way out", fascia name boards, roundels,
  tile-lettering panels, live dot-matrix indicators driven by the timetable).
- **Trains**: Blender-built deep-tube and sub-surface cars (interiors, moquette, poles, sliding doors, line diagrams, destination displays)
  that approach, stop, open doors and depart on the timetable. **Ride** them: the world scrolls past as tunnel while the next station is built
  and slides in; announcements, ambience and sway included. The track **bends** like the real one (heading and curvature from OpenStreetMap): rides turn through the tunnels, the cars swing round the
  bends, and over eighty platforms are curved (Bank, Tower Hill, Waterloo Bakerloo, Embankment, Euston, Liverpool Street, Bow Road, Loughton ...) with the gap that goes with them.
- **People**: 36 MakeHuman-based characters (clothes, hair, skins, bags) animated with retargeted CMU mocap; crowd flows follow the same routes
  the planner uses (gates, escalators — standing on the right — platforms, boarding and alighting), scaled by time of day; riders fill the carriages.
- **Audio**: 1300+ generated clips: station/line announcements in a British voice (keyed by station and line/destination), ambience layers
  that crossfade by location, door/gate/escalator/train sounds, footsteps.
- **Game modes**: single destination and multi-stop (visit 3–5 stations in any order), route hints, tube map with Thames, scoring against par; and **Explore**, where there is no destination, timer or score: pick any station (search or random), where in it to start (a street entrance, the ticket hall, the concourse or a platform), the day and the time, then roam it and ride any train. Esc in explore mode offers "Start somewhere else" (`--explore=Station_name --spot=platform --hour=10` starts one from the command line).
- **Tooling**: an autopilot bot that plays whole journeys (used for testing and for recording videos), walkability audits, video recorder.

## Run
```
tools/setup_assets.sh      # once: fetch/generate the large assets that are not stored in git (see docs/ASSETS.md; some steps take a while)
godot --path .             # or open the project in Godot 4.7 and press F5
```
Jump straight to a journey (handy for the authored stations): `godot --path . -- --start=Victoria --dest=Bank --spot=street_entrance --hour=8.5 --auto-start`
(station names with underscores for spaces; `--spot=platform` or `street_entrance`; `--seed=N`).
Controls (all rebindable under Settings > Controls; a gamepad works too): **WASD** or the left stick move · **Shift** / RB hurry (stamina), with **Ctrl** / LB run · mouse or right stick look · **E** / A sit down on a free seat (train seat or platform bench; move or press again to stand) · **M** / Y tube map (**G** / B switches between the classic diagram and the geographic map; right stick pans, triggers zoom) · **H** / X route hint · **Tab** skip time (when standing still or riding) ·
**F3** performance overlay · **F4** frame-time log · **F11** (or Alt+Enter) full screen · **Esc** / Start pause/menu. The main menu has the journey options and graphics (quality, render scale (Auto adapts to the GPU to keep about 60 fps), upscaler, anti-aliasing, full screen, crowd density); **Settings** has Sound (volumes, announcements, subtitles), Accessibility (colour-blind line colours, optional step-free journeys, HUD and subtitle size, no camera sway) and Controls.

See `docs/ARCHITECTURE.md` and `docs/ASSETS.md`. Code: `scripts/autoload` (Net, Clock, Timetable, Sfx), `scripts/sim` (Planner),
`scripts/world` (station generator, trains, crowds, signs, props), `scripts/game` (game loop, ride, HUD, map, autopilot), `scripts/people`.

## Known issues / roadmap
- Surface (outer-zone) stations are glass-roofed halls; rides between them still show a tunnel rather than open-air scenery.
- 19 major stations have layouts authored from TfL's station diagrams (Oxford Circus, King's Cross, Bank, Waterloo, Victoria, ... see docs/REAL_LAYOUTS.md); the rest are procedural per station (stable between runs) but use the real exit numbers, platform numbers and depths.
- The autopilot's multi-stop mode is slower than the planner's par (85-90%) and can wander into the wrong platform strip in crowds; it recovers by re-routing.
- Escalators use a simple shader for treads; stations that have lifts in reality have them beside the escalators (press E at the door: a fade and the wait and ride take their time, no car interior); the five lift-only stations (Borough, Covent Garden, Goodge Street, Hampstead, Russell Square) have lifts instead of escalators and a spiral emergency stair you can walk (the door beside the lifts, E; 193 steps at Covent Garden, 320 at Hampstead, the longest on the network); short drops (under about 6 m, 11 m at surface stations) are fixed stairs; a busker loop exists in the audio set but is not placed.
- Performance was measured on an RTX 3050 Ti laptop under a virtual display only; use F3 and the Graphics setting to tune on your machine.
- Real-station specifics (tile patterns, exact layouts) are generic; only names, lines, zones, depth class and line colours are per-station.

## Credits
See `CREDITS.md`. Uses TfL open data, ambientCG (CC0) textures, MakeHuman/MPFB assets (CC0/CC-BY), CMU motion capture, Google Fonts (OFL),
Piper TTS voices. Not affiliated with Transport for London.
