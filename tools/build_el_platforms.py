#!/usr/bin/env python3
"""How the Elizabeth line's outer (surface) stations are laid out, from OpenStreetMap's platform outlines and footways (build/geom/el_stations.json, fetched by tools/fetch_el_stations.py) and
TfL's platform numbers (data/platform_numbers.json). Writes data/el_platforms.json, derived numbers only (OpenStreetMap contributors, ODbL; see CREDITS.md):

  "<NaPTAN>": {"arrangement": "side" | "island",          the two Elizabeth line platform outlines are apart (side platforms, the two tracks between them) or touching (one island platform)
               "gap": metres between the platform edges (side platforms: 5.5 - 7.5, about 3.5 of it track spacing),
               "length": {"<pid>": metres of the platform outline along the track},
               "axis": [east, north]      unit vector along the platforms (its sign is arbitrary: the offsets below use the same one; the game turns it toward the neighbour a module's trains head for),
               "across": {"<pid>": metres},    where each platform's middle lies, perpendicular to `axis` (to the left of it, looking along `axis`, positive)
               "bridges": [metres from the middle of the platforms along `axis`, ...]     footbridges (a bridge footway / steps that spans both platforms)
               "stairs": [[metres along `axis`, metres across], ...]   steps ways that touch a platform outline }
  python3 tools/build_el_platforms.py
"""
import json, math, os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
GEOM = os.path.join(ROOT, "build", "geom", "el_stations.json")
OUT = os.path.join(ROOT, "data", "el_platforms.json")


def xy(p, lat0, lon0):
    return ((p["lon"] - lon0) * 111320.0 * math.cos(math.radians(lat0)), (p["lat"] - lat0) * 110574.0)


def seg_dist(p, a, b):
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    L2 = dx * dx + dy * dy
    t = 0.0 if L2 == 0 else max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - ay) * dy) / L2))
    return math.hypot(p[0] - (ax + t * dx), p[1] - (ay + t * dy))


def poly_dist(A, B):
    best = 1e9
    for p in A:
        for i in range(len(B) - 1):
            best = min(best, seg_dist(p, B[i], B[i + 1]))
    for p in B:
        for i in range(len(A) - 1):
            best = min(best, seg_dist(p, A[i], A[i + 1]))
    return best


def pca_axis(pts):
    n = len(pts)
    mx = sum(p[0] for p in pts) / n
    my = sum(p[1] for p in pts) / n
    sxx = sum((p[0] - mx) ** 2 for p in pts)
    syy = sum((p[1] - my) ** 2 for p in pts)
    sxy = sum((p[0] - mx) * (p[1] - my) for p in pts)
    th = 0.5 * math.atan2(2 * sxy, sxx - syy)
    return (math.cos(th), math.sin(th)), (mx, my)


def main():
    geo = json.load(open(GEOM))
    pn = json.load(open(os.path.join(ROOT, "data", "platform_numbers.json")))
    net = json.load(open(os.path.join(ROOT, "data", "network.json")))["stations"]
    lg = json.load(open(os.path.join(ROOT, "data", "line_geometry.json")))
    out = {"_comment": "Layout of the Elizabeth line's surface stations from OpenStreetMap platform outlines and footways (tools/build_el_platforms.py). Derived numbers only; (c) OpenStreetMap contributors, ODbL."}
    for sid, st in sorted(geo.items(), key=lambda kv: kv[1]["name"]):
        if not sid.startswith("910G") or sid not in pn or net.get(sid, {}).get("kind") != "surface":
            continue
        lat0, lon0 = st["lat"], st["lon"]
        nums = pn[sid]
        want = {}
        for key, refs in nums.items():
            pid = key.replace("|", ":")
            for r in refs:
                want.setdefault(str(r), set()).add(pid)
        polys = {}
        for w in st["ways"]:
            t = w.get("tags", {})
            if t.get("railway") == "platform" or t.get("public_transport") == "platform":
                ref = str(t.get("ref") or t.get("name") or "")
                if ref in want:
                    polys[ref] = [xy(p, lat0, lon0) for p in w["geometry"]]
        pids = {}
        for ref, ps in want.items():
            for pid in ps:
                pids.setdefault(pid, []).append(ref)
        if len(polys) < 2 or "elizabeth:Eastbound" not in pids and "elizabeth:Westbound" not in pids:
            print("skip", st["name"], "platform outlines:", sorted(polys))
            continue
        refs = sorted(polys)
        # the two outlines of the line (a pid with two numbers is an island platform's one outline per face)
        A = polys[refs[0]]
        B = polys[refs[-1]]
        gap = poly_dist(A, B)
        arrangement = "island" if gap < 2.0 else "side"
        axis, centre = pca_axis(A + B)
        length = {}
        across_of = {}
        perp = (-axis[1], axis[0])
        for ref, poly in polys.items():
            ps = [(p[0] - centre[0]) * axis[0] + (p[1] - centre[1]) * axis[1] for p in poly]
            cs = [(p[0] - centre[0]) * perp[0] + (p[1] - centre[1]) * perp[1] for p in poly]
            for pid in want[ref]:
                length[pid] = round(max(ps) - min(ps))
                across_of[pid] = round(sum(cs) / len(cs), 1)
        # footbridges and steps
        bridges, stairs = [], []
        for w in st["ways"]:
            t = w.get("tags", {})
            hw = t.get("highway")
            g = [xy(p, lat0, lon0) for p in w.get("geometry", [])]
            if not g:
                continue
            dA = min(poly_dist([p], A) for p in g)
            dB = min(poly_dist([p], B) for p in g)
            along = [(p[0] - centre[0]) * axis[0] + (p[1] - centre[1]) * axis[1] for p in g]
            across = [(p[0] - centre[0]) * perp[0] + (p[1] - centre[1]) * perp[1] for p in g]
            if t.get("bridge") == "yes" and hw in ("footway", "steps", "pedestrian") and dA < 25 and dB < 25 and (max(across) - min(across)) >= gap + 4.0:
                bridges.append(round(sum(along) / len(along)))
            elif hw == "steps" and min(dA, dB) < 6.0:
                stairs.append([round(sum(along) / len(along)), round(sum(across) / len(across), 1)])
        out[sid] = {"name": st["name"], "arrangement": arrangement, "gap": round(gap, 1), "length": length, "axis": [round(axis[0], 4), round(axis[1], 4)], "across": across_of,
                    "bridges": sorted(set(bridges)), "stairs": sorted(stairs)}
        print("%-22s %-6s gap %.1f  lengths %s  bridges %s  stairs %s" % (st["name"], arrangement, gap, length, sorted(set(bridges)), sorted(stairs)[:6]))
    json.dump(out, open(OUT, "w"), indent=1)
    print("wrote", OUT, len(out) - 1, "stations")


if __name__ == "__main__":
    main()
