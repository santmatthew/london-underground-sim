#!/usr/bin/env python3
"""Reproducible generator for every audio asset in assets/audio/.

    build/venv/bin/python tools/audio/make_audio.py                 # everything
    build/venv/bin/python tools/audio/make_audio.py --only speech   # station/train announcements (Piper TTS)
    build/venv/bin/python tools/audio/make_audio.py --only ambience # looping beds
    build/venv/bin/python tools/audio/make_audio.py --only sfx      # one-shots, trains, busker, UI
    build/venv/bin/python tools/audio/make_audio.py --names footstep_tile door_chime   # substring filter
    build/venv/bin/python tools/audio/make_audio.py --force         # ignore the speech cache

Speech is cached by (text, voice, style) signature in build/audio/speech_cache.json; Piper output has
random noise inside the model, so a forced re-render sounds slightly different (not bit-identical).
Procedural audio is seeded by asset name and is deterministic.  The manifest is merged, so partial
runs never drop other entries.
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import hashlib
import json
import multiprocessing as mp
import os
import shutil
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import numpy as np  # noqa: E402

import dsp  # noqa: E402
from dsp import SR  # noqa: E402

ROOT = HERE.parents[1]
OUT = ROOT / "assets" / "audio"
BUILD = ROOT / "build" / "audio"
MANIFEST = OUT / "manifest.json"
SPEECH_CACHE = BUILD / "speech_cache.json"
CODE_VERSION = "speech-v1"

os.environ.setdefault("OMP_NUM_THREADS", "1")
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")


# --------------------------------------------------------------------------------------
# non-speech assets
# --------------------------------------------------------------------------------------
def _non_speech_specs():
    import ambience
    import sfx
    specs = {}
    for name, (fn, meta) in ambience.LOOPS.items():
        specs[name] = {**dict(fn=fn, group="ambience", loop=True, norm=("done",), bitrate=96, spatial="2d"), **meta}
        if meta.get("channels") == 1:
            specs[name]["spatial"] = "3d"
    for name, m in sfx.registry().items():
        specs[name] = dict(m)
    return specs


def render_asset(name):
    """Worker: render one procedural asset, write OGG, return its manifest entry."""
    t0 = time.time()
    specs = _non_speech_specs()
    s = specs[name]
    res = s["fn"]()
    x = res[0] if isinstance(res, tuple) else res
    x = np.asarray(x, dtype=np.float64)
    norm = s["norm"]
    if norm[0] == "peak":
        x = dsp.normalize(x, peak_target=norm[1], ceiling_db=-1.0, wrap=s["loop"])
    elif norm[0] == "lufs":
        x = dsp.normalize(x, lufs_target=norm[1], ceiling_db=-2.0, wrap=s["loop"])
    x = x.astype(np.float32)
    rel = f"{s['group']}/{name}.ogg"
    if s["group"] == "ambience":
        rel = f"ambience/{name}.ogg"
    dsp.save_ogg(OUT / rel, x, bitrate=s.get("bitrate", 96))
    ch = 1 if x.ndim == 1 else x.shape[1]
    entry = dict(file=rel, duration=round(len(x) / SR, 3), loop=bool(s["loop"]), volume_db=s["volume_db"],
                 category=s["category"], channels=ch, lufs=round(dsp.lufs(x), 1), peak_db=round(dsp.peak_db(x), 1),
                 spatial=s.get("spatial", "2d"), desc=s.get("desc", ""))
    if s["loop"]:
        entry["loop_seam"] = round(dsp.loop_seam_error(x), 2)
        if entry["loop_seam"] > 5:
            print(f"  WARNING: {name}: loop seam ratio {entry['loop_seam']} before encoding", flush=True)
    return name, entry, time.time() - t0


# --------------------------------------------------------------------------------------
# speech
# --------------------------------------------------------------------------------------
_TTS = {}


def _speech_worker(group):
    """group = dict(voice, style, text, files=[rel,...]); render once, write every file."""
    import speech
    voice = group["voice"]
    if voice not in _TTS:
        _TTS[voice] = speech.Tts(voice)
    tts = _TTS[voice]
    x = tts.synth(group["text"])
    y = speech.finish(x, group["style"])
    first = OUT / group["files"][0]
    dsp.save_ogg(first, y, bitrate=56)
    for f in group["files"][1:]:
        (OUT / f).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(first, OUT / f)
    return dict(files=group["files"], duration=round(len(y) / SR, 3), lufs=round(dsp.lufs(y), 1),
                peak_db=round(dsp.peak_db(y), 1))


def run_speech(jobs_n, force, name_filter):
    import speech
    net = speech.load_network()
    pron = speech.load_pron()
    jobs = speech.build_jobs(net, pron)
    if name_filter:
        jobs = [j for j in jobs if any(f in j["key"] for f in name_filter)]
    cache = json.loads(SPEECH_CACHE.read_text()) if SPEECH_CACHE.exists() and not force else {}
    manifest = load_manifest()
    groups = {}
    for j in jobs:
        sig = hashlib.sha1(json.dumps([CODE_VERSION, j["voice"], j["style"], j["text"],
                                       speech.VOICES[j["voice"]]], sort_keys=True).encode()).hexdigest()[:16]
        j["sig"] = sig
        fresh = cache.get(j["file"]) == sig and (OUT / j["file"]).exists() and j["key"] in manifest["clips"]
        if fresh:
            continue
        g = groups.setdefault((j["voice"], j["style"], j["text"]), dict(voice=j["voice"], style=j["style"],
                                                                        text=j["text"], files=[], jobs=[]))
        g["files"].append(j["file"])
        g["jobs"].append(j)
    todo = list(groups.values())
    print(f"speech: {len(jobs)} clips, {len(todo)} unique renders needed", flush=True)
    results = {}
    t0 = time.time()
    if todo:
        for v in {g["voice"] for g in todo}:
            speech.ensure_voice(speech.VOICES[v])
        ctx = mp.get_context("spawn")
        with cf.ProcessPoolExecutor(max_workers=jobs_n, mp_context=ctx) as ex:
            futs = {ex.submit(_speech_worker, g): g for g in todo}
            done = 0
            for f in cf.as_completed(futs):
                g = futs[f]
                r = f.result()
                for job in g["jobs"]:
                    results[job["key"]] = r
                done += 1
                if done % 50 == 0 or done == len(todo):
                    print(f"  {done}/{len(todo)}  {time.time() - t0:.0f}s", flush=True)
    for j in jobs:
        r = results.get(j["key"])
        if r is None:
            continue
        cache[j["file"]] = j["sig"]
        e = dict(file=j["file"], duration=r["duration"], loop=False, volume_db=j["volume_db"], category=j["category"],
                 channels=1, lufs=r["lufs"], peak_db=r["peak_db"], spatial="2d" if j["style"] != "dry" else "2d",
                 voice=speech.VOICES[j["voice"]]["name"], text=j["shown"])
        for k in ("line", "dest", "via", "excluded_line"):
            if k in j:
                e[k] = j[k]
        manifest["clips"][j["key"]] = e
    SPEECH_CACHE.parent.mkdir(parents=True, exist_ok=True)
    SPEECH_CACHE.write_text(json.dumps(cache, indent=0))
    manifest["voices"] = {k: dict(model=f"en_GB-{v['name']}-{v['quality']}", role=r)
                          for (k, v), r in zip(speech.VOICES.items(), ("station / platform PA, on-train station announcements",
                                                                        "train driver"))}
    save_manifest(manifest)


# --------------------------------------------------------------------------------------
# manifest
# --------------------------------------------------------------------------------------
def load_manifest():
    if MANIFEST.exists():
        m = json.loads(MANIFEST.read_text())
        m.setdefault("clips", {})
        return m
    return dict(clips={})


def build_index(clips):
    idx = dict(station={}, terminates={}, platform_approach={}, platform_next={})
    for key in clips:
        p = key.split("/")
        if p[0] == "station" and len(p) >= 3:
            d = idx["station"].setdefault(p[1], {})
            if p[2] == "change_ex":
                d.setdefault("change_ex", {})[p[3]] = key
            else:
                d[p[2]] = key
        elif p[0] in ("terminates", "platform_approach", "platform_next") and len(p) >= 3:
            d = idx[p[0]].setdefault(p[1], {}).setdefault(p[2], {})
            if len(p) >= 4 and p[3].startswith("via_"):
                d.setdefault("via", {})[p[3][4:]] = key
            else:
                d["direct"] = key
    return idx


def save_manifest(m):
    m["clips"] = {k: v for k, v in sorted(m["clips"].items()) if (OUT / v["file"]).exists()}
    m["format"] = 1
    m["sample_rate"] = SR
    m["notes"] = ("clips[<key>].file is relative to assets/audio/. volume_db is the suggested base playback gain "
                  "(files are already loudness-normalised: speech ~-16 LUFS, ambience -22..-30 LUFS). loop=true files "
                  "are seamless: set AudioStreamOggVorbis.loop = true at load time. spatial: '3d' = mono/spatial "
                  "emitters, '2d' = bed / UI / wide stereo. See index for lookups by station id and line/destination.")
    m["index"] = build_index(m["clips"])
    m["generated"] = time.strftime("%Y-%m-%d %H:%M:%S")
    m["totals"] = dict(clips=len(m["clips"]),
                       total_seconds=round(sum(c["duration"] for c in m["clips"].values()), 1),
                       total_bytes=sum((OUT / c["file"]).stat().st_size for c in m["clips"].values()))
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    order = ["format", "sample_rate", "generated", "totals", "notes", "voices", "index", "clips"]
    out = {k: m[k] for k in order if k in m}
    MANIFEST.write_text(json.dumps(out, indent=1, ensure_ascii=False))


def run_procedural(kind, jobs_n, name_filter):
    specs = _non_speech_specs()
    names = [n for n, s in specs.items()
             if (kind == "all" or (kind == "ambience" and s["group"] == "ambience") or
                 (kind == "sfx" and s["group"] != "ambience"))]
    if name_filter:
        names = [n for n in names if any(f in n for f in name_filter)]
    print(f"procedural: {len(names)} assets", flush=True)
    manifest = load_manifest()
    ctx = mp.get_context("spawn")
    t0 = time.time()
    with cf.ProcessPoolExecutor(max_workers=jobs_n, mp_context=ctx) as ex:
        futs = [ex.submit(render_asset, n) for n in names]
        for i, f in enumerate(cf.as_completed(futs), 1):
            try:
                name, entry, dt = f.result()
            except Exception as e:  # keep going, report at the end
                print("  FAILED:", repr(e)[:300], flush=True)
                continue
            manifest["clips"][name] = entry
            print(f"  [{i}/{len(names)}] {name} ({dt:.1f}s)", flush=True)
    save_manifest(manifest)
    print(f"procedural done in {time.time() - t0:.0f}s")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", choices=["all", "speech", "ambience", "sfx"], default="all")
    ap.add_argument("--jobs", type=int, default=min(8, os.cpu_count() or 4))
    ap.add_argument("--force", action="store_true", help="re-render speech even if cached")
    ap.add_argument("--names", nargs="*", help="only assets whose key/name contains one of these substrings")
    a = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    BUILD.mkdir(parents=True, exist_ok=True)
    if a.only in ("all", "ambience", "sfx"):
        run_procedural(a.only, a.jobs, a.names)
    if a.only in ("all", "speech"):
        run_speech(a.jobs, a.force, a.names)
    print("done ->", MANIFEST)


if __name__ == "__main__":
    main()
