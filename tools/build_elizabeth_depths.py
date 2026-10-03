#!/usr/bin/env python3
"""Platform depths of the Elizabeth line stations -> data/elizabeth_depths.json.

Source: the platform levels (metres above ordnance datum) and ground levels of MichalPaszkiewicz/tubedepths (data/platformdepths.js, which adds the Elizabeth line to the
TfL FOI station-depth table, rounded to whole metres). Only the numbers are used. depth below street = ground level - platform level; at stations where the platforms are
at ground level (the rail stations of the outer sections, Custom House, Abbey Wood ...) that is 0.
  python3 tools/build_elizabeth_depths.py        (downloads the file; needs data/network.json built with the Elizabeth line)"""
import json, os, re, urllib.request

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
URL = "https://raw.githubusercontent.com/MichalPaszkiewicz/tubedepths/master/data/platformdepths.js"
net = json.load(open(os.path.join(ROOT, "data", "network.json")))
t = urllib.request.urlopen(urllib.request.Request(URL, headers={"User-Agent": "underground-sim-research/1.0"}), timeout=60).read().decode()
t = t[t.index("["):t.rindex("]") + 1]
t = re.sub(r"(\w+):", r'"\1":', t)
t = re.sub(r",\s*([}\]])", r"\1", t)
rows = json.loads(t)
by_name = {}
for sid, s in net["stations"].items():
    if "elizabeth" in s["lines"]:
        by_name.setdefault(s["name"].replace(" (Berks)", ""), sid)
out = {"_comment": "Elizabeth line platform depth in metres below street level, from MichalPaszkiewicz/tubedepths platformdepths.js (TfL FOI depth table, whole metres). tools/build_elizabeth_depths.py"}
for r in rows:
    for ln in r["stationLines"]:
        if ln["name"] != "Elizabeth":
            continue
        sid = by_name.get(r["name"])
        if sid is None:
            print("no station for", r["name"])
            continue
        lvl = ln["northOrEastbound"] if ln["northOrEastbound"] is not None else ln["southOrWestbound"]
        depth = max(0.0, round(float(r["groundLevel"]) - float(lvl), 1))
        out[sid] = {"depths": {"elizabeth": [depth]}, "source": "tubedepths (TfL FOI depth table, rounded to 1 m)"}
json.dump(out, open(os.path.join(ROOT, "data", "elizabeth_depths.json"), "w"), indent=1)
missing = [n for n, sid in by_name.items() if sid not in out]
print(len(out) - 1, "stations; no depth for:", missing)
