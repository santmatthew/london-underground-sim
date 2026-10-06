#!/usr/bin/env python3
"""How the platforms of the Underground's generated surface stations lie, from OpenStreetMap platform outlines (build/geom/surface_stations.json, fetched by tools/fetch_surface_stations.py) and
TfL's platform numbers (data/platform_numbers.json). Writes data/surface_platforms.json, derived numbers only (OpenStreetMap contributors, ODbL; see CREDITS.md):

  "<NaPTAN>": {"name": ..., "groups": {"<line group>": {
        "arrangement": "side" | "island",     the group's two platforms are apart (the two tracks between them) or touching / one outline (an island)
        "gap": metres between the platform edges,
        "axis": [east, north]                 unit vector along the platforms (its sign is arbitrary: the offsets below use the same one)
        "length": {"<pid>": metres},  "across": {"<pid>": metres},
        "stagger": metres                     the first (sorted) pid's middle minus the second's along `axis`, 0 unless the two outlines are alike in length (see STAGGER_* below)
        "bridges": [...], "footbridges": [{"x": metres along `axis` from the middle of the pair, "covered": bool}, ...]   as tools/build_el_platforms.py }}}

Only the groups with exactly two platforms, neither a terminus, whose two platforms each match one outline by their numbers (and no outline the numbers of another group also fit) are written: a group
the data does not settle is left to the generator's island. The Elizabeth line's own stations are in data/el_platforms.json (tools/build_el_platforms.py).
  python3 tools/build_surface_platforms.py
"""
import json, math, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_el_platforms import xy, poly_dist, pca_axis        # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
GEOM = os.path.join(ROOT, "build", "geom", "surface_stations.json")
OUT = os.path.join(ROOT, "data", "surface_platforms.json")
MIN_LEN = 60              # an outline shorter than this is a stair or a fragment, not a platform
STAGGER_LEN_DIFF = 25     # the two outlines must be this alike in length (metres) for their offset to be a stagger
STAGGER_MIN = 5.0
LEN_DIFF_MAX = 40         # side platforms whose outlines differ more than this are not read as a pair (one is merged with a neighbour, say): their middle, and so the footbridges' places, would be wrong


def ints(s):
    return set(int(t) for t in re.findall(r"\d+", str(s)))


def olen(o):
    """the length of an outline along its own axis"""
    ax, c = pca_axis(o["pts"])
    al = [(p[0] - c[0]) * ax[0] + (p[1] - c[1]) * ax[1] for p in o["pts"]]
    return max(al) - min(al)


def main():
    geo = json.load(open(GEOM))
    net = json.load(open(os.path.join(ROOT, "data", "network.json")))["stations"]
    lines = json.load(open(os.path.join(ROOT, "data", "network.json")))["lines"]
    pn = json.load(open(os.path.join(ROOT, "data", "platform_numbers.json")))
    out = {"_comment": "How the Underground's generated surface stations' platforms lie (tools/build_surface_platforms.py): side platforms or an island, the stagger and the footbridges, from OpenStreetMap platform outlines and footways. Derived numbers only; (c) OpenStreetMap contributors, ODbL."}
    stats = {"stations": 0, "groups": 0, "side": 0, "island": 0, "skipped": {}}

    def skip(why):
        stats["skipped"][why] = stats["skipped"].get(why, 0) + 1

    for sid, st in sorted(geo.items(), key=lambda kv: kv[1]["name"]):
        if sid not in net or sid not in pn:
            continue
        if os.path.exists(os.path.join(ROOT, "data", "layouts", sid + ".json")):
            stats["authored"] = stats.get("authored", 0) + 1       # an authored layout is the station's own: it is not generated
            continue
        ns = net[sid]
        lat0, lon0 = st["lat"], st["lon"]
        # the platform outlines near the station, with the platform numbers they carry
        outlines = []
        for w in st["ways"]:
            t = w.get("tags", {})
            if (t.get("railway") == "platform" or t.get("public_transport") == "platform") and w.get("geometry"):
                pts = [xy(p, lat0, lon0) for p in w["geometry"] if p]
                refs = ints(t.get("ref", "")) | ints(t.get("local_ref", ""))
                if len(pts) >= 3:
                    outlines.append({"pts": pts, "refs": refs, "id": len(outlines)})
        groups = {}
        for pid, pl in ns["platforms"].items():
            groups.setdefault(pl["group"], []).append(pid)
        # which groups each platform number could belong to (a number two groups both use makes an outline ambiguous)
        group_refs = {}
        pid_refs = {}
        for g, pids in groups.items():
            for pid in pids:
                pl = ns["platforms"][pid]
                d = pid.split(":")[1].split("#")[0] if ":" in pid else ""
                refs = set()
                for ln in pl["lines"]:
                    refs |= ints(pn[sid].get("%s|%s" % (ln, d), []))
                pid_refs[pid] = refs
                group_refs.setdefault(g, set()).update(refs)
        used = {}                 # outline id -> the groups whose numbers fit it
        for g, pids in groups.items():
            if g != "elizabeth" and len(pids) == 2:
                for o in outlines:
                    if o["refs"] & group_refs[g]:
                        used.setdefault(o["id"], set()).add(g)
        done_any = False
        entry = {"name": ns["name"], "groups": {}}

        def unsettled(g, why):
            """the outlines are there but contradict each other: written, so that nothing is inferred for the group (StationPlan.is_split)"""
            skip(why)
            entry["groups"][g] = {"arrangement": "unsettled", "why": why}
            stats["unsettled"] = stats.get("unsettled", 0) + 1
            return True
        for g, pids in groups.items():
            if g == "elizabeth":
                continue
            if len(pids) != 2 or any(ns["platforms"][p]["terminal"] for p in pids):
                skip("not a pair of through platforms")
                continue
            pa, pb = sorted(pids)
            ra, rb = pid_refs[pa], pid_refs[pb]
            unmapped = not ra or not rb
            big = [o for o in outlines if olen(o) >= MIN_LEN]          # (stairs and fragments are not platforms)
            if not unmapped:
                if any(g2 != g and (group_refs[g2] & (ra | rb)) for g2 in group_refs):
                    unsettled(g, "a number another group uses")
                    done_any = True
                    continue
                oa = [o for o in outlines if o["refs"] & ra]
                ob = [o for o in outlines if o["refs"] & rb]
                if not oa or not ob:
                    unmapped = True          # (the outlines carry no numbers: as below)
                elif any(len(used[o["id"]]) > 1 for o in oa + ob):
                    unsettled(g, "an outline another group's numbers fit")
                    done_any = True
                    continue
            if unmapped:
                # (no numbers that tell the outlines apart: a station whose only group this is and that has exactly two platform outlines has them as its pair - which outline is which platform is not known, so no stagger, and no `across`)
                if len(groups) != 1 or len(big) != 2:
                    skip("no platform numbers" if not ra or not rb else "outline not found")
                    continue
                oa, ob = [big[0]], [big[1]]
            # one outline for both (an island's: one polygon carrying both numbers) or one per platform
            A = [p for o in oa for p in o["pts"]]
            B = [p for o in ob for p in o["pts"]]
            same = any(o in ob for o in oa)
            if same:
                gap = 0.0
            else:
                gap = min(poly_dist(o1["pts"], o2["pts"]) for o1 in oa for o2 in ob)
            if 2.0 <= gap < 4.0:
                unsettled(g, "a gap too narrow for two tracks and too wide for an island (%.1f)" % gap)
                done_any = True
                continue
            arrangement = "island" if gap < 2.0 else "side"
            axis, centre = pca_axis(A + B)
            perp = (-axis[1], axis[0])
            along = lambda P: [(p[0] - centre[0]) * axis[0] + (p[1] - centre[1]) * axis[1] for p in P]
            across = lambda P: [(p[0] - centre[0]) * perp[0] + (p[1] - centre[1]) * perp[1] for p in P]
            la = along(A)
            lb = along(B)
            length = {pa: round(max(la) - min(la)), pb: round(max(lb) - min(lb))}
            across_of = {pa: round(sum(across(A)) / len(A), 1), pb: round(sum(across(B)) / len(B), 1)}
            if unmapped:
                across_of = {}
            if arrangement == "side" and (min(length.values()) < MIN_LEN or gap > 14.0):
                unsettled(g, "outlines do not look like a pair of platforms (length %s, gap %.1f)" % (str(list(length.values())), gap))
                done_any = True
                continue
            # (a gap that holds two tracks but outlines of unlike length: one is merged with a neighbour. The pair is side platforms, but the middle - and so the stagger and the footbridges' places - is not known)
            partial = arrangement == "side" and abs(length[pa] - length[pb]) > LEN_DIFF_MAX
            if arrangement == "side" and not unmapped:
                lo, hi = sorted(across_of.values())
                ids = set(o["id"] for o in oa + ob)
                between = [o for o in outlines if o["id"] not in ids and lo + 1.0 < sum(across(o["pts"])) / len(o["pts"]) < hi - 1.0 and min(along(o["pts"])) < max(la) and max(along(o["pts"])) > min(la)]
                if between:
                    unsettled(g, "another platform lies between the two")
                    done_any = True
                    continue
            stagger = 0
            if arrangement == "side" and not unmapped and not partial and abs(length[pa] - length[pb]) <= STAGGER_LEN_DIFF:
                off = (max(la) + min(la)) * 0.5 - (max(lb) + min(lb)) * 0.5
                if abs(off) >= STAGGER_MIN:
                    stagger = round(off)
            # footbridges (as tools/build_el_platforms.py): bridge footways that span both platforms, not pavements of road bridges, crossings or private ways
            foot = []
            bridges = []
            if arrangement == "side" and not partial:
                for w in st["ways"]:
                    t = w.get("tags", {})
                    hw = t.get("highway")
                    if t.get("bridge") != "yes" or hw not in ("footway", "steps", "pedestrian") or not w.get("geometry"):
                        continue
                    gpts = [xy(p, lat0, lon0) for p in w["geometry"] if p]
                    dA = min(poly_dist([p], A) for p in gpts)
                    dB = min(poly_dist([p], B) for p in gpts)
                    al = along(gpts)
                    ac = across(gpts)
                    if dA < 25 and dB < 25 and (max(ac) - min(ac)) >= gap + 4.0:
                        bridges.append(round(sum(al) / len(al)))
                        if hw != "steps" and t.get("footway") not in ("sidewalk", "crossing") and t.get("access") not in ("no", "private"):
                            foot.append((round(sum(al) / len(al)), t.get("covered") == "yes"))
            foot.sort()
            fb = []
            for x, cov in foot:
                if fb and x - fb[-1]["x"] < 12:
                    fb[-1]["covered"] = fb[-1]["covered"] or cov
                else:
                    fb.append({"x": x, "covered": cov})
            entry["groups"][g] = {"arrangement": arrangement, "gap": round(gap, 1), "axis": [round(axis[0], 4), round(axis[1], 4)], "length": length, "across": across_of,
                                  "stagger": stagger, "bridges": sorted(set(bridges)), "footbridges": fb}
            stats["groups"] += 1
            stats[arrangement] += 1
            done_any = True
            print("%-26s %-12s %-6s gap %5.1f  lengths %s  stagger %s  footbridges %s" % (ns["name"], g, arrangement, gap, list(length.values()), stagger, [f["x"] for f in fb]))
        if done_any:
            out[sid] = entry
            stats["stations"] += 1
    json.dump(out, open(OUT, "w"), indent=1)
    print(stats)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
