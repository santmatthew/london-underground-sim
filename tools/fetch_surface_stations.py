#!/usr/bin/env python3
"""What the Underground's generated surface stations look like from above, from OpenStreetMap: the platform outlines, the footbridges and the rail around each (the layout the generator then draws:
two separate platforms with the tracks between them, or one island). The same query as tools/fetch_el_stations.py for every station of kind "surface" that has no hand-authored layout
(data/layouts/<id>.json) and whose platform numbers TfL gives (data/platform_numbers.json). tools/build_surface_platforms.py reduces it to data/surface_platforms.json.
Output: build/geom/surface_stations.json (not shipped). Data (c) OpenStreetMap contributors, ODbL.
  tools/fetch_surface_stations.py            fetches the stations that are missing        --refetch   all again
"""
import json, os, sys, time, urllib.parse, urllib.request

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
GEOM = os.path.join(ROOT, "build", "geom")
OUT = os.path.join(GEOM, "surface_stations.json")
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


def targets():
    net = json.load(open(os.path.join(ROOT, "data", "network.json")))["stations"]
    pn = json.load(open(os.path.join(ROOT, "data", "platform_numbers.json")))
    authored = set(f[:-5] for f in os.listdir(os.path.join(ROOT, "data", "layouts")) if f.endswith(".json"))
    out = {}
    for sid, st in net.items():
        if st.get("kind") != "surface" or sid in authored or sid not in pn:
            continue
        groups = {}
        for pid, pl in st["platforms"].items():
            groups.setdefault(pl["group"], []).append(pl["terminal"])
        # (a group of two through platforms that is not the Elizabeth line's: what tools/build_surface_platforms.py can settle)
        if any(g != "elizabeth" and len(t) == 2 and not any(t) for g, t in groups.items()):
            out[sid] = st
    return out


def near(way, lat, lon, r):
    """does any vertex of the way lie within r metres of (lat, lon)?"""
    import math
    for p in way.get("geometry", []) or []:
        if p is None:
            continue
        dx = (p["lon"] - lon) * 111320.0 * math.cos(math.radians(lat))
        dy = (p["lat"] - lat) * 110574.0
        if dx * dx + dy * dy <= r * r:
            return True
    return False


def main():
    os.makedirs(GEOM, exist_ok=True)
    have = json.load(open(OUT)) if os.path.exists(OUT) and "--refetch" not in sys.argv else {}
    todo = [(sid, st) for sid, st in sorted(targets().items(), key=lambda kv: kv[1]["name"]) if sid not in have]
    # several stations a query (the public servers answer a few big queries sooner than many small ones); each way goes to every station it comes within R of
    BATCH = 8
    for i in range(0, len(todo), BATCH):
        batch = todo[i:i + BATCH]
        parts = []
        for sid, st in batch:
            a = "(around:%d,%f,%f)" % (R, st["lat"], st["lon"])
            parts.append('way["railway"="platform"]%s;way["public_transport"="platform"]%s;way["bridge"="yes"]["highway"~"footway|steps|pedestrian"]%s;way["railway"~"^(rail|subway|light_rail)$"]%s;' % (a, a, a, a))
        try:
            d = overpass("(" + "".join(parts) + ");out tags geom;")
        except RuntimeError as e:
            print("  skipped a batch", str(e)[:60], flush=True)
            continue
        for sid, st in batch:
            ways = [w for w in d["elements"] if near(w, st["lat"], st["lon"], R)]
            have[sid] = {"name": st["name"], "lat": st["lat"], "lon": st["lon"], "ways": ways}
            print("%-28s %d ways" % (st["name"], len(ways)), flush=True)
        json.dump(have, open(OUT, "w"))
        time.sleep(5)


if __name__ == "__main__":
    main()
