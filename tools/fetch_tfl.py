#!/usr/bin/env python3
"""Fetch the London Underground network from the TfL open API and write raw JSON to build/tfl_raw.json"""
import json, urllib.request, sys, os
LINES = ["bakerloo","central","circle","district","hammersmith-city","jubilee","metropolitan","northern","piccadilly","victoria","waterloo-city"]
def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "curl/8.5.0", "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)
raw = {}
for lid in LINES:
    raw[lid] = {}
    for d in ("inbound","outbound"):
        raw[lid][d] = get(f"https://api.tfl.gov.uk/Line/{lid}/Route/Sequence/{d}")
    print(lid, len(raw[lid]["outbound"]["stations"]), "stations", [r["name"] for r in raw[lid]["outbound"]["orderedLineRoutes"]])
os.makedirs(os.path.join(os.path.dirname(__file__), "..", "build"), exist_ok=True)
json.dump(raw, open(os.path.join(os.path.dirname(__file__), "..", "build", "tfl_raw.json"), "w"))
