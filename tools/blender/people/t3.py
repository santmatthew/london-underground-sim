import bpy, sys
exec(open("tools/blender/people/make_people.py").read().split("def main():")[0].replace("argv = sys.argv","argv = []; _x = sys.argv"))
reset_scene()
hi = HumanService._create_default_human_info_dict()
hi["phenotype"].update(dict(gender=1.0, age=0.5, muscle=0.5, weight=0.5, proportions=0.5, height=0.5))
hi["rig"]="game_engine"; hi["clothes"]=[]
hi["clothes_material_type"]="NONE"; hi["skin_material_type"]="NONE"
s = HumanService.get_default_deserialization_settings()
s["subdiv_levels"]=0; s["mask_helpers"]=False; s["detailed_helpers"]=True; s["extra_vertex_groups"]=False
body = HumanService.deserialize_from_dict(hi, s)
rig=body.parent
print("rig matrix_world", rig.matrix_world, rig.scale, rig.location)
print("body matrix", body.matrix_world, body.scale)
for n in ("Root","pelvis","spine_01","head","thigh_l","foot_l"):
    b=rig.data.bones[n]
    print(n, tuple(round(x,3) for x in b.head_local), tuple(round(x,3) for x in b.tail_local))
print("mesh z range", min(v.co.z for v in body.data.vertices), max(v.co.z for v in body.data.vertices))
