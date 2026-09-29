"""Merge specs + build info + texture info into assets/people/people_manifest.json (+ CREDITS.txt)."""
import os, sys, json, glob
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import people_spec as PS
OUT = os.path.join(PS.PROJECT, "assets", "people")
args = sys.argv[1:]
if args and args[0] == "--outdir":
    OUT = args[1]
chars = []
for sp in PS.SPECS:
    cid = sp["id"]
    ip = os.path.join(OUT, "chars", cid + ".info.json")
    tp = os.path.join(OUT, "tex", cid + ".tex.json")
    if not (os.path.exists(ip) and os.path.exists(tp)):
        continue
    info = json.load(open(ip)); tex = json.load(open(tp))
    rig = info["rig"]
    pelvis_h = rig["pelvis"]["head"][2]
    thigh = rig["thigh_l"]["head"]; foot = rig["foot_l"]["head"]
    leg_len = pelvis_h - foot[2]
    surfaces = ["skin", "face", "outfit"] + (["hair"] if sp["hair"] else [])
    T = "res://assets/people/tex/"
    slots = {}
    for slot, d in tex["slots"].items():
        if slot in ("top", "bottom", "outer", "main"):
            pal = {"top": "top", "bottom": "bottom", "outer": "outer", "main": "suit"}[slot]
            if slot == "top" and sp["outfit"].startswith("business"):
                pal = "shirt"
            slots[slot] = dict(item=d["item"], recolor=d["recolor"], default=d["default_tint"], palette=pal if d["recolor"] else "")
        else:
            slots[slot] = dict(item=d["item"], recolor=False, default=None, palette="")
    entry = dict(
        id=cid, index=sp["index"], file="res://assets/people/chars/%s.glb" % cid,
        name=sp["name"], gender="male" if sp["gender"] > 0.5 else "female", age=sp["age"],
        age_band=PS.age_band(sp["age"]), height_m=info["height_m"], ethnicity=sp["race"],
        outfit=sp["outfit"], has_bag=bool(sp["bag"]), bag=sp["bag"] or "", glasses=bool(sp["glasses"]),
        hat=bool(sp["hat"]), hair=sp["hair"] or "", hair_colour=sp["hair_col"],
        garments=[g[0] for g in sp["garments"]],
        surfaces=surfaces,
        material_slots=dict(skin=T + cid + "_skin.png", face=T + cid + "_face.png", outfit=T + cid + "_outfit.png",
                            outfit_normal=(T + cid + "_outfit_n.png") if tex["has_normal"] else "",
                            hair=(T + cid + "_hair.png") if sp["hair"] else ""),
        tint_slots=slots, hair_tint=tex["hair_tint"], skin_mean=tex["skin_mean"],
        pelvis_height_m=round(pelvis_h, 4), leg_length_m=round(leg_len, 4),
        tris_lod0=info["tris"], surface_tris=info["surf_tris"], layout=tex["layout"], atlas_size=tex["atlas_size"],
        rig_bone_count=len(info["bone_order"]),
    )
    chars.append(entry)
man = dict(version=1, count=len(chars), skeleton="game_engine (Unreal-style names), Skeleton3D under Armature",
           palettes={k: [[n, w, list(PS.CLOTH_COLOURS.get(n) or PS.HAIR_COLOURS.get(n))] for n, w in v] for k, v in PS.PALETTES.items()},
           characters=chars)
os.makedirs(OUT, exist_ok=True)
json.dump(man, open(os.path.join(OUT, "people_manifest.json"), "w"), indent=1)
print("manifest:", len(chars), "characters")
