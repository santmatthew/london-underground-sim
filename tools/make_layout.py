#!/usr/bin/env python3
"""Small builder for "comb" layouts (see docs/REAL_LAYOUTS.md): ticket halls side by side, escalator/stair banks going south into landings
stacked below them, platform modules east of the landings.  Everything that leaves a hall or landing goes south from its S wall, all escalators sit
west of all modules, so shafts never cross platforms.  Writes data/layouts/<naptan>.json.

usage (as a module):  from make_layout import make ; make("940GZZLUTCR", note, halls=[...], landings=[...], modules=[...])
  halls:    [{"id","x0","x1","gates","doors":[{"ref"?, "name"?}...]}]   (first hall = primary; doors are spread evenly)
  landings: [{"id","depth","w","d","parents":[{"from","lanes"}...]}]      depth = metres below the ticket-hall floor
  modules:  [{"attach","group","faces":[[pid,face],..],"lane":offset from the landing centre,"corr":metres}]
"""
import json, os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
CX = -10.0          # x of every escalator shaft


def make(naptan, note, halls, landings, modules):
    rooms, esc = [], []
    info = {}                       # id -> {"x0","x1","cx"}
    for h in halls:
        n = len(h["doors"])
        x0, x1 = h["x0"], h["x1"]
        doors = []
        for i, d in enumerate(h["doors"]):
            c = (x0 + x1) / 2.0 if n == 1 else x0 + 3.5 + (x1 - x0 - 7.0) * i / (n - 1)
            doors.append(dict(d, c=round(c, 1)))
        rooms.append({"id": h["id"], "kind": "hall", "rect": [x0, x1, -14, 8], "depth": 0, "gateline": {"z": -6, "n": h["gates"]}, "doors": doors})
        info[h["id"]] = {"x0": x0, "x1": x1, "cx": round((x0 + x1) / 2.0, 1)}
    for L in landings:
        cs = [info[p["from"]]["cx"] for p in L["parents"]]
        cx = round(sum(cs) / len(cs), 1)
        w = max(L["w"], (max(cs) - min(cs)) + 14.0)
        rooms.append({"id": L["id"], "kind": "landing", "size": [w, L["d"]], "depth": L["depth"]})
        info[L["id"]] = {"x0": cx - w / 2.0, "x1": cx + w / 2.0, "cx": cx}
        for pi, par in enumerate(L["parents"]):
            c = info[par["from"]]["cx"]
            e = {"id": "%s_%d" % (L["id"], pi), "from": par["from"], "to": L["id"], "dir": "S", "c": c, "lanes": par["lanes"]}
            if pi == 0:
                e["to_off"] = round(cx - c, 1)
            esc.append(e)
    mods = []
    for m in modules:
        mods.append({"attach": m["attach"], "lane_z": m.get("lane", 0), "lane_rel": True, "corr_len": m.get("corr", 12), "group": m["group"], "faces": m["faces"]})
    json.dump({"note": note, "rooms": rooms, "esc": esc, "modules": mods}, open(os.path.join(ROOT, "data", "layouts", naptan + ".json"), "w"), indent=1)
