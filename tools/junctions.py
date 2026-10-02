#!/usr/bin/env python3
"""Split the platforms of branch-junction stations (data/junctions.json) in data/network.json: one platform per direction AND branch, so that Camden Town has
Edgware-branch and High Barnet-branch platforms (1/2 and 3/4) instead of one northbound and one southbound platform shared by both.

  platform id   "northern:Northbound~edgware"   (group "northern.edgware": one platform module per branch, see StationPlan)
  platform dict {group, dir:"Northbound", branch:"Edgware branch", number:1, lines, terminal}

Station entry of data/junctions.json:
  line      the line whose services are split
  dirs      the direction labels of a service's forward / backward run (the network builder derives them from compass bearings, which is wrong at a few stations)
  branches  [{dir, id, label, via, number, module}]: the platform for direction `dir` used by services that also call at `via`; `number` is its real number and
            `module` the platform module (two entries with the same module share an island)
  shared    {Direction: number}: real numbers of the directions that are not split

Idempotent. build_network.py calls apply() before it writes the file; run `python3 tools/junctions.py` to patch an existing data/network.json in place."""
import json
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


def apply(lines, stations):
    cfg = json.load(open(os.path.join(ROOT, "data", "junctions.json")))["stations"]
    name2id = {}
    for sid, s in stations.items():
        name2id.setdefault(s["name"], sid)
    changed = 0
    for sname, jc in cfg.items():
        sid = name2id[sname]
        st = stations[sid]
        lid = jc["line"]
        shared = jc.get("shared", {})
        old_terminal = {pid: pl.get("terminal", False) for pid, pl in st["platforms"].items()}
        replaced = set()
        newp = {}
        for svc in lines[lid]["services"]:
            stops = svc["stops"]
            if sid not in stops:
                continue
            i = stops.index(sid)
            dirs = jc.get("dirs")
            for key, k in (("plat_fwd", 0), ("plat_bwd", 1)):
                pid = svc[key][i]
                if "~" in pid:
                    continue
                group = pid.split(":")[0]
                direction = dirs[k] if dirs else pid.split(":")[1]
                replaced.add(pid)
                changed += 1
                branch = None
                for b in jc["branches"]:
                    if b["dir"] == direction and name2id[b["via"]] in stops:
                        branch = b
                        break
                if branch is not None:
                    new = "%s:%s~%s" % (group, direction, branch["id"])
                    pl = newp.setdefault(new, {"group": "%s.%s" % (group, branch.get("module", branch["id"])), "dir": direction, "branch": branch["label"],
                                               "number": branch["number"], "lines": [lid], "terminal": False})
                else:
                    new = "%s:%s" % (group, direction)
                    pl = newp.setdefault(new, {"group": group, "dir": direction, "lines": [lid], "terminal": False})
                    if direction in shared:
                        pl["number"] = shared[direction]
                svc[key][i] = new
                if old_terminal.get(pid):
                    pl["terminal"] = True
        # drop the plain platforms that were replaced and are no longer used by any service at this station
        used = set()
        for ln in lines.values():
            for sv in ln["services"]:
                if sid in sv["stops"]:
                    j = sv["stops"].index(sid)
                    used.add(sv["plat_fwd"][j])
                    used.add(sv["plat_bwd"][j])
        for pid in replaced:
            if pid not in used and pid in st["platforms"]:
                del st["platforms"][pid]
        for pid, pl in newp.items():
            if pid in st["platforms"]:
                # a plain platform that other lines also use: keep their entry, add this line and the number
                ex = st["platforms"][pid]
                if lid not in ex["lines"]:
                    ex["lines"].append(lid)
                if "number" in pl:
                    ex["number"] = pl["number"]
            else:
                st["platforms"][pid] = pl
        st["platforms"] = dict(sorted(st["platforms"].items()))
    return changed


if __name__ == "__main__":
    path = os.path.join(ROOT, "data", "network.json")
    d = json.load(open(path))
    n = apply(d["lines"], d["stations"])
    json.dump(d, open(path, "w"), separators=(",", ":"))
    print("junctions: %d service stops moved to branch platforms" % n)
