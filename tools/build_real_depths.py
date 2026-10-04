#!/usr/bin/env python3
"""Platform depths below street for the stations that have none yet -> data/real_depths.json.

data/station_layouts.json (the TfL station layout diagrams, FOI 2015) and data/elizabeth_depths.json give a measured depth for about a hundred stations; the platform levels of data/platform_levels.json
(ground level and platform level above Ordnance Datum, TfL FOI table via tubedepths: tools/build_platform_levels.py) give one for nearly every other: depth = ground - platform level, per line group (the mean of its
platforms). Only underground or in-a-cutting depths are kept (3 m or more, 6 m or more for stations drawn open-air, where the generator's own 5-6.5 m is as good); a platform above the street cannot be built
(the plan only goes down from the hall). RealData merges the file under the measured ones.   python3 tools/build_real_depths.py"""
import json, os, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_line_geometry import _level

net = json.load(open(os.path.join(ROOT, "data", "network.json")))
authored = {f[:-5] for f in os.listdir(os.path.join(ROOT, "data", "layouts")) if f.endswith(".json")}          # (an authored layout has its own depths)
levels = json.load(open(os.path.join(ROOT, "data", "platform_levels.json")))
layouts = json.load(open(os.path.join(ROOT, "data", "station_layouts.json")))
el = json.load(open(os.path.join(ROOT, "data", "elizabeth_depths.json")))
out = {"_comment": "Platform depth in metres below street per line group, derived from data/platform_levels.json (ground level - platform level) for the stations without a measured one; tools/build_real_depths.py"}
n = 0
for sid, st in net["stations"].items():
    if sid not in levels or layouts.get(sid, {}).get("depths") or sid in authored:
        continue
    ground = levels[sid]["ground"]
    per_group = {}
    for pid, pl in st["platforms"].items():
        g = pl["group"].split(".")[0]
        lines = pl["lines"] or [pid.split(":")[0]]
        ds = []
        for ln in lines:
            if ln == "elizabeth" and sid in el:
                continue          # (measured: data/elizabeth_depths.json)
            lv = _level(levels, net, sid, ln, pid)
            if lv is not None:
                ds.append(ground - lv)
        if ds:
            per_group.setdefault(g, []).append(sum(ds) / len(ds))
    depths = {}
    floor = 6.0 if st["kind"] == "surface" else 3.0
    for g, ds in per_group.items():
        d = sum(ds) / len(ds)
        if d >= floor:
            depths[g] = [round(d, 1)]
    if depths:
        out[sid] = {"depths": depths, "source": "platform levels (TfL FOI table via tubedepths)"}
        n += 1
json.dump(out, open(os.path.join(ROOT, "data", "real_depths.json"), "w"), indent=0, separators=(",", ":"))
print("stations with a derived depth:", n)
