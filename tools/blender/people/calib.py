import bpy, sys, json, itertools
bpy.ops.preferences.addon_enable(module="bl_ext.user_default.mpfb")
from bl_ext.user_default.mpfb.services.humanservice import HumanService
import mathutils
def measure(gender, age, height, weight, race):
    hi = HumanService._create_default_human_info_dict()
    hi["phenotype"].update(dict(gender=gender, age=age, muscle=0.5, weight=weight, proportions=0.5, height=height))
    hi["phenotype"]["race"] = race
    s = HumanService.get_default_deserialization_settings()
    s["subdiv_levels"]=0; s["detailed_helpers"]=False; s["extra_vertex_groups"]=False
    hi["rig"]=""
    bm = HumanService.deserialize_from_dict(hi, s)
    # measure body group verts
    gi = bm.vertex_groups["body"].index
    zs=[v.co.z for v in bm.data.vertices if any(g.group==gi and g.weight>0.5 for g in v.groups)]
    key = bm.data.shape_keys
    # apply mix values -> use evaluated mesh
    dg = bpy.context.evaluated_depsgraph_get()
    ev = bm.evaluated_get(dg)
    me = ev.to_mesh()
    zz=[v.co.z for v in me.vertices]
    res=(min(zz),max(zz))
    ev.to_mesh_clear()
    bpy.data.objects.remove(bm)
    return res
out={}
race=dict(asian=0.05, caucasian=0.9, african=0.05)
for g in (0.0,1.0):
  for h in (0.0,0.25,0.5,0.75,1.0):
    lo,hi_=measure(g,0.5,h,0.5,race)
    print("gender",g,"height",h,"->",round(hi_-lo,3))
for age in (0.3,0.5,0.75,0.92):
    lo,hi_=measure(1.0,age,0.5,0.5,race); print("male age",age,round(hi_-lo,3))
    lo,hi_=measure(0.0,age,0.5,0.5,race); print("fem age",age,round(hi_-lo,3))
for rc in [dict(asian=0.9,caucasian=0.05,african=0.05), dict(asian=0.05,caucasian=0.05,african=0.9)]:
    lo,hi_=measure(1.0,0.5,0.5,0.5,rc); print("male",rc,round(hi_-lo,3))
    lo,hi_=measure(0.0,0.5,0.5,0.5,rc); print("fem",rc,round(hi_-lo,3))
