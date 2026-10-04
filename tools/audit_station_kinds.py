#!/usr/bin/env python3
"""Which stations does the simulator draw in the wrong setting? Compares each station's kind (data/network.json: "deep" arched tube platforms, "sub" covered box, "surface" open to the sky) with what OpenStreetMap
says the track does at its ends (data/line_geometry.json "sec") and the platform depth below street (data/platform_levels.json, TfL FOI table via tubedepths). Prints candidates; the corrections that were
checked are in data/station_kind_overrides.json (applied by tools/build_network.py).  python3 tools/audit_station_kinds.py"""
import collections, json, os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
d = json.load(open(os.path.join(ROOT, "data", "line_geometry.json")))["pairs"]
net = json.load(open(os.path.join(ROOT, "data", "network.json")))["stations"]
lev = json.load(open(os.path.join(ROOT, "data", "platform_levels.json")))
ends = collections.defaultdict(list)
for k, v in d.items():
    a, b = k.split(">")
    sec = v.get("sec")
    if sec:
        ends[a].append((sec[0][0], sec[0][1]))
        ends[b].append((sec[-1][0], sec[-1][1]))
for sid, lst in sorted(ends.items(), key=lambda kv: net[kv[0]]["name"]):
    codes = [c for c, l in lst if l >= 60]
    if not codes:
        continue
    tun = sum(1 for c in codes if c == 1)
    real = "tunnel" if tun == len(codes) else ("open" if tun == 0 else "mixed")
    kind = net[sid]["kind"]
    l = lev.get(sid, {})
    depth = max([l["ground"] - min(v) for v in l.get("lines", {}).values()]) if l.get("ground") is not None and l.get("lines") else None
    if (kind == "deep" and real == "open") or (kind == "surface" and real == "tunnel") or (kind == "sub" and real == "open"):
        print("%-28s drawn %-8s track %-6s depth %s" % (net[sid]["name"], kind, real, "?" if depth is None else "%.1f m" % depth))
