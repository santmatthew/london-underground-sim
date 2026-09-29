"""Clip extraction / looping / in-placing on top of retarget.py (numpy only)."""
import numpy as np
from retarget import *

FPS = 30.0


class Clip:
    def __init__(self, name, q, pos, rig):
        self.name = name
        self.q = q            # (F, N, 4)  local rotations, x y z w
        self.pos = pos        # (F, 3)  pelvis world position in the final Blender frame (ref skeleton scale)
        self.rig = rig
        self.loop = False
        self.meta = {}
        self.overrides = {}   # bone -> (F,4) constant/animated overrides applied late (finger poses etc.)


def slerp_batch(q0, q1, t):
    d = np.sum(q0 * q1, axis=-1, keepdims=True)
    q1 = np.where(d < 0, -q1, q1)
    d = np.abs(d)
    d = np.clip(d, -1, 1)
    om = np.arccos(d)
    so = np.sin(om)
    small = so < 1e-6
    a = np.where(small, 1 - t, np.sin((1 - t) * om) / np.where(small, 1, so))
    b = np.where(small, t, np.sin(t * om) / np.where(small, 1, so))
    r = a * q0 + b * q1
    return r / np.linalg.norm(r, axis=-1, keepdims=True)


def resample(q, pos, f0, f1, n_out, src_fps):
    """sample n_out+1 frames uniformly from fractional frame f0..f1 (source frame indices)"""
    ts = np.linspace(f0, f1, n_out + 1)
    i0 = np.clip(np.floor(ts).astype(int), 0, q.shape[0] - 1)
    i1 = np.clip(i0 + 1, 0, q.shape[0] - 1)
    a = (ts - i0)[:, None, None]
    qq = slerp_batch(q[i0], q[i1], a)
    pp = pos[i0] * (1 - a[:, :, 0]) + pos[i1] * a[:, :, 0]
    return qq, pp


def heading_yaw(src, f0, f1):
    """yaw (about BVH +Y) that rotates the mean hips facing of frames f0..f1 to +Z"""
    R = src.WR[f0:f1, 0]
    fwd = R @ np.array([0, 0, 1.0])
    ang = np.arctan2(fwd[:, 0], fwd[:, 2])
    m = np.arctan2(np.mean(np.sin(ang)), np.mean(np.cos(ang)))
    return m    # rotating by -m; retarget() applies Ry(world_yaw) so pass -m


def travel_yaw(src, f0, f1):
    d = src.WP[f1 - 1, 0] - src.WP[f0, 0]
    return np.arctan2(d[0], d[2])


def ryaw(a):
    return a


def retarget_range(src, rig, f0, f1, yaw):
    """retarget with the source rotated by -yaw about vertical so that heading yaw -> +Z"""
    return retarget(src, rig, world_yaw=-yaw)


def target_fk(rig, L, pelvis_world):
    """world positions (F,N,3) and world pose rotations (F,N,3,3) with root at rest"""
    F = L.shape[0]
    N = len(rig.names)
    Rw = np.zeros((F, N, 3, 3))
    P = np.zeros((F, N, 3))
    for i in range(N):
        p = rig.parent[i]
        if p < 0:
            Rw[:, i] = L[:, i]
            P[:, i] = rig.head[i]
        else:
            Rw[:, i] = Rw[:, p] @ L[:, i]
            P[:, i] = P[:, p] + Rw[:, p] @ (rig.head[i] - rig.head[p])
    # pelvis is a child of Root: replace its position by the animated one and re-propagate
    pi = rig.idx["pelvis"]
    delta = pelvis_world - P[:, pi]
    stack = [pi]
    while stack:
        i = stack.pop()
        P[:, i] += delta
        stack.extend(rig.children[i])
    return P, Rw


def ground_offset(rig, L, pelvis_world, pct=8):
    P, _ = target_fk(rig, L, pelvis_world)
    la = P[:, rig.idx["foot_l"], 2]
    ra = P[:, rig.idx["foot_r"], 2]
    lo = np.minimum(la, ra)
    rest = rig.head[rig.idx["foot_l"]][2]
    return rest - np.percentile(lo, pct)


def detrend_loop(q, pos):
    """make last frame == first frame: distribute the mismatch linearly over the clip"""
    F = q.shape[0]
    n = F - 1
    t = np.linspace(0, 1, F)[:, None, None]
    q0 = q[0]
    qn = q[-1]
    # D = qn^-1 * q0  (right-multiplied correction)
    def qmul(a, b):
        x1, y1, z1, w1 = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
        x2, y2, z2, w2 = b[..., 0], b[..., 1], b[..., 2], b[..., 3]
        return np.stack([w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2, w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2,
                         w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2, w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2], -1)
    qn_inv = qn * np.array([-1, -1, -1, 1.0])
    D = qmul(qn_inv, q0)
    D = np.where((D[..., 3] < 0)[..., None], -D, D)
    ident = np.zeros_like(D)
    ident[..., 3] = 1
    Dt = slerp_batch(np.broadcast_to(ident, (F,) + D.shape), np.broadcast_to(D, (F,) + D.shape), t)
    q2 = qmul(q, Dt)
    pos2 = pos - (pos[-1] - pos[0])[None, :] * np.linspace(0, 1, F)[:, None]
    return q2, pos2


def walk_cycle(src, rig, t0=None, t1=None, which=0, name="walk"):
    """extract one full stride starting at left-foot-forward from the steady part of a walking clip"""
    fps = src.fps
    n = src.nf
    a = int(n * 0.1) if t0 is None else int(t0 * fps)
    b = int(n * 0.95) if t1 is None else int(t1 * fps)
    yaw = travel_yaw(src, a, b)
    # foot separation along the travel direction
    b_ = src.b
    fwd = np.array([np.sin(yaw), 0, np.cos(yaw)])
    lf = src.WP[:, b_.idx["LeftFoot"]] @ fwd
    rf = src.WP[:, b_.idx["RightFoot"]] @ fwd
    s = lf - rf
    k = int(fps / 30 * 4) | 1
    ker = np.ones(k) / k
    s = np.convolve(s, ker, mode="same")
    peaks = [i for i in range(a + 2, b - 2) if s[i] >= s[i - 1] and s[i] > s[i + 1] and s[i] > 0.15 * s[a:b].max()]
    # merge close peaks
    merged = []
    for p in peaks:
        if merged and p - merged[-1] < fps * 0.4:
            if s[p] > s[merged[-1]]:
                merged[-1] = p
        else:
            merged.append(p)
    if len(merged) < 2:
        raise RuntimeError("no stride found in %s" % src.b.path)
    periods = np.diff(merged)
    med = np.median(periods)
    cand = [i for i in range(len(periods)) if abs(periods[i] - med) < 0.12 * med]
    i = cand[len(cand) // 2] if which == 0 else cand[min(which, len(cand) - 1)]
    f0, f1 = merged[i], merged[i + 1]
    L, Rw, pos, sc = retarget(src, rig, world_yaw=-yaw)
    T = (f1 - f0) / fps
    nout = int(round(T * FPS))
    q = mat_to_quat(L)
    q = fix_quat_continuity(q)
    qq, pp = resample(q, pos, f0, f0 + (f1 - f0), nout, fps)
    disp = pp[-1] - pp[0]
    qq, pp = detrend_loop(qq, pp)
    # yaw is normalised so travel is along +Y (blender final frame); remove average sway offset in x
    pp[:, 0] -= pp[:, 0].mean()
    pp[:, 1] -= pp[:, 1].mean()
    speed = float(np.linalg.norm(disp[:2])) / (nout / FPS)
    return qq, pp, dict(stride_speed_mps=speed, duration=nout / FPS, frames=nout + 1, src=src.b.path.split("/")[-1],
                        src_range=[f0 / fps, f1 / fps], scale=float(sc))


def loop_search(src, rig, t0, t1, dmin, dmax, feature_bones=None, step_s=0.1, exclude=None):
    """find (f0,f1) in [t0,t1] with duration in [dmin,dmax] whose end pose best matches the start pose."""
    fps = src.fps
    yaw = heading_yaw(src, int(t0 * fps), int(t1 * fps))
    L, Rw, pos, sc = retarget(src, rig, world_yaw=-yaw)
    names = feature_bones or ["pelvis", "spine_02", "spine_03", "neck_01", "head", "upperarm_l", "upperarm_r",
                              "lowerarm_l", "lowerarm_r", "thigh_l", "thigh_r", "calf_l", "calf_r"]
    idx = [rig.idx[n] for n in names]
    feat = Rw[:, idx].reshape(Rw.shape[0], -1)
    feat = np.concatenate([feat, pos[:, 2:3] * 3.0, (pos[:, :2] - pos[:, :2].mean(0)) * 2.0], 1)
    st = int(step_s * fps)
    cand = np.arange(int(t0 * fps), int(t1 * fps), st)
    best = (1e9, None)
    res = []
    for i, a in enumerate(cand):
        for b in cand[i + 1:]:
            d = (b - a) / fps
            if d < dmin or d > dmax:
                continue
            e = np.sum((feat[a] - feat[b]) ** 2)
            # velocity match (4 frames = 1/30 s)
            va = feat[min(a + 4, len(feat) - 1)] - feat[a]
            vb = feat[min(b + 4, len(feat) - 1)] - feat[b]
            e += 4.0 * np.sum((va - vb) ** 2)
            # prefer motion that is not completely frozen
            act = np.mean(np.abs(np.diff(feat[a:b:4], axis=0)))
            res.append((e / (1.0 + 20 * act), a, b))
    res.sort()
    return res, L, pos, sc


def make_loop_clip(src, rig, f0, f1, L, pos, name):
    fps = src.fps
    T = (f1 - f0) / fps
    nout = int(round(T * FPS))
    q = fix_quat_continuity(mat_to_quat(L))
    qq, pp = resample(q, pos, f0, f1, nout, fps)
    qq, pp = detrend_loop(qq, pp)
    pp[:, 0] -= pp[:, 0].mean()
    pp[:, 1] -= pp[:, 1].mean()
    return qq, pp, dict(duration=nout / FPS, frames=nout + 1, src=src.b.path.split("/")[-1], src_range=[f0 / fps, f1 / fps])


def make_once_clip(src, rig, t0, t1, L, pos, name, keep_start_xy=True):
    fps = src.fps
    f0 = t0 * fps
    f1 = t1 * fps
    nout = int(round((f1 - f0) / fps * FPS))
    q = fix_quat_continuity(mat_to_quat(L))
    qq, pp = resample(q, pos, f0, f1, nout, fps)
    pp = pp.copy()
    pp[:, :2] -= pp[0, :2]
    return qq, pp, dict(duration=nout / FPS, frames=nout + 1, src=src.b.path.split("/")[-1], src_range=[t0, t1])
