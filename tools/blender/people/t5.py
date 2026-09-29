import sys, json; sys.path.insert(0,"tools/blender/people")
import numpy as np
from retarget import *
rig=Rig("assets/people/chars/person_03.info.json")
src=Source("build/mocap/07_01.bvh", skip=2)
L,Rw,pos,s=retarget(src,rig)
print("scale",s, "leg src",src.leg,"tgt",rig.leg_length(), "frames", src.nf)
q=mat_to_quat(L)   # (F,N,4)
# pick frames
sel=[0,30,60,90,120]
out={"names":rig.names,"frames":[]}
root=rig.head[rig.idx["Root"]]
for f in sel:
    out["frames"].append({"q":q[f].tolist(),"pelvis":(pos[f]-np.array([0,0,0])).tolist()})
json.dump(out,open("build/sandbox_people/assets/debug_pose.json","w"))
print("pelvis rest", rig.head[rig.idx["pelvis"]], "root", root)
print(pos[:3], pos[:,1].min(), pos[:,1].max())
