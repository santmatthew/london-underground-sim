#!/usr/bin/env python3
"""Everything known about a station, ready for writing its layout brief (see tools/layout_builder.py).

usage:  python3 tools/layout_facts.py "<station name or NaPTAN>" [--crop=x0,y0,x1,y1] [--width=2600]

Prints the platform groups (with directions), the depth-table values, the real exits, the TfL facility record, the diagram page(s), and a brief skeleton.
Renders the station's TfL layout diagram pages upright (the scans are rotated 90 degrees) into build/refs_tfl_fyi/view/ and prints the file paths to look at.
--crop takes fractions of the upright page (e.g. --crop=0.3,0.2,0.8,0.7) to zoom into part of it.

The diagrams are TfL copyright: they are a PRIVATE reference in build/ (git-ignored); only facts (topology, depths, exit letters) go into briefs. Never commit or copy them.
"""
import json
import os
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
REF = os.path.join(ROOT, "build", "refs_tfl_fyi")
NET = json.load(open(os.path.join(ROOT, "data", "network.json")))["stations"]
REAL = json.load(open(os.path.join(ROOT, "data", "stations_real.json")))
DEPTHS = json.load(open(os.path.join(ROOT, "data", "station_layouts.json")))
PAGES = json.load(open(os.path.join(REF, "station_pages.json"))) if os.path.exists(os.path.join(REF, "station_pages.json")) else {}


def resolve(arg):
    if arg in NET:
        return arg
    for k, s in NET.items():
        if s["name"] == arg:
            return k
    low = arg.lower()
    hits = [k for k, s in NET.items() if s["name"].lower() == low]
    if hits:
        return hits[0]
    raise SystemExit("unknown station %r" % arg)


def render(page, slug, crop, width):
    from PIL import Image
    src = os.path.join(REF, "pages300", page)
    if not os.path.exists(src):
        src = os.path.join(REF, "pages", page)
    im = Image.open(src).convert("RGB").rotate(90, expand=True)         # counter-clockwise: the drawing reads upright
    if crop:
        w, h = im.size
        im = im.crop((int(crop[0] * w), int(crop[1] * h), int(crop[2] * w), int(crop[3] * h)))
    if im.size[0] > width:
        im = im.resize((width, int(im.size[1] * width / im.size[0])), Image.LANCZOS)
    os.makedirs(os.path.join(REF, "view"), exist_ok=True)
    tag = "" if not crop else "_crop_%d_%d_%d_%d" % tuple(int(c * 100) for c in crop)
    out = os.path.join(REF, "view", "%s_%s%s.png" % (slug, page.replace(".png", ""), tag))
    im.save(out)
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        print(__doc__)
        return
    crop = None
    width = 2600
    for a in sys.argv[1:]:
        if a.startswith("--crop="):
            crop = [float(x) for x in a[7:].split(",")]
        if a.startswith("--width="):
            width = int(a[8:])
    naptan = resolve(args[0])
    st = NET[naptan]
    r = REAL.get(naptan, {})
    print("STATION  %s   naptan %s   zone %s   kind %s" % (st["name"], naptan, st.get("zone"), st.get("kind")))
    print("LINES    %s" % ", ".join(st["lines"]))
    groups = {}
    for pid, p in st["platforms"].items():
        groups.setdefault(p["group"], []).append(pid)
    print("PLATFORM GROUPS (every group must be placed in a level of the brief):")
    for g, pids in groups.items():
        print("   %-18s %s" % (g, ", ".join(sorted(pid.split(":")[1] for pid in pids))))
    dd = DEPTHS.get(naptan, {}).get("depths", {})
    print("DEPTHS (OCR of the diagram's depth table; UNRELIABLE - a leading digit is often lost, e.g. 15.5 read as 3.5 - and often missing: read the table off the image): %s" % (json.dumps(dd) if dd else "none read"))
    fac = r.get("facility", {})
    print("TfL FACILITIES  ticket halls %s, gates %s, escalators %s, lifts %s" % (fac.get("ticket_halls"), fac.get("gates"), fac.get("escalators"), fac.get("lifts")))
    ents = []
    for e in r.get("entrances", []):
        if (e.get("e", 0.0) ** 2 + e.get("n", 0.0) ** 2) ** 0.5 <= 130.0 and (e.get("ref") or e.get("name")):
            ents.append("%s %s%s" % (e.get("ref", ""), e.get("name", ""), " (exit only)" if e.get("exit_only") else ""))
    print("REAL EXITS (OSM; ref + name; used automatically when a hall gives no exits): %s" % ("; ".join(ents) if ents else "none mapped"))
    pages = PAGES.get(st["name"]) or PAGES.get(st["name"].replace(" (Circle)", "")) or []
    slug = "".join(c if c.isalnum() else "_" for c in st["name"])
    if not pages:
        print("DIAGRAM  none for this station")
    for p in pages:
        print("DIAGRAM  %s" % render(p, slug, crop, width))
    print("\nBRIEF SKELETON (save as tools/layouts/briefs/%s.json, then: python3 tools/layout_builder.py <file>; tools/check_layout.sh \"%s\")" % (naptan, st["name"]))
    sk = {"naptan": naptan, "source": "TfL station layout diagram <drawing number>",
          "halls": [{"id": "hall", "exits": [{"ref": "A"}]}],
          "levels": [{"id": "conc%d" % (i + 1), "depth": (dd.get(g) or [0.0])[0], "groups": [g]} for i, g in enumerate(groups)],
          "banks": [{"from": "hall", "to": "conc1", "lanes": [1, -1, 1]}] + [{"from": "conc%d" % i, "to": "conc%d" % (i + 1), "lanes": [1, -1, 1]} for i in range(1, len(groups))]}
    print(json.dumps(sk, indent=2))


if __name__ == "__main__":
    main()
