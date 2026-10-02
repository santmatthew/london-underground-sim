#!/usr/bin/env python3
"""Report for tools/fps_experiment.sh: per rung of the ladder the frame-rate statistics, how much it varies over the 5 minutes (per 30 s bucket), the GPU / CPU side
(clocks, power, temperature, throttle bits), plus plots. usage: fps_report.py [run_dir]   (default: the latest run)
Writes <run>/report.md, <run>/frametimes.png (timeline per rung), <run>/distribution.png (box plot) and <run>/drift.png (fps per 30 s bucket)."""
import csv
import os
import statistics as st
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
run = sys.argv[1] if len(sys.argv) > 1 else open(os.path.join(ROOT, "build", "fps", "latest")).read().strip()
if not os.path.isabs(run):
    run = os.path.join(ROOT, run)
ORDER = ["L0", "L1", "L2", "L3", "L4", "L5", "L5_open", "L3_bug", "L5_bug", "L6_game"]
TITLES = {"L0": "L0 empty scene", "L1": "L1 architecture only", "L2": "L2 + dressing", "L3": "L3 + signs (static station)", "L4": "L4 + trains", "L5": "L5 + crowd (Oxford Circus)",
          "L5_open": "L5 open-air (Acton Town)", "L3_bug": "L3 with the old map redraw", "L5_bug": "L5 with the old map redraw", "L6_game": "L6 whole game (autopilot, vsync off)"}


def num(x):
    try:
        return float(x)
    except ValueError:
        return float("nan")


def load(path):
    rows = list(csv.DictReader(open(path)))
    return {k: [num(r[k]) for r in rows] for k in rows[0]} if rows else {}


def pct(v, p):
    s = sorted(v)
    return s[min(len(s) - 1, int(len(s) * p))]


def stats(d, skip):
    idx = [i for i, t in enumerate(d["t_s"]) if t >= skip]
    ft = [d["frame_ms"][i] for i in idx]
    out = {"frames": len(ft)}
    if not ft:
        return out
    out["fps_mean"] = 1000.0 * len(ft) / sum(ft)
    out["p50"] = pct(ft, 0.5)
    out["p95"] = pct(ft, 0.95)
    out["p99"] = pct(ft, 0.99)
    out["max"] = max(ft)
    out["fps_1low"] = 1000.0 / out["p99"]
    out["over33"] = sum(1 for v in ft if v > 33.4)
    out["over50"] = sum(1 for v in ft if v > 50.0)
    out["over100"] = sum(1 for v in ft if v > 100.0)
    out["sd"] = st.pstdev(ft)
    for k in ("gpu_ms", "render_cpu_ms", "draws", "prims", "vram_mb", "mem_mb"):
        v = [d[k][i] for i in idx]
        out[k] = st.median(v)
    # fps per 30 s bucket
    buckets = {}
    for i in idx:
        buckets.setdefault(int(d["t_s"][i] // 30), []).append(d["frame_ms"][i])
    full = [(b, v) for b, v in sorted(buckets.items()) if sum(v) >= 29000.0]          # drop the first and last partial 30 s buckets
    out["buckets"] = [(b, 1000.0 * len(v) / sum(v)) for b, v in full]
    return out


def sysstats(path):
    if not os.path.exists(path):
        return {}
    d = load(path)
    if not d:
        return {}
    out = {}
    for k in ("gpu_sm_mhz", "gpu_w", "gpu_c", "gpu_util", "cpu_avg_mhz", "cpu_c", "cpu_util"):
        v = [x for x in d.get(k, []) if x == x]
        if v:
            out[k] = (min(v), st.mean(v), max(v))
    rows = list(csv.DictReader(open(path)))
    out["throttle"] = sorted({r["throttle"] for r in rows})
    out["pstate"] = sorted({r["pstate"] for r in rows})
    return out


data, sysd = {}, {}
for r in ORDER:
    p = os.path.join(run, r + ".csv")
    if os.path.exists(p):
        data[r] = load(p)
        sysd[r] = sysstats(os.path.join(run, r + "_sys.csv"))
md = ["# Frame-rate experiment", "", "Run: `%s`. Each rung runs 300 s with a scripted walk (hall -> platform and back at 1.6 m/s). The first 5 s (40 s for the whole game, which builds a station first) are not counted." % os.path.basename(run), ""]
md += ["| rung | fps mean | frame ms p50 | p95 | p99 | max | 1% low fps | frames >33 ms | >50 ms | >100 ms | GPU ms p50 | render CPU ms p50 | draws | M tris | fps range over 30 s buckets |", "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
S = {}
for r, d in data.items():
    s = stats(d, 40.0 if r == "L6_game" else 5.0)
    S[r] = s
    if s["frames"] == 0:
        continue
    bk = [b[1] for b in s["buckets"]]
    md.append("| %s | %.1f | %.2f | %.2f | %.2f | %.1f | %.1f | %d | %d | %d | %.2f | %.2f | %.0f | %.2f | %.0f - %.0f |" % (
        TITLES[r], s["fps_mean"], s["p50"], s["p95"], s["p99"], s["max"], s["fps_1low"], s["over33"], s["over50"], s["over100"], s["gpu_ms"], s["render_cpu_ms"], s["draws"],
        s["prims"] / 1e6, min(bk) if bk else 0, max(bk) if bk else 0))
md += ["", "## Machine during each rung", "", "| rung | GPU SM clock MHz min / mean / max | GPU W mean / max | GPU C max | GPU util % mean | P-states | throttle bits seen | CPU MHz mean | CPU C max | CPU util % mean |", "|---|---|---|---|---|---|---|---|---|---|"]
for r, s in sysd.items():
    if not s:
        continue
    f = lambda k, i: s[k][i] if k in s else float("nan")
    md.append("| %s | %.0f / %.0f / %.0f | %.1f / %.1f | %.0f | %.0f | %s | %s | %.0f | %.0f | %.0f |" % (
        TITLES[r], f("gpu_sm_mhz", 0), f("gpu_sm_mhz", 1), f("gpu_sm_mhz", 2), f("gpu_w", 1), f("gpu_w", 2), f("gpu_c", 2), f("gpu_util", 1), ",".join(s["pstate"]), ",".join(s["throttle"]),
        f("cpu_avg_mhz", 1), f("cpu_c", 2), f("cpu_util", 1)))
md += ["", "Throttle bits (nvidia-smi `clocks_throttle_reasons.active`): 0x1 = GPU idle, 0x2 = application clocks, 0x4 = software power cap, 0x8 = hardware slowdown, 0x20 = software thermal slowdown, 0x40 = hardware thermal slowdown, 0x80 = power brake.", ""]
open(os.path.join(run, "report.md"), "w").write("\n".join(md) + "\n")
print("\n".join(md))

# plots
cols = [r for r in ORDER if r in S and S[r]["frames"] > 0]
fig, axs = plt.subplots(len(cols), 1, figsize=(12, 1.6 * len(cols) + 1), sharex=True)
axs = axs if len(cols) > 1 else [axs]
for ax, r in zip(axs, cols):
    d = data[r]
    t = d["t_s"]
    ax.plot(t, d["frame_ms"], lw=0.4, color="#1f77b4")
    ax.set_ylabel(r, rotation=0, ha="right", va="center", fontsize=8)
    ax.set_ylim(0, min(max(d["frame_ms"]) * 1.05, 120))
    ax.axhline(16.7, color="#2ca02c", lw=0.5)
    ax.axhline(33.3, color="#d62728", lw=0.5)
axs[-1].set_xlabel("seconds (frame time in ms; green = 60 fps, red = 30 fps)")
fig.tight_layout()
fig.savefig(os.path.join(run, "frametimes.png"), dpi=110)

fig, ax = plt.subplots(figsize=(11, 5))
ax.boxplot([[v for v, t in zip(data[r]["frame_ms"], data[r]["t_s"]) if t >= (40 if r == "L6_game" else 5)] for r in cols], tick_labels=cols, showfliers=False, whis=(1, 99))
ax.set_ylabel("frame time ms (box = 25-75 %, whiskers 1-99 %)")
ax.axhline(16.7, color="#2ca02c", lw=0.6)
ax.axhline(33.3, color="#d62728", lw=0.6)
fig.tight_layout()
fig.savefig(os.path.join(run, "distribution.png"), dpi=110)

fig, ax = plt.subplots(figsize=(11, 5))
for r in cols:
    b = S[r]["buckets"]
    ax.plot([x[0] * 30 for x in b], [x[1] for x in b], marker="o", ms=3, label=r)
ax.set_xlabel("seconds into the run")
ax.set_ylabel("fps (30 s buckets)")
ax.set_yscale("log")
ax.legend(fontsize=7, ncol=2)
fig.tight_layout()
fig.savefig(os.path.join(run, "drift.png"), dpi=110)
print("plots written to", run)
