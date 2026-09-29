"""Speech generation: Piper TTS front end, pronunciation handling, PA colouration, job list.

Voices (cached under build/audio/voices/):
  female_pa   -> en_GB-cori-high        (UK English female, LibriVox; station / platform PA)
  male_driver -> en_GB-vctk-medium, speaker p243 (London male, CSTR VCTK corpus, CC-BY 4.0; train driver)
"""
from __future__ import annotations

import json
import re
import unicodedata
from pathlib import Path

import numpy as np

import dsp
from dsp import SR

ROOT = Path(__file__).resolve().parents[2]
VOICE_DIR = ROOT / "build" / "audio" / "voices"
HF = "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_GB"

VOICES = {
    "female_pa": dict(name="cori", quality="high", speaker=None, length=1.06, noise=0.55, noise_w=0.70, ipa="en"),
    # VCTK speaker p243: male, London accent (CC-BY 4.0 corpus, so the voice is licence-clean)
    "male_driver": dict(name="vctk", quality="medium", speaker="p243", length=1.10, noise=0.45, noise_w=0.55, ipa="rp"),
}

PRON_PATH = Path(__file__).with_name("pronunciations.json")


# --------------------------------------------------------------------------------------
# network data -> spoken names
# --------------------------------------------------------------------------------------
LINE_SPOKEN = {"hammersmith-city": "Hammersmith and City", "waterloo-city": "Waterloo and City"}


def line_name(lid, lines):
    return LINE_SPOKEN.get(lid) or lines[lid]["name"]


def load_pron():
    return json.loads(PRON_PATH.read_text(encoding="utf-8"))


_PAREN_DROP = re.compile(r"\s*\((?:Circle|Bakerloo|H&C|D&P|Central)(?: Line)?\)")


def clean_name(raw: str) -> str:
    """Raw NaPTAN/TfL station name -> the name a person would say (before pronunciation overrides)."""
    n = _PAREN_DROP.sub("", raw)
    n = re.sub(r"\((\w[^)]*)\)", r"\1", n)          # "(Olympia)" -> "Olympia"
    n = n.replace("&", "and").replace("St.", "Saint")
    n = n.replace("-", " ")
    return re.sub(r"\s+", " ", n).strip()


def apply_pron(text: str, pron: dict) -> str:
    """Replace known words/phrases with respellings or [[IPA]] segments (longest match first)."""
    table = pron["replace"]
    keys = sorted(table, key=len, reverse=True)
    out, i = [], 0
    low_ok = lambda a, b: a == b
    while i < len(text):
        for k in keys:
            if text.startswith(k, i) and (i == 0 or not text[i - 1].isalnum()) and \
                    (i + len(k) >= len(text) or not text[i + len(k)].isalnum()):
                out.append(table[k])
                i += len(k)
                break
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


def join_names(names):
    if len(names) == 1:
        return names[0]
    return ", ".join(names[:-1]) + " and " + names[-1]


def load_network():
    return json.loads((ROOT / "data" / "network.json").read_text(encoding="utf-8"))


def slug(s):
    return re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_")


def service_destinations(net):
    """Unique (line, dest_id, via or None) over both ends of every service."""
    out = {}
    for lid, line in net["lines"].items():
        for s in line["services"]:
            m = re.search(r"\bvia (.+)$", s["name"])
            via = m.group(1).strip() if m else None
            for dest in (s["stops"][0], s["stops"][-1]):
                out[(lid, dest, via)] = True
    return sorted(out, key=lambda k: (k[0], k[1], k[2] or ""))


# --------------------------------------------------------------------------------------
# Piper front end
# --------------------------------------------------------------------------------------
def ensure_voice(v):
    import urllib.request
    VOICE_DIR.mkdir(parents=True, exist_ok=True)
    base = f"en_GB-{v['name']}-{v['quality']}"
    for ext in (".onnx", ".onnx.json"):
        p = VOICE_DIR / (base + ext)
        if not p.exists() or p.stat().st_size < 1000:
            url = f"{HF}/{v['name']}/{v['quality']}/{base}{ext}"
            print("downloading", url, flush=True)
            urllib.request.urlretrieve(url, p)
    return VOICE_DIR / (base + ".onnx")


class Tts:
    """Loads a Piper voice (1 ORT thread) and renders text containing optional [[IPA]] segments."""

    def __init__(self, key):
        import onnxruntime as ort
        from piper import PiperVoice
        self.key = key
        self.cfg = VOICES[key]
        path = ensure_voice(self.cfg)
        pv = PiperVoice.load(path)
        so = ort.SessionOptions()
        so.intra_op_num_threads = 1
        so.inter_op_num_threads = 1
        pv.session = ort.InferenceSession(str(path), sess_options=so, providers=["CPUExecutionProvider"])
        self.pv = pv
        self.sr = pv.config.sample_rate
        self.idmap = pv.config.phoneme_id_map
        spk = self.cfg["speaker"]
        self.speaker_id = pv.config.speaker_id_map[spk] if isinstance(spk, str) else spk

    # RP-notation IPA (as written in pronunciations.json) -> the voice's own espeak dialect
    def _ipa(self, s):
        if self.cfg["ipa"] == "en":
            s = s.replace("æ", "a").replace("ɐ", "ə")
            s = re.sub(r"ɪ(?=$|\s)", "i", s)
        return list(unicodedata.normalize("NFD", s))

    def phonemes(self, text):
        """Return list of sentences (each a list of phoneme characters)."""
        parts = re.split(r"(\[\[.*?\]\])", text)
        sents = [[]]

        def add(ph):
            cur = sents[-1]
            if cur and cur[-1] not in (" ", ) and ph and ph[0] not in " .,;:!?":
                cur.append(" ")
            cur.extend(ph)

        for part in parts:
            if part.startswith("[["):
                add(self._ipa(part[2:-2]))
                continue
            m = re.match(r"^\s*([.,;:!?]+)?\s*(.*)$", part, re.S)
            lead, rest = m.group(1), m.group(2)
            if lead:
                for ch in lead:
                    sents[-1].append(ch)
                    if ch in ".!?":
                        sents.append([])
            if rest.strip():
                # trailing punctuation belongs to the espeak call (sentence prosody)
                for sp in self.pv.phonemize(rest):
                    if not sp:
                        continue
                    add(sp)
                    if sp[-1] in ".!?":
                        sents.append([])
        return [s for s in sents if any(c not in " .,;:!?" for c in s)]

    def synth(self, text, length=None, noise=None, noise_w=None, pause=0.32):
        from piper import SynthesisConfig
        c = self.cfg
        cfg = SynthesisConfig(speaker_id=self.speaker_id, length_scale=length or c["length"],
                              noise_scale=noise if noise is not None else c["noise"],
                              noise_w_scale=noise_w if noise_w is not None else c["noise_w"],
                              normalize_audio=False)
        pieces = []
        for ph in self.phonemes(text):
            ids = self.pv.phonemes_to_ids(ph)
            a = self.pv.phoneme_ids_to_audio(ids, cfg)
            a = np.asarray(a, dtype=np.float64).reshape(-1)
            if pieces:
                pieces.append(np.zeros(int(pause * self.sr)))
            pieces.append(a)
        return dsp.resample_to(np.concatenate(pieces), self.sr, SR)


def trim(x, thresh_db=-42.0, head=0.06, tail=0.14, sr=SR):
    a = np.abs(x)
    pk = a.max()
    idx = np.nonzero(a > pk * 10 ** (thresh_db / 20))[0]
    if len(idx) == 0:
        return x
    i0 = max(0, idx[0] - int(head * sr))
    i1 = min(len(x), idx[-1] + int(tail * sr))
    y = x[i0:i1].copy()
    f = int(0.008 * sr)
    y[:f] *= np.linspace(0, 1, f)
    y[-f:] *= np.linspace(1, 0, f)
    return y


# --------------------------------------------------------------------------------------
# post-processing styles
# --------------------------------------------------------------------------------------
def _eq(x, lo, hi, order=2):
    return dsp.lowpass(dsp.highpass(x, lo, order), hi, order)


def style_chain(x, style, rng_seed=0):
    """Colour a dry speech render.  Returns float64 mono at 44.1 kHz (not yet loudness-normalised)."""
    from scipy import signal
    if style == "dry":
        return dsp.highpass(x, 80, 2)
    if style == "train_pa":
        # on-train PA: slightly boxy small speakers, band-limited, gentle compression, no room
        y = _eq(x, 200, 8000)
        y = signal.sosfilt(dsp.peaking_sos(2200, 0.9, 2.5), y)
        y = dsp.compress(y, -26, 2.2, 0.004, 0.09, 3.0)
        return y
    if style == "driver":
        # driver's cab PA / handset: narrower, mid-heavy, a touch of grit
        y = _eq(x, 220, 5200, 2)
        y = signal.sosfilt(dsp.peaking_sos(1400, 1.0, 3.0), y)
        y = dsp.compress(y, -28, 2.8, 0.003, 0.08, 4.0)
        y = dsp.soft_clip(y * 1.6, 1.2) / 1.6
        return y
    if style == "platform_pa":
        # horn loudspeakers in a tiled hall: 300 Hz - 6 kHz, presence bump, compression, small reverb
        y = _eq(x, 300, 6000, 2)
        y = signal.sosfilt(dsp.peaking_sos(2500, 0.8, 3.0), y)
        y = dsp.compress(y, -26, 2.6, 0.003, 0.1, 4.0)
        y = dsp.soft_clip(y * 1.4, 1.1) / 1.4
        rng = dsp.rng_for("pa_ir", rng_seed)
        ir = dsp.make_ir(0.75, rng, predelay=0.014, band_mult=(0.9, 1.0, 0.8, 0.4), n_early=10, early_span=0.035,
                         stereo=False)
        wet = dsp.reverb(y, ir, wet=0.22, tail=True)
        return wet
    raise ValueError(style)


def finish(x, style, lufs_target=-16.0):
    x = trim(x)
    x = style_chain(x, style)
    x = trim(x, -50.0, 0.02, 0.12)
    x = np.concatenate([np.zeros(int(0.04 * SR)), x, np.zeros(int(0.10 * SR))])
    x = dsp.normalize(x, lufs_target=lufs_target, ceiling_db=-2.5)   # Vorbis overshoots ~1 dB
    return x.astype(np.float32)


# --------------------------------------------------------------------------------------
# job list
# --------------------------------------------------------------------------------------
GENERIC = [
    # name, voice, style, text
    ("mind_the_gap", "female_pa", "train_pa", "Mind the gap."),
    ("mind_the_gap_platform", "female_pa", "platform_pa", "Mind the gap."),
    ("mind_the_gap_between_the_train_and_the_platform", "female_pa", "platform_pa",
     "Please mind the gap between the train and the platform."),
    ("stand_clear_of_the_doors", "male_driver", "driver", "Stand clear of the doors, please."),
    ("stand_clear_doors_closing", "male_driver", "driver", "Stand clear of the doors, please. The doors are closing."),
    ("this_train_terminates_here_all_change", "male_driver", "driver",
     "This train terminates here. All change, please. All change."),
    ("please_alight", "male_driver", "driver",
     "Please alight here, and take all your belongings with you."),
    ("this_train_is_not_in_service", "male_driver", "driver",
     "This train is not in service. Please do not board this train."),
    ("stand_behind_the_yellow_line", "female_pa", "platform_pa",
     "Please stand behind the yellow line, and let passengers off the train first."),
    ("please_keep_moving_along_the_platform", "female_pa", "platform_pa",
     "Please keep moving along the platform, to allow other passengers to get off the train."),
    ("please_move_right_down_inside_the_carriages", "female_pa", "platform_pa",
     "Please move right down inside the carriages, to make room for other passengers."),
    ("please_stand_on_the_right_escalator", "female_pa", "platform_pa",
     "Please stand on the right on the escalators, and let others walk past on the left."),
    ("holding_here_for_a_short_while", "male_driver", "driver",
     "Ladies and gentlemen, we are being held here for a short while, as the train in front is still in the station. "
     "We should be moving shortly. Thank you for your patience."),
    ("delayed_signal_failure", "female_pa", "platform_pa",
     "Due to a signal failure, there are delays on this line. Please allow extra time for your journey. "
     "We apologise for any inconvenience."),
    ("driver_signal_failure", "male_driver", "driver",
     "Ladies and gentlemen, I apologise for the delay. We are waiting for a signal failure ahead to be cleared. "
     "We will be moving as soon as we can."),
    ("good_morning", "female_pa", "platform_pa", "Good morning. Welcome to the London Underground."),
    ("good_afternoon", "female_pa", "platform_pa", "Good afternoon. Welcome to the London Underground."),
    ("good_evening", "female_pa", "platform_pa", "Good evening, and welcome to the London Underground."),
    ("driver_good_evening", "male_driver", "driver",
     "Good evening, ladies and gentlemen, and welcome aboard this train."),
    ("lost_property", "female_pa", "platform_pa",
     "If you have lost an item on the London Underground, please ask a member of staff, "
     "or visit the Transport for London website."),
    ("keep_your_belongings_with_you", "female_pa", "platform_pa",
     "Please keep all your personal belongings with you at all times."),
    ("the_next_train_is", "female_pa", "platform_pa", "The next train is"),
    ("next_train_approaching_stand_back", "female_pa", "platform_pa",
     "The next train is now approaching. Please stand back from the platform edge."),
    ("train_now_approaching", "female_pa", "platform_pa", "The next train is now approaching."),
    ("please_stand_back_from_the_platform_edge", "female_pa", "platform_pa",
     "Please stand back from the platform edge."),
    ("this_train_is_ready_to_depart", "male_driver", "driver", "This train is ready to depart. Please stand clear."),
    ("word_due", "female_pa", "platform_pa", "Due."),
    ("word_minutes", "female_pa", "platform_pa", "Minutes."),
    ("word_minute", "female_pa", "platform_pa", "Minute."),
]


def numbers():
    words = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
             "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty"]
    jobs = []
    for i, w in enumerate(words, 1):
        jobs.append((f"num_{i:02d}", "female_pa", "platform_pa", f"{w.capitalize()}."))
    for i in range(1, 16):
        w = words[i - 1]
        txt = "The next train is due in one minute." if i == 1 else f"The next train is due in {w} minutes."
        jobs.append((f"next_train_due_in_{i:02d}_min", "female_pa", "platform_pa", txt))
    return jobs


def build_jobs(net, pron):
    """All speech clips as dicts: key, file (relative to assets/audio), voice, style, text, category."""
    stations = net["stations"]
    lines = net["lines"]
    jobs = []
    sp = {sid: apply_pron(clean_name(s["name"]), pron) for sid, s in stations.items()}
    lp = {lid: apply_pron(line_name(lid, lines), pron) for lid in lines}
    plain = {sid: clean_name(s["name"]) for sid, s in stations.items()}

    def add(key, rel, voice, style, text, category, shown, vol=0.0, **kw):
        jobs.append(dict(key=key, file=rel, voice=voice, style=style, text=text, shown=shown, category=category,
                         volume_db=vol, **kw))

    for sid in sorted(stations):
        s = stations[sid]
        nm, pl = sp[sid], plain[sid]
        base = f"speech/station/{sid}"
        add(f"station/{sid}/this", f"{base}_this.ogg", "female_pa", "train_pa", f"This is {nm}.",
            "speech_station", f"This is {pl}.")
        add(f"station/{sid}/next", f"{base}_next.ogg", "female_pa", "train_pa", f"The next station is {nm}.",
            "speech_station", f"The next station is {pl}.")
        add(f"station/{sid}/alight", f"{base}_alight.ogg", "female_pa", "train_pa", f"{nm}. Mind the gap.",
            "speech_station", f"{pl}. Mind the gap.")
        ls = [l for l in s["lines"]]
        if len(ls) >= 2:
            lst = join_names([line_name(l, lines) for l in ls])
            lst_s = join_names([lp[l] for l in ls])
            add(f"station/{sid}/change", f"{base}_change.ogg", "female_pa", "train_pa",
                f"Interchange with the {lst_s} lines.", "speech_station", f"Interchange with the {lst} lines.")
            for l in ls:
                others = [o for o in ls if o != l]
                on = join_names([line_name(o, lines) for o in others])
                on_s = join_names([lp[o] for o in others])
                plural = "lines" if len(others) > 1 else "line"
                add(f"station/{sid}/change_ex/{l}", f"{base}_change_ex_{l}.ogg", "female_pa", "train_pa",
                    f"Change here for the {on_s} {plural}.", "speech_station",
                    f"Change here for the {on} {plural}.", excluded_line=l)
    # destinations
    for lid, dest, via in service_destinations(net):
        ln = line_name(lid, lines)
        lns = lp[lid]
        dn = sp[dest]
        vtxt = ""
        vslug = ""
        if via:
            vtxt = " via " + apply_pron(via, pron)
            vslug = "_via_" + slug(via)
        shown_via = f" via {via}" if via else ""
        k = f"{lid}/{dest}" + (f"/via_{slug(via)}" if via else "")
        add(f"terminates/{k}", f"speech/terminates/{lid}_{dest}{vslug}_to.ogg", "female_pa", "train_pa",
            f"This is a {lns} line train to {dn}{vtxt}.", "speech_train_dest",
            f"This is a {ln} line train to {plain[dest]}{shown_via}.", line=lid, dest=dest, via=via)
        add(f"platform_approach/{k}", f"speech/platform/{lid}_{dest}{vslug}_approach.ogg", "female_pa", "platform_pa",
            f"The next train approaching is a {lns} line train to {dn}{vtxt}. Please stand back from the platform edge.",
            "speech_platform",
            f"The next train approaching is a {ln} line train to {plain[dest]}{shown_via}. "
            f"Please stand back from the platform edge.", line=lid, dest=dest, via=via)
        add(f"platform_next/{k}", f"speech/platform/{lid}_{dest}{vslug}_next.ogg", "female_pa", "platform_pa",
            f"The next train is a {lns} line train to {dn}{vtxt}.", "speech_platform",
            f"The next train is a {ln} line train to {plain[dest]}{shown_via}.", line=lid, dest=dest, via=via)
    for name, voice, style, text in GENERIC + numbers():
        cat = "speech_driver" if voice == "male_driver" else "speech_pa"
        add(name, f"speech/generic/{name}.ogg", voice, style, apply_pron(text, pron), cat, text)
    return jobs
