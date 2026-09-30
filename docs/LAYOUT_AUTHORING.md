# Authoring a real station layout

A station is described by a small **brief** (`tools/layouts/briefs/<naptan>.json`) read off TfL's station layout diagram; `tools/layout_builder.py` turns it into
`data/layouts/<naptan>.json` (all the geometry is automatic) and `tools/check_layout.sh` proves the result: it compiles, every route is walkable, no sign clips, no
visible wall is walk-through, and a moving player capsule can walk every route. Nothing about geometry is written by hand.

## Procedure (one station, ~5 minutes)
1. `python3 tools/layout_facts.py "<station>"` prints the platform groups, depth-table values, real exits, TfL facility counts, a brief skeleton, and the path of the
   upright diagram image(s). **Look at the image(s)** (Read tool). For detail: `--crop=x0,y0,x1,y1` (fractions of the page) or `--width=3600`.
2. Write `tools/layouts/briefs/<naptan>.json` (schema below).
3. `python3 tools/layout_builder.py tools/layouts/briefs/<naptan>.json` (a "BRIEF ERROR" says exactly what to change).
4. `tools/check_layout.sh "<station>"` (1-2 minutes). Read every FAIL line and fix the brief, not the code. Repeat 3-4 until PASS.
5. If you cannot reach PASS in about 4 attempts, leave the brief as your best attempt, delete nothing, and report what fails and why.

## Brief schema
```json
{
  "naptan": "940GZZLUVIC",
  "source": "TfL station layout diagram V047-02",
  "halls": [ {"id": "A", "exits": [{"ref": "A", "name": "Victoria Station"}, {"ref": "F"}], "gates": 12},
             {"id": "B", "exits": [{"ref": "B"}, {"ref": "C"}]} ],
  "hall_links": [["A", "B"]],
  "levels": [ {"id": "conc", "depth": 6.4, "groups": ["ss"]}, {"id": "low", "depth": 17.9, "groups": ["victoria"]} ],
  "banks": [ {"from": "A", "to": "conc", "lanes": [1, -1, 1]}, {"from": "B", "to": "conc", "lanes": [1, -1], "stairs": true},
             {"from": "conc", "to": "low", "lanes": [1, -1, 1, -1]} ]
}
```
* **halls** = street-level ticket halls, each with its own gateline and street exits. One hall per "TICKET HALL" on the diagram (the TfL facility count printed by
  `layout_facts.py` is a cross-check). `exits`: one entry per street exit shown/lettered on the diagram, in the order they should appear along the hall. `gates` optional
  (derived from the TfL record). If a hall has no `exits`, the station's real OSM entrances are shared out over the halls.
* **hall_links** = pairs of halls that share paid space (a passage between ticket halls that does not go through a barrier). Give it only if the diagram shows such a link;
  the two halls must be neighbours in the `halls` list.
* **levels** = the rooms below the halls: concourses / landings / platform levels, each with its **depth in metres below street** and the **platform groups** whose platforms
  are reached on it (`layout_facts.py` lists the groups: every group must be placed in exactly one level). A concourse that serves no platforms has `"groups": []`.
  `depth`: the diagram's "APPROXIMATE DEPTH BELOW STREET LEVEL" table gives the platform levels (metres); read it from the image (the OCR'd values are only a hint);
  intermediate concourses are not tabulated - estimate them between their neighbours (about 40-60% of the way down) and say so in your report.
* **banks** = escalator / stair banks going **down** from a hall or level to a deeper level. `lanes`: one entry per escalator, 1 = down, -1 = up (`[1,-1,1]` = 3 units).
  Count the numbered units the diagram labels ("ESCALATORS 4,5,6" = 3 lanes); use `stairs: true` for fixed stairs (also automatic for drops under 6 m).
  If the diagram shows a hall reaching two levels directly, just list both banks: the builder chains the deeper one from the shallower level (same total drop).

## Reading the diagrams
* Axonometric drawings: the ticket hall(s) at the top (street or subway level), escalator banks as ribbons of parallel lines with an arrow, concourses as flat slabs,
  platforms as long tunnels/boxes labelled "PLATFORM n" with direction and destination, a depth table at the bottom right. Ignore lifts, emergency stairs and exits, fan
  shafts, disused areas, National Rail / Overground / DLR platforms and mainline concourses - only Underground platform groups matter.
* Exit letters (A, B, C ...) mark street exits. Use them as `ref` when the diagram gives no other name. **Never invent street or place names**: use a name only if it is
  printed on the diagram (e.g. "TO MAINLINE STATION", "EXIT TO ... ROAD") or comes from `layout_facts.py`'s real-exit list; otherwise give the exit a `ref` only.
* If a diagram is hard to read, say which part and what you assumed; a simple honest brief (one hall, the right levels and depths) beats a guess.

## Rules
* Write only `tools/layouts/briefs/<naptan>.json` and the `data/layouts/<naptan>.json` the builder makes. Do not edit code, tests, other stations' files, or run git.
* The diagrams are TfL copyright: private reference under `build/`. Never copy them out of `build/` or into a brief; a brief holds facts only.
* Keep `source` to the drawing number on the diagram ("N185-02" in its title block).
