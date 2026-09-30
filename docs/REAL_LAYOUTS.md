# Real station layouts

Goal: stations that match the real ones. Three layers, each usable on its own.

## 1. Data for every station (done)
`data/stations_real.json` (tools/fetch_station_real.py, from `tools/extract_osm_stations.py` + TfL API):
entrances with real exit numbers/names and positions, platform outlines (ref, level, length, bearing), stairs/escalators/corridor ways near the station,
gate / escalator / lift / ticket-hall counts.
`data/platform_numbers.json` (tools/fetch_platform_numbers.py): real platform number per line and direction (TfL live arrivals).
`data/station_layouts.json` (tools/build_layout_depths.py): platform depth below street level per line group.

`StationPlan.generate` uses them where present: number and names of street doors, gate lanes, escalator lanes, platform numbers, depths
(stairs instead of escalators for flights under 6 m). Stations without data keep the generated values.

## 2. Sources for exact topology
| Source | What | Use |
|---|---|---|
| TfL "station layout" axonometric diagrams (FOI 2015, whatdotheyknow.com/request/maps_of_public_corridors_on_larg) | every platform, passage, stair, escalator, ticket hall of ~110 deep/sub-surface stations on 8 lines, plus a depth table | **private reference only** (TfL copyright): read by eye / OCR; only facts go into our data. Downloaded to `build/refs_tfl_fyi/` (git-ignored). Scanned images, not to scale |
| TfL Stop Structure API (api-portal.tfl.gov.uk, free key) | entrances, ticket halls, concourses, platforms and interchanges per station | not used yet (needs registration) |
| TfL station topology GTFS (api.tfl.gov.uk/stationdata/*.zip) | levels, step-free pathways, platform numbers/directions | downloaded to `build/tfl_topology/`; step-free routes only |
| OpenStreetMap (Geofabrik Greater London extract) | exits, platform outlines, stairs/escalators/corridors (patchy indoor mapping) | digested in `stations_real.json` |

What no public source provides: surveyed dimensions of halls, corridors and platforms. Corridor lengths are estimates (diagrams are topologically
exact, not to scale); OSM geometry refines them where a station is well mapped.

## 3. Authored layouts (next)
Hubs with several ticket halls, cross-links and stacked platforms (Oxford Circus, Bank/Monument, King's Cross St. Pancras, ...) cannot be a
single hall plus a chain of escalators. Plan: a per-station layout description (rooms, escalator/stair banks, corridors, platform modules,
several ticket halls each with its own gateline and exits) compiled into the same `StationPlan` structures (rooms, escs, modules, walking graph),
so signage, crowds, planner and bot keep working. Author from the diagrams; validate with `walkbot_test`, `walk_test`, `sign_audit_test` and bot journeys.

## Authored so far, and known limitations
Authored (data/layouts/, built from the TfL diagrams with tools/make_layout.py; per-station scripts in tools/layouts/ where kept):
Oxford Circus, King's Cross St. Pancras, Bank, Waterloo, Tottenham Court Road, Euston, Green Park, Liverpool Street, Victoria.
`tools/hub_walks.sh` walks every one of them (each ticket hall -> every platform, and every platform -> street) in one go.

- **Tunnel stubs cross landings (visual only).** Every platform module continues its running tunnel `PlatformModule.TUNNEL_EXT` = 170 m past
  both platform ends (trains approach along it, the ride scenery joins it). In the comb layouts the landing sits in front of the platform's west end,
  so that stub passes through the landing at the same level: from some angles a landing shows a piece of beige tunnel wall and track trough.
  The shell has no collision there and trains are non-solid away from the platform, so nothing blocks; `_check_overlaps` deliberately models a
  module as its platform length only. A proper fix needs the rooms beside the tunnel (not in line with it) or clipping the stub together with
  the train visibility and the ride approach.
- Street names for exits come from OSM where mapped; where the diagram only gives a letter (Victoria B, C) the exit has a number and no street name.
- Dimensions are estimates (the diagrams are topological, not to scale); depths come from the diagrams' depth tables.

