"""Reusable synthesis building blocks: impacts, tones, footsteps, crowd babble, distant trains, gusts."""
from __future__ import annotations

import numpy as np
from scipy import signal

from dsp import (SR, add_at, band_noise, bandpass, bp_mag, brown, db2lin, decorrelated_stereo, env_ar,
                 fft_filter, highpass, hp_mag, interp_env, lowpass, lp_mag, make_ir, mod_gain, nsamp, pan_gains,
                 peaking_sos, pink, resample_to, resonator_sos, reverb, rms, smooth_random, spec_noise,
                 to_stereo)


# --------------------------------------------------------------------------------------
# primitives
# --------------------------------------------------------------------------------------
def damped_sine(dur, f, decay60, sr=SR, phase=0.0, amp=1.0):
    n = nsamp(dur, sr)
    t = np.arange(n) / sr
    return amp * np.sin(2 * np.pi * f * t + phase) * np.exp(-6.9078 * t / max(decay60, 1e-4))


def noise_burst(dur, rng, lo, hi, decay60, sr=SR, attack=0.0004, order=2, amp=1.0):
    """Band-limited noise burst with exponential decay."""
    n = nsamp(dur, sr)
    w = rng.standard_normal(n)
    if lo and hi:
        w = signal.sosfilt(signal.butter(order, [lo / (sr / 2), min(hi, sr * 0.49) / (sr / 2)], "bandpass",
                                         output="sos"), w)
    elif hi:
        w = signal.sosfilt(signal.butter(order, hi / (sr / 2), "lowpass", output="sos"), w)
    elif lo:
        w = signal.sosfilt(signal.butter(order, lo / (sr / 2), "highpass", output="sos"), w)
    w /= (np.sqrt(np.mean(w ** 2)) + 1e-12)
    return amp * w * env_ar(n, attack, decay60, sr)


def tone(dur, f, sr=SR, harm=(1.0,), attack=0.004, release=0.012, amp=1.0, phase=0.0, fm=None):
    n = nsamp(dur, sr)
    t = np.arange(n) / sr
    ph = 2 * np.pi * f * t + phase
    if fm is not None:
        ph = ph + fm
    y = np.zeros(n)
    for k, a in enumerate(harm):
        y += a * np.sin((k + 1) * ph)
    env = np.clip(t / attack, 0, 1) * np.clip((dur - t) / release, 0, 1)
    return amp * y * env


BELL = ((1.0, 1.0, 1.0), (2.0, 0.35, 0.7), (2.76, 0.45, 0.55), (4.07, 0.22, 0.4), (5.4, 0.15, 0.3), (6.9, 0.08, 0.2))


def bell(dur, f, decay=1.0, sr=SR, partials=BELL, attack=0.002, amp=1.0, detune=0.0, rng=None):
    n = nsamp(dur, sr)
    t = np.arange(n) / sr
    y = np.zeros(n)
    for ratio, a, dk in partials:
        fr = f * ratio * (1 + (detune * (rng.random() - 0.5) if rng is not None else 0))
        y += a * np.sin(2 * np.pi * fr * t + (rng.uniform(0, 6.28) if rng is not None else 0)) * \
            np.exp(-6.9078 * t / (decay * dk))
    y *= np.clip(t / attack, 0, 1)
    return amp * y / max(1e-9, np.max(np.abs(y)))


def sum_pad(*arrs):
    """Sum 1-d arrays of different lengths (zero padded at the end)."""
    n = max(len(a) for a in arrs)
    out = np.zeros(n)
    for a in arrs:
        out[:len(a)] += a
    return out


def speaker_eq(x, lo=700, hi=7000, sr=SR):
    """Small piezo / loudspeaker colouration."""
    y = highpass(x, lo, 2, sr)
    return lowpass(y, hi, 2, sr)


# --------------------------------------------------------------------------------------
# footsteps
# --------------------------------------------------------------------------------------
SURFACES = {
    # heel_band, heel decay, thump (freq range, decay), modes (freq, amp, decay60), ring gain, toe gain, lp
    "tile": dict(heel=(1800, 8000), heel_d=0.010, heel_amp=1.0, thump=(120, 190), thump_d=0.045, thump_amp=0.55,
                 modes=[(2500, 0.55, 0.030), (3900, 0.32, 0.022), (700, 0.45, 0.070), (1350, 0.3, 0.045)],
                 toe=0.55, lp=9500),
    "concrete": dict(heel=(700, 4200), heel_d=0.009, heel_amp=0.9, thump=(90, 150), thump_d=0.055, thump_amp=0.8,
                     modes=[(1100, 0.3, 0.025), (2200, 0.15, 0.015)], toe=0.5, lp=5500),
    "rubber": dict(heel=(250, 1800), heel_d=0.022, heel_amp=0.55, thump=(60, 110), thump_d=0.07, thump_amp=1.0,
                   modes=[(180, 0.25, 0.05)], toe=0.7, lp=2800),
    "metal": dict(heel=(1500, 9000), heel_d=0.012, heel_amp=0.8, thump=(140, 230), thump_d=0.06, thump_amp=0.5,
                  modes=[(690, 0.55, 0.22), (1240, 0.45, 0.20), (2050, 0.38, 0.16), (3150, 0.28, 0.12),
                         (4350, 0.18, 0.09), (5600, 0.1, 0.07)],
                  toe=0.65, lp=11000),
    "escalator": dict(heel=(1000, 6500), heel_d=0.010, heel_amp=0.8, thump=(160, 260), thump_d=0.07, thump_amp=0.75,
                      modes=[(240, 0.6, 0.11), (520, 0.5, 0.10), (940, 0.35, 0.08), (1650, 0.3, 0.06),
                             (2900, 0.2, 0.04)],
                      toe=0.6, lp=8000),
}


def footstep(surface, rng, sr=SR, shoe=None):
    """One footfall (heel strike + toe roll) on the given surface. Mono, ~0.5 s."""
    p = SURFACES[surface]
    n = nsamp(0.65 if surface in ("metal", "escalator") else 0.5, sr)
    y = np.zeros(n)
    hard = shoe if shoe is not None else rng.uniform(0.6, 1.0)
    vf = rng.uniform(0.9, 1.12)          # global pitch variation of the floor modes
    strength = rng.uniform(0.75, 1.0)
    swing = 0.0

    def impact(t0, gain, brightness):
        nonlocal y
        i0 = nsamp(t0, sr)
        # broadband heel click
        lo, hi = p["heel"]
        c = noise_burst(0.06, rng, lo * (0.8 + 0.4 * hard), min(hi * brightness, sr * 0.45),
                        p["heel_d"] * rng.uniform(0.8, 1.3), sr)
        add_at(y, c, i0, gain * p["heel_amp"] * (0.5 + 0.7 * hard))
        # low body thump
        tf = rng.uniform(*p["thump"])
        th = damped_sine(0.2, tf, p["thump_d"] * rng.uniform(0.8, 1.3), sr, rng.uniform(0, 6.28))
        add_at(y, th, i0 + 6, gain * p["thump_amp"] * 0.9)
        # surface resonances
        for f, a, d in p["modes"]:
            fm = f * vf * rng.uniform(0.94, 1.06)
            if fm > sr * 0.45:
                continue
            m = damped_sine(min(d * 2.2, 0.5), fm, d * rng.uniform(0.8, 1.25), sr, rng.uniform(0, 6.28))
            add_at(y, m, i0 + int(rng.integers(0, 12)), gain * a * rng.uniform(0.6, 1.2) * (0.4 + 0.6 * hard) * 0.5)

    impact(0.008, strength, 1.0)
    # toe slap / roll-forward after 90..150 ms, duller and quieter
    impact(rng.uniform(0.085, 0.150), strength * p["toe"] * rng.uniform(0.7, 1.0), 0.6)
    # a little scuff noise between heel and toe
    sc = noise_burst(0.09, rng, 1500, 6000, 0.05, sr, attack=0.02, amp=0.05 * rng.uniform(0.5, 1.5))
    add_at(y, sc, nsamp(0.03, sr))
    y = lowpass(y, p["lp"] * rng.uniform(0.85, 1.1), 2, sr)
    y *= np.clip((n - np.arange(n)) / (0.04 * sr), 0, 1)
    return y


# --------------------------------------------------------------------------------------
# crowd babble (formant-filtered noise bursts)
# --------------------------------------------------------------------------------------
VOWELS = {"a": (730, 1090, 2440), "e": (530, 1840, 2480), "i": (300, 2200, 3000), "o": (500, 900, 2400),
          "u": (330, 900, 2300), "x": (500, 1400, 2500), "ae": (660, 1700, 2400)}


def voice_track(n, rng, sr=22050, female=False, syl=(0.11, 0.25), phrase=(0.8, 3.2), pause=(0.25, 2.4),
                pitch=None, gap_end=0.35, chatty=1.0):
    """One speaker's worth of unintelligible speech: glottal source -> vowel formant filters, syllabic
    envelope grouped into phrases, plus fricative bursts.  Starts/ends in silence (loop safe)."""
    t = np.arange(n) / sr
    f0b = pitch or (rng.uniform(175, 245) if female else rng.uniform(88, 135))
    scale = (rng.uniform(1.12, 1.22) if female else rng.uniform(0.94, 1.05))
    vkeys = list(VOWELS)
    syls = []                   # (t0, dur, vowel_key, amp, f0, fric)
    pos = rng.uniform(0.3, 1.5)
    total = n / sr - gap_end
    while pos < total - 0.3:
        plen = rng.uniform(*phrase)
        pf0 = f0b * np.exp(rng.normal(0, 0.10))
        k = 0
        tend = min(pos + plen, total)
        while pos < tend:
            d = rng.uniform(*syl)
            if pos + d > total:
                break
            frac = (pos - (tend - plen)) / plen
            f0 = pf0 * (1.08 - 0.20 * frac) * np.exp(rng.normal(0, 0.05))
            fr = rng.random() < 0.28
            syls.append((pos, d, vkeys[rng.integers(0, len(vkeys))], rng.uniform(0.45, 1.0) * (1.0 - 0.3 * frac),
                         f0, fr))
            pos += d + rng.uniform(0.015, 0.07)
            k += 1
        pos += rng.uniform(*pause) / chatty
    env_v = {v: np.zeros(n) for v in vkeys}
    f0_pts_t, f0_pts = [0.0], [f0b]
    fric = np.zeros(n)
    for t0, d, v, a, f0, fr in syls:
        i0 = int(t0 * sr)
        m = int(d * sr)
        if i0 + m >= n:
            continue
        h = np.sin(np.pi * np.arange(m) / m) ** 1.3
        env_v[v][i0:i0 + m] = np.maximum(env_v[v][i0:i0 + m], a * h)
        f0_pts_t += [t0, t0 + d]
        f0_pts += [f0 * 1.03, f0 * 0.97]
        if fr:
            fd = int(rng.uniform(0.05, 0.11) * sr)
            j0 = max(0, i0 - fd)
            fh = np.sin(np.pi * np.arange(i0 - j0 + 1) / max(1, i0 - j0 + 1)) ** 1.5
            fric[j0:i0 + 1] += 0.35 * a * fh[:i0 - j0 + 1]
    f0_pts_t.append(n / sr)
    f0_pts.append(f0b)
    f0 = np.interp(t, f0_pts_t, f0_pts) * (1 + 0.004 * smooth_random(n, rng, 8, sr))
    phase = np.cumsum(f0) / sr
    saw = 2 * (phase % 1.0) - 1
    src = saw + 0.18 * rng.standard_normal(n)
    src = lowpass(src, 4200, 1, sr)
    out = np.zeros(n)
    for v in vkeys:
        if env_v[v].max() <= 0:
            continue
        F = VOWELS[v]
        yv = np.zeros(n)
        for f, bw, g in zip(F, (80, 110, 160), (1.0, 0.65, 0.4)):
            fs = min(f * scale, sr * 0.45)
            yv += g * signal.sosfilt(resonator_sos(fs, fs / bw, sr), src)
        out += env_v[v] * yv
    # fricatives (s / sh like): high-passed noise
    fn = signal.sosfilt(signal.butter(2, [3500 / (sr / 2), min(9000, sr * 0.47) / (sr / 2)], "bandpass",
                                      output="sos"), rng.standard_normal(n))
    out += 0.35 * fric * fn / (rms(fn) + 1e-9) * rms(out) * 0.9
    out /= (rms(out) + 1e-12)
    return out.astype(np.float32)


def crowd_mix(n, rng, n_voices, sr=22050, pool=8, female_frac=0.5, spread=1.0, gain_range=(-14, 0),
              chatty=1.0, phrase=(0.8, 3.2), pause=(0.25, 2.4)):
    """Stereo mix of many shifted copies of a pool of voice tracks, returned at 44.1 kHz."""
    tracks = [voice_track(n, rng, sr, female=(rng.random() < female_frac), chatty=chatty, phrase=phrase,
                          pause=pause) for _ in range(pool)]
    mix = np.zeros((n, 2))
    for i in range(n_voices):
        tr = np.roll(tracks[i % pool], int(rng.integers(0, n)))
        g = db2lin(rng.uniform(*gain_range))
        l, r = pan_gains(rng.uniform(-spread, spread))
        # farther voices (quieter) are duller
        if g < db2lin(gain_range[0] * 0.5):
            tr = lowpass(tr, 2400, 1, sr)
        mix[:, 0] += g * l * tr
        mix[:, 1] += g * r * tr
    mix = resample_to(mix, sr, SR, periodic=True)
    return mix


# --------------------------------------------------------------------------------------
# distant train, gusts
# --------------------------------------------------------------------------------------
def distant_train(dur, rng, sr=SR, speed=1.0, clack=True, level=1.0, pan=(-0.6, 0.6), room_rt=2.6, seed_ir=None):
    """A train passing in a neighbouring tunnel, heard through walls: swelling low rumble, muffled
    rail clatter that follows the speed, tunnel reverb.  Stereo, exactly ``dur`` seconds."""
    n = nsamp(dur, sr)
    u = np.linspace(0, 1, n)
    rise = rng.uniform(0.42, 0.6)
    env = np.where(u < rise, np.sin(0.5 * np.pi * np.clip(u / rise, 0, 1)) ** 1.7,
                   np.cos(0.5 * np.pi * np.clip((u - rise) / (1 - rise), 0, 1)) ** 2.2)
    env = env ** 1.2
    speed_c = env ** 0.5
    low = band_noise(n, rng, 25, 160, 2, slope=-0.3, sr=sr) * env
    mid = band_noise(n, rng, 120, 700, 2, slope=-0.7, sr=sr) * env ** 1.4 * 0.5
    hi = band_noise(n, rng, 600, 2200, 2, slope=-1.0, sr=sr) * env ** 2.0 * 0.15
    wobble = mod_gain(n, rng, 2.5, 1.5, sr)
    x = (low + mid + hi) * wobble
    if clack:
        # clatter events at a rate proportional to speed
        rate = 2.4 * speed * (0.35 + 0.65 * speed_c)
        ph = np.cumsum(rate) / sr
        idx = np.nonzero(np.diff(np.floor(ph)) > 0)[0]
        ck = np.zeros(n)
        for i in idx:
            a = env[i] ** 1.3
            if a < 0.03:
                continue
            e = sum_pad(noise_burst(0.12, rng, 60, 900, 0.05, sr, attack=0.002) * 0.9,
                        damped_sine(0.15, rng.uniform(55, 80), 0.06, sr) * 1.2)
            add_at(ck, e, i, a * rng.uniform(0.6, 1.1))
        x = x + 0.65 * ck
    # faint motor tone (very far, only a hint)
    x = lowpass(x, 1500, 2, sr)
    p = np.linspace(pan[0], pan[1], n)
    l, r = pan_gains(p)
    st = np.stack([x * l, x * r], axis=-1)
    ir = make_ir(room_rt, rng, sr, predelay=0.02, band_mult=(1.3, 1.0, 0.5, 0.2))
    st = reverb(st, ir, wet=1.1, tail=False)
    return level * st / (rms(st) + 1e-9) * 0.1


def wind_gust(dur, rng, sr=SR, peak_at=0.72, strength=1.0, stereo=True):
    """The air push ahead of a train in a tunnel: rising whoosh with gusting, whistling resonance,
    debris rattle and a low pressure thump at the peak."""
    n = nsamp(dur, sr)
    t = np.arange(n) / sr
    tp = dur * peak_at
    u = t / tp
    rise = np.where(t < tp, np.clip(u, 0, 1) ** 2.4, np.exp(-6.9 * (t - tp) / (dur - tp) * 1.2))
    chans = []
    for c in range(2 if stereo else 1):
        low = band_noise(n, rng, 40, 300, 2, slope=-0.4, sr=sr)
        mid = band_noise(n, rng, 200, 1100, 2, slope=-0.6, sr=sr)
        hi = band_noise(n, rng, 900, 4500, 2, slope=-1.2, sr=sr)
        g = mod_gain(n, rng, 1.6, 3.0, sr)
        y = (1.0 * low * rise ** 0.8 + 0.85 * mid * rise ** 1.3 + 0.28 * hi * rise ** 2.0) * g
        chans.append(y)
    y = np.stack(chans, axis=-1)
    # tunnel whistle: narrow resonances gliding slowly
    for f0, q, a in ((540, 40, 0.10), (830, 35, 0.06)):
        w = spec_noise(n, rng, lambda f: 1.0 / np.sqrt(1 + ((f - f0) / (f0 / q)) ** 4), sr)
        glide = 1.0 + 0.0
        y += (w * rise ** 2.2 * a * rng.uniform(0.9, 1.1))[:, None] * np.array([1.0, 0.9])[None, :y.shape[1]]
    # debris / dust rattle: sparse ticks, denser at the peak
    ticks = np.zeros(n)
    for i in np.nonzero(rng.random(n) < (rise ** 2.5) * 0.0009)[0]:
        e = noise_burst(0.02, rng, 1800, 7000, 0.006, sr)
        add_at(ticks, e, i, rng.uniform(0.1, 0.4) * rise[i])
    y += 0.35 * ticks[:, None]
    # pressure thump at the peak
    th = damped_sine(1.0, 38, 0.35, sr) + 0.5 * damped_sine(1.0, 62, 0.25, sr)
    thump = np.zeros(n)
    add_at(thump, th * np.clip(np.arange(len(th)) / (0.15 * sr), 0, 1), int(tp * sr) - int(0.1 * sr), 0.9 * strength)
    y += thump[:, None]
    y *= np.clip((n - np.arange(n)) / (0.25 * sr), 0, 1)[:, None] * np.clip(np.arange(n) / (0.15 * sr), 0, 1)[:, None]
    y = y / (rms(y) + 1e-9) * 0.2
    return y if stereo else y[:, 0]
