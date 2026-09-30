#!/usr/bin/env python3
"""Brief -> station layout.  Turns a compact description of a real station (read from a TfL layout diagram) into data/layouts/<naptan>.json
for LayoutCompiler, doing all the geometry (hall sizes, door spacing, where each escalator bank sits, landing widths, module lanes) itself.

A brief is a JSON file  tools/layouts/briefs/<naptan>.json:

  {
    "naptan": "940GZZLUVIC",                       # or "station": "Victoria"
    "source": "TfL station layout diagram V047-02",  # free text, goes into the layout's note
    "halls": [                                     # street-level ticket halls, each with its own gateline; the first is the primary one
      {"id": "A", "exits": [{"ref": "A", "name": "Victoria Station"}, {"name": "Buckingham Palace Road"}], "gates": 12},
      {"id": "B", "exits": [{"ref": "B"}, {"ref": "C"}]}
    ],
    "hall_links": [["A", "B"]],                     # halls joined inside the barriers (the second is placed beside the first)
    "levels": [                                    # rooms below the halls (concourses, platform-level landings), by depth below the hall floor (m)
      {"id": "conc", "depth": 6.4, "groups": ["ss"]},              # groups = platform groups whose platforms are reached here (or single platforms, "northern:Northbound",
                                                                   #   for a group whose platforms sit at different depths: list each on its own level)
      {"id": "low", "depth": 17.9, "groups": ["victoria"]}
    ],
    "banks": [                                     # escalator / stair banks (down); lanes: 1 = down, -1 = up; stairs true = fixed stairs
      {"from": "A", "to": "conc", "lanes": [1, -1, 1]},
      {"from": "B", "to": "conc", "lanes": [1, -1], "stairs": true},
      {"from": "conc", "to": "low", "lanes": [1, -1, 1, -1]}
    ]
  }

Everything not given is derived from the real data: exits from OSM/TfL (if a hall has no "exits" the station's real entrances are shared out over the halls),
depths from the diagram depth tables (station_layouts.json), faces from the station's platform groups (network.json), gate counts from the TfL facility record.

Rules the geometry relies on (the builder tells you when a brief breaks them):
  * a level is reached by at least one bank from a shallower room; groups appear in exactly one level; banks always go DOWN;
  * a hall with banks to landings of different depths gets the deeper ones chained from the shallower landing (same total drop) - a landing placed once;
  * halls that share paid space are listed in hall_links; linked halls touch, the others have a gap.

usage:  python3 tools/layout_builder.py <brief.json>...      (writes data/layouts/<naptan>.json and prints a summary)
"""
import json
import os
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
NET = json.load(open(os.path.join(ROOT, "data", "network.json")))["stations"]
REAL = json.load(open(os.path.join(ROOT, "data", "stations_real.json")))
LAYOUT_DEPTHS = json.load(open(os.path.join(ROOT, "data", "station_layouts.json")))

CORR_MIN = 36.0                # platform passage length (PlatformModule.TUNNEL_MIN + 6): the tunnel must stop before the landing
HALL_Z = (-14.0, 8.0)          # every hall spans these z
LANDING_MIN_W = 36.0
BANK_HALF = 2.6                # half width of a 3-lane bank, plus margin handled below


class BriefError(Exception):
    pass


def station_by_name(name):
    for k, s in NET.items():
        if s["name"] == name:
            return k
    raise BriefError("no station called %r" % name)


def real_entrances(naptan):
    out = []
    for e in REAL.get(naptan, {}).get("entrances", []):
        if (e.get("e", 0.0) ** 2 + e.get("n", 0.0) ** 2) ** 0.5 > 130.0:
            continue
        if str(e.get("ref", "")) != "" or str(e.get("name", "")) != "":
            out.append(e)

    def key(e):
        try:
            r = int(str(e.get("ref", "0")).strip() or 0)
        except ValueError:
            r = 0
        return (r, str(e.get("ref", "")), str(e.get("name", "")))

    out.sort(key=key)
    return out


def groups_of(naptan):
    g = {}
    for pid, p in NET[naptan]["platforms"].items():
        g.setdefault(p["group"], []).append(pid)
    return g


def hall_width(n_doors, n_banks):
    return float(max(24, 6 * n_doors + 10, 14 * n_banks + 8))


def normalise(brief):
    """validate, fill in defaults, return a working copy"""
    b = json.loads(json.dumps(brief))
    if "naptan" not in b:
        if "station" not in b:
            raise BriefError('brief needs "naptan" or "station"')
        b["naptan"] = station_by_name(b["station"])
    if b["naptan"] not in NET:
        raise BriefError("unknown naptan %s" % b["naptan"])
    groups = groups_of(b["naptan"])
    ids = set()
    if not b.get("halls"):
        raise BriefError("a brief needs at least one hall")
    for h in b["halls"]:
        if h["id"] in ids:
            raise BriefError("duplicate id %s" % h["id"])
        ids.add(h["id"])
    depth_default = LAYOUT_DEPTHS.get(b["naptan"], {}).get("depths", {})
    used_pids = set()
    all_pids = set(NET[b["naptan"]]["platforms"])
    for lv in b.get("levels", []):
        if lv["id"] in ids:
            raise BriefError("duplicate id %s" % lv["id"])
        ids.add(lv["id"])
        for g in lv.get("groups", []):
            # an entry is a whole platform group ("northern") or a single platform ("northern:Northbound") for groups whose platforms sit at different depths
            pids = [g] if g in all_pids else groups.get(g)
            if pids is None:
                raise BriefError("level %s: %r is neither a platform group nor a platform of this station (groups: %s; platforms: %s)" % (lv["id"], g, sorted(groups), sorted(all_pids)))
            for pid in pids:
                if pid in used_pids:
                    raise BriefError("platform %s is placed in two levels" % pid)
                used_pids.add(pid)
        if "depth" not in lv:
            gs = [g.split(":")[0] for g in lv.get("groups", []) if g.split(":")[0] in depth_default]
            if not gs:
                raise BriefError("level %s has no depth and no depth table for its groups" % lv["id"])
            lv["depth"] = float(depth_default[gs[0]][0])
        lv["depth"] = float(lv["depth"])
    missing = all_pids - used_pids
    if missing:
        raise BriefError("platforms not placed in any level: %s (add their group - or the single platforms - to a level's groups)" % sorted(missing))
    b.setdefault("levels", [])
    b.setdefault("banks", [])
    b.setdefault("hall_links", [])
    hall_ids = [h["id"] for h in b["halls"]]
    lvl = {lv["id"]: lv for lv in b["levels"]}
    for k in b["banks"]:
        for end in ("from", "to"):
            if k[end] not in ids:
                raise BriefError("bank %s -> %s: unknown room %s" % (k["from"], k["to"], k[end]))
        if k["to"] in hall_ids:
            raise BriefError("bank %s -> %s: banks go down into levels, not into halls" % (k["from"], k["to"]))
        pd = 0.0 if k["from"] in hall_ids else lvl[k["from"]]["depth"]
        if lvl[k["to"]]["depth"] <= pd + 0.5:
            raise BriefError("bank %s -> %s does not go down (%.1f m -> %.1f m)" % (k["from"], k["to"], pd, lvl[k["to"]]["depth"]))
        k.setdefault("lanes", [1, -1, 1])
    for lk in b["hall_links"]:
        for x in lk:
            if x not in hall_ids:
                raise BriefError("hall_links: %s is not a hall" % x)
    # banks into one level must all start at the same depth (the escalators land on one wall of one room)
    for lv in b["levels"]:
        srcs = sorted({round(0.0 if k["from"] in hall_ids else lvl[k["from"]]["depth"], 1) for k in b["banks"] if k["to"] == lv["id"]})
        if len(srcs) > 1:
            raise BriefError("level %s is fed by banks starting at different depths (%s m): every bank into a level must come from rooms at the same depth - "
                             "feed it from one level, or give the extra bank its own intermediate level" % (lv["id"], ", ".join(str(x) for x in srcs)))
    # every level must be reachable from a hall
    reach = set(hall_ids)
    for _ in range(len(b["levels"]) + 1):
        for k in b["banks"]:
            if k["from"] in reach:
                reach.add(k["to"])
    for lv in b["levels"]:
        if lv["id"] not in reach:
            raise BriefError("level %s is not reached by any bank" % lv["id"])
    return b


def chain_deeper_banks(b, notes):
    """a room with banks into landings of different depths: keep the shallowest child on it, chain the deeper ones from the next shallower child"""
    lvl = {lv["id"]: lv for lv in b["levels"]}
    changed = True
    while changed:
        changed = False
        by_from = {}
        for k in b["banks"]:
            by_from.setdefault(k["from"], []).append(k)
        for src, ks in by_from.items():
            depths = sorted({lvl[k["to"]]["depth"] for k in ks})
            if len(depths) < 2:
                continue
            for k in ks:
                d = lvl[k["to"]]["depth"]
                if d > depths[0] + 0.01:
                    shallower = [x for x in depths if x < d - 0.01][-1]
                    parent = [kk["to"] for kk in ks if abs(lvl[kk["to"]]["depth"] - shallower) < 0.01][0]
                    notes.append("bank %s->%s rerouted from %s (the landings of different depth cannot share a wall)" % (src, k["to"], parent))
                    k["from"] = parent
                    changed = True
                    break
            if changed:
                break


def build(brief):
    b = normalise(brief)
    naptan = b["naptan"]
    notes = []
    chain_deeper_banks(b, notes)
    st = NET[naptan]
    groups = groups_of(naptan)
    hall_ids = [h["id"] for h in b["halls"]]
    lvl = {lv["id"]: lv for lv in b["levels"]}
    out_banks = {}
    for k in b["banks"]:
        out_banks.setdefault(k["from"], []).append(k)

    # ---- exits: from the brief, else the station's real entrances shared out over the halls
    real = real_entrances(naptan)
    for i, h in enumerate(b["halls"]):
        if not h.get("exits"):
            share = real[i::len(b["halls"])] if real else []
            h["exits"] = [{"ref": str(e.get("ref", "")), "name": ""} if str(e.get("ref", "")) else {"name": str(e.get("name", ""))} for e in share]
            if not h["exits"]:
                h["exits"] = [{"name": st["name"]}]
    total_gates = int(REAL.get(naptan, {}).get("facility", {}).get("gates") or 0)
    total_gates = max(total_gates, 8 * len(b["halls"]))

    # ---- halls along x: the first is centred on x=0, the others go west; linked halls touch, the others have a gap
    widths = {h["id"]: hall_width(len(h["exits"]), len(out_banks.get(h["id"], []))) for h in b["halls"]}
    linked = set()
    for lk in b["hall_links"]:
        linked.add((lk[0], lk[1]))
        linked.add((lk[1], lk[0]))
    rect = {}
    cursor = None
    prev = None
    for h in b["halls"]:
        w = widths[h["id"]]
        if prev is None:
            x1 = w / 2.0
        else:
            gap = 0.0 if (prev, h["id"]) in linked else 8.0
            x1 = cursor - gap
        x0 = x1 - w
        rect[h["id"]] = (x0, x1)
        cursor = x0
        prev = h["id"]
    for lk in b["hall_links"]:
        i, j = hall_ids.index(lk[0]), hall_ids.index(lk[1])
        if abs(i - j) != 1:
            raise BriefError("hall_links %s-%s: linked halls must be neighbours in the halls list (reorder halls)" % (lk[0], lk[1]))
    rooms, escs, links = [], [], []
    sum_w = sum(widths.values())
    for h in b["halls"]:
        x0, x1 = rect[h["id"]]
        n = len(h["exits"])
        doors = []
        for i, d in enumerate(h["exits"]):
            c = (x0 + x1) / 2.0 if n == 1 else x0 + 3.5 + (x1 - x0 - 7.0) * i / (n - 1)
            dd = {"c": round(c, 1)}
            if d.get("ref"):
                dd["ref"] = str(d["ref"])
            if d.get("name"):
                dd["name"] = str(d["name"])
            doors.append(dd)
        gates = int(h.get("gates") or max(6, min(24, round(total_gates * widths[h["id"]] / sum_w))))
        rooms.append({"id": h["id"], "kind": "hall", "rect": [x0, x1, HALL_Z[0], HALL_Z[1]], "depth": 0, "gateline": {"z": -6, "n": gates}, "doors": doors})
    for lk in b["hall_links"]:
        east, west = (lk[0], lk[1]) if rect[lk[0]][0] > rect[lk[1]][0] else (lk[1], lk[0])
        links.append({"id": "link_%s_%s" % (east, west), "a": east, "b": west, "side": "W", "c": 2.0, "w": 6.0, "h": 3.0})

    # ---- levels top down: each level's banks spread over its parent, the landing centred under its incoming banks
    geom = {h["id"]: {"cx": (rect[h["id"]][0] + rect[h["id"]][1]) / 2.0, "w": widths[h["id"]]} for h in b["halls"]}
    order = sorted(b["levels"], key=lambda lv: lv["depth"])
    counters = {}
    for lv in order:
        inc = [k for k in b["banks"] if k["to"] == lv["id"]]
        if not inc:
            raise BriefError("level %s has no incoming bank" % lv["id"])
        cs = []
        for k in inc:
            src = k["from"]
            if src not in geom:
                raise BriefError("bank %s -> %s: %s is placed after it (banks must go from shallower to deeper rooms)" % (src, lv["id"], src))
            n_out = len(out_banks[src])
            j = counters.get(src, 0)
            counters[src] = j + 1
            g = geom[src]
            c = g["cx"] - g["w"] / 2.0 + (j + 0.5) * g["w"] / n_out
            k["_c"] = round(c, 1)
            cs.append(k["_c"])
        cx = round(sum(cs) / len(cs), 1)
        n_mod = len({(NET[naptan]["platforms"][g]["group"] if g in NET[naptan]["platforms"] else g) for g in lv.get("groups", [])})
        span = max(cs) - min(cs)
        n_out = len(out_banks.get(lv["id"], []))
        w = max(LANDING_MIN_W, span + 16.0, 14.0 * n_out + 12.0)
        d = max(16.0, 18.0 * max(n_mod - 1, 0) + 12.0)
        geom[lv["id"]] = {"cx": cx, "w": w}
        rooms.append({"id": lv["id"], "kind": "landing", "size": [round(w, 1), round(d, 1)], "depth": lv["depth"]})
        for pi, k in enumerate(inc):
            e = {"id": "%s_%d" % (lv["id"], pi), "from": k["from"], "to": lv["id"], "dir": "S", "c": k["_c"], "lanes": k["lanes"]}
            if k.get("stairs"):
                e["stairs"] = True
            elif k.get("stairs") is False:
                e["stairs"] = False
            if pi == 0:
                e["to_off"] = round(cx - k["_c"], 1)
            escs.append(e)

    # ---- platform modules: one per group, east of its level, faces = every platform of the group
    mods = []
    for lv in order:
        by_group = {}
        for g in lv.get("groups", []):
            if g in NET[naptan]["platforms"]:
                by_group.setdefault(NET[naptan]["platforms"][g]["group"], []).append(g)
            else:
                by_group.setdefault(g, []).extend(groups[g])
        for gi, (g, pids) in enumerate(by_group.items()):
            lane = round((gi - (len(by_group) - 1) / 2.0) * 18.0, 1)
            mods.append({"attach": lv["id"], "lane_z": lane, "lane_rel": True, "corr_len": float(b.get("corr", CORR_MIN)), "group": g, "faces": [[pid, 0] for pid in pids]})
    note = "%s, from %s (topology; dimensions estimated)" % (st["name"], b.get("source", "a TfL station layout diagram"))
    if notes:
        note += "; " + "; ".join(notes)
    layout = {"note": note, "rooms": rooms, "esc": escs, "modules": mods}
    if links:
        layout["links"] = links
    return layout, notes


def write(brief_path):
    brief = json.load(open(brief_path))
    layout, notes = build(brief)
    naptan = normalise(brief)["naptan"]
    path = os.path.join(ROOT, "data", "layouts", naptan + ".json")
    json.dump(layout, open(path, "w"), indent=1)
    return naptan, path, notes


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    ok = True
    for p in sys.argv[1:]:
        try:
            naptan, path, notes = write(p)
            print("%s -> %s%s" % (os.path.basename(p), os.path.relpath(path, ROOT), ("   [" + "; ".join(notes) + "]") if notes else ""))
        except BriefError as e:
            ok = False
            print("%s: BRIEF ERROR: %s" % (os.path.basename(p), e))
    sys.exit(0 if ok else 2)
