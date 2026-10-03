#!/usr/bin/env python3
"""Collect real platform numbers per station/line/direction from TfL live arrivals ("Westbound - Platform 1").

Arrivals only show platforms that have trains right now, so we sample every line repeatedly and merge.
usage: fetch_platform_numbers.py [samples=8] [gap_seconds=75]     -> data/platform_numbers.json
{ "<naptan>": { "<line>|<Direction>": [number, ...] } }   (Direction as TfL writes it: Northbound/Southbound/Eastbound/Westbound/Inner Rail/Outer Rail)
"""
import json, os, re, sys, time, urllib.request

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "data", "platform_numbers.json")
LINES = ["bakerloo", "central", "circle", "district", "hammersmith-city", "jubilee", "metropolitan", "northern", "piccadilly", "victoria", "waterloo-city", "elizabeth"]
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from elizabeth_ids import EL_MERGE
_net = json.load(open(os.path.join(ROOT, "data", "network.json")))["stations"]
_x_by_name = {v["name"]: v["x"] for v in _net.values()}


def el_direction(a):
    """The Elizabeth line's arrivals give "Platform 4" without a direction: the platform is Eastbound when the train's destination lies east of the station, else Westbound"""
    dest = (a.get("destinationName") or "").replace(" Rail Station", "").replace("London ", "").replace(" (Elizabeth line)", "").strip()
    here = _net.get(EL_MERGE.get(a["naptanId"], a["naptanId"]))
    x = _x_by_name.get(dest)
    if here is None or x is None:
        return ""
    return "Eastbound" if x > here["x"] else "Westbound"


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
                nap = a["naptanId"]
                if lid == "elizabeth":
                    nap = EL_MERGE.get(nap, nap)
                    direction = direction or el_direction(a)
                    if direction == "" or nap not in _net:
                        continue
                key = "%s|%s" % (lid, direction)
                lst = res.setdefault(nap, {}).setdefault(key, [])
                if num not in lst:
                    lst.append(num)
                    n_new += 1
        # a terminus has one Elizabeth line platform id in the network: all its real numbers belong to it
        for nap, ent in res.items():
            pids = [p for p in (_net.get(nap, {}).get("platforms", {})) if p.startswith("elizabeth:")]
            if len(pids) == 1 and any(k.startswith("elizabeth|") for k in ent):
                keep = "elizabeth|" + pids[0].split(":")[1]
                allnum = sorted(set(n for k, v in ent.items() if k.startswith("elizabeth|") for n in v))
                for k in [k for k in ent if k.startswith("elizabeth|")]:
                    del ent[k]
                ent[keep] = allnum
        json.dump(res, open(OUT, "w"), separators=(",", ":"), sort_keys=True)
        print("sample %d/%d: %d new (stations %d)" % (s + 1, samples, n_new, len(res)), flush=True)
        if s + 1 < samples:
            time.sleep(gap)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
