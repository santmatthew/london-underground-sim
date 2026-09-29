"""Retarget CMU mocap onto the game_engine skeleton and write build/people_tmp/anims_raw.json (+ anims_meta.json).

    build/people_tmp/venv/bin/python tools/blender/people/make_anims.py [--only name,name]

Then run  godot --headless --path build/sandbox_people --script res://tools/build_anim_library.gd  to make people_anims.res.
"""
import sys, os, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from anim_tools import *
import procedural as PR

PROJECT = "/home/msant/Projects/Personal/underground-sim"
MOCAP = PROJECT + "/build/mocap/"
REF_CHAR = "person_03"
OUT_RAW = PROJECT + "/build/people_tmp/anims_raw.json"
OUT_META = PROJECT + "/assets/people/anims/anims_meta.json"

only = None
if "--only" in sys.argv:
    only = set(sys.argv[sys.argv.index("--only") + 1].split(","))

rig = Rig("%s/assets/people/chars/%s.info.json" % (PROJECT, REF_CHAR))
info = rig.info["rig"]
ref_pelvis_h = info["pelvis"]["head"][2]
ref_leg_len = ref_pelvis_h - info["foot_l"]["head"][2]
ROOT_Z = info["Root"]["head"][2]
sources = {}


def S(name, skip=None):
    if name not in sources:
        sources[name] = Source(MOCAP + name + ".bvh", skip)
    return sources[name]


clips = {}


def add(name, q, pos, meta, loop, kind, ground=True, overrides=None):
    q = q.copy()
    pos = pos.copy()
    if ground:
        L = quat_to_mat(q)
        off = ground_offset(rig, L, pos)
        pos[:, 2] += off
    c = dict(q=q, pos=pos, meta=dict(meta), loop=loop, kind=kind, overrides=overrides or {})
    c["meta"]["loop"] = loop
    c["meta"]["kind"] = kind
    clips[name] = c
    print("  %-22s frames=%3d dur=%.2fs %s" % (name, q.shape[0], (q.shape[0] - 1) / FPS, {k: (round(v, 3) if isinstance(v, float) else v) for k, v in meta.items() if k in ("stride_speed_mps", "yaw_delta_deg")}))


def want(name):
    return only is None or name in only


# ---------------------------------------------------------------- walking
WALKS = [("walk_slow", "07_04"), ("walk_stroll", "16_15"), ("walk_normal", "07_01"), ("walk_casual", "35_01"),
         ("walk_relaxed", "02_01"), ("walk_brisk", "08_01"), ("walk_brisk_b", "16_21"), ("walk_hurry", "07_12")]
for name, f in WALKS:
    if not want(name):
        continue
    q, p, m = walk_cycle(S(f), rig)
    add(name, q, p, m, True, "locomotion")


# ---------------------------------------------------------------- loops (idle / sit)
def loop_clip(name, f, t0, t1, dmin, dmax, kind, pick=0, ground=True, step=0.2, yaw_span=None):
    src = S(f)
    res, L, pos, sc = loop_search(src, rig, t0, t1, dmin, dmax, step_s=step)
    e, a, b = res[pick]
    q, p, m = make_loop_clip(src, rig, a, b, L, pos, name)
    m["loop_error"] = float(e)
    add(name, q, p, m, True, kind, ground=ground)


def yaw_ramp(q, pos, delta_deg):
    """add a smoothly ramped yaw (about vertical, CCW+) to the pelvis so the clip's total yaw change is delta_deg more"""
    F = q.shape[0]
    pi = rig.idx["pelvis"]
    t = np.linspace(0, 1, F)
    s_ = t * t * (3 - 2 * t)
    ang = np.radians(delta_deg) * s_
    Rz = np.zeros((F, 3, 3))
    Rz[:, 0, 0] = np.cos(ang); Rz[:, 0, 1] = -np.sin(ang); Rz[:, 1, 0] = np.sin(ang); Rz[:, 1, 1] = np.cos(ang); Rz[:, 2, 2] = 1
    Rp = quat_to_mat(q[:, pi])
    q = q.copy()
    q[:, pi] = fix_quat_continuity(mat_to_quat(Rz @ Rp))
    pos = pos.copy()
    pos[:, :2] = np.einsum("fij,fj->fi", Rz[:, :2, :2], pos[:, :2])
    return q, pos


def once_clip(name, f, t0, t1, kind, yaw_from=None, ground=True, yaw_mode="start", anchor="start", target_yaw=None):
    src = S(f)
    fps = src.fps
    a = int(t0 * fps)
    if yaw_mode == "start":
        yaw = heading_yaw(src, a, a + int(0.3 * fps))
    else:
        yaw = heading_yaw(src, a, int(t1 * fps))
    L, Rw, pos, sc = retarget(src, rig, world_yaw=-yaw)
    q, p, m = make_once_clip(src, rig, t0, t1, L, pos, name)
    # yaw delta of the pelvis over the clip (about vertical, Blender frame: +Z up; CCW positive = left turn)
    R0 = quat_to_mat(q[0, rig.idx["pelvis"]])
    Rn = quat_to_mat(q[-1, rig.idx["pelvis"]])
    f0 = R0 @ np.array([0, 1.0, 0])
    f1 = Rn @ np.array([0, 1.0, 0])
    dy = float(np.degrees(np.arctan2(f1[0] * -1, f1[1]) - np.arctan2(f0[0] * -1, f0[1])))
    dy = (dy + 180) % 360 - 180
    if target_yaw is not None:
        q, p = yaw_ramp(q, p, target_yaw - dy)
        m["yaw_delta_measured_deg"] = dy
        dy = target_yaw
    if anchor == "end":
        p = p.copy()
        p[:, :2] -= p[-1, :2]
    m["yaw_delta_deg"] = dy
    m["anchor"] = anchor
    add(name, q, p, m, False, kind, ground=ground)


if want("idle_stand_1"):
    loop_clip("idle_stand_1", "77_02", 0.5, 7.8, 3.0, 4.2, "idle")
if want("idle_stand_2"):
    loop_clip("idle_stand_2", "40_10", 17.0, 35.0, 4.0, 6.0, "idle")
if want("idle_stand_3"):
    loop_clip("idle_stand_3", "40_10", 35.0, 51.0, 4.0, 6.0, "idle")
if want("sit_idle_1"):
    loop_clip("sit_idle_1", "14_31", 3.0, 7.3, 3.4, 4.3, "sit")
if want("sit_idle_2"):
    loop_clip("sit_idle_2", "14_32", 12.0, 16.6, 3.4, 4.6, "sit")
if want("sit_down"):
    once_clip("sit_down", "14_31", 1.2, 3.4, "transition", anchor="end", target_yaw=0.0)
if want("stand_up"):
    once_clip("stand_up", "14_31", 7.0, 8.3, "transition", target_yaw=0.0)
if want("turn_right_90"):
    once_clip("turn_right_90", "69_19", 0.6, 3.05, "turn", target_yaw=-90.0)
if want("turn_left_90") or want("turn_right_90"):
    pass

# ---------------------------------------------------------------- procedural / derived
PR.build_derived(clips, rig, add, want, ROOT_Z)

# ---------------------------------------------------------------- write
out = {"fps": FPS, "clips": {}}
meta = {"fps": FPS, "ref": {"character": REF_CHAR, "pelvis_height": ref_pelvis_h, "leg_length": ref_leg_len,
                            "root_z": ROOT_Z},
        "note": "stride_speed_mps is the ground speed a clip was captured at, for the reference skeleton; a character with leg_length L moves at stride_speed*L/ref.leg_length at playback speed 1.0",
        "skeleton": "MPFB game_engine rig (Unreal style bone names), all rest orientations identity",
        "track_paths": "Skeleton3D:<bone_name> relative to AnimationPlayer.root_node, which must be the glb 'Armature' node (parent of Skeleton3D). pelvis position track is scaled by Skeleton3D.motion_scale = pelvis_height / ref.pelvis_height",
        "yaw_note": "clips with yaw_delta_deg != 0 (turn_*_90) rotate the pelvis; when they finish rotate the character node by yaw_delta_deg (CCW=left, degrees about +Y) and continue with an idle clip",
        "anchor_note": "sit_down ends at the seated pelvis position (anchor=end): place the node so the seated pelvis is over the seat; sit_* / stand_up are authored relative to that seat point",
        "clips": {}}
for name, c in clips.items():
    q = c["q"]
    F = q.shape[0]
    tracks = {}
    for i, bn in enumerate(rig.names):
        if bn == "Root":
            continue
        qi = q[:, i]
        ov = c["overrides"].get(bn)
        if ov is not None:
            qi = ov
        ident = np.abs(qi[:, 3]).min() > 0.99999
        if ident and bn not in c["overrides"]:
            continue
        # constant tracks -> single key
        if np.abs(qi - qi[0]).max() < 1e-4:
            tracks[bn] = [np.round(qi[0], 6).tolist()]
        else:
            tracks[bn] = np.round(qi, 6).tolist()
    pos = c["pos"].copy()
    pos_local = pos - np.array([0, 0, ROOT_Z])
    out["clips"][name] = dict(frames=F, length=(F - 1) / FPS, loop=c["loop"], tracks=tracks,
                              pelvis=np.round(pos_local, 5).tolist())
    m = dict(c["meta"])
    m["duration"] = (F - 1) / FPS
    m["frames"] = F
    meta["clips"][name] = m
os.makedirs(os.path.dirname(OUT_META), exist_ok=True)
old = {}
if only and os.path.exists(OUT_RAW):
    old = json.load(open(OUT_RAW))
    for k, v in old["clips"].items():
        out["clips"].setdefault(k, v)
    om = json.load(open(OUT_META))
    for k, v in om["clips"].items():
        meta["clips"].setdefault(k, v)
json.dump(out, open(OUT_RAW, "w"))
json.dump(meta, open(OUT_META, "w"), indent=1)
print("wrote", len(out["clips"]), "clips")
