#!/usr/bin/env python3
"""Download the OpenStreetMap features we need for ALL stations in a handful of tile queries (the public Overpass servers only allow two
concurrent slots, so one query per station is hopelessly slow). Tiles are cached in build/osm_bulk/. ODbL data, see CREDITS.md.

Features: subway entrances (real exit numbers/names), underground platforms (ref, level, geometry), escalators/conveyors and steps
with level tags.
usage: fetch_osm_bulk.py
"""
import json, os, sys, time, urllib.parse, urllib.request

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "build", "osm_bulk")
UA = {"User-Agent": "UndergroundSimReference/0.1 (personal project; reference data only)", "Accept": "*/*",
      "Content-Type": "application/x-www-form-urlencoded"}
HOSTS = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"]

LAT0, LAT1, LON0, LON1 = 51.27, 51.80, -0.65, 0.31
NLAT, NLON = 8, 10


def query(s, w, n, e):
    b = "(%.5f,%.5f,%.5f,%.5f)" % (s, w, n, e)
    return ('[out:json][timeout:240];('
            'node["railway"="subway_entrance"]%s;'
            'way["railway"="platform"]["level"~"^-"]%s;'
            'way["railway"="platform"]["layer"~"^-"]%s;'
            'way["public_transport"="platform"]["subway"="yes"]%s;'
            'way["conveying"]["level"]%s;'
            'way["conveying"]["layer"~"^-"]%s;'
            'way["highway"="steps"]["level"~"-"]%s;'
            ');out tags geom;') % (b, b, b, b, b, b, b)


def fetch(q):
    last = None
    for attempt in range(6):
        for host in HOSTS:
            try:
                req = urllib.request.Request(host, headers=UA, data=urllib.parse.urlencode({"data": q}).encode())
                with urllib.request.urlopen(req, timeout=400) as r:
                    return json.load(r)
            except Exception as ex:
                last = ex
                print("   retry:", ex, flush=True)
                time.sleep(15 * (attempt + 1))
    raise RuntimeError(last)


def main():
    os.makedirs(OUT, exist_ok=True)
    dlat = (LAT1 - LAT0) / NLAT
    dlon = (LON1 - LON0) / NLON
    total = 0
    for i in range(NLAT):
        for j in range(NLON):
            fn = os.path.join(OUT, "tile_%d_%d.json" % (i, j))
            if os.path.exists(fn):
                continue
            s, w = LAT0 + i * dlat, LON0 + j * dlon
            t0 = time.time()
            d = fetch(query(s, w, s + dlat, w + dlon))
            json.dump(d, open(fn, "w"))
            total += len(d["elements"])
            print("tile %d,%d: %d elements in %.0fs" % (i, j, len(d["elements"]), time.time() - t0), flush=True)
            time.sleep(3)
    print("done", total)


if __name__ == "__main__":
    main()
