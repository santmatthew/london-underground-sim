#!/usr/bin/env python3
"""QA for assets/audio: run with build/venv/bin/python tools/audio/qa_audio.py [--quick]

Checks
  * every manifest entry has a file; no orphan .ogg files on disk
  * decoded duration / channel count / sample rate match the manifest
  * clipping (decoded peak >= -0.5 dBFS or runs of near-full-scale samples), silent files
  * loudness sanity per category (speech ~ -16 LUFS, ambience quieter)
  * loops: waveform step across the seam vs typical sample-to-sample step, and RMS of the first
    vs last 100 ms
  * coverage: every station has this/next/alight (+ change clips for interchanges), every
    (line, destination[, via]) service end has terminates / platform_approach / platform_next
  * total size and duration, per category
Exit status 1 when any hard check fails.
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import json
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import dsp  # noqa: E402

ROOT = HERE.parents[1]
OUT = ROOT / "assets" / "audio"


def probe(path):
    p = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
                        "stream=channels,sample_rate,codec_name", "-of", "json", str(path)], capture_output=True)
    return json.loads(p.stdout)["streams"][0]


def analyse(key, entry):
    path = OUT / entry["file"]
    res = dict(key=key, ok=True, msgs=[], warn=[])
    if not path.exists():
        res["ok"] = False
        res["msgs"].append("missing file")
        return res
    info = probe(path)
    x = dsp.load_ogg(path)                       # (n, ch) float32
    ch = x.shape[1]
    dur = x.shape[0] / dsp.SR
    res.update(size=path.stat().st_size, dur=dur, ch=ch)
    if info["codec_name"] != "vorbis":
        res["ok"] = False
        res["msgs"].append(f"codec {info['codec_name']}")
    if int(info["sample_rate"]) != dsp.SR:
        res["ok"] = False
        res["msgs"].append(f"sample rate {info['sample_rate']}")
    if ch != entry["channels"]:
        res["ok"] = False
        res["msgs"].append(f"channels {ch} != manifest {entry['channels']}")
    if abs(dur - entry["duration"]) > 0.05:
        res["ok"] = False
        res["msgs"].append(f"duration {dur:.3f} != manifest {entry['duration']}")
    pk = float(np.max(np.abs(x)))
    res["peak_db"] = float(dsp.lin2db(pk))
    if pk >= 0.944:                              # -0.5 dBFS
        res["ok"] = False
        res["msgs"].append(f"peak {res['peak_db']:.2f} dBFS (clipping risk)")
    hot = np.abs(x) > 0.98
    if hot.any() and (np.convolve(hot.any(axis=1).astype(int), np.ones(3, int), "valid") == 3).any():
        res["ok"] = False
        res["msgs"].append("run of >=3 near-full-scale samples")
    rms = float(np.sqrt(np.mean(x.astype(np.float64) ** 2)))
    if rms < 10 ** (-65 / 20):
        res["ok"] = False
        res["msgs"].append("silent")
    L = dsp.lufs(x)
    res["lufs"] = L
    cat = entry["category"]
    if cat.startswith("speech") and not (-18.0 <= L <= -14.5) and entry["file"].startswith("speech"):
        res["warn"].append(f"speech loudness {L:.1f} LUFS")
    if cat in ("ambience", "crowd", "ambience_3d", "train_interior", "train_exterior") and L > -20:
        res["warn"].append(f"ambience loud: {L:.1f} LUFS")
    if entry["loop"]:
        a = x.astype(np.float64)
        d = np.abs(a[0] - a[-1]).mean()
        steps = np.abs(np.diff(a, axis=0)).mean(axis=1)
        ref = np.percentile(steps, 99.5) + 1e-9
        res["seam"] = float(d / ref)
        n100 = int(0.5 * dsp.SR)
        r0 = 20 * np.log10(np.sqrt(np.mean(a[:n100] ** 2)) + 1e-9)
        r1 = 20 * np.log10(np.sqrt(np.mean(a[-n100:] ** 2)) + 1e-9)
        res["edge_db"] = float(r0 - r1)
        if res["seam"] > 4.0:
            res["ok"] = False
            res["msgs"].append(f"loop seam jump {res['seam']:.2f}x the 99.5th percentile step")
        elif res["seam"] > 2.5:
            res["warn"].append(f"loop seam step {res['seam']:.2f}x the 99.5th percentile step (lossy edge?)")
        if abs(r0 - r1) > 3.0 and entry["category"] != "music":
            res["warn"].append(f"loop edge RMS differs by {r0 - r1:+.1f} dB")
        if entry["duration"] < 5:
            res["warn"].append("very short loop")
    return res


def coverage(man):
    import speech
    net = speech.load_network()
    clips = man["clips"]
    miss = []
    for sid, s in net["stations"].items():
        for k in ("this", "next", "alight"):
            if f"station/{sid}/{k}" not in clips:
                miss.append(f"station/{sid}/{k}")
        ls = s["lines"]
        if len(ls) >= 2:
            if f"station/{sid}/change" not in clips:
                miss.append(f"station/{sid}/change")
            for l in ls:
                if f"station/{sid}/change_ex/{l}" not in clips:
                    miss.append(f"station/{sid}/change_ex/{l}")
    for lid, dest, via in speech.service_destinations(net):
        k = f"{lid}/{dest}" + (f"/via_{speech.slug(via)}" if via else "")
        for pre in ("terminates", "platform_approach", "platform_next"):
            if f"{pre}/{k}" not in clips:
                miss.append(f"{pre}/{k}")
    for name in ("mind_the_gap", "stand_clear_of_the_doors", "stand_clear_doors_closing",
                 "this_train_terminates_here_all_change", "please_alight", "this_train_is_not_in_service",
                 "stand_behind_the_yellow_line", "please_keep_moving_along_the_platform",
                 "please_move_right_down_inside_the_carriages", "please_stand_on_the_right_escalator",
                 "holding_here_for_a_short_while", "delayed_signal_failure", "good_evening", "lost_property",
                 "the_next_train_is", "tunnel_rumble_loop", "platform_ambience_loop", "concourse_ambience_loop",
                 "corridor_ambience_loop", "escalator_loop", "train_interior_run_slow_loop",
                 "train_interior_run_fast_loop", "train_arrive_platform", "train_depart_platform", "door_chime_open",
                 "door_chime_close", "door_slide_open", "door_slide_close", "gate_beep_ok", "gate_beep_error",
                 "gate_flap_open", "gate_flap_close", "escalator_step_on", "busker_loop", "crowd_murmur_dense_loop",
                 "crowd_murmur_light_loop", "wind_gust_tunnel_air_push", "ui_click_soft", "ui_notification_chime",
                 "phone_notification"):
        if name not in clips:
            miss.append(name)
    for s in ("tile", "concrete", "rubber", "metal", "escalator"):
        for i in range(1, 7):
            if f"footstep_{s}_{i}" not in clips:
                miss.append(f"footstep_{s}_{i}")
    return miss


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--jobs", type=int, default=8)
    ap.add_argument("--names", nargs="*")
    a = ap.parse_args()
    man = json.loads((OUT / "manifest.json").read_text())
    clips = man["clips"]
    keys = [k for k in clips if not a.names or any(n in k for n in a.names)]
    fails, warns = [], []
    rows = []
    with cf.ThreadPoolExecutor(max_workers=a.jobs) as ex:
        for r in ex.map(lambda k: analyse(k, clips[k]), keys):
            rows.append(r)
            if not r["ok"]:
                fails.append(r)
            if r["warn"]:
                warns.append(r)
    on_disk = {str(p.relative_to(OUT)) for p in OUT.rglob("*.ogg")}
    listed = {c["file"] for c in clips.values()}
    orphans = sorted(on_disk - listed)
    cov = coverage(man) if not a.names else []

    print(f"files checked: {len(rows)}   manifest clips: {len(clips)}")
    tot = sum(r.get("size", 0) for r in rows)
    print(f"total size: {tot / 1e6:.1f} MB   total duration: {sum(r.get('dur', 0) for r in rows) / 60:.1f} min")
    bycat = defaultdict(lambda: [0, 0, 0.0])
    for r in rows:
        c = clips[r["key"]]["category"]
        bycat[c][0] += 1
        bycat[c][1] += r.get("size", 0)
        bycat[c][2] += r.get("dur", 0)
    print(f"{'category':18s} {'files':>6s} {'MB':>8s} {'minutes':>8s}")
    for c, (n, sz, d) in sorted(bycat.items()):
        print(f"{c:18s} {n:6d} {sz / 1e6:8.2f} {d / 60:8.1f}")
    loops = [r for r in rows if "seam" in r]
    if loops:
        print("\nloops (seam = seam step / 99.5th-percentile sample step, should be <2.5; edge = RMS(first 500 ms) - RMS(last 500 ms)):")
        for r in sorted(loops, key=lambda r: r["key"]):
            print(f"  {r['key']:34s} {r['dur']:6.1f}s seam={r['seam']:.2f} edge={r['edge_db']:+.1f}dB "
                  f"lufs={r['lufs']:.1f} peak={r['peak_db']:.1f}")
    print("\nlongest / biggest:")
    for r in sorted(rows, key=lambda r: -r.get("size", 0))[:6]:
        print(f"  {r['key']:40s} {r.get('size', 0) / 1e3:7.0f} kB {r.get('dur', 0):6.1f}s")
    if warns:
        print(f"\nWARNINGS ({len(warns)}):")
        for r in warns[:40]:
            print("  ", r["key"], "; ".join(r["warn"]))
    if orphans:
        print(f"\nORPHAN files not in manifest ({len(orphans)}):", orphans[:10])
    if cov:
        print(f"\nMISSING coverage ({len(cov)}):", cov[:20])
    if fails:
        print(f"\nFAILURES ({len(fails)}):")
        for r in fails[:50]:
            print("  ", r["key"], "; ".join(r["msgs"]))
    ok = not fails and not cov and not orphans
    print("\nQA", "PASSED" if ok else "FAILED")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
