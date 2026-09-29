#!/usr/bin/env python3
"""Read the Greater London OpenStreetMap extract (Geofabrik, ODbL) and write the station-relevant features to build/osm_bulk/tile_extract.json
in the same element format as an Overpass `out tags geom` reply, so tools/fetch_station_real.py can digest them.

Features kept (near any station of data/network.json only): subway entrances, underground platforms, escalators/conveyors, indoor steps,
and underground footways/corridors (tunnel=yes / indoor / negative level).
usage: build/venv/bin/python tools/extract_osm_stations.py [path/to/greater-london.osm.pbf]
"""
import json, math, os, sys
import osmium

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
PBF = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "osm_extract", "greater-london.osm.pbf")
OUT = os.path.join(ROOT, "build", "osm_bulk", "tile_extract.json")
RADIUS = 300.0     # metres around a station centre
KEEP = ("name", "ref", "level", "layer", "railway", "highway", "conveying", "line", "entrance", "indoor", "incline", "width", "length",
        "operator", "public_transport", "tunnel", "bridge", "wheelchair", "elevator", "location", "step_count", "subway", "area", "min_level",
        "max_level", "level:ref", "door", "access")

net = json.load(open(os.path.join(ROOT, "data", "network.json")))
STATIONS = [(v["lat"], v["lon"]) for v in net["stations"].values()]
# coarse grid for quick "near a station" tests
CELL = 0.004
grid = {}
for i, (la, lo) in enumerate(STATIONS):
    for di in (-1, 0, 1):
        for dj in (-1, 0, 1):
            grid.setdefault((int(la / CELL) + di, int(lo / CELL) + dj), []).append(i)


def near_station(lat, lon):
    for i in grid.get((int(lat / CELL), int(lon / CELL)), []):
        la, lo = STATIONS[i]
        dy = (lat - la) * 111320.0
        dx = (lon - lo) * 111320.0 * math.cos(math.radians(la))
        if dx * dx + dy * dy <= RADIUS * RADIUS:
            return True
    return False


def neg(v):
    return v is not None and "-" in v


class H(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.out = []

    def node(self, n):
        if n.tags.get("railway") == "subway_entrance" and n.location.valid() and near_station(n.location.lat, n.location.lon):
            self.out.append({"type": "node", "id": n.id, "lat": n.location.lat, "lon": n.location.lon,
                             "tags": {k: n.tags[k] for k in KEEP if k in n.tags}})

    def way(self, w):
        t = w.tags
        lv = t.get("level") or t.get("layer")
        wanted = False
        if t.get("railway") == "platform" and (neg(t.get("level")) or neg(t.get("layer")) or t.get("subway") == "yes" or t.get("tunnel") == "yes"):
            wanted = True
        elif t.get("public_transport") == "platform" and (t.get("subway") == "yes" or neg(lv)):
            wanted = True
        elif t.get("conveying") and (t.get("level") or neg(t.get("layer")) or t.get("tunnel") == "yes" or t.get("indoor")):
            wanted = True
        elif t.get("highway") == "steps" and (neg(t.get("level")) or neg(t.get("layer")) or t.get("indoor")):
            wanted = True
        elif t.get("highway") in ("footway", "corridor", "path") and (t.get("indoor") == "corridor" or (t.get("tunnel") == "yes" and neg(lv)) or neg(t.get("level"))):
            wanted = True
        if not wanted:
            return
        try:
            pts = [(n.lat, n.lon) for n in w.nodes if n.location.valid()]
        except Exception:
            return
        if not pts or not near_station(sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)):
            return
        self.out.append({"type": "way", "id": w.id, "tags": {k: t[k] for k in KEEP if k in t},
                         "geometry": [{"lat": p[0], "lon": p[1]} for p in pts]})


def main():
    h = H()
    h.apply_file(PBF, locations=True, idx="flex_mem")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump({"elements": h.out}, open(OUT, "w"))
    from collections import Counter
    c = Counter()
    for e in h.out:
        t = e["tags"]
        c[t.get("railway") or t.get("conveying") and "conveying" or t.get("highway") or t.get("public_transport")] += 1
    print("wrote", OUT, len(h.out), "elements", dict(c))


if __name__ == "__main__":
    main()
