#!/usr/bin/env python3
"""Polite per-line signage reference fetcher (Wikimedia Commons, backoff on 429). Output build/refs/lines/<line>_<n>.jpg"""
import json, urllib.request, urllib.parse, urllib.error, os, time, sys
UA={"User-Agent":"UndergroundSimReference/0.1 (personal project; reference only; contact via GitHub none)"}
OUT=os.path.join(os.path.dirname(os.path.abspath(__file__)),"..","build","refs","lines")
os.makedirs(OUT,exist_ok=True)
def get(url):
    for attempt in range(6):
        try:
            return urllib.request.urlopen(urllib.request.Request(url,headers=UA),timeout=60).read()
        except urllib.error.HTTPError as e:
            if e.code==429:
                wait=30*(attempt+1); print("429, waiting",wait,flush=True); time.sleep(wait); continue
            raise
    raise RuntimeError("giving up")
def api(**p):
    p["format"]="json"
    return json.loads(get("https://commons.wikimedia.org/w/api.php?"+urllib.parse.urlencode(p)))
LINES={
 "bakerloo":["Bakerloo line platform sign","Bakerloo line platform Underground station"],
 "central":["Central line platform sign","Central line Underground station platform sign"],
 "circle":["Circle line platform sign","Circle line Underground station sign"],
 "district":["District line platform sign","District line Underground station sign"],
 "hc":["Hammersmith & City line platform sign","Hammersmith City line Underground sign"],
 "jubilee":["Jubilee line platform sign","Jubilee line Underground station sign"],
 "metropolitan":["Metropolitan line platform sign","Metropolitan line Underground station sign"],
 "northern":["Northern line platform sign","Northern line Underground station sign"],
 "piccadilly":["Piccadilly line platform sign","Piccadilly line Underground station sign"],
 "victoria":["Victoria line platform sign","Victoria line Underground station sign"],
 "wc":["Waterloo & City line sign","Waterloo City line Underground sign"],
}
cred=[]
for line,qs in LINES.items():
    k=0; seen=set()
    for q in qs:
        try:
            r=api(action="query",generator="search",gsrsearch=q+" filetype:bitmap",gsrnamespace=6,gsrlimit=12,prop="imageinfo",iiprop="url|size|extmetadata",iiurlwidth=900)
        except Exception as e:
            print("search fail",q,e,flush=True); continue
        time.sleep(3)
        for pg in sorted(r.get("query",{}).get("pages",{}).values(),key=lambda x:x.get("index",0)):
            t=pg["title"]
            if t in seen: continue
            seen.add(t)
            ii=pg["imageinfo"][0]
            if ii["width"]<600 or not ii.get("thumburl"): continue
            lic=ii.get("extmetadata",{}).get("LicenseShortName",{}).get("value","?")
            if not any(x in lic for x in("CC","Public")): continue
            fn=os.path.join(OUT,f"{line}_{k}.jpg")
            try: open(fn,"wb").write(get(ii["thumburl"]))
            except Exception as e: print("dl fail",e,flush=True); continue
            cred.append(f"{line}_{k}.jpg | {t} | {lic}")
            print(line,k,t[:70],flush=True)
            k+=1; time.sleep(3)
            if k>=3: break
        if k>=3: break
open(os.path.join(OUT,"CREDITS.txt"),"a").write("\n".join(cred)+"\n")
print("DONE",flush=True)
