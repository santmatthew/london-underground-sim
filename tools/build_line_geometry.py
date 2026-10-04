#!/usr/bin/env python3
"""Step 2 of the curved-track pipeline: turn the OpenStreetMap route relations fetched by tools/fetch_line_geometry.py into data/line_geometry.json.

For every pair of consecutive stops of a relation (one direction of one line) the track between the two stop positions is extracted (shortest path over the relation's own
track ways), smoothed and reduced to its HEADING along the way (degrees x10 every STEP metres, relative to the heading at the first stop) and its real length.
For every stop the heading change across the platform (PLAT_SPAN metres centred on the stop) is stored too: that is what makes a platform curved (Bank, Liverpool Street ...).

  data/line_geometry.json = {
    "step": 20,
    "pairs": {"<from NaPTAN>><to NaPTAN>": {"len": metres, "h": [heading x10 at 0, STEP, 2 STEP ... , len], "sec": [[kind, metres], ...], "dz": metres}},   # dz: how far the next station's platform lies above this one's (data/platform_levels.json); sec: what the track runs through, in order (tools/fetch_line_sections.py)
    "platforms": {"<NaPTAN>": {"<next NaPTAN>": {"dh": degrees over PLAT_SPAN (+ = turns left in the direction of travel), "line": "central"}}}
  }
Only derived numbers are stored (OpenStreetMap contributors, ODbL; see CREDITS.md).
"""
import glob, heapq, json, math, os, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
GEOM = os.path.join(ROOT, "build", "geom")
OUT = os.path.join(ROOT, "data", "line_geometry.json")
LAT0 = 51.5074
STEP = 20.0
PLAT_SPAN = 110.0
SMOOTH = 30.0           # heading is measured over a window this long: OSM ways are digitised by hand, nodes every few metres are noise
LINE_OF_REF = {"Bakerloo": "bakerloo", "Central": "central", "Circle": "circle", "District": "district", "Hammersmith & City": "hammersmith-city",
               "Jubilee": "jubilee", "Metropolitan": "metropolitan", "Northern": "northern", "Piccadilly": "piccadilly", "Victoria": "victoria",
               "Waterloo & City": "waterloo-city", "Elizabeth": "elizabeth"}


def xy(lat, lon):
    return ((lon + 0.1278) * 111320.0 * math.cos(math.radians(LAT0)), (lat - LAT0) * 110574.0)


def key(p):
    return (round(p[0], 2), round(p[1], 2))


class Graph:
    def __init__(self):
        self.pts = {}           # key -> (x, y)
        self.adj = {}           # key -> [(key, length)]

    def add_way(self, poly):
        for a, b in zip(poly, poly[1:]):
            ka, kb = key(a), key(b)
            if ka == kb:
                continue
            self.pts[ka] = a
            self.pts[kb] = b
            d = math.dist(a, b)
            self.adj.setdefault(ka, []).append((kb, d))
            self.adj.setdefault(kb, []).append((ka, d))

    def snap(self, p, tol=40.0):
        """nearest vertex (or the nearest point of an edge, made into a vertex) within tol"""
        best = None
        for k, q in self.pts.items():
            d = math.dist(p, q)
            if best is None or d < best[0]:
                best = (d, k)
        return best[1] if best and best[0] <= tol else None

    def path(self, ka, kb):
        dist = {ka: 0.0}
        prev = {}
        pq = [(0.0, ka)]
        while pq:
            d, k = heapq.heappop(pq)
            if k == kb:
                break
            if d > dist.get(k, 1e18):
                continue
            for nk, w in self.adj.get(k, []):
                nd = d + w
                if nd < dist.get(nk, 1e18):
                    dist[nk] = nd
                    prev[nk] = k
                    heapq.heappush(pq, (nd, nk))
        if kb not in dist:
            return None
        out = [kb]
        while out[-1] != ka:
            out.append(prev[out[-1]])
        return [self.pts[k] for k in reversed(out)]


def cum(poly):
    s = [0.0]
    for a, b in zip(poly, poly[1:]):
        s.append(s[-1] + math.dist(a, b))
    return s


def at(poly, cs, s):
    s = max(0.0, min(s, cs[-1]))
    lo, hi = 0, len(cs) - 1
    while hi - lo > 1:
        m = (lo + hi) // 2
        if cs[m] <= s:
            lo = m
        else:
            hi = m
    t = (s - cs[lo]) / max(cs[hi] - cs[lo], 1e-9)
    return (poly[lo][0] + (poly[hi][0] - poly[lo][0]) * t, poly[lo][1] + (poly[hi][1] - poly[lo][1]) * t)


def heading_profile(poly, step=STEP):
    """heading (radians, unwrapped) at s = 0, step ... length, each measured over a SMOOTH-long window centred there (one-sided at the ends)"""
    cs = cum(poly)
    L = cs[-1]
    n = int(math.floor(L / step))
    ss = [i * step for i in range(n + 1)]
    if L - ss[-1] > 1.0:
        ss.append(L)
    out = []
    for s in ss:
        a = max(0.0, s - SMOOTH * 0.5)
        b = min(L, s + SMOOTH * 0.5)
        if b - a < SMOOTH * 0.5:
            a, b = max(0.0, b - SMOOTH * 0.5), min(L, a + SMOOTH * 0.5)
        pa, pb = at(poly, cs, a), at(poly, cs, b)
        out.append(math.atan2(pb[1] - pa[1], pb[0] - pa[0]))
    for i in range(1, len(out)):
        while out[i] - out[i - 1] > math.pi:
            out[i] -= 2 * math.pi
        while out[i] - out[i - 1] < -math.pi:
            out[i] += 2 * math.pi
    return ss, out


def sub(poly, s0, s1):
    cs = cum(poly)
    s0, s1 = max(0.0, s0), min(cs[-1], s1)
    pts = [at(poly, cs, s0)]
    for p, c in zip(poly, cs):
        if s0 < c < s1:
            pts.append(p)
    pts.append(at(poly, cs, s1))
    return pts


def nearest_on(poly, p):
    best = (1e18, None)
    for a, b in zip(poly, poly[1:]):
        ab = (b[0] - a[0], b[1] - a[1])
        l2 = ab[0] ** 2 + ab[1] ** 2
        t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * ab[0] + (p[1] - a[1]) * ab[1]) / l2))
        q = (a[0] + ab[0] * t, a[1] + ab[1] * t)
        d = math.dist(p, q)
        if d < best[0]:
            best = (d, q)
    return best


SECTION_CODES = {"open": 0, "tunnel": 1, "cutting": 2, "embankment": 3, "viaduct": 4}
SEC_STEP = 8.0
SEC_NEAR = 4.0          # a way within this many metres of the track is the track


class SegIndex:
    """a spatial grid over the segments of a set of ways"""
    CELL = 40.0

    def __init__(self):
        self.g = {}

    def add_way(self, poly):
        for a, b in zip(poly, poly[1:]):
            x0, x1 = sorted((a[0], b[0]))
            y0, y1 = sorted((a[1], b[1]))
            for ix in range(int(x0 // self.CELL), int(x1 // self.CELL) + 1):
                for iy in range(int(y0 // self.CELL), int(y1 // self.CELL) + 1):
                    self.g.setdefault((ix, iy), []).append((a, b))

    def near(self, p, d):
        ix, iy = int(p[0] // self.CELL), int(p[1] // self.CELL)
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for a, b in self.g.get((ix + dx, iy + dy), ()):
                    ab = (b[0] - a[0], b[1] - a[1])
                    l2 = ab[0] ** 2 + ab[1] ** 2
                    t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * ab[0] + (p[1] - a[1]) * ab[1]) / l2))
                    if math.dist(p, (a[0] + ab[0] * t, a[1] + ab[1] * t)) <= d:
                        return True
        return False


def load_sections():
    """{kind: SegIndex} of the tunnel / cutting / embankment / bridge ways (tools/fetch_line_sections.py), empty when not fetched"""
    out = {}
    for kind in ("tunnel", "cutting", "embankment", "bridge"):
        fp = os.path.join(GEOM, "ways_%s.json" % kind)
        if not os.path.exists(fp):
            continue
        ix = SegIndex()
        for e in json.load(open(fp)):
            pts = [xy(p["lat"], p["lon"]) for p in e.get("geometry", []) if p]
            if len(pts) >= 2:
                ix.add_way(pts)
        out[kind] = ix
    return out


def classify_path(poly, secs):
    """[[code, metres], ...] along the track `poly`: tunnel, else cutting, else embankment, else viaduct (a bridge of 60 m or more), else open; stretches under 40 m are absorbed by their neighbours"""
    cs = cum(poly)
    L = cs[-1]
    n = max(1, int(round(L / SEC_STEP)))
    raw = []
    for i in range(n):
        p = at(poly, cs, (i + 0.5) * L / n)
        kind = "open"
        for k in ("tunnel", "cutting", "embankment", "bridge"):
            if k in secs and secs[k].near(p, SEC_NEAR):
                kind = k
                break
        raw.append(kind)
    # bridges are viaducts only when long
    runs = []
    for k in raw:
        if runs and runs[-1][0] == k:
            runs[-1][1] += 1
        else:
            runs.append([k, 1])
    for r in runs:
        if r[0] == "bridge":
            r[0] = "viaduct" if r[1] * L / n >= 60.0 else "open"
    # merge short runs into the previous (or next) run
    def merged(rs):
        out = []
        for r in rs:
            if out and out[-1][0] == r[0]:
                out[-1][1] += r[1]
            else:
                out.append(list(r))
        return out
    runs = merged(runs)
    changed = True
    while changed and len(runs) > 1:
        changed = False
        for i, r in enumerate(runs):
            if r[1] * L / n < 40.0:
                j = i - 1 if i > 0 else i + 1
                runs[j][1] += r[1]
                del runs[i]
                changed = True
                break
        runs = merged(runs)
    return [[SECTION_CODES[r[0]], round(r[1] * L / n, 1)] for r in runs]


def supplement_elizabeth(net, sxy, pairs, secs):
    """The Elizabeth line's relation has no track ways in the core tunnels (and none at Heathrow): the hops it lacks are found over the line's own ways (tools/fetch_line_sections.py, kind
    "elizabeth", tagged line=Elizabeth), the shortest way between the track nearest each station"""
    fp = os.path.join(GEOM, "ways_elizabeth.json")
    if not os.path.exists(fp):
        return 0
    g = Graph()
    for e in json.load(open(fp)):
        poly = [xy(p["lat"], p["lon"]) for p in e.get("geometry", []) if p]
        if len(poly) >= 2:
            g.add_way(poly)
    added = 0
    hops = set()
    for svc in net["lines"]["elizabeth"]["services"]:
        for a, b in zip(svc["stops"], svc["stops"][1:]):
            hops.add((a, b))
    for a, b in sorted(hops):
        if a + ">" + b in pairs or b + ">" + a in pairs or a not in sxy or b not in sxy:
            continue
        ka, kb = g.snap(sxy[a], 300.0) or g.snap(sxy[a], 800.0), g.snap(sxy[b], 300.0) or g.snap(sxy[b], 800.0)          # (some stations are marked at their entrance, far from the platforms)
        if ka is None or kb is None:
            print("  elizabeth: no track near", net["stations"][a]["name"] if ka is None else net["stations"][b]["name"])
            continue
        pa = g.path(ka, kb)
        straight = math.dist(g.pts[ka], g.pts[kb])
        if pa is None or len(pa) < 2:
            print("  elizabeth: no path", net["stations"][a]["name"], "->", net["stations"][b]["name"])
            continue
        length = cum(pa)[-1]
        if length > straight * 1.8 + 200.0:
            print("  elizabeth: path too long", net["stations"][a]["name"], "->", net["stations"][b]["name"], round(length), "m for", round(straight), "m")
            continue
        ss, hh = heading_profile(pa)
        k = a + ">" + b
        pairs[k] = {"len": round(ss[-1], 1), "h": [int(round(math.degrees(h - hh[0]) * 10.0)) for h in hh], "line": "elizabeth"}
        if secs:
            pairs[k]["sec"] = classify_path(pa, secs)
        added += 1
        print("  elizabeth: %s -> %s %.0f m" % (net["stations"][a]["name"], net["stations"][b]["name"], length))
    return added


SS_LINES = ("district", "metropolitan", "hammersmith-city", "circle")


def _dir_index(pid):
    d = pid.split(":")[-1].lower() if pid else ""
    if d.startswith(("north", "east")):
        return 0
    if d.startswith(("south", "west")):
        return 1
    return None


def _level(levels, net, sid, line, pid):
    """platform level (m above Ordnance Datum) of `line`'s platform `pid` at station `sid`, None without data"""
    ent = levels.get(sid)
    if not ent:
        return None
    lines = ent["lines"]
    key = line
    if pid and "~cx" in pid and (line + "_cx") in lines:
        key = line + "_cx"          # (Euston has a record for each branch of the Northern line: the platform id says which)
    pair = lines.get(key)
    if pair is None and line in SS_LINES:
        got = [v for k, v in lines.items() if k in SS_LINES]
        if got:
            pair = [sum(v[0] for v in got) / len(got), sum(v[1] for v in got) / len(got)]
    if pair is None:
        return None
    i = _dir_index(pid)
    return pair[i] if i is not None else (pair[0] + pair[1]) / 2.0


def add_levels(net, pairs):
    """"dz": how far the platform of the next station is above (+) the platform here, from the platform levels of data/platform_levels.json (tools/build_platform_levels.py); a hop that several lines
    use can differ between them (their platforms are at different heights): "dzl" then has it per line"""
    fp = os.path.join(ROOT, "data", "platform_levels.json")
    if not os.path.exists(fp):
        return 0
    levels = json.load(open(fp))
    n = 0
    odd = []
    for k, e in pairs.items():
        a, b = k.split(">")
        per = {}
        for line, ldata in net["lines"].items():
            pa = pb = None
            for svc in ldata["services"]:
                st = svc["stops"]
                for i in range(len(st) - 1):
                    if st[i] == a and st[i + 1] == b:
                        pa, pb = svc["plat_fwd"][i], svc["plat_fwd"][i + 1]
                    elif st[i] == b and st[i + 1] == a:
                        pa, pb = svc["plat_bwd"][i + 1], svc["plat_bwd"][i]
                    if pa:
                        break
                if pa:
                    break
            if not pa:
                continue
            la = _level(levels, net, a, line, pa)
            lb = _level(levels, net, b, line, pb)
            if la is not None and lb is not None:
                per[line] = round(lb - la, 1)
        if not per:
            continue
        e["dz"] = per.get(e.get("line"), next(iter(per.values())))
        if len(set(per.values())) > 1:
            e["dzl"] = per
        n += 1
        for line, dz in per.items():
            if abs(dz) > 0.05 * e["len"] and abs(dz) > 4.0:
                odd.append("%s -> %s (%s): %+.1f m over %.0f m" % (net["stations"][a]["name"], net["stations"][b]["name"], line, dz, e["len"]))
    for o in odd:
        print("  steep:", o)
    return n


def load_platforms():
    """every platform outline in Greater London (tools/fetch_line_geometry.py): [(bounding box, polyline)]"""
    fp = os.path.join(GEOM, "platforms_london.json")
    out = []
    if not os.path.exists(fp):
        return out
    for e in json.load(open(fp)).get("elements", []):
        pts = [xy(p["lat"], p["lon"]) for p in e.get("geometry", []) if p]
        if len(pts) >= 2:
            xs, ys = [q[0] for q in pts], [q[1] for q in pts]
            out.append(((min(xs), min(ys), max(xs), max(ys)), pts))
    return out


def door_side(stop, path, plat_ways, reach=4.0):
    """on which side of the track (looking the way the train goes) the platform at `stop` lies: 'L' or 'R' (the nearest platform outline, within `reach` metres of the stop on the track), 'B' when
    there is one almost as near on the other side too, '' when no outline is that close. (The opposite track's platform is 5 m or more away; a platform edge is 1.5-2.5 m from the track.)"""
    if path is None or len(path) < 2:
        return ""
    cs = cum(path)
    a, b = at(path, cs, 0.0), at(path, cs, min(15.0, cs[-1]))
    d = (b[0] - a[0], b[1] - a[1])
    if d == (0.0, 0.0):
        return ""
    near = {"L": None, "R": None}
    for pw in plat_ways:
        if isinstance(pw, tuple):                      # (bounding box, polyline) from load_platforms: skip what is clearly too far
            bb, pw = pw
            if stop[0] < bb[0] - 15 or stop[0] > bb[2] + 15 or stop[1] < bb[1] - 15 or stop[1] > bb[3] + 15:
                continue
        dist, q = nearest_on(pw, stop)
        if q is None or dist > 15.0 or dist < 0.8:
            continue
        cross = d[0] * (q[1] - stop[1]) - d[1] * (q[0] - stop[0])
        k = "L" if cross > 0 else "R"
        if near[k] is None or dist < near[k]:
            near[k] = dist
    dl, dr = near["L"], near["R"]
    best = min([x for x in (dl, dr) if x is not None], default=None)
    if best is None or best > reach:
        return ""
    if dl is not None and dr is not None and abs(dl - dr) < 1.5:
        return "B"
    return "L" if (dl is not None and dl == best) else "R"


def main():
    net = json.load(open(os.path.join(ROOT, "data", "network.json")))
    stations = net["stations"]
    lines_of = {sid: set(s["lines"]) if not isinstance(s["lines"], dict) else set(s["lines"].keys()) for sid, s in stations.items()}
    sxy = {sid: xy(s["lat"], s["lon"]) for sid, s in stations.items()}
    files = sorted(glob.glob(os.path.join(GEOM, "rel", "*.json")))
    pairs, plats = {}, {}
    all_platforms = load_platforms()
    secs = load_sections()
    stats = {"rel": 0, "pairs": 0, "nopath": 0, "nostation": 0}
    for fp in files:
        rel = json.load(open(fp))
        if not rel or "members" not in rel:
            continue
        tags = rel.get("tags", {})
        name = tags.get("name", "")
        line = LINE_OF_REF.get(tags.get("ref", ""), None) or ("elizabeth" if name.startswith("Elizabeth") else None)
        if not line or "sidings" in name:
            continue
        g = Graph()
        stops = []
        plat_ways = []            # the platform outlines of the relation (to see on which side of the track each platform lies)
        for m in rel["members"]:
            if m["type"] == "way" and m.get("role", "").startswith("platform") and m.get("geometry"):
                pw = [xy(p["lat"], p["lon"]) for p in m["geometry"] if p]
                if len(pw) >= 2:
                    plat_ways.append(pw)
                continue
            if m["type"] == "way" and m.get("role", "") in ("", "forward", "backward") and m.get("geometry"):
                # (a relation fetched with a bounding box has no coordinates for what lies outside it: the way is cut there)
                piece = []
                for p in m["geometry"] + [None]:
                    if p is None:
                        if len(piece) > 1:
                            g.add_way(piece)
                        piece = []
                    else:
                        piece.append(xy(p["lat"], p["lon"]))
            elif m["type"] == "node" and m.get("role", "").startswith("stop"):
                stops.append(xy(m["lat"], m["lon"]) if "lat" in m else None)
        if not g.pts or len(stops) < 2:
            continue
        stats["rel"] += 1
        # which station is each stop: the nearest one that this line serves
        seq = []
        for p in stops:
            if p is None:                          # (outside the bounding box)
                seq.append(None)
                continue
            best = None
            for sid, q in sxy.items():
                if line not in lines_of[sid]:
                    continue
                d = math.dist(p, q)
                if best is None or d < best[0]:
                    best = (d, sid)
            if best is None or best[0] > 220.0:
                stats["nostation"] += 1
                seq.append(None)
            else:
                seq.append(best[1])
        verts = [g.snap(p) if p is not None else None for p in stops]
        paths = []
        for i in range(len(stops) - 1):
            a, b = seq[i], seq[i + 1]
            if a is None or b is None or a == b or verts[i] is None or verts[i + 1] is None:
                paths.append(None)
                continue
            pa = g.path(verts[i], verts[i + 1])
            if pa is None or len(pa) < 2:
                stats["nopath"] += 1
                paths.append(None)
                continue
            paths.append(pa)
            k = a + ">" + b
            if k in pairs:
                continue
            ss, hh = heading_profile(pa)
            pairs[k] = {"len": round(ss[-1], 1), "h": [int(round(math.degrees(h - hh[0]) * 10.0)) for h in hh], "line": line}
            if secs:
                pairs[k]["sec"] = classify_path(pa, secs)
            stats["pairs"] += 1
        # the platform of stop i: the track PLAT_SPAN metres around it, from the end of the path that arrives and the start of the one that leaves
        for i in range(len(stops)):
            sid = seq[i]
            if sid is None:
                continue
            nxt = seq[i + 1] if i + 1 < len(seq) else None
            if nxt is None or paths[i] is None:
                continue
            side = door_side(stops[i], paths[i], plat_ways + all_platforms)
            if side:
                plats.setdefault(sid, {}).setdefault(nxt, {"line": line})["side"] = side
            half = PLAT_SPAN * 0.5
            ahead = sub(paths[i], 0.0, half)
            behind = None
            if i > 0 and paths[i - 1] is not None:
                cs = cum(paths[i - 1])
                behind = sub(paths[i - 1], cs[-1] - half, cs[-1])
            poly = (behind[:-1] if behind else []) + ahead
            if len(poly) < 2 or cum(poly)[-1] < PLAT_SPAN * 0.8:
                continue
            c2 = cum(poly)
            ha = math.atan2(*(lambda p, q: (q[1] - p[1], q[0] - p[0]))(at(poly, c2, 0.0), at(poly, c2, SMOOTH)))
            hb = math.atan2(*(lambda p, q: (q[1] - p[1], q[0] - p[0]))(at(poly, c2, c2[-1] - SMOOTH), at(poly, c2, c2[-1])))
            dh = (hb - ha + math.pi) % (2 * math.pi) - math.pi
            ent = plats.setdefault(sid, {}).setdefault(nxt, {"line": line})
            ent["dh"] = round(math.degrees(dh), 1)
    stats["el_added"] = supplement_elizabeth(net, sxy, pairs, secs)
    stats["dz"] = add_levels(net, pairs)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump({"step": STEP, "span": PLAT_SPAN, "pairs": pairs, "platforms": plats}, open(OUT, "w"), separators=(",", ":"))
    print(stats, "pairs:", len(pairs), "platform entries:", sum(len(v) for v in plats.values()), "bytes:", os.path.getsize(OUT))


if __name__ == "__main__":
    main()
