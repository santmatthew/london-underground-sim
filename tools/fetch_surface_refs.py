#!/usr/bin/env python3
"""Reference photos of surface / sub-surface Tube stations (private, build/refs_dress/surface, never committed): searches Wikimedia Commons per query,
keeps the best 2 openly licensed hits (CC / public domain, >= 900 px wide) and records credits.  usage: fetch_surface_refs.py [queries file]"""
import json, os, re, sys, time, urllib.parse, urllib.request
UA = {"User-Agent": "UndergroundSimReference/0.1 (personal project; reference photos only)"}
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "refs_dress", "surface")
QUERIES = [
 "Arnos Grove station platform", "Southgate Underground station platform", "Oakwood Underground station", "Sudbury Town station platform", "Northfields station platform",
 "Boston Manor station platform", "Acton Town station platform", "Park Royal Underground station platform", "Hounslow West station platform", "Bounds Green station platform",
 "Pinner station platform", "Chesham station platform", "Rickmansworth station platform", "Northwood station platform Metropolitan", "Harrow-on-the-Hill station platforms",
 "Moor Park station platform", "Chorleywood station platform", "Amersham station platform",
 "Upminster station platform", "Richmond station platforms District", "Kew Gardens station platform", "Chiswick Park station platform", "Parsons Green station platform",
 "Putney Bridge station platform", "Ravenscourt Park station platform", "West Brompton station platform", "Barking station platform", "Hornchurch station platform", "Elm Park station platform",
 "Epping station platform Central line", "Loughton station platform", "Theydon Bois station platform", "Woodford station platform", "Snaresbrook station platform",
 "Perivale station platform", "Hanger Lane station platform", "Greenford station platform", "Ruislip Gardens station platform", "West Ruislip station platform",
 "High Barnet station platform", "Totteridge and Whetstone station platform", "Mill Hill East station platform", "Edgware station platform Northern line", "Finchley Central station platform",
 "Morden station platform", "Colindale station platform", "Burnt Oak station platform",
 "Harrow and Wealdstone station platform", "Stonebridge Park station platform", "Kenton station platform Bakerloo", "Queensbury station platform", "Stanmore station platform", "Canons Park station platform",
 "Temple station platform District line", "Sloane Square station platform", "Blackfriars Underground station platform", "Mansion House station platform", "Embankment station District line platform",
 "Edgware Road Circle line platform", "Great Portland Street station platform", "Euston Square station platform", "Farringdon station Underground platform", "Barbican station platform",
 "Aldgate East station platform", "Whitechapel station platform", "Shepherd's Bush Market station platform", "Goldhawk Road station platform", "Ladbroke Grove station platform", "Westbourne Park station platform",
 "Ealing Broadway station platform District", "Wimbledon station District platform", "Bow Road station platform", "Fulham Broadway station platform", "Gunnersbury station platform",
 "Stamford Brook station platform", "Turnham Green station platform", "Bayswater station platform", "High Street Kensington station platform", "Paddington Hammersmith City platform",
]
if len(sys.argv) > 1:
    QUERIES = [q.strip() for q in open(sys.argv[1]) if q.strip()]
def api(**p):
    p["format"] = "json"
    url = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(p)
    return json.load(urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=40))
def slug(s):
    return re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_")
cred = open(os.path.join(OUT, "CREDITS.txt"), "a")
have = set(os.listdir(OUT))
for q in QUERIES:
    got = 0
    try:
        r = api(action="query", generator="search", gsrsearch=q + " filetype:bitmap", gsrnamespace=6, gsrlimit=12, prop="imageinfo", iiprop="url|size|extmetadata", iiurlwidth=1280)
    except Exception as e:
        print("search fail", q, e); time.sleep(5); continue
    pages = sorted(r.get("query", {}).get("pages", {}).values(), key=lambda x: x.get("index", 0))
    for pg in pages:
        ii = pg["imageinfo"][0]
        md = ii.get("extmetadata", {})
        lic = md.get("LicenseShortName", {}).get("value", "?")
        if ii["width"] < 900 or not ii.get("thumburl") or not any(x in lic for x in ("CC", "Public")):
            continue
        t = pg["title"].lower()
        if any(b in t for b in ("map", "logo", "ticket", "diagram", "poster", "plan")):
            continue
        fn = "%s_%d.jpg" % (slug(q.replace(" station", "").replace(" platform", "").replace(" platforms", "")), got)
        if fn in have:
            got += 1
            if got >= 2: break
            continue
        try:
            open(os.path.join(OUT, fn), "wb").write(urllib.request.urlopen(urllib.request.Request(ii["thumburl"], headers=UA), timeout=60).read())
        except Exception as e:
            print("dl fail", fn, e); time.sleep(4); continue
        au = re.sub("<[^>]+>", "", md.get("Artist", {}).get("value", "?"))[:40]
        cred.write("%s | %s | %s | %s | %s\n" % (fn, pg["title"], lic, au, ii.get("descriptionurl", ""))); cred.flush()
        got += 1
        time.sleep(1.5)
        if got >= 2: break
    print(q, got, flush=True)
    time.sleep(1.0)
