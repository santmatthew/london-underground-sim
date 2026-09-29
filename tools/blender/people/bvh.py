"""Minimal BVH reader + forward kinematics with numpy (CMU mocap, Y up, +Z forward, +X = character's left)."""
import numpy as np


class BVH:
    def __init__(self, path):
        self.path = path
        txt = open(path).read()
        head, motion = txt.split("MOTION")
        self.names = []
        self.parent = []
        self.offset = []
        self.channels = []
        stack = []
        cur = -1
        toks = head.replace("{", " { ").replace("}", " } ").split()
        i = 0
        while i < len(toks):
            t = toks[i]
            if t in ("ROOT", "JOINT"):
                self.names.append(toks[i + 1])
                self.parent.append(stack[-1] if stack else -1)
                self.offset.append(None)
                self.channels.append(None)
                cur = len(self.names) - 1
                i += 2
            elif t == "End":
                # End Site { OFFSET x y z }
                self._endsite = getattr(self, "_endsite", {})
                self._endsite[cur] = [float(toks[i + 4]), float(toks[i + 5]), float(toks[i + 6])]
                i += 8
                continue
            elif t == "{":
                stack.append(cur)
                i += 1
            elif t == "}":
                stack.pop()
                cur = stack[-1] if stack else -1
                i += 1
            elif t == "OFFSET":
                idx = len(self.names) - 1
                # only assign for the joint whose block we're in (End Site handled above)
                self.offset[cur] = [float(toks[i + 1]), float(toks[i + 2]), float(toks[i + 3])]
                i += 4
            elif t == "CHANNELS":
                n = int(toks[i + 1])
                self.channels[cur] = toks[i + 2:i + 2 + n]
                i += 2 + n
            else:
                i += 1
        self.offset = np.array(self.offset, dtype=np.float64)
        lines = motion.strip().splitlines()
        self.nframes = int(lines[0].split()[-1])
        self.frame_time = float(lines[1].split()[-1])
        data = np.array([[float(x) for x in l.split()] for l in lines[2:2 + self.nframes]], dtype=np.float64)
        self.data = data
        self.nj = len(self.names)
        self.idx = {n: i for i, n in enumerate(self.names)}
        # channel layout
        self.chan_slices = []
        c = 0
        for ch in self.channels:
            self.chan_slices.append((c, c + len(ch)))
            c += len(ch)
        self.children = [[] for _ in range(self.nj)]
        for j, p in enumerate(self.parent):
            if p >= 0:
                self.children[p].append(j)

    def fps(self):
        return 1.0 / self.frame_time

    def local_rotations(self):
        """returns (F, J, 3, 3) local rotation matrices and (F, 3) root position"""
        F = self.nframes
        R = np.tile(np.eye(3), (F, self.nj, 1, 1))
        rootpos = np.zeros((F, 3))
        for j in range(self.nj):
            a, b = self.chan_slices[j]
            chans = self.channels[j]
            m = np.tile(np.eye(3), (F, 1, 1))
            for k, cn in enumerate(chans):
                v = self.data[:, a + k]
                if cn.endswith("position"):
                    ax = "XYZ".index(cn[0])
                    if j == 0:
                        rootpos[:, ax] = v
                else:
                    ang = np.radians(v)
                    ax = cn[0]
                    c, s = np.cos(ang), np.sin(ang)
                    r = np.tile(np.eye(3), (F, 1, 1))
                    if ax == "X":
                        r[:, 1, 1] = c; r[:, 1, 2] = -s; r[:, 2, 1] = s; r[:, 2, 2] = c
                    elif ax == "Y":
                        r[:, 0, 0] = c; r[:, 0, 2] = s; r[:, 2, 0] = -s; r[:, 2, 2] = c
                    else:
                        r[:, 0, 0] = c; r[:, 0, 1] = -s; r[:, 1, 0] = s; r[:, 1, 1] = c
                    # channels are listed in application order (first listed = outermost)
                    m = m @ r
            R[:, j] = m
        return R, rootpos

    def fk(self):
        """world rotations (F,J,3,3), world positions (F,J,3)"""
        R, rp = self.local_rotations()
        F = self.nframes
        WR = np.zeros_like(R)
        WP = np.zeros((F, self.nj, 3))
        for j in range(self.nj):
            p = self.parent[j]
            if p < 0:
                WR[:, j] = R[:, j]
                WP[:, j] = rp + 0.0
            else:
                WR[:, j] = WR[:, p] @ R[:, j]
                WP[:, j] = WP[:, p] + np.einsum("fij,j->fi", WR[:, p], self.offset[j])
        return WR, WP
