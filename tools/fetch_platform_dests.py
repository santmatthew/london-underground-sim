#!/usr/bin/env python3
"""Which trains use which platform: samples TfL live arrivals repeatedly and records, per station / line / platform number, the destinations and "towards" text of the
trains predicted there.  usage: fetch_platform_dests.py [samples=15] [gap_seconds=60]  -> data/platform_destinations.json
{ "<naptan>": { "<line>|<Direction>|<number>": { "dest": {"<destNaptan>": "<name>"}, "towards": ["Edgware via Bank", ...], "n": <predictions seen> } } }
Used to tell which branch a junction platform serves (tools/junctions.py / data/junctions.json were checked against Wikipedia for Camden Town, Euston, Kennington)."""
import json, os, re, sys, time, urllib.request

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "data", "platform_destinations.json")
LINES = ["bakerloo", "central", "circle", "district", "hammersmith-city", "jubilee", "metropolitan", "northern", "piccadilly", "victoria", "waterloo-city"]


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "curl/8.5.0", "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def main():
    samples = int(sys.argv[1]) if len(sys.argv) > 1 else 15
    gap = float(sys.argv[2]) if len(sys.argv) > 2 else 60.0
    res = json.load(open(OUT)) if os.path.exists(OUT) else {}
    for s in range(samples):
        seen = 0
        for lid in LINES:
            try:
                arr = get("https://api.tfl.gov.uk/Line/%s/Arrivals" % lid)
            except Exception as e:
                print("fail", lid, e)
                continue
            for a in arr:
                m = re.match(r"\s*(.*?)\s*-\s*Platform\s*(\d+)", a.get("platformName", "")) or re.match(r"\s*()Platform\s*(\d+)", a.get("platformName", ""))
                if not m:
                    continue
                key = "%s|%s|%d" % (lid, (m.group(1) or "").strip(), int(m.group(2)))
                e = res.setdefault(a["naptanId"], {}).setdefault(key, {"dest": {}, "towards": [], "n": 0})
                if a.get("destinationNaptanId"):
                    e["dest"][a["destinationNaptanId"]] = a.get("destinationName", "")
                t = a.get("towards", "")
                if t and t not in e["towards"]:
                    e["towards"].append(t)
                e["n"] += 1
                seen += 1
        json.dump(res, open(OUT, "w"), separators=(",", ":"), sort_keys=True)
        print("sample %d/%d: %d predictions (stations %d)" % (s + 1, samples, seen, len(res)), flush=True)
        if s + 1 < samples:
            time.sleep(gap)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
