import bpy, sys
exec(open("tools/blender/people/make_people.py").read().split("def main():")[0].replace("argv = sys.argv","argv = []; _x = sys.argv"))
reset_scene()
spec=PS.SPECS[0]
hi = HumanService._create_default_human_info_dict()
hi["phenotype"].update(dict(gender=1.0, age=0.5, muscle=0.5, weight=0.5, proportions=0.5, height=0.5))
hi["rig"]="game_engine"; hi["clothes"]["mindfront_shoes_oxford_male.mhclo"] if False else None
hi["clothes"]=["mindfront_shoes_oxford_male.mhclo"]
hi["clothes_material_type"]="NONE"; hi["skin_material_type"]="NONE"
s = HumanService.get_default_deserialization_settings()
s["subdiv_levels"]=0; s["mask_helpers"]=False; s["detailed_helpers"]=True; s["extra_vertex_groups"]=False
body = HumanService.deserialize_from_dict(hi, s)
rig=body.parent
names={vg.index:vg.name for vg in body.vertex_groups}
bones={b.name for b in rig.data.bones}
from collections import Counter
c=Counter(); cz={}
for v in body.data.vertices:
    ws={names[g.group]:g.weight for g in v.groups if names[g.group] in bones}
    inbody=any(names[g.group]=="body" and g.weight>0.5 for g in v.groups)
    if not inbody: continue
    if ws:
        k=max(ws,key=ws.get); c[k]+=1; cz.setdefault(k,[]).append(v.co.z)
    else: c["none"]+=1
for k,n in c.most_common(12): print(k,n, (round(min(cz[k]),3), round(max(cz[k]),3)) if k in cz else "")
