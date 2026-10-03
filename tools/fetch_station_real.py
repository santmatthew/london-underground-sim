#!/usr/bin/env python3
"""Fetch real-world structure of every Underground station and digest it into data/stations_real.json.

Sources (both open data, attribution in CREDITS.md):
  * TfL Unified API  /StopPoint/<naptan>   (Open Government Licence v3): entrances and platforms with coordinates, facility counts
    (gates, escalators, lifts, ticket halls).
  * OpenStreetMap via Overpass (ODbL): subway entrances (real exit numbers and names), platforms (ref, level, geometry), stairs and
    escalators (level/layer), running-tunnel ways (line, depth layer).

usage: fetch_station_real.py [--only "Oxford Circus"] [--refresh] [--missing]
  --missing  only the stations of data/network.json that data/stations_real.json does not have yet (the Elizabeth line's rail stations); their OSM features come from Overpass
             (the bulk extract covers Greater London's Underground stations only), and the file's other entries are kept
Raw responses are cached in build/real_raw/ (git-ignored); the digest goes to data/stations_real.json (committed, small).
"""
import json, math, os, sys, time, urllib.request, urllib.parse

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
RAW = os.path.join(ROOT, "build", "real_raw")
OUT = os.path.join(ROOT, "data", "stations_real.json")
TFL_UA = {"User-Agent": "curl/8.5.0", "Accept": "application/json"}
OSM_UA = {"User-Agent": "UndergroundSimReference/0.1 (personal project; reference data only)", "Accept": "*/*",
          "Content-Type": "application/x-www-form-urlencoded"}
OVERPASS = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"]
KEEP = ("name", "ref", "level", "layer", "railway", "highway", "conveying", "line", "entrance", "indoor", "incline", "width", "length",
        "operator", "public_transport", "tunnel", "bridge", "wheelchair", "elevator", "location", "step_count")


def tfl(naptan):
    for attempt in range(6):
        try:
            req = urllib.request.Request("https://api.tfl.gov.uk/StopPoint/" + naptan, headers=TFL_UA)
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)
        except Exception as e:                      # 429: back off
            time.sleep(4 * (attempt + 1))
            last = e
    raise RuntimeError(last)


def overpass(q):
    last = None
    for host in OVERPASS:
        for attempt in range(3):
            try:
                req = urllib.request.Request(host, headers=OSM_UA, data=urllib.parse.urlencode({"data": q}).encode())
                with urllib.request.urlopen(req, timeout=180) as r:
                    return json.load(r)
            except Exception as e:  # 429 / 504 etc.: back off politely
                last = e
                time.sleep(8 * (attempt + 1))
    raise RuntimeError("overpass failed: %s" % last)


def osm_query(lat, lon, radius):
    a = "around:%d,%.6f,%.6f" % (radius, lat, lon)
    return ('[out:json][timeout:120];('
            'node["railway"="subway_entrance"](%s);'
            'node["railway"="train_station_entrance"](%s);'
            'way["railway"="platform"](%s);'
            'way["public_transport"="platform"]["subway"="yes"](%s);'
            'way["highway"="steps"](%s);'
            'way["conveying"](%s);'
            'way["railway"="subway"](%s);'
            ');out tags geom 700;') % (a, a, a, a, a, a, a)


def m_per_deg(lat):
    return 111320.0, 111320.0 * math.cos(math.radians(lat))


def to_xy(lat0, lon0, lat, lon):
    my, mx = m_per_deg(lat0)
    return ((lon - lon0) * mx, (lat - lat0) * my)          # east, north (metres)


def bearing_deg(dx, dy):
    return (math.degrees(math.atan2(dx, dy)) + 360.0) % 360.0


def tags(t):
    return {k: t[k] for k in KEEP if k in t}


def _thin(pts, keep=6):
    """first, last and a few vertices in between"""
    if len(pts) <= keep:
        return pts
    idx = sorted(set([0, len(pts) - 1] + [round(i * (len(pts) - 1) / (keep - 1)) for i in range(keep)]))
    return [pts[i] for i in idx]


def digest(naptan, st, tj, oj):
    lat0, lon0 = st["lat"], st["lon"]
    props = {p["key"]: p["value"] for p in tj.get("additionalProperties", [])}

    def num(k):
        try:
            return int(props.get(k, "0"))
        except ValueError:
            return 0
    facility = {"gates": num("Gates"), "escalators": num("Escalators"), "lifts": num("Lifts"), "ticket_halls": num("Ticket Halls"),
                "zone": props.get("Zone", ""), "bridge": props.get("Bridge", "") == "yes"}
    if naptan.startswith(("910G", "HUB")) and facility["lifts"] == 0:
        # the TfL record of a rail station has no counts, but every Elizabeth line station is step-free from street to platform (Wikipedia, "Elizabeth line"): lifts, count unknown
        facility["lifts"] = 2
    tfl_ent, tfl_plat = [], []
    for c in tj.get("children", []):
        e, n = to_xy(lat0, lon0, c["lat"], c["lon"])
        if c.get("stopType") in ("NaptanMetroEntrance", "NaptanRailEntrance"):
            tfl_ent.append({"id": c["id"], "e": round(e, 1), "n": round(n, 1)})
        elif c.get("stopType") == "NaptanMetroPlatform":
            tfl_plat.append({"id": c["id"], "e": round(e, 1), "n": round(n, 1)})
    ent, plat, steps, tunnels, ways = [], [], {"count": 0, "levels": {}}, [], []
    for el in (oj or {}).get("elements", []):
        t = el.get("tags", {})
        if el["type"] == "node" and t.get("railway") in ("subway_entrance", "train_station_entrance"):
            e, n = to_xy(lat0, lon0, el["lat"], el["lon"])
            ent.append({"ref": t.get("ref", ""), "name": t.get("name", ""), "exit_only": t.get("entrance") == "exit", "e": round(e, 1), "n": round(n, 1)})
            continue
        geom = el.get("geometry", [])
        if not geom:
            continue
        pts = [to_xy(lat0, lon0, g["lat"], g["lon"]) for g in geom]
        cx = sum(p[0] for p in pts) / len(pts)
        cy = sum(p[1] for p in pts) / len(pts)
        # principal axis (longest extent) for length / bearing
        best = (0.0, 0.0, 0.0)
        for i in range(len(pts)):
            for j in range(i + 1, len(pts)):
                d = math.hypot(pts[i][0] - pts[j][0], pts[i][1] - pts[j][1])
                if d > best[0]:
                    best = (d, pts[j][0] - pts[i][0], pts[j][1] - pts[i][1])
        length = best[0]
        brg = bearing_deg(best[1], best[2]) % 180.0
        if t.get("railway") == "platform" or t.get("public_transport") == "platform":
            plat.append({"ref": t.get("ref", ""), "name": t.get("name", ""), "level": t.get("level", t.get("layer", "")), "line": t.get("line", ""),
                         "e": round(cx, 1), "n": round(cy, 1), "length": round(length, 1), "bearing": round(brg, 1)})
        elif t.get("highway") in ("footway", "corridor", "path") and not t.get("conveying"):
            lvl = t.get("level", t.get("layer", ""))
            ways.append({"k": "corridor", "level": lvl, "pts": [[round(p[0], 1), round(p[1], 1)] for p in _thin(pts)]})
        elif t.get("highway") == "steps" or t.get("conveying"):
            ways.append({"k": "escalator" if t.get("conveying") else "steps", "level": t.get("level", t.get("layer", "")), "pts": [[round(p[0], 1), round(p[1], 1)] for p in _thin(pts)],
                         "dir": t.get("conveying", "")})
            steps["count"] += 1
            lv = t.get("level", t.get("layer", ""))
            steps["levels"][lv] = steps["levels"].get(lv, 0) + 1
            if t.get("conveying"):
                steps["escalators"] = steps.get("escalators", 0) + 1
        elif t.get("railway") == "subway":
            tunnels.append({"line": t.get("line", t.get("name", "")), "layer": t.get("layer", ""), "e": round(cx, 1), "n": round(cy, 1),
                            "bearing": round(brg, 1)})
    return {"name": st["name"], "lat": lat0, "lon": lon0, "facility": facility, "tfl_entrances": tfl_ent, "tfl_platforms": tfl_plat,
            "entrances": ent, "platforms": plat, "steps": steps, "tunnels": tunnels[:40], "ways": ways[:220]}


def load_bulk():
    """all OSM elements from the tiles written by fetch_osm_bulk.py, with a centre point for quick radius tests"""
    import glob
    els, seen = [], set()
    for fn in sorted(glob.glob(os.path.join(ROOT, "build", "osm_bulk", "tile_*.json"))):
        for el in json.load(open(fn)).get("elements", []):
            key = (el["type"], el["id"])
            if key in seen:
                continue
            seen.add(key)
            if el["type"] == "node":
                el["_c"] = (el["lat"], el["lon"])
            else:
                g = el.get("geometry", [])
                if not g:
                    continue
                el["_c"] = (sum(p["lat"] for p in g) / len(g), sum(p["lon"] for p in g) / len(g))
            els.append(el)
    return els


def near(els, lat, lon, radius):
    my, mx = m_per_deg(lat)
    out = []
    for el in els:
        dy = (el["_c"][0] - lat) * my
        dx = (el["_c"][1] - lon) * mx
        if dx * dx + dy * dy <= radius * radius:
            out.append(el)
    return {"elements": out}


def main():
    only = None
    refresh = "--refresh" in sys.argv
    if "--only" in sys.argv:
        only = sys.argv[sys.argv.index("--only") + 1]
    os.makedirs(RAW, exist_ok=True)
    net = json.load(open(os.path.join(ROOT, "data", "network.json")))
    existing = json.load(open(OUT)) if os.path.exists(OUT) else {}
    missing = "--missing" in sys.argv
    todo = [(k, v) for k, v in net["stations"].items() if (only is None or v["name"] == only) and (not missing or k not in existing)]
    bulk = load_bulk() if not missing else []
    print("bulk OSM elements:", len(bulk))
    result = dict(existing) if (missing or only is not None) else {}
    for i, (naptan, st) in enumerate(todo):
        if naptan in result and not refresh and only is None:
            continue
        cache = os.path.join(RAW, naptan + ".tfl.json")
        if os.path.exists(cache) and not refresh:
            tj = json.load(open(cache))
        else:
            try:
                tj = tfl(naptan)
                json.dump(tj, open(cache, "w"))
            except Exception as e:
                print("TfL fail", naptan, e)
                tj = {"additionalProperties": [], "children": []}
            time.sleep(0.6)
        rad = 260 if len(st["lines"]) >= 3 else 190
        if missing:
            ocache = os.path.join(RAW, naptan + ".osm.json")
            if os.path.exists(ocache) and not refresh:
                oj = json.load(open(ocache))
            else:
                try:
                    oj = overpass(osm_query(st["lat"], st["lon"], 220))
                    json.dump(oj, open(ocache, "w"))
                except Exception as e:
                    print("OSM fail", naptan, e)
                    oj = {"elements": []}
                time.sleep(2.0)
        else:
            oj = near(bulk, st["lat"], st["lon"], rad)
        result[naptan] = digest(naptan, st, tj, oj)
        d = result[naptan]
        print("%3d/%d %-32s ent osm %d tfl %d | plat osm %d tfl %d | esc %s gates %s halls %s | steps %d" % (
            i + 1, len(todo), st["name"][:32], len(d["entrances"]), len(d["tfl_entrances"]), len(d["platforms"]), len(d["tfl_platforms"]),
            d["facility"]["escalators"], d["facility"]["gates"], d["facility"]["ticket_halls"], d["steps"]["count"]), flush=True)
        if (i + 1) % 10 == 0:
            json.dump(result, open(OUT, "w"), separators=(",", ":"))
    json.dump(result, open(OUT, "w"), separators=(",", ":"))
    print("wrote", OUT, len(result), "stations")


if __name__ == "__main__":
    main()
