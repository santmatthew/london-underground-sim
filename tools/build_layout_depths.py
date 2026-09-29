#!/usr/bin/env python3
"""Turn OCR'd depth tables of TfL's station layout diagrams (private reference PDFs, see docs/REAL_LAYOUTS.md) into data/station_layouts.json.

The drawings themselves are TfL copyright and are never committed; this file only holds the *facts* read from them (platform depth in metres
below street level per line group).  usage: build_layout_depths.py   (needs build/refs_tfl_fyi/{depth_rows2.json,station_pages.json})
"""
import json, os, re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
REF = os.path.join(ROOT, "build", "refs_tfl_fyi")
OUT = os.path.join(ROOT, "data", "station_layouts.json")

rows = json.load(open(os.path.join(REF, "depth_rows2.json")))
net = json.load(open(os.path.join(ROOT, "data", "network.json")))
by_name = {v["name"]: k for k, v in net["stations"].items()}


def group_of(label):
    s = label.upper()
    if "TICKET" in s:
        return "hall"
    for key, g in (("BAKERLOO", "bakerloo"), ("CENTRAL", "central"), ("JUBILEE", "jubilee"), ("NORTHERN", "northern"), ("PICCADILLY", "piccadilly"),
                   ("VICTORIA", "victoria"), ("WATERLOO", "waterloo-city"), ("DISTRICT", "ss"), ("CIRCLE", "ss"), ("METROPOLITAN", "ss"),
                   ("HAMMERSMITH", "ss")):
        if key in s:
            return g
    return ""


out = {}
for name, rs in rows.items():
    if name not in by_name or not rs:
        continue
    d = {}
    for label, depth in rs:
        g = group_of(label)
        if not g or depth < 3.0 or depth > 60.0:
            continue
        lst = d.setdefault(g, [])
        if depth not in lst:
            lst.append(depth)
    if d:
        entry = {"depths": {g: sorted(v) for g, v in d.items() if g != "hall"}, "source": "TfL station layout diagram (FOI 2015), depth table"}
        if "hall" in d:
            entry["hall_depth"] = d["hall"][0]
        out[by_name[name]] = entry
json.dump(out, open(OUT, "w"), indent=0, sort_keys=True)
print("wrote", OUT, len(out), "stations")
