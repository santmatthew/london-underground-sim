#!/usr/bin/env python3
"""Platform heights of the Underground and Elizabeth line stations -> data/platform_levels.json.

Source: MichalPaszkiewicz/tubedepths (data/platformdepths.js, the TfL FOI station-depth table plus the Elizabeth line): for every station its ground level and, per line, the level of the
platforms of each direction (north / eastbound and south / westbound), in metres above Ordnance Datum. tools/build_elizabeth_depths.py fetched the file once into build/elizabeth/platformdepths_full.json
(private, not shipped); only the numbers are stored here. tools/build_line_geometry.py turns them into the climb ("dz") of every hop of track.
  python3 tools/build_platform_levels.py"""
import json, os, re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(ROOT, "build", "elizabeth", "platformdepths_full.json")
OUT = os.path.join(ROOT, "data", "platform_levels.json")
LINE_ID = {"Bakerloo": "bakerloo", "Central": "central", "Circle": "circle", "District": "district", "Hammersmith & City": "hammersmith-city", "Jubilee": "jubilee", "Metropolitan": "metropolitan",
           "Northern": "northern", "Piccadilly": "piccadilly", "Victoria": "victoria", "Waterloo & City": "waterloo-city", "Elizabeth": "elizabeth"}
# network name -> record name where they differ (Euston has one record per branch of the Northern line: handled below)
RENAME = {"Shepherd's Bush (Central)": "Shepherd's Bush", "Paddington (H&C)": "Paddington", "Hammersmith (H&C)": "Hammersmith", "Hammersmith (D&P)": "Hammersmith",
          "Heathrow Terminals 2 & 3": "Heathrow Terminals 1-2-3", "Burnham (Berks)": "Burnham", "Langley (Berks)": "Langley"}


def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower().replace("&", "and"))


def main():
    rows = json.load(open(SRC))
    by = {norm(r["name"]): r for r in rows}
    net = json.load(open(os.path.join(ROOT, "data", "network.json")))
    out = {"_comment": "Platform levels in metres above Ordnance Datum per station and line: [north- or eastbound, south- or westbound]; ground = street level. From MichalPaszkiewicz/tubedepths (TfL FOI depth table), numbers only; tools/build_platform_levels.py"}
    miss = []
    for sid, s in net["stations"].items():
        name = s["name"]
        if name == "Euston":
            ent = {"lines": {}}
            for key, rec in (("", "Euston City Branch"), ("_cx", "Euston Charing X Branch")):
                r = by[norm(rec)]
                ent["ground"] = r["groundLevel"]
                for l in r["stationLines"]:
                    if l["name"] in LINE_ID:
                        ent["lines"][LINE_ID[l["name"]] + key] = [l["northOrEastbound"], l["southOrWestbound"]]
            out[sid] = ent
            continue
        r = by.get(norm(RENAME.get(name, name)))
        if r is None:
            miss.append(name)
            continue
        out[sid] = {"ground": r["groundLevel"], "lines": {LINE_ID[l["name"]]: [l["northOrEastbound"], l["southOrWestbound"]] for l in r["stationLines"] if l["name"] in LINE_ID}}
    json.dump(out, open(OUT, "w"), indent=0, separators=(",", ":"))
    print("stations with levels:", len(out) - 1, "without:", miss)


if __name__ == "__main__":
    main()
