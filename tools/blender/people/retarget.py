"""Retarget CMU BVH motion onto the MPFB game_engine skeleton (world-space delta transfer with rest-pose alignment).

All target maths is done in the *final Blender frame* used by make_people.py (Z up, character faces +Y, left = -X).
Because make_people.py normalises every bone's rest orientation to identity, the local rotation quaternions computed
here are directly the values of Godot's bone tracks (no axis swizzling needed).
"""
import json
import numpy as np
from bvh import BVH

# BVH (Y up, +Z fwd, +X left) -> final Blender frame (Z up, +Y fwd, -X left)
C = np.array([[-1.0, 0, 0], [0, 0, 1.0], [0, 1.0, 0]])

# target bone -> (source joint, target direction child ('TAIL' = use recorded original tail), source direction child)
def _lr(t, s, tchild, schild):
    out = []
    for side_t, side_s in (("l", "Left"), ("r", "Right")):
        out.append((t.replace("#", side_t), s.replace("#", side_s), tchild.replace("#", side_t), schild.replace("#", side_s)))
    return out

MAP = [
    ("pelvis", "Hips", "spine_01", "Spine"),
    ("spine_01", "LowerBack", "spine_02", "Spine"),          # LowerBack->Spine
    ("spine_02", "Spine", "spine_03", "Spine1"),
    ("spine_03", "Spine1", "neck_01", "Neck1"),
    ("neck_01", "Neck1", "head", "Head"),
    ("head", "Head", "TAIL", "Head:END"),
]
for t, s, tc, sc in [
    ("clavicle_#", "#Shoulder", "upperarm_#", "#Arm"),
    ("upperarm_#", "#Arm", "lowerarm_#", "#ForeArm"),
    ("lowerarm_#", "#ForeArm", "hand_#", "#Hand"),
    ("hand_#", "#Hand", "middle_01_#", "#HandIndex1"),
    ("thigh_#", "#UpLeg", "calf_#", "#Leg"),
    ("calf_#", "#Leg", "foot_#", "#Foot"),
    ("foot_#", "#Foot", "ball_#", "#ToeBase"),
    ("ball_#", "#ToeBase", "TAIL", "#ToeBase:END"),
]:
    MAP += _lr(t, s, tc, sc)
# source names are 'LeftUpLeg' etc; CMU uses 'LeftShoulder', 'LeftArm', 'LeftHandIndex1', 'LeftToeBase'


def rot_between(a, b):
    """minimal rotation matrix taking unit vector a to unit vector b"""
    a = a / np.linalg.norm(a)
    b = b / np.linalg.norm(b)
    v = np.cross(a, b)
    c = float(np.dot(a, b))
    if c > 0.999999:
        return np.eye(3)
    if c < -0.999999:
        # 180 deg about any perpendicular axis
        ax = np.cross(a, [1, 0, 0])
        if np.linalg.norm(ax) < 1e-6:
            ax = np.cross(a, [0, 1, 0])
        ax /= np.linalg.norm(ax)
        return 2 * np.outer(ax, ax) - np.eye(3)
    vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + vx + vx @ vx * (1.0 / (1.0 + c))


def mat_to_quat(R):
    """R (...,3,3) -> quaternion (...,4) x,y,z,w"""
    R = np.asarray(R)
    sh = R.shape[:-2]
    R = R.reshape(-1, 3, 3)
    n = R.shape[0]
    q = np.zeros((n, 4))
    tr = R[:, 0, 0] + R[:, 1, 1] + R[:, 2, 2]
    for i in range(n):
        r = R[i]
        if tr[i] > 0:
            s = np.sqrt(tr[i] + 1.0) * 2
            q[i] = [(r[2, 1] - r[1, 2]) / s, (r[0, 2] - r[2, 0]) / s, (r[1, 0] - r[0, 1]) / s, 0.25 * s]
        elif r[0, 0] > r[1, 1] and r[0, 0] > r[2, 2]:
            s = np.sqrt(1.0 + r[0, 0] - r[1, 1] - r[2, 2]) * 2
            q[i] = [0.25 * s, (r[0, 1] + r[1, 0]) / s, (r[0, 2] + r[2, 0]) / s, (r[2, 1] - r[1, 2]) / s]
        elif r[1, 1] > r[2, 2]:
            s = np.sqrt(1.0 + r[1, 1] - r[0, 0] - r[2, 2]) * 2
            q[i] = [(r[0, 1] + r[1, 0]) / s, 0.25 * s, (r[1, 2] + r[2, 1]) / s, (r[0, 2] - r[2, 0]) / s]
        else:
            s = np.sqrt(1.0 + r[2, 2] - r[0, 0] - r[1, 1]) * 2
            q[i] = [(r[0, 2] + r[2, 0]) / s, (r[1, 2] + r[2, 1]) / s, 0.25 * s, (r[1, 0] - r[0, 1]) / s]
    q /= np.linalg.norm(q, axis=1, keepdims=True)
    return q.reshape(sh + (4,))


def quat_to_mat(q):
    q = np.asarray(q)
    sh = q.shape[:-1]
    q = q.reshape(-1, 4)
    x, y, z, w = q[:, 0], q[:, 1], q[:, 2], q[:, 3]
    R = np.zeros((q.shape[0], 3, 3))
    R[:, 0, 0] = 1 - 2 * (y * y + z * z); R[:, 0, 1] = 2 * (x * y - z * w); R[:, 0, 2] = 2 * (x * z + y * w)
    R[:, 1, 0] = 2 * (x * y + z * w); R[:, 1, 1] = 1 - 2 * (x * x + z * z); R[:, 1, 2] = 2 * (y * z - x * w)
    R[:, 2, 0] = 2 * (x * z - y * w); R[:, 2, 1] = 2 * (y * z + x * w); R[:, 2, 2] = 1 - 2 * (x * x + y * y)
    return R.reshape(sh + (3, 3))


def fix_quat_continuity(q):
    """q (F,...,4): flip signs so consecutive frames are in the same hemisphere"""
    q = q.copy()
    for f in range(1, q.shape[0]):
        d = np.sum(q[f] * q[f - 1], axis=-1)
        q[f] = np.where((d < 0)[..., None], -q[f], q[f])
    return q


def axis_angle_mat(axis, ang):
    axis = np.asarray(axis, float)
    axis = axis / np.linalg.norm(axis)
    K = np.array([[0, -axis[2], axis[1]], [axis[2], 0, -axis[0]], [-axis[1], axis[0], 0]])
    return np.eye(3) + np.sin(ang) * K + (1 - np.cos(ang)) * K @ K


class Rig:
    """target skeleton (reference character) from person_NN.info.json"""

    def __init__(self, info_path):
        info = json.load(open(info_path))
        self.info = info
        self.names = info["bone_order"]
        self.idx = {n: i for i, n in enumerate(self.names)}
        rig = info["rig"]
        self.parent = [self.idx[rig[n]["parent"]] if rig[n]["parent"] else -1 for n in self.names]
        self.head = np.array([rig[n]["head"] for n in self.names])
        self.tail = np.array([rig[n]["tail_orig"] for n in self.names])
        self.height = info["height_m"]
        self.children = [[] for _ in self.names]
        for i, p in enumerate(self.parent):
            if p >= 0:
                self.children[p].append(i)

    def bone_dir(self, name, child):
        i = self.idx[name]
        if child == "TAIL":
            d = self.tail[i] - self.head[i]
        else:
            d = self.head[self.idx[child]] - self.head[i]
        return d / np.linalg.norm(d)

    def leg_length(self):
        # hip joint -> ankle joint (thigh + calf lengths)
        t = self.head[self.idx["thigh_l"]]
        c = self.head[self.idx["calf_l"]]
        f = self.head[self.idx["foot_l"]]
        return np.linalg.norm(c - t) + np.linalg.norm(f - c)


class Source:
    def __init__(self, path, skip=None):
        self.b = BVH(path)
        b = self.b
        WR, WP = b.fk()
        if skip is None:
            # some CMU files start with an all-zero rest frame
            skip = 0
            while skip < 10 and np.abs(b.data[skip, :3]).max() < 1e-6:
                skip += 1
            skip += 1
        self.WR = WR[skip:]
        self.WP = WP[skip:]
        self.fps = b.fps()
        self.nf = self.WR.shape[0]
        self.leg = np.linalg.norm(b.offset[b.idx["LeftLeg"]]) + np.linalg.norm(b.offset[b.idx["LeftFoot"]])

    def rest_dir(self, joint, child):
        b = self.b
        j = b.idx[joint]
        if child.endswith(":END"):
            off = b._endsite[b.idx[child[:-4]]]
            d = np.array(off)
        else:
            k = b.idx[child]
            # world offset from joint to child at rest (all rest rotations identity)
            d = np.zeros(3)
            # walk up from child to joint accumulating offsets
            cur = k
            while cur != j:
                d = d + b.offset[cur]
                cur = b.parent[cur]
        return d / np.linalg.norm(d)


def retarget(src, rig, world_yaw=None):
    """returns local rotation matrices (F, N, 3, 3) for every target bone (unmapped: identity), pelvis world position (F,3)
    in the target (final Blender) frame at the reference skeleton scale."""
    F = src.nf
    N = len(rig.names)
    Rw = np.tile(np.eye(3), (F, N, 1, 1))     # world pose rotation per target bone (delta * alignment)
    R_src = src.WR
    if world_yaw is not None:
        Ry = np.array([[np.cos(world_yaw), 0, np.sin(world_yaw)], [0, 1, 0], [-np.sin(world_yaw), 0, np.cos(world_yaw)]])
        R_src = Ry @ R_src
    mapped = {}
    for tname, sname, tchild, schild in MAP:
        dt = rig.bone_dir(tname, tchild)
        ds = C @ src.rest_dir(sname, schild)
        A = rot_between(dt, ds)
        if tname.startswith("clavicle"):
            # CMU's clavicle joint sits higher than MPFB's (13 deg up vs 11 deg down at rest): aligning directions would
            # shrug the shoulders permanently, so transfer only the rotation delta here
            A = np.eye(3)
        D = C @ R_src[:, src.b.idx[sname]] @ C.T
        Rw[:, rig.idx[tname]] = D @ A
        mapped[tname] = True
    # unmapped bones inherit their parent's world rotation (local identity)
    order = list(range(N))
    L = np.tile(np.eye(3), (F, N, 1, 1))
    for i in order:
        p = rig.parent[i]
        name = rig.names[i]
        if name in mapped:
            Rp = Rw[:, p] if p >= 0 else np.tile(np.eye(3), (F, 1, 1))
            L[:, i] = np.transpose(Rp, (0, 2, 1)) @ Rw[:, i]
        else:
            Rw[:, i] = Rw[:, p] if p >= 0 else np.eye(3)
            L[:, i] = np.eye(3)
    # pelvis position: source hips scaled by leg-length ratio
    s = rig.leg_length() / src.leg
    hp = src.WP[:, 0].copy()
    if world_yaw is not None:
        hp = (Ry @ hp.T).T
    pos = (C @ hp.T).T * s
    return L, Rw, pos, s
