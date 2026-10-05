"""Looping ambience beds.  Every generator returns (audio, info) where audio is periodic by
construction (see dsp.py) so the seam is inaudible."""
from __future__ import annotations

import numpy as np
from scipy import signal

from dsp import (SR, add_at, band_noise, bp_mag, brown, db2lin, decorrelated_stereo, env_ar, fft_filter, highpass,
                 hp_mag, lowpass, lp_mag, make_ir, mod_gain, nsamp, pan_gains, periodic_sines, pink, resample_to,
                 reverb, rms, rng_for, smooth_random, spec_noise)
from synth_common import (bell, crowd_mix, damped_sine, distant_train, footstep, noise_burst, speaker_eq, sum_pad,
                          tone, voice_track)


def _even(n):
    return n + (n % 2)


def _hum(n, rng, seconds, base, harm_amps, drift=0.0):
    """Mains-style hum: harmonics with integer cycles/loop so it wraps perfectly."""
    cyc = [max(1, round(base * (k + 1) * seconds)) for k in range(len(harm_amps))]
    y = periodic_sines(n, rng, cyc, harm_amps)
    if drift:
        y = y * (1 + drift * smooth_random(n, rng, 0.2))
    return y


def _scatter(bus, rng, count, gen, gain_db, pan=(-1, 1), tmin=0.0):
    """Drop ``count`` events made by gen(rng) at random (wrapping) positions into a stereo bus."""
    n = bus.shape[0]
    for _ in range(count):
        ev = gen(rng)
        g = db2lin(rng.uniform(*gain_db))
        l, r = pan_gains(rng.uniform(*pan))
        pos = int(rng.uniform(0, n))
        add_at(bus[:, 0], ev if ev.ndim == 1 else ev[:, 0], pos, g * l, wrap=True)
        add_at(bus[:, 1], ev if ev.ndim == 1 else ev[:, 1], pos, g * r, wrap=True)


def _far(ev, fc, order=2):
    return lowpass(ev, fc, order)


def lvl(x, db):
    """Scale a stem to the given RMS level in dB (bed reference = 0 dB)."""
    return x * (db2lin(db) / rms(x))


def _pa_announcement(rng, dur=5.5, sr=22050):
    """Muffled 'someone announcing something' burst: single slow female voice, band-limited, clipped."""
    n = int(dur * sr)
    v = voice_track(n, rng, sr, female=True, syl=(0.14, 0.30), phrase=(3.0, 4.5), pause=(0.35, 0.8), pitch=205,
                    gap_end=0.6)
    v = resample_to(v.astype(np.float64), sr, SR)
    v = highpass(lowpass(v, 3800, 2), 380, 2)
    v = np.tanh(v * 1.6) / 1.6
    m = int(0.25 * SR)
    v[:m] *= np.linspace(0, 1, m)
    v[-m:] *= np.linspace(1, 0, m)
    return v


def _gate_beep(rng):
    e = tone(0.16, 1900 * rng.uniform(0.97, 1.03), harm=(1.0, 0.25), attack=0.004, release=0.02)
    return speaker_eq(e, 900, 6000)


def _luggage_roll(rng, dur=3.5):
    n = nsamp(dur)
    t = np.arange(n) / SR
    env = np.sin(np.pi * t / dur) ** 1.5
    base = band_noise(n, rng, 140, 1200, 2, slope=-0.5) * env
    rate = rng.uniform(9, 14)                            # tile joints / small wheel
    pulses = (0.6 + 0.4 * np.sin(2 * np.pi * rate * t + rng.uniform(0, 6)) ** 2) * env
    y = base * pulses * 0.6 + band_noise(n, rng, 1500, 5000, 2) * env * 0.05
    return y


def _finish(x, target_lufs, ceiling=-2.0):
    from dsp import normalize
    return normalize(x, lufs_target=target_lufs, ceiling_db=ceiling, wrap=True).astype(np.float32)


# --------------------------------------------------------------------------------------
# tunnel
# --------------------------------------------------------------------------------------
def tunnel_rumble_loop(seconds=45.0):
    n = nsamp(seconds)
    rng = rng_for("tunnel_rumble_loop")
    ch = []
    for _ in range(2):
        sub = spec_noise(n, rng, lambda f: f ** -1.0 * bp_mag(f, 16, 85, 3))
        body = spec_noise(n, rng, lambda f: f ** -0.8 * bp_mag(f, 55, 420, 2))
        air = spec_noise(n, rng, lambda f: (f / 1000) ** -0.6 * bp_mag(f, 350, 5000, 2))
        hiss = spec_noise(n, rng, lambda f: bp_mag(f, 3500, 11000, 2))
        y = (1.0 * sub * mod_gain(n, rng, 0.11, 2.5) + 0.6 * body * mod_gain(n, rng, 0.25, 2.0)
             + 0.11 * air * mod_gain(n, rng, 0.17, 3.0) + 0.02 * hiss * mod_gain(n, rng, 0.3, 3.0))
        ch.append(y)
    y = np.stack(ch, -1)
    # ventilation-fan drone with slow beating
    hum = _hum(n, rng, seconds, 31.2, (0.22, 0.14, 0.09, 0.05)) * mod_gain(n, rng, 0.1, 1.5)
    y += 0.5 * hum[:, None] * np.array([1.0, 0.85])
    # sparse water drips / distant metallic ticks, heavily reverberated
    bus = np.zeros((n, 2))
    for _ in range(int(seconds / 5.5)):
        f = rng.uniform(900, 2600)
        ev = bell(0.5, f, decay=0.18, partials=((1, 1, 1), (2.4, 0.3, 0.5)))
        add_at(bus[:, 0], ev, int(rng.uniform(0, n)), db2lin(rng.uniform(-32, -22)) * rng.uniform(0, 1), wrap=True)
        add_at(bus[:, 1], ev, int(rng.uniform(0, n)), db2lin(rng.uniform(-32, -22)) * rng.uniform(0, 1), wrap=True)
    bus = reverb(bus, make_ir(5.0, rng, predelay=0.03, band_mult=(1.4, 1.0, 0.6, 0.3)), wet=0.8, circular=True)
    y += bus * 0.35
    y = reverb(y, make_ir(4.5, rng, predelay=0.02, band_mult=(1.5, 1.0, 0.55, 0.25)), wet=0.5, circular=True)
    return _finish(y, -24.0), dict(loop=True)


# --------------------------------------------------------------------------------------
# platform
# --------------------------------------------------------------------------------------
def platform_ambience_loop(seconds=60.0):
    n = _even(nsamp(seconds))
    rng = rng_for("platform_ambience_loop")
    # air movement (two decorrelated channels)
    air = np.stack([spec_noise(n, rng, lambda f: f ** -0.6 * bp_mag(f, 70, 1400, 2)) *
                    mod_gain(n, rng, 0.11, 3.0) for _ in range(2)], -1)
    air2 = np.stack([spec_noise(n, rng, lambda f: bp_mag(f, 1500, 7000, 2)) * mod_gain(n, rng, 0.15, 4.0)
                     for _ in range(2)], -1)
    sub = np.stack([spec_noise(n, rng, lambda f: f ** -0.8 * bp_mag(f, 30, 150, 3)) * mod_gain(n, rng, 0.1, 2.0)
                    for _ in range(2)], -1)
    y = 1.0 * air + 0.05 * air2 + 0.45 * sub
    # ventilation fan + PA amplifier hum
    fan = _hum(n, rng, seconds, 100.0, (0.10, 0.05, 0.03), drift=0.3)
    pa_hum = _hum(n, rng, seconds, 50.0, (0.03, 0.05, 0.02, 0.012))
    y += (fan + pa_hum)[:, None] * np.array([0.9, 1.0])
    y += 0.012 * np.stack([spec_noise(n, rng, lambda f: bp_mag(f, 4000, 9000, 2)) for _ in range(2)], -1)
    # sound-field events go through the hall reverb
    bus = np.zeros((n, 2))
    # faint crowd
    n22 = n // 2
    bus += lvl(crowd_mix(n22, rng, 16, 22050, pool=8, gain_range=(-16, -3), chatty=0.7), -14.0)
    # distant trains
    for i in range(3):
        d = distant_train(rng.uniform(9, 13), rng, speed=rng.uniform(0.8, 1.2), level=1.0,
                          pan=(rng.uniform(-0.8, -0.2), rng.uniform(0.2, 0.8)) if i % 2 else (rng.uniform(0.2, 0.8),
                                                                                              rng.uniform(-0.8, -0.2)))
        d = lvl(d, -2.0)
        for c in range(2):
            add_at(bus[:, c], d[:, c], int((i + rng.uniform(0.1, 0.9)) * n / 3), 1.0, wrap=True)
    # far footsteps
    def fs(r):
        return _far(footstep(r.choice(["tile", "tile", "concrete", "rubber"]), r), 3200)
    _scatter(bus, rng, 16, fs, (-24, -10))
    # far PA announcements
    for _ in range(2):
        ev = lvl(_pa_announcement(rng), -9.0)
        add_at(bus[:, 0], ev, int(rng.uniform(0, n)), 1.0, wrap=True)
    dry = bus.copy()
    hall = make_ir(2.1, rng, predelay=0.02, band_mult=(1.1, 1.0, 0.7, 0.4))
    wet = reverb(bus, hall, wet=1.0, circular=True)
    y += 0.30 * dry + 0.55 * wet
    return _finish(y, -27.0), dict(loop=True)


# --------------------------------------------------------------------------------------
# concourse
# --------------------------------------------------------------------------------------
def concourse_ambience_loop(seconds=60.0):
    n = _even(nsamp(seconds))
    rng = rng_for("concourse_ambience_loop")
    hum = _hum(n, rng, seconds, 50.0, (0.04, 0.07, 0.03, 0.02, 0.01), drift=0.2)
    air = np.stack([spec_noise(n, rng, lambda f: f ** -0.7 * bp_mag(f, 45, 900, 2)) * mod_gain(n, rng, 0.09, 2.5)
                    for _ in range(2)], -1)
    y = 0.7 * air + hum[:, None] * 0.8
    bus = np.zeros((n, 2))
    bus += lvl(crowd_mix(n // 2, rng, 34, 22050, pool=10, gain_range=(-18, -2), chatty=1.2), -3.0)
    # footsteps of many people, at all distances
    def fs(r):
        s = r.choice(["tile", "tile", "concrete", "concrete", "rubber"])
        f = footstep(s, r)
        return f if r.random() < 0.35 else _far(f, r.uniform(1800, 4200))
    _scatter(bus, rng, 110, fs, (-26, -8))
    _scatter(bus, rng, 5, lambda r: lvl(_luggage_roll(r, r.uniform(2.5, 4.5)), 0.0), (-16, -10))
    _scatter(bus, rng, 4, _gate_beep, (-24, -16))
    for i in range(4):
        ev = lvl(_pa_announcement(rng, dur=rng.uniform(4.5, 7)), -4.0)
        add_at(bus[:, 0], ev, int((i + rng.uniform(0.1, 0.9)) * n / 4), 1.0, wrap=True)
        add_at(bus[:, 1], ev, int((i + rng.uniform(0.1, 0.9)) * n / 4), 0.6, wrap=True)
    # trains rumbling somewhere below
    for i in range(2):
        d = lvl(distant_train(rng.uniform(9, 12), rng, speed=1.0, clack=False, level=1.0), -1.0)
        for c in range(2):
            add_at(bus[:, c], lowpass(d[:, c], 300, 2), int((i + rng.uniform(0.1, 0.9)) * n / 2), 1.0, wrap=True)
    hall = make_ir(3.4, rng, predelay=0.03, band_mult=(1.15, 1.0, 0.75, 0.45))
    wet = reverb(bus, hall, wet=1.0, circular=True)
    y += 0.30 * bus + 0.85 * wet
    return _finish(y, -26.0), dict(loop=True)


# --------------------------------------------------------------------------------------
# corridor
# --------------------------------------------------------------------------------------
def _corridor_ir(rng, rt=1.2, gap=0.0135, sr=SR):
    n = nsamp(rt * 1.2)
    ir = np.zeros((n, 2))
    for c in range(2):
        t = np.arange(n) / sr
        # flutter echo between parallel walls
        k = 1
        while k * gap < rt * 1.15:
            i = int(k * gap * sr * (1 + 0.01 * c))
            if i < n:
                ir[i, c] += ((-1) ** k) * 0.72 ** k * (1.0 if c == 0 else 0.9)
            k += 1
        tail = spec_noise(n, rng, lambda f: bp_mag(f, 120, 5000, 2)) * np.exp(-6.9 * t / rt) * 0.06
        ir[:, c] += highpass(tail, 90, 2)
        ir[0, c] += 1.0
    ir /= np.sqrt(np.sum(ir ** 2, axis=0, keepdims=True))
    return ir


def corridor_ambience_loop(seconds=40.0):
    n = _even(nsamp(seconds))
    rng = rng_for("corridor_ambience_loop")
    # draughts along the passage
    draft = np.stack([spec_noise(n, rng, lambda f: f ** -0.5 * bp_mag(f, 90, 1800, 2)) *
                      mod_gain(n, rng, 0.07, 4.5) for _ in range(2)], -1)
    hiss = np.stack([spec_noise(n, rng, lambda f: bp_mag(f, 2500, 8000, 2)) * mod_gain(n, rng, 0.1, 3.5)
                     for _ in range(2)], -1)
    hum = _hum(n, rng, seconds, 100.0, (0.06, 0.04, 0.03, 0.02, 0.012), drift=0.15)
    y = 0.9 * draft + 0.05 * hiss + hum[:, None] * 0.7
    bus = np.zeros((n, 2))
    bus += lvl(crowd_mix(n // 2, rng, 7, 22050, pool=6, gain_range=(-16, -4), chatty=0.6), -10.0)
    def fs(r):
        s = r.choice(["tile", "tile", "concrete"])
        f = footstep(s, r)
        return f if r.random() < 0.3 else _far(f, r.uniform(2000, 4500))
    _scatter(bus, rng, 22, fs, (-20, -4))
    d = lvl(distant_train(rng.uniform(8, 11), rng, speed=1.0, clack=False, level=1.0), -2.0)
    for c in range(2):
        add_at(bus[:, c], lowpass(d[:, c], 260, 2), int(rng.uniform(0, n)), 1.0, wrap=True)
    ir = _corridor_ir(rng)
    wet = reverb(bus, ir, wet=1.0, circular=True)
    y += 0.3 * bus + 0.75 * wet
    y = reverb(y, make_ir(0.9, rng, predelay=0.006), wet=0.25, circular=True)
    return _finish(y, -28.0), dict(loop=True)


# --------------------------------------------------------------------------------------
# crowd murmur
# --------------------------------------------------------------------------------------
def crowd_murmur_dense_loop(seconds=40.0):
    n = _even(nsamp(seconds))
    rng = rng_for("crowd_murmur_dense_loop")
    x = crowd_mix(n // 2, rng, 70, 22050, pool=12, gain_range=(-14, 0), chatty=1.6, phrase=(0.8, 2.6),
                  pause=(0.15, 1.4))
    hall = make_ir(2.2, rng, predelay=0.015, band_mult=(1.1, 1.0, 0.7, 0.4))
    y = x * 0.65 + reverb(x, hall, wet=0.75, dry=0.0, circular=True)
    y += 0.02 * np.stack([spec_noise(n, rng, lambda f: bp_mag(f, 90, 800, 2)) for _ in range(2)], -1)
    return _finish(y, -22.0), dict(loop=True)


def crowd_murmur_light_loop(seconds=40.0):
    n = _even(nsamp(seconds))
    rng = rng_for("crowd_murmur_light_loop")
    x = crowd_mix(n // 2, rng, 12, 22050, pool=8, gain_range=(-14, 0), chatty=0.9)
    hall = make_ir(1.8, rng, predelay=0.015, band_mult=(1.1, 1.0, 0.7, 0.4))
    y = x * 0.75 + reverb(x, hall, wet=0.55, dry=0.0, circular=True)
    y += 0.012 * np.stack([spec_noise(n, rng, lambda f: bp_mag(f, 90, 800, 2)) for _ in range(2)], -1)
    return _finish(y, -25.0), dict(loop=True)


# --------------------------------------------------------------------------------------
# escalator
# --------------------------------------------------------------------------------------
STEPS_PER_S = 0.75 / 0.4          # the escalator's speed over the pitch of its steps (Escalator.SPEED / STEP_PITCH): a step passes every 0.533 s; 16 s is exactly 30 of them


def escalator_loop(seconds=16.0, steps_per_s=STEPS_PER_S):
    n = nsamp(seconds)
    rng = rng_for("escalator_loop")
    t = np.arange(n) / SR
    # motor + gearbox: exact periodic sinusoids
    cyc = [round(f * seconds) for f in (49.0, 98.0, 147.0, 196.0, 294.0, 392.0)]
    motor = periodic_sines(n, rng, cyc, (1.0, 0.75, 0.5, 0.28, 0.16, 0.10))
    motor *= 1 + 0.08 * np.sin(2 * np.pi * (steps_per_s / 2 * seconds) * t / seconds)
    g0 = round(620 * seconds)
    whine = np.sin(2 * np.pi * g0 * t / seconds + 0.9 * np.sin(2 * np.pi * 3 * t / seconds)) \
        + 0.35 * np.sin(2 * np.pi * 2 * g0 * t / seconds + 0.5)
    rumble = spec_noise(n, rng, lambda f: f ** -0.8 * bp_mag(f, 25, 160, 3))
    chain = spec_noise(n, rng, lambda f: (f / 1000) ** -0.4 * bp_mag(f, 250, 3400, 2))
    # step pulses (raised cosine at the step rate) modulate the chain/roller noise
    ns = int(round(seconds * steps_per_s))
    ph = (t * steps_per_s) % 1.0
    pulse = 0.55 + 0.45 * np.cos(2 * np.pi * ph) ** 2
    jitter = np.ones(n)
    for k in range(ns):
        i0, i1 = int(k / steps_per_s * SR), int((k + 1) / steps_per_s * SR)
        jitter[i0:i1] = rng.uniform(0.75, 1.15)
    y = 0.22 * motor + 0.035 * whine + 0.7 * rumble + 0.28 * chain * pulse * jitter
    # discrete tread / roller events
    ev = np.zeros(n)
    for k in range(ns):
        pos = int((k / steps_per_s + 0.02 * rng.uniform(-1, 1)) * SR)
        big = (k % 8 == 3)
        e = sum_pad(noise_burst(0.05, rng, 700, 4500, 0.02, amp=0.6 * rng.uniform(0.7, 1.1) * (1.3 if big else 1.0)),
                    damped_sine(0.16, rng.uniform(78, 105) * (0.75 if big else 1.0), 0.07,
                                amp=1.2 * (1.4 if big else 1.0)),
                    damped_sine(0.3, 660 * rng.uniform(0.97, 1.03), 0.12, amp=0.45) if big else np.zeros(1))
        add_at(ev, e, pos, 0.5 * rng.uniform(0.8, 1.15), wrap=True)
    y += ev
    # handrail friction hiss + two squeaks
    hr = spec_noise(n, rng, lambda f: bp_mag(f, 1800, 6500, 2)) * mod_gain(n, rng, 0.3, 3.0)
    y += 0.02 * hr
    for _ in range(3):
        d = rng.uniform(0.35, 0.7)
        m = nsamp(d)
        tt = np.arange(m) / SR
        f = rng.uniform(1900, 2900) * (1 + 0.06 * np.sin(2 * np.pi * rng.uniform(4, 9) * tt))
        sq = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * tt / d) ** 2
        add_at(y, sq, int(rng.uniform(0, n)), 0.012, wrap=True)
    y = reverb(y, make_ir(0.5, rng, predelay=0.004, stereo=False), wet=0.3, circular=True)
    return _finish(y, -25.0), dict(loop=True)


def escalator_comb_loop(seconds=16.0, steps_per_s=STEPS_PER_S):
    """What is heard at the end of an escalator, where each step runs under (or out from) the comb plate: a dry metallic tick-tick at the step rate, the teeth of the comb among the grooves of the tread,
    and a faint ring of the plate. 30 steps in the loop, each a little different; nothing else (the motor and the chain are in escalator_loop)."""
    n = nsamp(seconds)
    rng = rng_for("escalator_comb_loop")
    y = np.zeros(n)
    ns = int(round(seconds * steps_per_s))
    for k in range(ns):
        pos = int((k / steps_per_s + 0.012 * rng.uniform(-1, 1)) * SR)
        a = rng.uniform(0.7, 1.15)
        tick = sum_pad(noise_burst(0.014, rng, 1800, 6200, 0.004, amp=1.0 * a),
                       noise_burst(0.010, rng, 900, 3000, 0.003, amp=0.55 * a),
                       damped_sine(0.07, 2150 * rng.uniform(0.96, 1.04), 0.03, amp=0.18 * a),
                       damped_sine(0.05, 1480 * rng.uniform(0.97, 1.03), 0.02, amp=0.10 * a))
        add_at(y, tick, pos, 1.0, wrap=True)
        # the second tooth of the comb, a few milliseconds behind
        add_at(y, tick, pos + int(rng.uniform(0.007, 0.012) * SR), 0.45, wrap=True)
    y = reverb(y, make_ir(0.35, rng, predelay=0.003, stereo=False), wet=0.2, circular=True)
    return _finish(y, -30.0), dict(loop=True)


# --------------------------------------------------------------------------------------
# train interior
# --------------------------------------------------------------------------------------
def _clack(rng, size=1.0, bright=1.0):
    """Single rail-joint hit as felt inside a car."""
    return sum_pad(damped_sine(0.22, rng.uniform(62, 88), 0.09, amp=1.6 * size),
                   damped_sine(0.18, rng.uniform(170, 240), 0.05, amp=0.7 * size),
                   noise_burst(0.12, rng, 450, 2800 * bright, 0.035, amp=1.9 * size),
                   noise_burst(0.03, rng, 2500, 7000, 0.008, amp=0.25 * size * bright))


def train_interior_run(kind="slow"):
    fast = kind == "fast"
    T0 = 0.60 if fast else 0.95
    k = 50 if fast else 32
    n = int(round(k * T0 * SR))
    n += n % 2
    T = n / k / SR
    rng = rng_for("train_interior_run_" + kind)
    seconds = n / SR
    ch = []
    lv = dict(rumble=1.0, roar=0.38 if fast else 0.22, hiss=0.05 if fast else 0.035)
    for c in range(2):
        rumble = spec_noise(n, rng, lambda f: f ** -0.4 * bp_mag(f, 35, 380, 3))
        rumble *= mod_gain(n, rng, 0.35, 2.0)
        roar = spec_noise(n, rng, lambda f: (f / 1000) ** -1.0 * bp_mag(f, 380, 3200, 2))
        roar *= mod_gain(n, rng, 0.8, 2.5)
        hiss = spec_noise(n, rng, lambda f: bp_mag(f, 2800, 9500, 2)) * 0.5
        ch.append(lv["rumble"] * rumble + lv["roar"] * roar + lv["hiss"] * hiss)
    y = np.stack(ch, -1)
    # cabin boom: peaking near 90 Hz
    from dsp import peaking_sos, pfilt
    y = pfilt(y, peaking_sos(92, 1.1, 5.0))
    # traction motor tones (faint on the slow variant)
    f0 = 372.0 if fast else 236.0
    cyc = [round(f0 * m * seconds) for m in (1, 2, 3)]
    tt = np.arange(n) / n
    whine = periodic_sines(n, rng, cyc, (0.030 if fast else 0.012, 0.014 if fast else 0.005, 0.007 if fast else 0.002))
    whine *= 1 + 0.3 * np.sin(2 * np.pi * 3 * tt)
    y += whine[:, None] * np.array([1.0, 0.8])
    # rail-joint rhythm: two bogies, two axles each ("clickety-clack")
    offs = np.array([0.0, 0.145, 0.50, 0.645])
    amps = np.array([1.0, 0.78, 0.86, 0.62])
    ev = np.zeros((n, 2))
    for p in range(k):
        for o, a in zip(offs, amps):
            pos = int(round((p + o) * T * SR + rng.normal(0, 0.002) * SR))
            e = _clack(rng, size=a * rng.uniform(0.85, 1.15) * (1.15 if fast else 1.0),
                       bright=1.2 if fast else 1.0)
            pan = -0.25 if o < 0.3 else 0.25
            l, r = pan_gains(pan + rng.normal(0, 0.08))
            add_at(ev[:, 0], e, pos, l, wrap=True)
            add_at(ev[:, 1], e, pos, r, wrap=True)
    y += (1.0 if fast else 0.9) * ev
    # occasional rattles
    for _ in range(6 if fast else 4):
        d = rng.uniform(0.12, 0.3)
        r_ = noise_burst(d, rng, 1200, 4200, d * 0.6, amp=0.05 * rng.uniform(0.5, 1.2), attack=0.02)
        add_at(y[:, 0], r_, int(rng.uniform(0, n)), 1.0, wrap=True)
        add_at(y[:, 1], r_, int(rng.uniform(0, n)), 1.0, wrap=True)
    y = reverb(y, make_ir(0.16, rng, predelay=0.003, band_mult=(1.0, 1.0, 0.8, 0.5), n_early=6, early_span=0.02),
               wet=0.35, circular=True)
    return _finish(y, -22.0 if fast else -24.0), dict(loop=True)


def train_interior_idle_loop(seconds=30.0):
    """Inside a stationary train: air-conditioning hiss, compressor cycling, transformer hum."""
    n = nsamp(seconds)
    rng = rng_for("train_interior_idle_loop")
    ch = []
    for _ in range(2):
        low = spec_noise(n, rng, lambda f: f ** -0.5 * bp_mag(f, 40, 300, 2)) * mod_gain(n, rng, 0.2, 1.5)
        ac = spec_noise(n, rng, lambda f: (f / 1000) ** -0.3 * bp_mag(f, 1500, 9000, 2)) * mod_gain(n, rng, 0.25, 1.2)
        ch.append(0.35 * low + 0.22 * ac)
    y = np.stack(ch, -1)
    hum = _hum(n, rng, seconds, 100.0, (0.06, 0.035, 0.02), drift=0.1)
    y += hum[:, None]
    # air compressor: 4 s of pumping chug every 15 s
    t = np.arange(n) / SR
    for c0 in (3.0, 18.0):
        d = 4.2
        m = nsamp(d)
        tt = np.arange(m) / SR
        chug = (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 5.5 * tt))) * 0.6 + 0.4
        e = band_noise(m, rng, 50, 400, 2, slope=-0.3) * chug * np.clip(np.minimum(tt / 0.4, (d - tt) / 0.6), 0, 1)
        e = e + 0.5 * np.sin(2 * np.pi * 55 * tt) * np.clip(np.minimum(tt / 0.4, (d - tt) / 0.6), 0, 1) * chug
        add_at(y[:, 0], e, nsamp(c0 * seconds / 30.0), 0.35, wrap=True)
        add_at(y[:, 1], e, nsamp(c0 * seconds / 30.0), 0.32, wrap=True)
    y = reverb(y, make_ir(0.2, rng, predelay=0.003), wet=0.25, circular=True)
    return _finish(y, -30.0), dict(loop=True)


def train_idle_platform_loop(seconds=30.0):
    """A train standing at the platform, heard from outside: transformer hum, fans, compressor."""
    n = nsamp(seconds)
    rng = rng_for("train_idle_platform_loop")
    ch = []
    for _ in range(2):
        low = spec_noise(n, rng, lambda f: f ** -0.5 * bp_mag(f, 45, 350, 2)) * mod_gain(n, rng, 0.2, 1.5)
        fan = spec_noise(n, rng, lambda f: (f / 1000) ** -0.5 * bp_mag(f, 500, 6000, 2)) * mod_gain(n, rng, 0.3, 2.0)
        ch.append(0.4 * low + 0.10 * fan)
    y = np.stack(ch, -1)
    y += _hum(n, rng, seconds, 100.0, (0.09, 0.05, 0.03, 0.015), drift=0.1)[:, None]
    for c0 in (6.0, 21.0):
        d = 3.6
        m = nsamp(d)
        tt = np.arange(m) / SR
        chug = (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 6 * tt))) * 0.55 + 0.45
        w = np.clip(np.minimum(tt / 0.3, (d - tt) / 0.5), 0, 1)
        e = (band_noise(m, rng, 60, 700, 2) * 0.6 + np.sin(2 * np.pi * 62 * tt)) * chug * w
        add_at(y[:, 0], e, nsamp(c0 * seconds / 30.0), 0.4, wrap=True)
        add_at(y[:, 1], e, nsamp(c0 * seconds / 30.0), 0.4, wrap=True)
    y = reverb(y, make_ir(1.3, rng, predelay=0.012), wet=0.3, circular=True)
    return _finish(y, -28.0), dict(loop=True)


# --------------------------------------------------------------------------------------
# open air (surface platforms): wind in trees, distant road, birdsong by day
# --------------------------------------------------------------------------------------
def _bird_phrase(rng):
    """A short bird phrase: 2-6 tweets, each a fast frequency sweep with a sharp envelope (mono, ~0.4-1.4 s)."""
    kind = rng.choice(["trill", "tweet", "chirp"])
    notes = []
    base = rng.uniform(2400, 5200)
    count = {"trill": rng.integers(5, 10), "tweet": rng.integers(2, 4), "chirp": rng.integers(3, 6)}[kind]
    gap = {"trill": 0.055, "tweet": 0.16, "chirp": 0.09}[kind]
    out = np.zeros(int((count * (gap + 0.12) + 0.2) * SR))
    t0 = 0.0
    for k in range(count):
        dur = {"trill": 0.045, "tweet": 0.13, "chirp": 0.07}[kind] * rng.uniform(0.85, 1.2)
        m = int(dur * SR)
        u = np.linspace(0, 1, m)
        sweep = rng.uniform(-0.35, 0.45) if kind != "trill" else rng.uniform(0.1, 0.3)
        f = base * (1 + 0.04 * k * (1 if kind == "chirp" else 0)) * (1 + sweep * u) * (1 + 0.04 * np.sin(2 * np.pi * rng.uniform(18, 40) * u))
        ph = 2 * np.pi * np.cumsum(f) / SR
        y = np.sin(ph) + 0.18 * np.sin(2 * ph)
        env = np.sin(np.pi * np.clip(u, 0, 1)) ** 1.5
        add_at(out, y * env, int(t0 * SR), 1.0)
        t0 += dur + gap * rng.uniform(0.8, 1.3)
    return out


def _car_pass(rng, dur=6.0):
    """A car on a road some way off: swelling road noise, a low engine note, a pan sweep; stereo."""
    n = nsamp(dur)
    u = np.linspace(0, 1, n)
    env = np.sin(np.pi * u) ** 2.0
    road = band_noise(n, rng, 250, 2200, 2, slope=-0.6) * env
    low = band_noise(n, rng, 60, 320, 2, slope=-0.5) * env ** 1.3
    y = road * 0.5 + low * 0.9
    direction = rng.choice([-1, 1])
    theta = (0.5 + direction * (u - 0.5) * rng.uniform(0.9, 1.5)) * np.pi * 0.5
    theta = np.clip(theta, 0, np.pi * 0.5)
    return np.stack([y * np.cos(theta), y * np.sin(theta)], -1)


def _outdoor(name, seconds, birds, cars, wind_db, seed_extra=""):
    n = _even(nsamp(seconds))
    rng = rng_for(name + seed_extra)
    # wind: broad low whoosh with gusts, leaf rustle above it
    wind = np.stack([spec_noise(n, rng, lambda f: f ** -0.7 * bp_mag(f, 90, 1100, 2)) * mod_gain(n, rng, 0.07, 6.0) for _ in range(2)], -1)
    leaves = np.stack([spec_noise(n, rng, lambda f: bp_mag(f, 2200, 7500, 2)) * mod_gain(n, rng, 0.17, 5.0) for _ in range(2)], -1)
    # the city beyond: a steady road wash and a low urban hum
    road = np.stack([spec_noise(n, rng, lambda f: f ** -1.0 * bp_mag(f, 45, 480, 3)) * mod_gain(n, rng, 0.05, 3.0) for _ in range(2)], -1)
    hum = _hum(n, rng, seconds, 60.0, (0.03, 0.02), drift=0.4)
    y = wind * db2lin(wind_db) + 0.10 * leaves * db2lin(wind_db) + 0.55 * road + hum[:, None] * 0.4
    bus = np.zeros((n, 2))
    for _ in range(cars):
        ev = lvl(_car_pass(rng, rng.uniform(4.5, 8.0)), rng.uniform(-6, 0))
        pos = int(rng.uniform(0, n))
        for c in range(2):
            add_at(bus[:, c], ev[:, c], pos, 1.0, wrap=True)
    for _ in range(birds):
        ev = _bird_phrase(rng)
        g = db2lin(rng.uniform(-24, -12))
        l, r = pan_gains(rng.uniform(-0.9, 0.9))
        pos = int(rng.uniform(0, n))
        add_at(bus[:, 0], ev, pos, g * l, wrap=True)
        add_at(bus[:, 1], ev, pos, g * r, wrap=True)
    y += bus * 0.35
    return _finish(y, -29.0), dict(loop=True)


def outdoor_day_loop(seconds=60.0):
    return _outdoor("outdoor_day_loop", seconds, birds=34, cars=5, wind_db=0.0)


def outdoor_night_loop(seconds=60.0):
    return _outdoor("outdoor_night_loop", seconds, birds=0, cars=2, wind_db=-3.0)


LOOPS = {
    "tunnel_rumble_loop": (tunnel_rumble_loop, dict(category="ambience", volume_db=-3.0, desc="Deep tunnel bass rumble, air and far drips")),
    "platform_ambience_loop": (platform_ambience_loop, dict(category="ambience", volume_db=-3.0, desc="Tiled platform: air, fans, PA hum, faint crowd, far trains and footsteps")),
    "concourse_ambience_loop": (concourse_ambience_loop, dict(category="ambience", volume_db=-3.0, desc="Large reverberant concourse: crowd wash, footsteps, far announcements and gate beeps")),
    "corridor_ambience_loop": (corridor_ambience_loop, dict(category="ambience", volume_db=-3.0, desc="Passageway with flutter echo, draughts and far footsteps")),
    "crowd_murmur_dense_loop": (crowd_murmur_dense_loop, dict(category="crowd", volume_db=-4.0, desc="Dense crowd babble (~70 voices)")),
    "crowd_murmur_light_loop": (crowd_murmur_light_loop, dict(category="crowd", volume_db=-4.0, desc="Light crowd murmur (~12 voices)")),
    "escalator_loop": (escalator_loop, dict(category="ambience_3d", volume_db=-3.0, desc="Escalator motor, chain and step rumble, 30 steps at the real step rate (mono, for 3D emitters)", channels=1)),
    "escalator_comb_loop": (escalator_comb_loop, dict(category="ambience_3d", volume_db=-3.0, desc="The comb plate at the end of an escalator: a tick-tick at every step (mono, short range, one emitter at each end)", channels=1)),
    "train_interior_run_slow_loop": (lambda: train_interior_run("slow"), dict(category="train_interior", volume_db=-3.0, desc="Inside a car, moderate speed: rumble, ~0.95 s clickety-clack, AC hiss")),
    "train_interior_run_fast_loop": (lambda: train_interior_run("fast"), dict(category="train_interior", volume_db=-3.0, desc="Inside a car, high speed: louder roar, ~0.6 s clack, motor tone")),
    "train_interior_idle_loop": (train_interior_idle_loop, dict(category="train_interior", volume_db=-3.0, desc="Inside a standing train: AC, compressor cycling, hum")),
    "outdoor_day_loop": (outdoor_day_loop, dict(category="ambience", volume_db=-3.0, desc="Open-air platform by day: wind in trees, distant road, birdsong")),
    "outdoor_night_loop": (outdoor_night_loop, dict(category="ambience", volume_db=-3.0, desc="Open-air platform at night: wind, distant road, urban hum")),
    "train_idle_platform_loop": (train_idle_platform_loop, dict(category="train_exterior", volume_db=-3.0, desc="Standing train heard from the platform")),
}
