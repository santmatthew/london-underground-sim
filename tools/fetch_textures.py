#!/usr/bin/env python3
"""Download CC0 PBR texture sets from ambientCG into assets/textures/<Name>/ (Color, NormalGL, Roughness, AO, Metalness)."""
import urllib.request, zipfile, io, os, sys
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "textures")
SETS = {  # id: resolution
    "Tiles107": "2K", "Tiles109": "1K", "Tiles110": "1K", "Tiles140": "1K", "Tiles133A": "1K",
    "Terrazzo004": "2K", "Terrazzo018": "1K", "Terrazzo005": "1K",
    "Concrete034": "2K", "Concrete046": "1K", "Concrete030": "2K", "Concrete036": "2K", "Concrete031": "1K", "Concrete042A": "1K",
    "Rubber004": "1K", "Rubber001": "1K",
    "Metal032": "1K", "Metal063": "1K", "Metal055A": "1K", "Metal061B": "1K",
    "PaintedPlaster017": "1K", "Plaster007": "1K", "Fabric030": "1K", "Marble016": "1K",
}
KEEP = ("_Color", "_NormalGL", "_Roughness", "_AmbientOcclusion", "_Metalness")
for name, res in SETS.items():
    out = os.path.join(ROOT, name)
    if os.path.isdir(out) and os.listdir(out):
        continue
    url = f"https://ambientcg.com/get?file={name}_{res}-JPG.zip"
    req = urllib.request.Request(url, headers={"User-Agent": "curl/8.5.0"})
    data = urllib.request.urlopen(req, timeout=120).read()
    os.makedirs(out, exist_ok=True)
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        for n in z.namelist():
            base = os.path.splitext(n)[0]
            if any(base.endswith(k) for k in KEEP):
                k = [k for k in KEEP if base.endswith(k)][0]
                open(os.path.join(out, k[1:] + ".jpg"), "wb").write(z.read(n))
    print("ok", name, res, sorted(os.listdir(out)))
