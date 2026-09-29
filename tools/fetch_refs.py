#!/usr/bin/env python3
"""Download a small reference-photo set from Wikimedia Commons into build/refs (REFERENCE ONLY - not shipped)."""
import sys, json, urllib.request, urllib.parse, re, os, time
UA = {"User-Agent": "UndergroundSimReference/0.1 (personal project; reference photos only)"}
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "refs")
os.makedirs(OUT, exist_ok=True)
QUERIES = {
 "platform_deep": "London Underground deep tube platform tiled tunnel",
 "platform_central": "Central line platform tube station interior",
 "platform_victoria": "Victoria line platform interior",
 "platform_northern": "Northern line platform interior station",
 "platform_jubilee": "Jubilee line platform screen doors interior",
 "escalator": "London Underground escalators station interior",
 "ticket_hall": "London Underground ticket hall interior",
 "gateline": "London Underground ticket barriers gateline",
 "passage": "London Underground passage tiled corridor interchange",
 "signage": "London Underground station wayfinding signs platform",
 "indicator": "London Underground platform dot matrix indicator next train",
 "train_interior": "London Underground train interior seats moquette",
 "subsurface": "Baker Street Metropolitan line platform interior",
 "district": "District line platform sub-surface station interior",
 "crowd": "London Underground platform crowded rush hour",
}
def api(**p):
    p["format"] = "json"
    url = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(p)
    return json.load(urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=40))
credits = []
tags = sys.argv[1:] or list(QUERIES)
for tag in tags:
    r = api(action="query", generator="search", gsrsearch=QUERIES[tag] + " filetype:bitmap", gsrnamespace=6, gsrlimit=6,
            prop="imageinfo", iiprop="url|size|extmetadata", iiurlwidth=1024)
    pages = sorted(r.get("query", {}).get("pages", {}).values(), key=lambda x: x.get("index", 0))
    k = 0
    for pg in pages:
        ii = pg["imageinfo"][0]
        if ii["width"] < 800: continue
        md = ii.get("extmetadata", {})
        lic = md.get("LicenseShortName", {}).get("value", "?")
        if not any(x in lic for x in ("CC", "Public")): continue
        fn = os.path.join(OUT, f"{tag}_{k}.jpg")
        try:
            data = urllib.request.urlopen(urllib.request.Request(ii["thumburl"], headers=UA), timeout=60).read()
        except Exception as e:
            print("fail", pg["title"], e); time.sleep(2); continue
        open(fn, "wb").write(data)
        au = re.sub("<[^>]+>", "", md.get("Artist", {}).get("value", "?"))[:50]
        credits.append(f"{os.path.basename(fn)} | {pg['title']} | {lic} | {au}")
        k += 1
        time.sleep(1.0)
        if k >= 3: break
open(os.path.join(OUT, "CREDITS.txt"), "a").write("\n".join(credits) + "\n")
print(len(credits), "photos")
