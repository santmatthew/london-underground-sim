#!/usr/bin/env python3
"""Search Wikimedia Commons for openly-licensed reference photos.  usage: commons_search.py "query" [n]
Prints title, licence, author, size, GPS/heading (if any) and the direct thumbnail URL."""
import sys, json, urllib.request, urllib.parse, re
UA = {"User-Agent": "UndergroundSimReference/0.1 (personal project; reference photos only)"}
def api(**p):
    p["format"] = "json"
    url = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(p)
    return json.load(urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=40))
q = sys.argv[1]; n = int(sys.argv[2]) if len(sys.argv) > 2 else 8
r = api(action="query", generator="search", gsrsearch=q + " filetype:bitmap", gsrnamespace=6, gsrlimit=n,
        prop="imageinfo|coordinates", iiprop="url|size|extmetadata", iiurlwidth=1280, colimit=n)
for pg in sorted(r.get("query", {}).get("pages", {}).values(), key=lambda x: x.get("index", 0)):
    ii = pg["imageinfo"][0]
    md = ii.get("extmetadata", {})
    lic = md.get("LicenseShortName", {}).get("value", "?")
    au = re.sub("<[^>]+>", "", md.get("Artist", {}).get("value", "?"))[:40]
    co = pg.get("coordinates", [{}])[0]
    print(pg["title"], "|", lic, "|", au, "|", ii["width"], "x", ii["height"], "| gps:", co.get("lat"), co.get("lon"))
    print("   ", ii.get("thumburl"))
