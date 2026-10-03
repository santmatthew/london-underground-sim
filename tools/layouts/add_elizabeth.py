#!/usr/bin/env python3
"""Adds the Elizabeth line platforms to the authored layouts of the stations it shares with the Underground (data/layouts/<naptan>.json).

The line's platforms get a landing of their own at the depth in data/elizabeth_depths.json (tools/build_elizabeth_depths.py), reached from the station's easternmost ticket hall by a bank
that leaves the hall's EAST wall (every other bank of these layouts goes south, and a module's tunnel runs east at its landing's lane: a landing east of the hall, level with it, has nothing
in the way). Platforms the data marks as terminal (Paddington, Heathrow Terminal 4) get both faces: a terminating train may use either.
Idempotent: whatever was added before (room "conc_el", bank "conc_el_*", the module of group "elizabeth") is removed first.   python3 tools/layouts/add_elizabeth.py [naptan ...]"""
import json, os, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
net = json.load(open(os.path.join(ROOT, "data", "network.json")))["stations"]
depths = json.load(open(os.path.join(ROOT, "data", "elizabeth_depths.json")))

# naptan: (escalator lanes, depth override, note). 1 = down, -1 = up
STATIONS = {
    "940GZZLUPAC": ([1, -1, 1, -1], None),
    "940GZZLUBND": ([1, -1, 1, -1], None),
    "940GZZLUTCR": ([1, -1, 1], None),
    "940GZZLUFCN": ([1, -1, 1], None),
    "940GZZLULVT": ([1, -1, 1, -1], None),
    "940GZZLUWPL": ([1, -1, 1], None),
    "940GZZLUCYF": ([1, -1, 1], None),
    "940GZZLUHR4": ([1, -1], 12.0),          # no measured depth: about that of the Piccadilly platforms there (12.9 m)
}


def add(naptan, lanes, depth_override):
    path = os.path.join(ROOT, "data", "layouts", naptan + ".json")
    d = json.load(open(path))
    d["rooms"] = [r for r in d["rooms"] if r["id"] != "conc_el"]
    d["esc"] = [e for e in d["esc"] if not e["id"].startswith("conc_el")]
    d["modules"] = [m for m in d["modules"] if m["group"] != "elizabeth"]
    halls = [r for r in d["rooms"] if r["kind"] == "hall"]
    east = max(halls, key=lambda r: r["rect"][1])
    depth = depth_override if depth_override else float(depths[naptan]["depths"]["elizabeth"][0])
    pids = {p: v for p, v in net[naptan]["platforms"].items() if v["group"] == "elizabeth"}
    terminal = [p for p, v in pids.items() if v["terminal"]]
    mods = []
    if terminal:
        # a terminal platform is an island with a face on each side; two terminal platforms: two islands
        for i, p in enumerate(sorted(pids)):
            mods.append({"faces": [[p, 0], [p, 1]], "lane_z": (i - (len(pids) - 1) / 2.0) * 18.0})
    else:
        mods.append({"faces": [[p, 0] for p in sorted(pids)], "lane_z": 0})
    depth_z = 16.0 + 18.0 * (len(mods) - 1)
    d["rooms"].append({"id": "conc_el", "kind": "landing", "size": [44, depth_z], "depth": depth})
    cz = round((east["rect"][2] + east["rect"][3]) / 2.0, 1)
    d["esc"].append({"id": "conc_el_0", "from": east["id"], "to": "conc_el", "dir": "E", "c": cz, "lanes": lanes, "to_off": 0.0})
    for m in mods:
        d["modules"].append({"attach": "conc_el", "lane_z": m["lane_z"], "lane_rel": True, "corr_len": 12, "group": "elizabeth", "faces": m["faces"]})
    note = d.get("note", "")
    if "Elizabeth line" not in note:
        d["note"] = note + "; Elizabeth line platforms %.1f m below street (tubedepths), reached from the east side of the hall (simplified)" % depth
    json.dump(d, open(path, "w"), indent=1)
    print(naptan, net[naptan]["name"], "-> depth %.1f, %d module(s), bank from %s east wall at z=%s" % (depth, len(mods), east["id"], cz))


if __name__ == "__main__":
    want = sys.argv[1:] or list(STATIONS)
    for n in want:
        add(n, *STATIONS[n])
