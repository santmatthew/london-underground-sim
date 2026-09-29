"""contact sheet of stick figures: bvh_sheet.py file.bvh out.png t0 t1 step_s"""
import sys; sys.path.insert(0, "tools/blender/people")
import numpy as np, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from bvh import BVH
f, out, t0, t1, st = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5])
b = BVH(f); WR, WP = b.fk()
fps = b.fps()
times = np.arange(t0, t1, st)
n = len(times); cols = min(n, 10); rows = (n + cols - 1) // cols
fig, axs = plt.subplots(rows, cols, figsize=(cols * 1.6, rows * 2.4), squeeze=False)
# centre on first frame hips (x,z)
for k, t in enumerate(times):
    ax = axs[k // cols][k % cols]
    fr = min(int(t * fps), b.nframes - 1)
    P = WP[fr] - np.array([WP[fr, 0, 0], 0, WP[fr, 0, 2]])
    for j, p in enumerate(b.parent):
        if p >= 0:
            # side view: forward (z) horizontal, y vertical
            ax.plot([P[p, 2], P[j, 2]], [P[p, 1], P[j, 1]], "-", lw=1.2, color="k" if "Left" not in b.names[j] else "r")
    ax.set_xlim(-14, 14); ax.set_ylim(-1, 27); ax.set_aspect("equal"); ax.axis("off")
    ax.set_title("%.1fs" % t, fontsize=7)
plt.tight_layout(); plt.savefig(out, dpi=80)
