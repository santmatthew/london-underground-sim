#!/usr/bin/env python3
"""Download up to N photos from a Commons category (reference only). usage: fetch_cat.py "Category:Foo" tag N"""
import sys, json, urllib.request, urllib.parse, re, os, time
UA={"User-Agent":"UndergroundSimReference/0.1 (personal project; reference only)"}
OUT=os.path.join(os.path.dirname(os.path.abspath(__file__)),"..","build","refs")
def api(**p):
    p["format"]="json"
    return json.load(urllib.request.urlopen(urllib.request.Request("https://commons.wikimedia.org/w/api.php?"+urllib.parse.urlencode(p),headers=UA),timeout=40))
cat,tag,n=sys.argv[1],sys.argv[2],int(sys.argv[3])
r=api(action="query",generator="categorymembers",gcmtitle=cat,gcmtype="file",gcmlimit=max(n*3,12),prop="imageinfo",iiprop="url|size|extmetadata",iiurlwidth=1024)
k=0; cred=[]
for pg in r.get("query",{}).get("pages",{}).values():
    ii=pg["imageinfo"][0]
    if ii["width"]<700 or not ii.get("thumburl"): continue
    lic=ii.get("extmetadata",{}).get("LicenseShortName",{}).get("value","?")
    if not any(x in lic for x in("CC","Public")): continue
    fn=os.path.join(OUT,f"{tag}_{k}.jpg")
    try: open(fn,"wb").write(urllib.request.urlopen(urllib.request.Request(ii["thumburl"],headers=UA),timeout=60).read())
    except Exception as e: print("fail",e); time.sleep(3); continue
    cred.append(f"{tag}_{k}.jpg | {pg['title']} | {lic}")
    k+=1; time.sleep(1.2)
    if k>=n: break
open(os.path.join(OUT,"CREDITS.txt"),"a").write("\n".join(cred)+"\n")
print(tag,k)
