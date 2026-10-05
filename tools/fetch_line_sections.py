#!/usr/bin/env python3
"""What the track runs through, from OpenStreetMap: the railway ways of Greater London that are in a tunnel, in a cutting, on an embankment or on a bridge / viaduct (tags and geometry), and the Elizabeth line's own tracks.
tools/build_line_geometry.py lays the track of every hop of every line over them and stores, for each hop, which stretches are tunnel / cutting / embankment / viaduct / open ground
(data/line_geometry.json, key "sec"). Output: build/geom/ways_<kind>.json (not shipped). Data (c) OpenStreetMap contributors, ODbL.
  tools/fetch_line_sections.py            fetches what is missing        --refetch   fetches everything again (ALL kinds: the tunnel / cutting data may then differ from what data/line_geometry.json was built from;
                                            to redo one kind: python3 -c "import fetch_line_sections as f, json; json.dump(f.overpass(f.KINDS['elizabeth_gaps'])['elements'], open(f.GEOM + '/ways_elizabeth_gaps.json', 'w'))")
"""
import json, os, sys, time, urllib.parse, urllib.request

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
GEOM = os.path.join(ROOT, "build", "geom")
UA = {"User-Agent": "UndergroundSimReference/0.1 (personal project; reference data only)", "Accept": "*/*", "Content-Type": "application/x-www-form-urlencoded"}
HOSTS = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"]
BBOX = "51.38,-0.55,51.72,0.35"
EL_BBOX = "51.40,-1.05,51.70,0.30"          # the whole Elizabeth line, Reading to Shenfield and Abbey Wood
BERKS_BBOX = "51.46,-0.90,51.56,-0.55"      # the line west of the Greater London extract, Slough to Twyford (the same four kinds again: what the track runs through out there)
RAILS = '"railway"~"^(subway|rail|light_rail)$"'
KINDS = {
    "tunnel": 'way[%s]["tunnel"~"^(yes|building_passage|culvert)$"](%s);out tags geom;' % (RAILS, BBOX),
    "cutting": 'way[%s]["cutting"~"^(yes|left|right|both)$"](%s);out tags geom;' % (RAILS, BBOX),
    "embankment": 'way[%s]["embankment"~"^(yes|left|right|both)$"](%s);out tags geom;' % (RAILS, BBOX),
    "bridge": 'way[%s]["bridge"~"^(yes|viaduct|aqueduct|movable)$"](%s);out tags geom;' % (RAILS, BBOX),
    # the Elizabeth line's own tracks, tunnel or not (the relation of the line has no ways in the core): build_line_geometry.py finds the hops that the relation lacks in them
    "elizabeth": 'way["railway"="rail"]["line"="Elizabeth"](%s);out tags geom;' % EL_BBOX,
    # the hops of the line that its tagged ways do not cover (Burnham - Taplow - Maidenhead - Twyford beyond the Greater London extract, the Heathrow Terminals 2 & 3 - 5 tunnel): every running
    # rail way around them; build_line_geometry.py finds the track between the stations in them (the line uses the relief lines: which of the parallel tracks is not told, the headings are alike)
    "tunnel_berks": 'way[%s]["tunnel"~"^(yes|building_passage|culvert)$"](%s);out tags geom;' % (RAILS, BERKS_BBOX),
    "cutting_berks": 'way[%s]["cutting"~"^(yes|left|right|both)$"](%s);out tags geom;' % (RAILS, BERKS_BBOX),
    "embankment_berks": 'way[%s]["embankment"~"^(yes|left|right|both)$"](%s);out tags geom;' % (RAILS, BERKS_BBOX),
    "bridge_berks": 'way[%s]["bridge"~"^(yes|viaduct|aqueduct|movable)$"](%s);out tags geom;' % (RAILS, BERKS_BBOX),
    "elizabeth_gaps": '(way["railway"="rail"]["service"!~"^(siding|yard|spur)$"](51.46,-0.90,51.56,-0.60);way["railway"="rail"]["service"!~"^(siding|yard|spur)$"](51.45,-0.52,51.50,-0.43););out tags geom;',
}


def overpass(q, tries=5):
    last = None
    for attempt in range(tries):
        for host in HOSTS:
            try:
                req = urllib.request.Request(host, headers=UA, data=urllib.parse.urlencode({"data": "[out:json][timeout:170];" + q}).encode())
                with urllib.request.urlopen(req, timeout=200) as r:
                    return json.load(r)
            except Exception as e:
                last = e
                print("  overpass error:", str(e)[:100], flush=True)
                time.sleep(10 * (attempt + 1))
    raise RuntimeError(last)


def main():
    os.makedirs(GEOM, exist_ok=True)
    for kind, q in KINDS.items():
        fp = os.path.join(GEOM, "ways_%s.json" % kind)
        if os.path.exists(fp) and "--refetch" not in sys.argv:
            continue
        d = overpass(q)
        els = d["elements"]
        json.dump(els, open(fp, "w"))
        print("%-10s %d ways" % (kind, len(els)), flush=True)
        time.sleep(8)


if __name__ == "__main__":
    main()
