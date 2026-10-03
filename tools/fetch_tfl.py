#!/usr/bin/env python3
"""Fetch the London Underground network (and the Elizabeth line) from the TfL open API into build/tfl_raw.json.
  python3 tools/fetch_tfl.py                 all lines (rewrites the file)
  python3 tools/fetch_tfl.py elizabeth       only the named line(s); the others in the file are kept"""
import json, urllib.request, sys, os
LINES = ["bakerloo","central","circle","district","hammersmith-city","jubilee","metropolitan","northern","piccadilly","victoria","waterloo-city","elizabeth"]
def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "curl/8.5.0", "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)
path = os.path.join(os.path.dirname(__file__), "..", "build", "tfl_raw.json")
want = sys.argv[1:] or LINES
raw = json.load(open(path)) if (sys.argv[1:] and os.path.exists(path)) else {}
for lid in want:
    raw[lid] = {}
    for d in ("inbound","outbound"):
        raw[lid][d] = get(f"https://api.tfl.gov.uk/Line/{lid}/Route/Sequence/{d}")
    print(lid, len(raw[lid]["outbound"]["stations"]), "stations", [r["name"] for r in raw[lid]["outbound"]["orderedLineRoutes"]])
os.makedirs(os.path.dirname(path), exist_ok=True)
json.dump(raw, open(path, "w"))
