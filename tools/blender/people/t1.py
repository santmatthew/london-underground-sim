import bpy, sys, os, json, addon_utils, traceback
print("ENABLE", bpy.ops.preferences.addon_enable(module="bl_ext.user_default.mpfb"))
from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.targetservice import TargetService
from bl_ext.user_default.mpfb.services.assetservice import AssetService
hi = HumanService._create_default_human_info_dict()
hi["phenotype"].update(dict(gender=1.0, age=0.5, muscle=0.5, weight=0.5, proportions=0.5, height=0.5))
hi["phenotype"]["race"] = dict(asian=0.0, caucasian=1.0, african=0.0)
hi["rig"] = "game_engine"
hi["eyes"] = "low-poly.mhclo"
hi["eyebrows"]="eyebrow001.mhclo"
hi["eyelashes"]="eyelashes01.mhclo"
hi["hair"]="short02.mhclo"
hi["skin_mhmat"]="young_caucasian_male.mhmat"
hi["skin_material_type"]="GAMEENGINE"
hi["clothes"]=["male_casualsuit01.mhclo","shoes01.mhclo"]
hi["proxy"]=""
s = HumanService.get_default_deserialization_settings()
s["subdiv_levels"]=0
s["mask_helpers"]=True
s["detailed_helpers"]=False
s["extra_vertex_groups"]=False
try:
    bm = HumanService.deserialize_from_dict(hi, s)
except Exception:
    traceback.print_exc(); raise
for o in bpy.data.objects:
    print(o.name, o.type, o.parent.name if o.parent else None, len(o.data.vertices) if o.type=='MESH' else '', [m.name for m in o.modifiers], [m.name for m in o.data.materials] if o.type=='MESH' else '')
print(bm.dimensions)

rig=[o for o in bpy.data.objects if o.type=='ARMATURE'][0]
print("BONES", len(rig.data.bones), [b.name for b in rig.data.bones][:60])
for o in bpy.data.objects:
    if o.type=='MESH': 
        me=o.data
        print(o.name, "tris", sum(len(p.vertices)-2 for p in me.polygons), "vgroups", len(o.vertex_groups), [ (k,o[k]) for k in o.keys() if k.startswith("mpfb") or "source" in k][:5], [m.name for m in o.modifiers])
