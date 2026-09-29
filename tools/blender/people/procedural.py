"""Derived / procedural clips: mirrors, IK arm poses (rail, phone, escalator handrail), finger grips."""
import numpy as np
from anim_tools import *

FINGER_ANG = {"index": (12, 20, 12), "middle": (16, 24, 14), "ring": (20, 26, 16), "pinky": (24, 28, 18),
              "thumb": (8, 12, 8)}
GRIP_ANG = {"index": (45, 60, 40), "middle": (50, 65, 45), "ring": (55, 68, 48), "pinky": (58, 70, 50),
            "thumb": (20, 25, 25)}
PHONE_ANG = {"index": (20, 25, 15), "middle": (45, 60, 40), "ring": (52, 65, 45), "pinky": (55, 68, 48),
             "thumb": (5, 8, 5)}
TOUCH_ANG = {"index": (10, 15, 8), "middle": (40, 55, 35), "ring": (48, 60, 42), "pinky": (52, 66, 46),
             "thumb": (10, 12, 10)}


def mirror_clip(c, rig):
    q = c["q"].copy()
    out = np.zeros_like(q)
    for i, n in enumerate(rig.names):
        if n.endswith("_l"):
            j = rig.idx[n[:-2] + "_r"]
        elif n.endswith("_r"):
            j = rig.idx[n[:-2] + "_l"]
        else:
            j = i
        out[:, j] = q[:, i] * np.array([1, -1, -1, 1.0])
    pos = c["pos"].copy()
    pos[:, 0] *= -1
    ov = {}
    for k, v in c["overrides"].items():
        if k.endswith("_l"):
            k2 = k[:-2] + "_r"
        elif k.endswith("_r"):
            k2 = k[:-2] + "_l"
        else:
            k2 = k
        ov[k2] = v * np.array([1, -1, -1, 1.0])
    return out, pos, ov


def qmul(a, b):
    x1, y1, z1, w1 = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    x2, y2, z2, w2 = b[..., 0], b[..., 1], b[..., 2], b[..., 3]
    return np.stack([w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2, w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2,
                     w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2, w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2], -1)


def qaxis(axis, deg):
    axis = np.asarray(axis, float)
    axis = axis / np.linalg.norm(axis)
    h = np.radians(deg) / 2
    return np.array([*(axis * np.sin(h)), np.cos(h)])


def unit(v):
    return v / np.linalg.norm(v, axis=-1, keepdims=True)


def rot_between_batch(a, b):
    """a (3,) or (F,3), b (F,3) -> (F,3,3)"""
    a = np.broadcast_to(a, b.shape)
    out = np.zeros(b.shape[:1] + (3, 3))
    for i in range(b.shape[0]):
        out[i] = rot_between(a[i], b[i])
    return out


def ik_arm(rig, q_base, pelvis, side, wrist_fn, pole, clav_lift_deg=0.0, hand_rot=None, elbow_bias=0.0):
    """re-solve clavicle/upperarm/lowerarm/hand of one arm so the wrist reaches wrist_fn(P, Rw) (F,3).
    q_base (F,N,4) local quats, pelvis (F,3) world pelvis pos.  Returns new q (copy)."""
    F = q_base.shape[0]
    L = quat_to_mat(q_base)
    P, Rw = target_fk(rig, L, pelvis)
    idx = rig.idx
    cl, ua, la, ha, sp = idx["clavicle_" + side], idx["upperarm_" + side], idx["lowerarm_" + side], idx["hand_" + side], idx["spine_03"]
    Rs = Rw[:, sp]
    # extra clavicle lift about the chest's forward axis
    sgn = 1.0 if side == "l" else -1.0
    if clav_lift_deg != 0:
        ang = np.radians(clav_lift_deg * sgn)
        fwdv = np.array([0, 1.0, 0])
        K = np.array([[0, -fwdv[2], fwdv[1]], [fwdv[2], 0, -fwdv[0]], [-fwdv[1], fwdv[0], 0]])
        Rext = np.eye(3) + np.sin(ang) * K + (1 - np.cos(ang)) * K @ K
        Rcl = Rs @ Rext @ np.transpose(Rs, (0, 2, 1)) @ Rw[:, cl]
    else:
        Rcl = Rw[:, cl]
    S = P[:, cl] + Rcl @ (rig.head[ua] - rig.head[cl])
    W = wrist_fn(P, Rw)
    l1 = np.linalg.norm(rig.head[la] - rig.head[ua])
    l2 = np.linalg.norm(rig.head[ha] - rig.head[la])
    d_vec = W - S
    d = np.linalg.norm(d_vec, axis=1)
    d = np.clip(d, abs(l1 - l2) + 1e-3, (l1 + l2) * 0.995)
    u = unit(d_vec)
    a = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
    h = np.sqrt(np.maximum(l1 * l1 - a * a, 1e-8))
    pole_w = np.einsum("fij,j->fi", Rs, pole) if pole.ndim == 1 else pole
    w = pole_w - np.sum(pole_w * u, 1, keepdims=True) * u
    w = unit(w)
    E = S + u * a[:, None] + w * h[:, None]
    dir_ua = unit(E - S)
    dir_fa = unit(W - E)
    d_ua0 = unit(rig.head[la] - rig.head[ua])
    d_fa0 = unit(rig.head[ha] - rig.head[la])
    R_ua = rot_between_batch(d_ua0, dir_ua)
    fa_dir_after_ua = np.einsum("fij,j->fi", R_ua, d_fa0)
    R_fa = np.zeros_like(R_ua)
    for i in range(F):
        R_fa[i] = rot_between(fa_dir_after_ua[i], dir_fa[i]) @ R_ua[i]
    R_h = R_fa if hand_rot is None else R_fa @ hand_rot
    newL = L.copy()
    Rs_T = np.transpose(Rs, (0, 2, 1))
    newL[:, cl] = Rs_T @ Rcl
    newL[:, ua] = np.transpose(Rcl, (0, 2, 1)) @ R_ua
    newL[:, la] = np.transpose(R_ua, (0, 2, 1)) @ R_fa
    newL[:, ha] = np.transpose(R_fa, (0, 2, 1)) @ R_h
    q = q_base.copy()
    for i in (cl, ua, la, ha):
        q[:, i] = fix_quat_continuity(mat_to_quat(newL[:, i]))
    return q


def finger_overrides(rig, side, angs, F, base_angs=FINGER_ANG):
    """absolute local quats for finger bones (rest = relaxed hand baked by make_people); axes from info json"""
    axes = rig.info.get("finger_axes", {})
    ov = {}
    for f, a in angs.items():
        for k in range(3):
            nm = "%s_0%d_%s" % (f, k + 1, side)
            if nm not in axes:
                continue
            extra = a[k] - base_angs[f][k]
            ov[nm] = np.tile(qaxis(axes[nm], extra), (F, 1))
    return ov


def add_pitch(q, rig, bones_deg, F=None):
    """extra local rotation about the bone's X axis (positive = chin up)"""
    q = q.copy()
    for b, deg in bones_deg.items():
        i = rig.idx[b]
        q[:, i] = qmul(q[:, i], qaxis([1, 0, 0], deg))
    return q


def sway(q, pos, rig, amp_deg=1.2, amp_pos=0.008, cycles=1, phase=0.0):
    """periodic side-to-side train sway: roll spine + lateral pelvis shift (loops if cycles is an integer)"""
    F = q.shape[0]
    t = np.linspace(0, 1, F)
    s = np.sin(2 * np.pi * (cycles * t + phase))
    q = q.copy()
    pos = pos.copy()
    for b, k in (("spine_01", 0.5), ("spine_02", 0.6), ("spine_03", 0.4)):
        i = rig.idx[b]
        for f in range(F):
            q[f, i] = qmul(q[f, i], qaxis([0, 1, 0], amp_deg * k * s[f]))
    pos[:, 0] += amp_pos * s
    return q, pos


def build_derived(clips, rig, add, want, ROOT_Z):
    if want("turn_left_90") and "turn_right_90" in clips:
        c = clips["turn_right_90"]
        q, pos, ov = mirror_clip(c, rig)
        m = dict(c["meta"])
        m["yaw_delta_deg"] = -m.get("yaw_delta_deg", -90.0)
        add("turn_left_90", q, pos, m, False, "turn", ground=False, overrides=ov)

    def base(name):
        c = clips[name]
        return c["q"], c["pos"].copy(), c["meta"]

    shoulder_rest = {s: rig.head[rig.idx["upperarm_" + s]] for s in "lr"}
    pel_rest = rig.head[rig.idx["pelvis"]]
    ZERO_ROOT = np.array([0, 0, 0.0])

    # ---- hold overhead rail (right hand up), grip fingers
    for side, nm in (("r", "stand_hold"), ("l", "stand_hold_l")):
        if not want(nm) or "idle_stand_3" not in clips:
            continue
        q0, pos0, m0 = base("idle_stand_3")
        sgn = 1.0 if side == "r" else -1.0   # right side is +x in the final frame
        tgt = shoulder_rest[side] + np.array([-0.03 * sgn, 0.22, 0.44])
        tgt_fixed = lambda P, Rw, tgt=tgt, pos0=pos0: np.tile(tgt, (P.shape[0], 1)) + (pos0 - pos0.mean(0)) * np.array([1, 1, 0])
        q = ik_arm(rig, q0, pos0, side, tgt_fixed, np.array([0.5 * sgn, -0.4, -1.0]), clav_lift_deg=8.0)
        q, pos = sway(q, pos0, rig, 1.5, 0.006, cycles=1)
        # a slight lean toward the hand (holding on)
        ov = finger_overrides(rig, side, GRIP_ANG, q.shape[0])
        m = dict(m0)
        m["note"] = "one hand (%s) gripping an overhead rail, train sway" % side
        add(nm, q, pos, m, True, "hold", ground=False, overrides=ov)

    # ---- vertical pole at shoulder height
    for side, nm in (("r", "stand_pole"), ("l", "stand_pole_l")):
        if not want(nm) or "idle_stand_2" not in clips:
            continue
        q0, pos0, m0 = base("idle_stand_2")
        sgn = 1.0 if side == "r" else -1.0
        tgt = shoulder_rest[side] + np.array([-0.02 * sgn, 0.34, -0.03])
        fn = lambda P, Rw, tgt=tgt: np.tile(tgt, (P.shape[0], 1))
        q = ik_arm(rig, q0, pos0, side, fn, np.array([0.6 * sgn, -0.2, -1.0]), clav_lift_deg=2.0)
        q, pos = sway(q, pos0, rig, 1.0, 0.005, cycles=1)
        ov = finger_overrides(rig, side, GRIP_ANG, q.shape[0])
        m = dict(m0)
        m["note"] = "one hand gripping a vertical pole at chest height"
        add(nm, q, pos, m, True, "hold", ground=False, overrides=ov)

    # ---- escalator: one hand on the moving handrail beside the body
    for side, nm in (("r", "escalator_stand"), ("l", "escalator_stand_l")):
        if not want(nm) or "idle_stand_1" not in clips:
            continue
        q0, pos0, m0 = base("idle_stand_1")
        sgn = 1.0 if side == "r" else -1.0
        tgt = np.array([0.40 * sgn, 0.10, 0.96])
        fn = lambda P, Rw, tgt=tgt, pos0=pos0: np.tile(tgt, (P.shape[0], 1)) + (pos0 - pos0.mean(0)) * np.array([1, 1, 0]) * 0.5
        q = ik_arm(rig, q0, pos0, side, fn, np.array([0.6 * sgn, -0.5, -1.0]), clav_lift_deg=0.0)
        q, pos = sway(q, pos0, rig, 0.6, 0.003, cycles=2, phase=0.3)
        ov = finger_overrides(rig, side, GRIP_ANG, q.shape[0])
        # hand lies flat-ish on the rail: only a light grip
        ov = finger_overrides(rig, side, {k: tuple(0.6 * a for a in v) for k, v in GRIP_ANG.items()}, q.shape[0])
        m = dict(m0)
        m["note"] = "standing on an escalator step, %s hand resting on the handrail" % side
        add(nm, q, pos, m, True, "escalator", ground=False, overrides=ov)

    # ---- looking at a phone: standing and seated
    def phone(nm, basename, kind, chest_off_r, chest_off_l, head_pitch):
        if not want(nm) or basename not in clips:
            return
        q0, pos0, m0 = base(basename)
        q = q0
        for side, off in (("r", chest_off_r), ("l", chest_off_l)):
            sgn = 1.0 if side == "r" else -1.0
            def fn(P, Rw, off=off):
                sp = rig.idx["spine_03"]
                return P[:, sp] + np.einsum("fij,j->fi", Rw[:, sp], off)
            q = ik_arm(rig, q, pos0, side, fn, np.array([0.7 * sgn, -0.5, -1.0]), clav_lift_deg=0.0)
        q = add_pitch(q, rig, head_pitch)
        ov = {}
        ov.update(finger_overrides(rig, "r", PHONE_ANG, q.shape[0]))
        ov.update(finger_overrides(rig, "l", TOUCH_ANG, q.shape[0]))
        m = dict(m0)
        m["note"] = "looking down at a phone held in front of the chest"
        add(nm, q, pos0, m, True, kind, ground=False, overrides=ov)

    phone("idle_phone", "idle_stand_1", "idle", np.array([0.06, 0.30, -0.06]), np.array([-0.05, 0.27, -0.10]),
          {"neck_01": -12, "head": -14})
    phone("sit_phone", "sit_idle_1", "sit", np.array([0.06, 0.28, -0.08]), np.array([-0.05, 0.25, -0.12]),
          {"neck_01": -12, "head": -14})
