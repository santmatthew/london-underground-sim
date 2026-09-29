import bpy, sys, bmesh
sys.argv=[sys.argv[0]]
exec(open("tools/blender/people/make_people.py").read().split("def main():")[0])
spec = PS.SPECS[0]
reset_scene()
# replicate up to body creation
race = PS.RACE[spec["race"]]
hi = HumanService._create_default_human_info_dict()
hi["phenotype"].update(dict(gender=1.0, age=0.5, muscle=0.5, weight=0.5, proportions=0.5, height=0.5))
hi["phenotype"]["race"] = dict(asian=race[0], caucasian=race[1], african=race[2])
hi["rig"]="game_engine"; hi["clothes"]=["mindfront_m_suit_01.mhclo","mindfront_shoes_oxford_male.mhclo"]
hi["clothes_material_type"]="NONE"; hi["skin_material_type"]="NONE"
s = HumanService.get_default_deserialization_settings()
s["subdiv_levels"]=0; s["mask_helpers"]=False; s["detailed_helpers"]=False; s["extra_vertex_groups"]=False
body = HumanService.deserialize_from_dict(hi, s)
print([vg.name for vg in body.vertex_groups if not vg.name.endswith(("_l","_r")) ][:40])
print("mods", [m.name for m in body.modifiers])
strip_shape_keys(body)
names={vg.index:vg.name for vg in body.vertex_groups}
counts={}
for v in body.data.vertices:
    for g in v.groups:
        n=names[g.group]
        if n=="body" or n.startswith("Delete."):
            counts[n]=counts.get(n,0)+ (1 if g.weight>0.5 else 0)
print(counts, len(body.data.vertices))

from collections import Counter
c=Counter()
bones={b.name for b in body.parent.data.bones}
for v in body.data.vertices:
    ws={names[g.group]:g.weight for g in v.groups if names[g.group] in bones}
    if ws: c[max(ws,key=ws.get)]+=1
    else: c["none"]+=1
print(c.most_common(40))
