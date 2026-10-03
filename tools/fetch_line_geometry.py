#!/usr/bin/env python3
"""Fetch the track geometry of the Underground / Elizabeth line from OpenStreetMap route relations (route=subway, network London Underground).

Step 1 of the curved-track pipeline (see tools/build_line_geometry.py for step 2):
  tools/fetch_line_geometry.py            lists the relations (build/geom/relations.json) and fetches the geometry of each (build/geom/rel/<id>.json)
Cached files are kept; delete one to refetch it. Data (c) OpenStreetMap contributors, ODbL: only the derived numbers (data/line_geometry.json) are shipped.
"""
import json, os, sys, time, urllib.parse, urllib.request

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
GEOM = os.path.join(ROOT, "build", "geom")
REL = os.path.join(GEOM, "rel")
UA = {"User-Agent": "UndergroundSimReference/0.1 (personal project; reference data only)", "Accept": "*/*",
      "Content-Type": "application/x-www-form-urlencoded"}
HOSTS = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"]
# (the Elizabeth line relations run out to Reading and Shenfield, and the big ones time out: only Greater London's worth of geometry is fetched, which is also what the sim shows)
LONDON = "51.38,-0.55,51.72,0.35"
LIST_Q = '[out:json][timeout:120];(rel["route"="subway"]["network"="London Underground"];rel["route"="subway"]["name"~"^Elizabeth line"];);out tags;'


def overpass(q, tries=4):
    last = None
    for attempt in range(tries):
        for host in HOSTS:
            try:
                req = urllib.request.Request(host, headers=UA, data=urllib.parse.urlencode({"data": q}).encode())
                with urllib.request.urlopen(req, timeout=180) as r:
                    return json.load(r)
            except Exception as e:
                last = e
                print("  overpass error:", str(e)[:100], flush=True)
                time.sleep(6 * (attempt + 1))
    raise RuntimeError("overpass failed: %s" % last)


PLAT_Q = '[out:json][timeout:160];(way["railway"="platform"](%s);way["public_transport"="platform"]["subway"="yes"](%s););out geom;' % (LONDON, LONDON)


def main():
    os.makedirs(REL, exist_ok=True)
    pp = os.path.join(GEOM, "platforms_london.json")
    if not os.path.exists(pp) or "--replatform" in sys.argv:
        # every platform outline in Greater London in one go: which side of the track each platform lies on (tools/build_line_geometry.py, door_side)
        json.dump(overpass(PLAT_Q), open(pp, "w"))
    lp = os.path.join(GEOM, "relations.json")
    if not os.path.exists(lp) or "--relist" in sys.argv:
        rels = overpass(LIST_Q)["elements"]
        json.dump(rels, open(lp, "w"))
    rels = json.load(open(lp))
    el_ids = {r["id"]: r["tags"].get("ref") == "Elizabeth" for r in rels}
    # (the Elizabeth line first: with the London bbox they come quickly; the few big Northern line relations that time out go last)
    todo = [r["id"] for r in sorted(rels, key=lambda r: r["tags"].get("ref") != "Elizabeth") if not os.path.exists(os.path.join(REL, "%d.json" % r["id"]))]
    print("%d relations, %d to fetch" % (len(rels), len(todo)))
    BATCH = 1
    for i in range(0, len(todo), BATCH):
        ids = todo[i:i + BATCH]
        el = el_ids.get(ids[0], False)
        try:
            d = overpass('[out:json][timeout:120];rel(id:%s);out geom%s;' % (",".join(str(x) for x in ids), "(%s)" % LONDON), 2)
        except RuntimeError:
            print("  skipped", ids, flush=True)
            continue
        got = {e["id"]: e for e in d["elements"]}
        for rid in ids:
            json.dump(got.get(rid, {}), open(os.path.join(REL, "%d.json" % rid), "w"))
        print("[%d/%d] %s" % (min(i + BATCH, len(todo)), len(todo), ids), flush=True)
        time.sleep(6)


if __name__ == "__main__":
    main()
