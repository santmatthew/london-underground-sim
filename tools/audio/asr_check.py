#!/usr/bin/env python3
"""Optional speech QA with Whisper (needs `pip install faster-whisper` in *some* venv; it is NOT a
dependency of the generator).  Transcribes speech clips and scores them against their intended text,
then optionally re-renders clips whose score is well below that of the *same name* in sibling clips
(TTS occasionally drops or garbles a syllable; Whisper also mishears genuine local pronunciations, so a
plain threshold would flag hundreds of correct clips).

  python asr_check.py score  [--shard i/n] [--out build/audio/asr_scores.json] [substr ...]
  python asr_check.py repair [--tries 4] [--drop 0.2] (uses build/audio/asr_scores.json, needs piper venv too)

`repair` must be run with a Python that has BOTH faster-whisper and the piper venv packages (e.g. install
faster-whisper into build/venv), because it re-renders through speech.Tts.
"""
from __future__ import annotations

import argparse
import difflib
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
ROOT = HERE.parents[1]
OUT = ROOT / "assets" / "audio"
SCORES = ROOT / "build" / "audio" / "asr_scores.json"

norm = lambda s: re.sub(r"[^a-z0-9 ]", "", s.lower().replace("-", " ").replace("&", " and ")).split()


def sim(expected, heard):
    return difflib.SequenceMatcher(None, norm(expected), norm(heard)).ratio()


def model(threads=6):
    from faster_whisper import WhisperModel
    return WhisperModel("small.en", device="cpu", compute_type="int8", cpu_threads=threads)


def transcribe(m, path):
    segs, _ = m.transcribe(str(path), language="en", beam_size=5, condition_on_previous_text=False)
    return " ".join(s.text.strip() for s in segs)


def cmd_score(a):
    man = json.loads((OUT / "manifest.json").read_text())
    keys = [k for k, v in man["clips"].items() if v["category"].startswith("speech") and "text" in v
            and (not a.substr or any(s in k for s in a.substr))]
    if a.shard:
        i, n = map(int, a.shard.split("/"))
        keys = keys[i::n]
    m = model(a.threads)
    res = {}
    for j, k in enumerate(keys):
        v = man["clips"][k]
        t = transcribe(m, OUT / v["file"])
        res[k] = [round(sim(v["text"], t), 3), t]
        if j % 50 == 0:
            print(j, len(keys), flush=True)
    out = Path(a.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(res, indent=0, ensure_ascii=False))


def station_of(key):
    p = key.split("/")
    return p[1] if p[0] == "station" else None


def flagged(scores, drop=0.2, floor=0.9):
    """Clips clearly worse than the best sibling clip that names the same station (or, for
    non-station clips, below the floor)."""
    by = {}
    for k, (s, _) in scores.items():
        st = station_of(k)
        if st:
            by.setdefault(st, []).append(s)
    out = []
    for k, (s, t) in scores.items():
        st = station_of(k)
        if st:
            base = max(by[st])
            if s < floor and s < base - drop:
                out.append(k)
        elif s < 0.8:
            out.append(k)
    return out


def cmd_repair(a):
    import make_audio as MA
    import speech
    import dsp
    scores = json.loads(Path(a.scores).read_text())
    man = json.loads((OUT / "manifest.json").read_text())
    bad = flagged(scores, a.drop)
    print("flagged", len(bad), flush=True)
    m = model(a.threads)
    tts = {}
    fixed = 0
    for k in bad:
        v = man["clips"][k]
        job = next(j for j in speech.build_jobs(speech.load_network(), speech.load_pron()) if j["key"] == k)
        best = (scores[k][0], None)
        if job["voice"] not in tts:
            tts[job["voice"]] = speech.Tts(job["voice"])
        for _ in range(a.tries):
            x = tts[job["voice"]].synth(job["text"])
            y = speech.finish(x, job["style"])
            tmp = ROOT / "build" / "audio" / "_cand.ogg"
            dsp.save_ogg(tmp, y, bitrate=56)
            s = sim(v["text"], transcribe(m, tmp))
            if s > best[0]:
                best = (s, y)
            if s >= 0.95:
                break
        if best[1] is not None:
            dsp.save_ogg(OUT / v["file"], best[1], bitrate=56)
            v["duration"] = round(len(best[1]) / dsp.SR, 3)
            v["lufs"] = round(dsp.lufs(best[1]), 1)
            v["peak_db"] = round(dsp.peak_db(best[1]), 1)
            fixed += 1
            print(f"  {k}: {scores[k][0]:.2f} -> {best[0]:.2f}", flush=True)
    print("repaired", fixed, "of", len(bad))
    MA.save_manifest(man)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("score")
    s.add_argument("substr", nargs="*")
    s.add_argument("--shard")
    s.add_argument("--threads", type=int, default=6)
    s.add_argument("--out", default=str(SCORES))
    r = sub.add_parser("repair")
    r.add_argument("--scores", default=str(SCORES))
    r.add_argument("--tries", type=int, default=4)
    r.add_argument("--drop", type=float, default=0.2)
    r.add_argument("--threads", type=int, default=6)
    a = ap.parse_args()
    (cmd_score if a.cmd == "score" else cmd_repair)(a)


if __name__ == "__main__":
    main()
