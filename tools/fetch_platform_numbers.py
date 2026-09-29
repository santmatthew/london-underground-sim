#!/usr/bin/env python3
"""Collect real platform numbers per station/line/direction from TfL live arrivals ("Westbound - Platform 1").

Arrivals only show platforms that have trains right now, so we sample every line repeatedly and merge.
usage: fetch_platform_numbers.py [samples=8] [gap_seconds=75]     -> data/platform_numbers.json
{ "<naptan>": { "<line>|<Direction>": [number, ...] } }   (Direction as TfL writes it: Northbound/Southbound/Eastbound/Westbound/Inner Rail/Outer Rail)
"""
import json, os, re, sys, time, urllib.request

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "data", "platform_numbers.json")
LINES = ["bakerloo", "central", "circle", "district", "hammersmith-city", "jubilee", "metropolitan", "northern", "piccadilly", "victoria", "waterloo-city"]


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "curl/8.5.0", "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def main():
    samples = int(sys.argv[1]) if len(sys.argv) > 1 else 8
    gap = float(sys.argv[2]) if len(sys.argv) > 2 else 75.0
    res = json.load(open(OUT)) if os.path.exists(OUT) else {}
    for s in range(samples):
        n_new = 0
        for lid in LINES:
            try:
                arr = get("https://api.tfl.gov.uk/Line/%s/Arrivals" % lid)
            except Exception as e:
                print("fail", lid, e)
                continue
            for a in arr:
                pn = a.get("platformName", "")
                m = re.match(r"\s*(.*?)\s*-\s*Platform\s*(\d+)", pn) or re.match(r"\s*()Platform\s*(\d+)", pn)
                if not m:
                    continue
                direction, num = (m.group(1) or "").strip(), int(m.group(2))
                key = "%s|%s" % (lid, direction)
                lst = res.setdefault(a["naptanId"], {}).setdefault(key, [])
                if num not in lst:
                    lst.append(num)
                    n_new += 1
        json.dump(res, open(OUT, "w"), separators=(",", ":"), sort_keys=True)
        print("sample %d/%d: %d new (stations %d)" % (s + 1, samples, n_new, len(res)), flush=True)
        if s + 1 < samples:
            time.sleep(gap)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
