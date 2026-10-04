#!/usr/bin/env python3
"""What the Elizabeth line's surface stations look like from above, from OpenStreetMap: the platform outlines, the roofs / canopies / shelters over them and the footbridges, within 220 m of each station.
tools/build_el_looks.py reads build/geom/el_stations.json and writes the per-station facts (platform layout, how much of each platform is roofed) to data/station_character.json.
Output: build/geom/el_stations.json (not shipped). Data (c) OpenStreetMap contributors, ODbL.
  tools/fetch_el_stations.py            fetches the stations that are missing        --refetch   all again
"""
import json, os, sys, time, urllib.parse, urllib.request

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
GEOM = os.path.join(ROOT, "build", "geom")
OUT = os.path.join(GEOM, "el_stations.json")
UA = {"User-Agent": "UndergroundSimReference/0.1 (personal project; reference data only)", "Accept": "*/*", "Content-Type": "application/x-www-form-urlencoded"}
HOSTS = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"]
R = 220


def overpass(q, tries=4):
    last = None
    for attempt in range(tries):
        for host in HOSTS:
            try:
                req = urllib.request.Request(host, headers=UA, data=urllib.parse.urlencode({"data": "[out:json][timeout:60];" + q}).encode())
                with urllib.request.urlopen(req, timeout=90) as r:
                    return json.load(r)
            except Exception as e:
                last = e
                print("  overpass error:", str(e)[:80], flush=True)
                time.sleep(6 * (attempt + 1))
    raise RuntimeError(last)


def main():
    net = json.load(open(os.path.join(ROOT, "data", "network.json")))
    els = {}
    for sid, st in net["stations"].items():
        lines = st["lines"] if isinstance(st["lines"], list) else list(st["lines"].keys())
        if "elizabeth" in lines:
            els[sid] = st
    have = json.load(open(OUT)) if os.path.exists(OUT) and "--refetch" not in sys.argv else {}
    for sid, st in sorted(els.items(), key=lambda kv: kv[1]["name"]):
        if sid in have:
            continue
        lat, lon = st["lat"], st["lon"]
        a = "(around:%d,%f,%f)" % (R, lat, lon)
        q = ('(way["railway"="platform"]%s;way["public_transport"="platform"]%s;way["building"="roof"]%s;way["man_made"="canopy"]%s;way["shelter"="yes"]%s;way["covered"="yes"]%s;'
             'way["bridge"="yes"]["highway"~"footway|steps|pedestrian"]%s;way["railway"="rail"]%s;);out tags geom;') % (a, a, a, a, a, a, a, a)
        try:
            d = overpass(q)
        except RuntimeError as e:
            print("  skipped", st["name"], str(e)[:60], flush=True)
            continue
        have[sid] = {"name": st["name"], "lat": lat, "lon": lon, "ways": d["elements"]}
        json.dump(have, open(OUT, "w"))
        print("%-28s %d ways" % (st["name"], len(d["elements"])), flush=True)
        time.sleep(4)


if __name__ == "__main__":
    main()
