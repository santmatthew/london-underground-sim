#!/usr/bin/env python3
"""Build data/network.json from build/tfl_raw.json (fetched by tools/fetch_tfl.py).

Output structure (all consumed by scripts/autoload/Net.gd):
  lines:    id -> {name, color, group ('ss' sub-surface / line id), services:[{id,name,stops:[station ids], plat_fwd:[..], plat_bwd:[..]}]}
  stations: id -> {name, lat, lon, x, y (km from Charing Cross), zone, lines:[..], kind, platforms:{pid:{group,dir,lines,terminal}}}
  links:    in-complex transfers between separate station nodes
A "platform id" is  "<group>:<Direction>"  e.g.  "central:Eastbound", "ss:Westbound".
"""
import json, math, os, re, collections, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
raw = json.load(open(os.path.join(ROOT, "build", "tfl_raw.json")))

LINE_META = {  # official TfL colours
    "bakerloo": ("Bakerloo", "#B36305"), "central": ("Central", "#E32017"), "circle": ("Circle", "#FFD300"),
    "district": ("District", "#00782A"), "hammersmith-city": ("Hammersmith & City", "#F3A9BB"),
    "jubilee": ("Jubilee", "#A0A5A9"), "metropolitan": ("Metropolitan", "#9B0056"), "northern": ("Northern", "#000000"),
    "piccadilly": ("Piccadilly", "#003688"), "victoria": ("Victoria", "#0098D4"), "waterloo-city": ("Waterloo & City", "#95CDBA"),
    "elizabeth": ("Elizabeth", "#6950A1"),
}
SUBSURFACE = {"circle", "district", "hammersmith-city", "metropolitan"}
LAT0, LON0 = 51.5074, -0.1278  # Charing Cross-ish


def clean_name(n):
    n = n.replace(" Underground Station", "").replace("-Underground", "").replace(" Rail Station", "")
    n = n.replace("(H&C Line)", "(H&C)").replace("(Dist&Picc Line)", "(D&P)").replace("(Circle Line)", "(Circle)")
    return n.strip()


def zone_int(z):
    """TfL zone ("2", "2/3", "3+4"); stations outside the fare zones (Reading, Slough, Shenfield ...) have none and count as zone 9"""
    if z is None:
        return 9
    m = re.match(r"\d+", z)
    return int(m.group(0)) if m else 9


def proj(lat, lon):
    return ((lon - LON0) * 111.32 * math.cos(math.radians(LAT0)), (lat - LAT0) * 110.57)


def bearing(a, b):
    """compass bearing degrees from station a -> b"""
    dx, dy = b["x"] - a["x"], b["y"] - a["y"]
    return (math.degrees(math.atan2(dx, dy)) + 360.0) % 360.0


LINE_AXIS = {"bakerloo": "NS", "northern": "NS", "victoria": "NS", "central": "EW", "waterloo-city": "EW", "district": "EW",
             "circle": "EW", "hammersmith-city": "EW", "jubilee": "mixed", "piccadilly": "mixed", "metropolitan": "mixed", "elizabeth": "EW"}


def label(b, axis="mixed"):
    b %= 360
    if axis == "NS": return "Northbound" if math.cos(math.radians(b)) >= 0 else "Southbound"
    if axis == "EW": return "Eastbound" if math.sin(math.radians(b)) >= 0 else "Westbound"
    if b >= 315 or b < 45: return "Northbound"
    if b < 135: return "Eastbound"
    if b < 225: return "Southbound"
    return "Westbound"


OPP = {"Northbound": "Southbound", "Southbound": "Northbound", "Eastbound": "Westbound", "Westbound": "Eastbound"}

# ---- stations -------------------------------------------------------------------------------
# The Elizabeth line's stops are rail-station ids (910G...). Where the line shares a station complex with the Underground, its platforms join the Underground station's node
# (one station, one plan, interchange inside it); the other stops become stations of their own.
from elizabeth_ids import EL_MERGE
# the stub Shenfield - Liverpool Street (main line) is not an Elizabeth line service
EL_SKIP_ROUTES = ("Shenfield &harr; London Liverpool Street",)
# how an Elizabeth-line-only station is built: Woolwich is a deep box under the Royal Arsenal, the rest are rail stations at ground level
KIND_OVERRIDE = {"910GWOLWXR": "sub"}
# where the platforms of a station really are (the rule above - deep tube lines are "deep", zone 1-2 sub-surface stations "sub", the rest "surface" - is wrong for a few dozen): data/station_kind_overrides.json,
# {NaPTAN: {"kind": "surface" | "sub" | "deep", "why": ...}}, found by comparing the stations with the track around them in OpenStreetMap (tools/audit_station_kinds.py) and checked against the platform depths and the literature
_kf = os.path.join(ROOT, "data", "station_kind_overrides.json")
KIND_FIX = {k: v["kind"] for k, v in json.load(open(_kf)).items() if not k.startswith("_")} if os.path.exists(_kf) else {}
stops = {}
for lid, dd in raw.items():
    for d, data in dd.items():
        for seq in data["stopPointSequences"]:
            for p in seq["stopPoint"]:
                if lid == "elizabeth" and p["id"] in EL_MERGE:
                    continue
                stops[p["id"]] = p
stations = {}
for sid, p in stops.items():
    x, y = proj(p["lat"], p["lon"])
    stations[sid] = {"name": clean_name(p["name"]), "lat": p["lat"], "lon": p["lon"], "x": round(x, 3), "y": round(y, 3),
                     "zone": zone_int(p.get("zone")), "lines": [], "platforms": {}, "hub": p.get("topMostParentId") or sid}

# ---- services ---------------------------------------------------------------------------------
# Which ordered routes to keep and their relative weights per line (see scripts/autoload/Timetable.gd for tph by time band)
lines = {}
for lid, dd in raw.items():
    name, color = LINE_META[lid]
    group = "ss" if lid in SUBSURFACE else lid
    seen = set()
    services = []
    for r in dd["outbound"]["orderedLineRoutes"]:
        if lid == "elizabeth" and re.sub(r"\s+", " ", r["name"]).strip() == re.sub(r"\s+", " ", EL_SKIP_ROUTES[0]):
            continue
        ids = [EL_MERGE.get(i, i) for i in r["naptanIds"]] if lid == "elizabeth" else r["naptanIds"]
        key = tuple(ids)
        if key in seen: continue
        seen.add(key)
        rname = re.sub(r"\s+", " ", r["name"].replace("&harr;", "–")).strip()
        services.append({"id": f"{lid}-{len(services)}", "name": rname, "stops": ids})
    if lid == "elizabeth":
        # The two patterns that carry most of the core's trains: Abbey Wood - Paddington and Shenfield - Paddington (the API lists only the through routes to Reading / Heathrow)
        pad = EL_MERGE["910GPADTLL"]
        by_end = {r["name"]: r for r in services}
        for src_name, end_name in (("Abbey Wood – Reading", "Abbey Wood – Paddington"), ("Shenfield – Heathrow Terminal 4", "Shenfield – Paddington")):
            src = next((r for r in services if r["name"] == src_name), None)
            if src is not None and pad in src["stops"]:
                services.append({"id": f"{lid}-{len(services)}", "name": end_name, "stops": src["stops"][:src["stops"].index(pad) + 1]})
    lines[lid] = {"name": name, "color": color, "group": group, "services": services}

# ---- platforms ----------------------------------------------------------------------------------
for lid, ln in lines.items():
    for svc in ln["services"]:
        ids = svc["stops"]
        n = len(ids)
        plat_fwd, plat_bwd = [], []
        axis = LINE_AXIS[lid]
        for i, sid in enumerate(ids):
            cur = stations[sid]
            if lid not in cur["lines"]: cur["lines"].append(lid)
            # heading of the train leaving towards ids[i+1] (or, at the last stop, the heading it arrived with)
            hf = bearing(cur, stations[ids[i + 1]]) if i + 1 < n else bearing(stations[ids[i - 1]], cur)
            # heading towards ids[i-1] (or, at stop 0, the heading a backward train arrives with)
            hb = bearing(cur, stations[ids[i - 1]]) if i > 0 else bearing(stations[ids[i + 1]], cur)
            lf, lb = label(hf, axis), label(hb, axis)
            if i == 0: lf = lb       # a train departing a terminus uses the platform trains arrive at
            if i == n - 1: lb = lf
            group = ln["group"]
            pf, pb = f"{group}:{lf}", f"{group}:{lb}"
            plat_fwd.append(pf)
            plat_bwd.append(pb)
            for pid, terminal in ((pf, i == n - 1 or i == 0), (pb, i == 0 or i == n - 1)):
                pl = cur["platforms"].setdefault(pid, {"group": group, "dir": pid.split(":")[1], "lines": [], "terminal": False})
                if lid not in pl["lines"]: pl["lines"].append(lid)
                if terminal: pl["terminal"] = True
        svc["plat_fwd"], svc["plat_bwd"] = plat_fwd, plat_bwd

# stops that appear in a line's stop sequences but that none of its services calls at (the Elizabeth line's API lists the main-line Liverpool Street) are not stations of this network
stations = {sid: s for sid, s in stations.items() if s["lines"]}

# ---- classification -----------------------------------------------------------------------------
for sid, s in stations.items():
    ls = set(s["lines"])
    deep_lines = ls - SUBSURFACE
    if deep_lines:
        deep = s["zone"] <= 2 or (ls & {"victoria", "jubilee", "northern"} and s["zone"] <= 3)
        s["kind"] = "deep" if deep else "surface"
    else:
        s["kind"] = "sub" if s["zone"] <= 2 else "surface"
    if sid in KIND_OVERRIDE:
        s["kind"] = KIND_OVERRIDE[sid]
    if sid in KIND_FIX:
        s["kind"] = KIND_FIX[sid]
    s["platforms"] = dict(sorted(s["platforms"].items()))

# in-complex links between separate station nodes (seconds of walking, incl. interchange overhead)
name2id = {}
for sid, s in stations.items(): name2id.setdefault(s["name"], sid)
links = []
for a, b, secs in (("Bank", "Monument", 240), ("Paddington", "Paddington (H&C)", 300)):
    if a in name2id and b in name2id:
        links.append({"a": name2id[a], "b": name2id[b], "walk_s": secs})

import junctions
junctions.apply(lines, stations)       # branch junctions (Camden Town, Euston, Kennington): one platform per direction and branch

out = {"lines": lines, "stations": stations, "links": links}
os.makedirs(os.path.join(ROOT, "data"), exist_ok=True)
json.dump(out, open(os.path.join(ROOT, "data", "network.json"), "w"), separators=(",", ":"))
print(f"{len(stations)} stations, {sum(len(l['services']) for l in lines.values())} services, "
      f"{sum(len(s['platforms']) for s in stations.values())} platform records, kinds:",
      dict(collections.Counter(s['kind'] for s in stations.values())))
# quick sanity print
for nm in ("Oxford Circus", "Bank", "King's Cross St. Pancras", "Baker Street", "Epping", "Morden"):
    sid = name2id.get(nm)
    if sid:
        s = stations[sid]
        print(nm, s["zone"], s["kind"], list(s["platforms"].keys()))
