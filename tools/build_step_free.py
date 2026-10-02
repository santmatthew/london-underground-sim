#!/usr/bin/env python3
"""Which platforms can be reached from the street without stairs or escalators -> data/step_free.json.
Source: TfL's station topology GTFS (build/tfl_topology/gtfs, "step-free routes only": stops.txt + pathways.txt, mode 1 = level / ramp, mode 5 = lift). A platform counts as step-free when
a chain of such pathways joins it to an "Outside <station>" node of its station (or of its hub: stations like Waterloo or Bank are one hub in the feed). The platform stops are named
<station>-Plat<NN>-<NB|SB|EB|WB|IR|OR>-<line>; they are matched to ours by line and direction.
Stations the feed does not cover keep no entry (the game treats them as not step-free: better to leave a station out than to send a wheelchair user to stairs).
    python3 tools/build_step_free.py"""
import collections
import csv
import json
import os
import re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
G = os.path.join(ROOT, "build", "tfl_topology", "gtfs")
DIRS = {"NB": "Northbound", "SB": "Southbound", "EB": "Eastbound", "WB": "Westbound", "IR": "Inner Rail", "OR": "Outer Rail"}


def main():
    stops = {r["stop_id"]: r for r in csv.DictReader(open(os.path.join(G, "stops.txt")))}
    adj = collections.defaultdict(set)
    for r in csv.DictReader(open(os.path.join(G, "pathways.txt"))):
        adj[r["from_stop_id"]].add(r["to_stop_id"])
        if r["is_bidirectional"] == "1":
            adj[r["to_stop_id"]].add(r["from_stop_id"])
    net = json.load(open(os.path.join(ROOT, "data", "network.json")))["stations"]
    out = {}
    covered_gtfs = covered_hub = 0
    for nid, s in net.items():
        parents = [nid] + ([s["hub"]] if s.get("hub") else [])
        outs = [k for k, v in stops.items() if v["parent_station"] in parents and v["location_type"] == "3" and v["stop_name"].startswith("Outside")]
        plats = [k for k, v in stops.items() if v["parent_station"] in parents and v["location_type"] == "0"]
        # at a hub keep the platforms of our lines (the hub also holds the rail platforms and the other Underground station's)
        lines = set(s["lines"])
        keep = []
        for p in plats:
            m = re.match(r".*-Plat(\w+?)-(\w+)-([\w-]+)$", p)
            if m and m.group(3) in lines and (p.startswith(nid) or not p.startswith("940G") or s.get("hub")):
                keep.append((p, m.group(2), m.group(3)))
        if not keep or not outs:
            continue
        if keep[0][0].startswith(nid):
            covered_gtfs += 1
        else:
            covered_hub += 1
        seen = set(outs)
        stack = list(outs)
        while stack:
            u = stack.pop()
            for w in adj[u]:
                if w not in seen:
                    seen.add(w)
                    stack.append(w)
        ent = {}
        for p, d, line in keep:
            key = "%s|%s" % (line, DIRS.get(d, d))
            ent[key] = ent.get(key, False) or (p in seen)
        out[nid] = ent
    json.dump(out, open(os.path.join(ROOT, "data", "step_free.json"), "w"), indent=0, sort_keys=True)
    full = sum(1 for e in out.values() if all(e.values()))
    some = sum(1 for e in out.values() if any(e.values()) and not all(e.values()))
    print("stations with data: %d (own entry %d, via hub %d) of %d;  every platform step-free: %d, some: %d, none: %d" % (len(out), covered_gtfs, covered_hub, len(net), full, some, len(out) - full - some))


if __name__ == "__main__":
    main()
