#!/usr/bin/env python3
"""Split the platforms of branch-junction stations (data/junctions.json) in data/network.json: one platform per direction AND branch, so that Camden Town has
Edgware-branch and High Barnet-branch platforms (1/2 and 3/4) instead of one northbound and one southbound platform shared by both.

  platform id   "northern:Northbound~edgware"   (group "northern.edgware": one platform module per branch, see StationPlan)
  platform dict {group, dir:"Northbound", branch:"Edgware branch", number:1, lines, terminal}

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
        via = {b["id"]: name2id[b["via"]] for b in jc["branches"]}
        newp = {}
        for svc in lines[lid]["services"]:
            stops = svc["stops"]
            if sid not in stops:
                continue
            i = stops.index(sid)
            branch = None
            for b in jc["branches"]:
                if via[b["id"]] in stops:
                    branch = b
                    break
            if branch is None:
                raise SystemExit("%s: service %s matches no branch" % (sname, svc["id"]))
            for key, direction in (("plat_fwd", jc["dirs"][0]), ("plat_bwd", jc["dirs"][1])):
                pid = svc[key][i]
                if "~" in pid:
                    continue
                # the direction comes from the service's travel (stops run south -> north), not from the bearing the network builder derived
                # (at Euston the builder labelled a Bank-branch train travelling south as northbound)
                base = "%s:%s" % (pid.split(":")[0], direction)
                new = "%s~%s" % (base, branch["id"])
                svc[key][i] = new
                changed += 1
                old = st["platforms"].get(pid) or {}
                pl = newp.setdefault(new, {"group": "%s.%s" % (old.get("group", lid), branch["id"]), "dir": direction, "branch": branch["label"],
                                           "number": branch["numbers"][direction], "lines": [lid], "terminal": False})
                if old.get("terminal"):
                    pl["terminal"] = True
        # drop the plain platforms that were split, keep any other (e.g. Euston's Victoria line)
        for pid in list(st["platforms"]):
            if st["platforms"][pid]["group"] == lid and "~" not in pid:
                del st["platforms"][pid]
        st["platforms"].update(newp)
        st["platforms"] = dict(sorted(st["platforms"].items()))
    return changed


if __name__ == "__main__":
    path = os.path.join(ROOT, "data", "network.json")
    d = json.load(open(path))
    n = apply(d["lines"], d["stations"])
    json.dump(d, open(path, "w"), separators=(",", ":"))
    print("junctions: %d service stops moved to branch platforms" % n)
