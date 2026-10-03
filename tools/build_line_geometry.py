#!/usr/bin/env python3
"""Step 2 of the curved-track pipeline: turn the OpenStreetMap route relations fetched by tools/fetch_line_geometry.py into data/line_geometry.json.

For every pair of consecutive stops of a relation (one direction of one line) the track between the two stop positions is extracted (shortest path over the relation's own
track ways), smoothed and reduced to its HEADING along the way (degrees x10 every STEP metres, relative to the heading at the first stop) and its real length.
For every stop the heading change across the platform (PLAT_SPAN metres centred on the stop) is stored too: that is what makes a platform curved (Bank, Liverpool Street ...).

  data/line_geometry.json = {
    "step": 20,
    "pairs": {"<from NaPTAN>><to NaPTAN>": {"len": metres, "h": [heading x10 at 0, STEP, 2 STEP ... , len]}},
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


def main():
    net = json.load(open(os.path.join(ROOT, "data", "network.json")))
    stations = net["stations"]
    lines_of = {sid: set(s["lines"]) if not isinstance(s["lines"], dict) else set(s["lines"].keys()) for sid, s in stations.items()}
    sxy = {sid: xy(s["lat"], s["lon"]) for sid, s in stations.items()}
    files = sorted(glob.glob(os.path.join(GEOM, "rel", "*.json")))
    pairs, plats = {}, {}
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
        for m in rel["members"]:
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
            stats["pairs"] += 1
        # the platform of stop i: the track PLAT_SPAN metres around it, from the end of the path that arrives and the start of the one that leaves
        for i in range(len(stops)):
            sid = seq[i]
            if sid is None:
                continue
            nxt = seq[i + 1] if i + 1 < len(seq) else None
            if nxt is None or paths[i] is None:
                continue
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
            plats.setdefault(sid, {})[nxt] = {"dh": round(math.degrees(dh), 1), "line": line}
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump({"step": STEP, "span": PLAT_SPAN, "pairs": pairs, "platforms": plats}, open(OUT, "w"), separators=(",", ":"))
    print(stats, "pairs:", len(pairs), "platform entries:", sum(len(v) for v in plats.values()), "bytes:", os.path.getsize(OUT))


if __name__ == "__main__":
    main()
