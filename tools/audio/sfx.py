"""One-shot sound effects, UI sounds, the busker loop and the registry that ties every non-speech
asset to its manifest metadata."""
from __future__ import annotations

import numpy as np
from scipy import signal

from dsp import (SR, add_at, band_noise, bp_mag, db2lin, env_ar, highpass, limit, lowpass, make_ir, mod_gain,
                 nsamp, normalize, pan_gains, peak_db, peaking_sos, pfilt, resonator_sos, reverb, rms, rng_for,
                 smooth_random, spec_noise)
from synth_common import (bell, damped_sine, distant_train, footstep, noise_burst, speaker_eq, sum_pad, tone,
                          wind_gust)


# --------------------------------------------------------------------------------------
# door / gate
# --------------------------------------------------------------------------------------
def _cabin(x, rt=0.18, wet=0.25, seed="cabin"):
    rng = rng_for(seed)
    return reverb(x, make_ir(rt, rng, predelay=0.003, stereo=False, n_early=6, early_span=0.02), wet=wet, tail=True)


def door_chime_open_audio():
    rng = rng_for("door_chime_open")
    part = ((1, 1, 1), (2.01, 0.28, 0.55), (3.0, 0.10, 0.3), (4.2, 0.05, 0.2))
    a = bell(1.1, 1046.5, 0.55, partials=part, amp=0.8)
    b = bell(1.3, 830.6, 0.70, partials=part, amp=0.9)
    y = np.zeros(nsamp(1.7))
    add_at(y, a, 0)
    add_at(y, b, nsamp(0.30))
    y = speaker_eq(y, 350, 9000)
    return _cabin(y, 0.25, 0.3, "chime_open")


def door_chime_close_audio():
    """Two-tone closing warning: eight alternating beeps."""
    f_hi, f_lo = 1568.0, 1244.5
    seq = [f_hi, f_lo] * 4
    y = np.zeros(nsamp(1.45))
    for i, f in enumerate(seq):
        b = tone(0.095, f, harm=(1.0, 0.0, 0.22, 0.0, 0.08), attack=0.004, release=0.012, amp=0.7)
        add_at(y, b, nsamp(0.02 + i * 0.155))
    y = speaker_eq(y, 600, 8000)
    return _cabin(y, 0.15, 0.2, "chime_close")


def _door_slide(kind):
    rng = rng_for("door_slide_" + kind)
    is_open = kind == "open"
    dur = 2.8 if is_open else 2.5
    n = nsamp(dur)
    t = np.arange(n) / SR
    ms, me = (0.20, 1.95) if is_open else (0.12, 1.55)
    u = np.clip((t - ms) / (me - ms), 0, 1)
    speed = (np.sin(np.pi * u) ** 0.7) * ((t > ms) & (t < me))
    if not is_open:
        speed = (np.sin(np.pi * u ** 0.8) ** 0.7) * ((t > ms) & (t < me))
    lowb = band_noise(n, rng, 60, 520, 2, slope=-0.3) * speed
    roll = band_noise(n, rng, 600, 3400, 2, slope=-0.6) * speed ** 1.4 * (0.65 + 0.35 * np.sin(2 * np.pi * 9 * t) ** 2)
    f = 240 + 420 * speed
    motor = np.sin(2 * np.pi * np.cumsum(f) / SR) * speed * 0.10 + 0.05 * np.sin(2 * np.pi * np.cumsum(2 * f) / SR) * speed
    y = 0.8 * lowb + 0.34 * roll + motor
    if is_open:
        add_at(y, noise_burst(0.6, rng, 2500, 9500, 0.32, attack=0.012, amp=0.55), nsamp(0.02))
        add_at(y, [noise_burst(0.02, rng, 900, 5000, 0.01, amp=0.6), damped_sine(0.06, 380, 0.025, amp=0.4)], nsamp(0.06))
        add_at(y, [damped_sine(0.3, 105, 0.11, amp=0.75), noise_burst(0.1, rng, 300, 2200, 0.04, amp=0.4)], nsamp(me))
        add_at(y, damped_sine(0.2, 92, 0.08, amp=0.32), nsamp(me + 0.11))
    else:
        add_at(y, noise_burst(0.02, rng, 900, 5000, 0.01, amp=0.5), nsamp(0.06))
        # leaves meet: heavy clunk + rubber seal squeak + pneumatic lock
        add_at(y, [damped_sine(0.4, 88, 0.16, amp=1.4), noise_burst(0.12, rng, 250, 2600, 0.05, amp=0.9),
                   damped_sine(0.2, 620, 0.06, amp=0.25)], nsamp(me))
        add_at(y, noise_burst(0.35, rng, 1500, 8000, 0.12, attack=0.01, amp=0.4), nsamp(me + 0.05))
        add_at(y, [noise_burst(0.05, rng, 400, 3000, 0.02, amp=0.6), damped_sine(0.15, 140, 0.05, amp=0.6)], nsamp(me + 0.42))
    y = lowpass(y, 9500, 2)
    return _cabin(y, 0.22, 0.28, "door_slide_" + kind)


def door_slide_open_audio():
    return _door_slide("open")


def door_slide_close_audio():
    return _door_slide("close")


def gate_beep_ok():
    y = tone(0.20, 1900.0, harm=(1.0, 0.12, 0.05), attack=0.004, release=0.03, amp=0.8)
    y = speaker_eq(y, 500, 9000)
    return _cabin(y, 0.08, 0.12, "beep_ok")


def gate_beep_error():
    y = np.zeros(nsamp(1.0))
    for i in range(3):
        t = np.arange(nsamp(0.17)) / SR
        b = signal.sawtooth(2 * np.pi * 430 * t) * 0.5 + np.sin(2 * np.pi * 430 * t)
        b *= np.clip(t / 0.006, 0, 1) * np.clip((0.17 - t) / 0.02, 0, 1)
        add_at(y, b, nsamp(0.02 + i * 0.25))
    y = speaker_eq(y, 300, 5200)
    return _cabin(y, 0.08, 0.12, "beep_err")


def _flap(kind):
    rng = rng_for("gate_flap_" + kind)
    n = nsamp(0.75)
    t = np.arange(n) / SR
    dur = 0.30
    u = np.clip(t / dur, 0, 1)
    f = 200 + 380 * (u if kind == "open" else 1 - u * 0.6)
    env = np.clip(np.minimum(t / 0.03, (dur + 0.03 - t) / 0.05), 0, 1)
    whir = (np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.35 + 0.15 * np.sin(2 * np.pi * np.cumsum(2.03 * f) / SR)) * env
    air = band_noise(n, rng, 1200, 5200, 2) * env * 0.3
    y = whir + air
    if kind == "open":
        add_at(y, [damped_sine(0.15, 165, 0.05, amp=0.7), noise_burst(0.05, rng, 500, 3500, 0.02, amp=0.5)], nsamp(dur))
    else:
        add_at(y, [damped_sine(0.2, 130, 0.07, amp=1.1), noise_burst(0.08, rng, 300, 4200, 0.03, amp=0.9),
                   damped_sine(0.1, 1900, 0.02, amp=0.15)], nsamp(dur))
        add_at(y, damped_sine(0.12, 110, 0.05, amp=0.3), nsamp(dur + 0.09))
    return _cabin(lowpass(y, 9500, 2), 0.1, 0.18, "flap_" + kind)


def gate_flap_open():
    return _flap("open")


def gate_flap_close():
    return _flap("close")


# --------------------------------------------------------------------------------------
# machines / ui
# --------------------------------------------------------------------------------------
def ticket_beep():
    y = tone(0.07, 1050.0, harm=(1.0, 0.0, 0.3, 0.0, 0.1), attack=0.003, release=0.012, amp=0.7)
    return _cabin(speaker_eq(y, 500, 7000), 0.08, 0.1, "tb")


def ticket_confirm():
    y = np.zeros(nsamp(0.4))
    add_at(y, tone(0.09, 880.0, harm=(1.0, 0.0, 0.3, 0.0, 0.1), amp=0.7), nsamp(0.0))
    add_at(y, tone(0.14, 1318.5, harm=(1.0, 0.0, 0.3, 0.0, 0.1), amp=0.7), nsamp(0.11))
    return _cabin(speaker_eq(y, 500, 7000), 0.08, 0.1, "tc")


def ticket_error():
    y = np.zeros(nsamp(0.8))
    for i in range(2):
        t = np.arange(nsamp(0.28)) / SR
        b = (signal.square(2 * np.pi * 196 * t) * 0.35 + np.sin(2 * np.pi * 196 * t)) * np.clip(t / 0.006, 0, 1) * \
            np.clip((0.28 - t) / 0.03, 0, 1)
        add_at(y, b, nsamp(0.02 + 0.34 * i))
    return _cabin(speaker_eq(y, 150, 4500), 0.08, 0.1, "te")


def coin_drop():
    rng = rng_for("coin_drop")
    y = np.zeros(nsamp(1.2))
    part = ((1, 1, 1), (1.51, 0.7, 0.8), (2.2, 0.45, 0.6), (2.85, 0.3, 0.45), (3.9, 0.15, 0.3))
    t0s = [0.0, 0.085, 0.145, 0.185, 0.21]
    for i, t0 in enumerate(t0s):
        c = bell(0.6, 3100 * rng.uniform(0.985, 1.015), 0.28 * (0.8 ** i) + 0.05, partials=part,
                 amp=0.8 * (0.62 ** i))
        c = sum_pad(c, noise_burst(0.02, rng, 2500, 9000, 0.008, amp=0.4 * (0.62 ** i)))
        add_at(y, c, nsamp(t0))
    # slide down the chute first
    y2 = np.zeros_like(y)
    sl = band_noise(nsamp(0.25), rng, 1200, 6000, 2) * np.hanning(nsamp(0.25)) * 0.15
    add_at(y2, sl, 0)
    add_at(y2, y, nsamp(0.25))
    y2 = y2[:nsamp(1.4)]
    return _cabin(highpass(y2, 400, 2), 0.14, 0.25, "coin")


def ticket_print():
    rng = rng_for("ticket_print")
    dur = 1.7
    n = nsamp(dur)
    t = np.arange(n) / SR
    gate = np.clip(np.minimum(t / 0.05, (1.55 - t) / 0.05), 0, 1) * (t < 1.55)
    pulses = (np.sign(np.sin(2 * np.pi * 62 * t)) * 0.5 + 0.5) * 0.6 + 0.4
    y = band_noise(n, rng, 500, 3800, 2) * pulses * gate * 0.35
    y += np.sin(2 * np.pi * np.cumsum(880 + 60 * np.sin(2 * np.pi * 3 * t)) / SR) * gate * 0.05
    y += band_noise(n, rng, 120, 500, 2) * gate * 0.2
    # cutter
    add_at(y, [noise_burst(0.05, rng, 1500, 7000, 0.015, amp=0.9), damped_sine(0.1, 240, 0.03, amp=0.5)], nsamp(1.6))
    add_at(y, [damped_sine(0.12, 150, 0.04, amp=0.5), noise_burst(0.03, rng, 800, 4000, 0.01, amp=0.5)], nsamp(1.66))
    return _cabin(y, 0.12, 0.2, "print")


def ui_click_soft():
    rng = rng_for("ui_click_soft")
    y = sum_pad(noise_burst(0.03, rng, 900, 5000, 0.006, amp=0.5), damped_sine(0.03, 1500, 0.008, amp=0.6),
                damped_sine(0.05, 380, 0.015, amp=0.35))
    return y


def ui_hover_soft():
    rng = rng_for("ui_hover_soft")
    return sum_pad(noise_burst(0.02, rng, 2500, 8000, 0.004, amp=0.4), damped_sine(0.03, 2400, 0.006, amp=0.4))


def _chime(notes, gap, decay, wetrt=0.6, amp=0.8, seed="ui"):
    y = np.zeros(nsamp(gap * len(notes) + decay + 0.4))
    part = ((1, 1, 1), (2.0, 0.22, 0.6), (3.0, 0.08, 0.35), (4.01, 0.04, 0.2))
    for i, f in enumerate(notes):
        add_at(y, bell(decay + 0.3, f, decay, partials=part, amp=amp), nsamp(i * gap))
    rng = rng_for(seed)
    return reverb(y, make_ir(wetrt, rng, predelay=0.01, stereo=False), wet=0.25, tail=True)


def ui_notification_chime():
    return _chime([783.99, 1174.66], 0.16, 0.7, seed="ui_notif")


def ui_success_chime():
    return _chime([523.25, 659.26, 783.99], 0.10, 0.6, seed="ui_ok")


def ui_error_soft():
    y = np.zeros(nsamp(0.7))
    add_at(y, tone(0.20, 329.6, harm=(1.0, 0.3), attack=0.01, release=0.08, amp=0.6), 0)
    add_at(y, tone(0.30, 261.6, harm=(1.0, 0.3), attack=0.01, release=0.15, amp=0.6), nsamp(0.17))
    return lowpass(y, 2500, 2)


def phone_notification():
    part = ((1, 1, 1), (2.0, 0.18, 0.5), (3.0, 0.06, 0.3))
    y = np.zeros(nsamp(1.4))
    for i, (f, t0) in enumerate(((1318.5, 0.0), (1568.0, 0.09), (2093.0, 0.18))):
        add_at(y, bell(0.8, f, 0.4, partials=part, amp=0.7), nsamp(t0))
    rng = rng_for("phone")
    return reverb(y, make_ir(0.35, rng, predelay=0.005, stereo=False), wet=0.2, tail=True)


def pa_chime():
    """Two-tone platform PA attention chime through a horn speaker."""
    part = ((1, 1, 1), (2.0, 0.3, 0.6), (2.99, 0.12, 0.4), (4.02, 0.06, 0.3))
    y = np.zeros(nsamp(2.2))
    add_at(y, bell(1.4, 659.26, 0.9, partials=part, amp=0.8), 0)
    add_at(y, bell(1.6, 523.25, 1.1, partials=part, amp=0.8), nsamp(0.55))
    y = speaker_eq(y, 300, 6000)
    rng = rng_for("pa_chime")
    return reverb(y, make_ir(1.0, rng, predelay=0.02, stereo=False), wet=0.3, tail=True)


# --------------------------------------------------------------------------------------
# footsteps
# --------------------------------------------------------------------------------------
def make_footstep(surface, i):
    rng = rng_for(f"footstep_{surface}_{i}")
    return footstep(surface, rng)


def escalator_step_on():
    rng = rng_for("escalator_step_on")
    f = footstep("escalator", rng, shoe=0.85)
    n = nsamp(0.9)
    y = np.zeros(n)
    add_at(y, f, nsamp(0.0))
    # tread scrape as the step accelerates the foot away, and the handrail/motor load
    t = np.arange(nsamp(0.5)) / SR
    scr = band_noise(len(t), rng, 1400, 6000, 2) * np.sin(np.pi * np.clip(t / 0.5, 0, 1)) ** 2 * 0.12
    add_at(y, scr, nsamp(0.05))
    add_at(y, damped_sine(0.5, 62, 0.2, amp=0.35), nsamp(0.03))
    add_at(y, sum_pad(damped_sine(0.3, 420, 0.1, amp=0.2), noise_burst(0.05, rng, 800, 3500, 0.02, amp=0.25)), nsamp(0.22))
    return y * np.clip((n - np.arange(n)) / (0.1 * SR), 0, 1)


# --------------------------------------------------------------------------------------
# tunnel one-shots
# --------------------------------------------------------------------------------------
def distant_train_a():
    return distant_train(11.0, rng_for("dtr_a"), speed=1.0, pan=(-0.7, 0.5))


def distant_train_b():
    return distant_train(14.0, rng_for("dtr_b"), speed=0.8, pan=(0.6, -0.4))


def distant_train_c():
    return distant_train(9.0, rng_for("dtr_c"), speed=1.25, pan=(-0.3, 0.8))


def distant_train_d():
    return distant_train(16.0, rng_for("dtr_d"), speed=0.7, clack=False, pan=(0.2, -0.6))


def wind_push():
    return wind_gust(9.0, rng_for("wind_push"), peak_at=0.78)


def wind_push_short():
    return wind_gust(4.8, rng_for("wind_push_short"), peak_at=0.75, strength=0.7)


# --------------------------------------------------------------------------------------
# busker: Karplus-Strong steel/nylon arpeggio in a reverberant tiled space
# --------------------------------------------------------------------------------------
def ks_pluck(f, dur, rng, brightness=0.5, t60=2.6, pos=0.18, amp=1.0):
    L = max(4, int(round(SR / f - 0.5)))
    f_act = SR / (L + 0.5)
    n = nsamp(dur * f / f_act) + L * 2
    ex = rng.uniform(-1, 1, L)
    for _ in range(int(2 + (1 - brightness) * 5)):
        ex = 0.5 * (ex + np.roll(ex, 1))
    p = max(1, int(pos * L))
    ex = ex - np.roll(ex, p)
    ex *= np.hanning(L) ** 0.3
    ex -= ex.mean()
    ex /= np.max(np.abs(ex)) + 1e-9
    per = f_act
    g = 10 ** (-3.0 / (per * t60))
    y = np.zeros(n + L + 2)
    y[:L] = ex
    s = L
    while s < n:
        e = min(s + L, y.shape[0])
        m = e - s
        a = y[s - L:s - L + m]
        b = y[s - L - 1:s - L - 1 + m] if s - L - 1 >= 0 else np.concatenate([[0.0], y[s - L:s - L + m - 1]])
        y[s:e] = g * 0.5 * (a + b)
        s += L
    y = y[:n]
    # retune by resampling (f_act -> f)
    ratio = f / f_act
    m = int(len(y) / ratio)
    idx = np.arange(m) * ratio
    yy = np.interp(idx, np.arange(len(y)), y)
    fade = int(0.05 * SR)
    yy[-fade:] *= np.linspace(1, 0, fade)
    return amp * yy[:nsamp(dur)]


def guitar_body(x):
    """A few body / top-plate resonances."""
    out = x.copy()
    for f0, q, g in ((98, 6.0, 0.55), (205, 8.0, 0.5), (390, 7.0, 0.3), (1150, 6.0, 0.14), (2400, 5.0, 0.08)):
        out = out + g * signal.sosfilt(resonator_sos(f0, q), x)
    return out


def busker_loop():
    rng = rng_for("busker_loop")
    seconds = 20.0
    n = nsamp(seconds)
    bpm = 96.0
    e8 = 60.0 / bpm / 2.0                       # eighth note
    hz = lambda m: 440.0 * 2 ** ((m - 69) / 12.0)
    # chord voicings as MIDI: [bass, 5th, root8, 3rd, 5th8]
    chords = {
        "Am": [45, 52, 57, 60, 64],
        "F": [41, 48, 53, 57, 60],
        "C": [48, 52, 55, 60, 64],
        "G": [43, 50, 55, 59, 62],
    }
    prog = ["Am", "F", "C", "G", "Am", "F", "C", "G"]
    patt_a = [0, 2, 3, 4, 3, 2, 1, 3]
    patt_b = [0, 2, 3, 4, 3, 4, 2, 3]
    mel = {  # a little top-line in the second half (midi, eighth index in bar)
        4: [(0, 76), (3, 72), (6, 69)],
        5: [(0, 72), (3, 69), (6, 65)],
        6: [(0, 76), (3, 79), (6, 76)],
        7: [(0, 74), (3, 71), (6, 67)],
    }
    y = np.zeros((n, 2))
    for bar, ch in enumerate(prog):
        notes = chords[ch]
        patt = patt_a if bar % 2 == 0 else patt_b
        for k in range(8):
            t0 = (bar * 8 + k) * e8 + rng.normal(0, 0.006)
            m = notes[patt[k]]
            vel = (1.0 if k == 0 else 0.62 if k % 2 == 0 else 0.5) * rng.uniform(0.85, 1.12)
            note = ks_pluck(hz(m), 3.4, rng, brightness=0.45 if m < 50 else 0.55, t60=3.2 * (110 / hz(m)) ** 0.25,
                            pos=rng.uniform(0.12, 0.25), amp=vel * (1.25 if m < 50 else 1.0))
            pan = np.interp(m, [40, 76], [-0.35, 0.35])
            l, r = pan_gains(pan)
            add_at(y[:, 0], note, nsamp(t0), l, wrap=True)
            add_at(y[:, 1], note, nsamp(t0), r, wrap=True)
            # finger noise at the pluck
            fn = noise_burst(0.03, rng, 1200, 6000, 0.008, amp=0.05 * vel)
            add_at(y[:, 0], fn, nsamp(t0), l, wrap=True)
            add_at(y[:, 1], fn, nsamp(t0), r, wrap=True)
        for k, m in [(k, m) for k, m in mel.get(bar, [])]:
            t0 = (bar * 8 + k) * e8 + rng.normal(0, 0.008)
            note = ks_pluck(hz(m), 2.8, rng, brightness=0.6, t60=2.4, pos=0.15, amp=1.15 * rng.uniform(0.9, 1.1))
            l, r = pan_gains(0.25)
            add_at(y[:, 0], note, nsamp(t0), l, wrap=True)
            add_at(y[:, 1], note, nsamp(t0), r, wrap=True)
    for c in range(2):
        y[:, c] = guitar_body(y[:, c])
    y = highpass(y, 70, 2, periodic=True)
    y = lowpass(y, 8500, 2, periodic=True)
    # tiled tube-hall space
    ir = make_ir(2.8, rng, predelay=0.028, band_mult=(1.1, 1.0, 0.75, 0.4), n_early=18, early_span=0.09)
    out = 0.75 * y + 0.9 * reverb(y, ir, wet=1.0, dry=0.0, circular=True)
    return out.astype(np.float32)


# --------------------------------------------------------------------------------------
# registry
# --------------------------------------------------------------------------------------
def _reg():
    from train import train_arrive_platform, train_depart_platform, train_pass_through
    R = {}

    def add(name, fn, group, category, norm, volume_db, desc, loop=False, bitrate=96, spatial="3d"):
        R[name] = dict(fn=fn, group=group, category=category, norm=norm, volume_db=volume_db, desc=desc,
                       loop=loop, bitrate=bitrate, spatial=spatial)

    P = "peak"
    L = "lufs"
    add("door_chime_open", door_chime_open_audio, "sfx/door", "sfx_door", (P, -8.0), -3.0, "Soft two-tone 'ding-dong' as doors unlock")
    add("door_chime_close", door_chime_close_audio, "sfx/door", "sfx_door", (P, -8.0), -3.0, "Two-tone closing warning, eight alternating beeps")
    add("door_slide_open", door_slide_open_audio, "sfx/door", "sfx_door", (P, -6.0), -3.0, "Pneumatic sliding door opening")
    add("door_slide_close", door_slide_close_audio, "sfx/door", "sfx_door", (P, -5.0), -3.0, "Sliding doors closing with seal thud")
    add("gate_beep_ok", gate_beep_ok, "sfx/gate", "sfx_gate", (P, -8.0), -3.0, "Contactless reader accept beep")
    add("gate_beep_error", gate_beep_error, "sfx/gate", "sfx_gate", (P, -8.0), -3.0, "Reader reject: three low buzzy beeps")
    add("gate_flap_open", gate_flap_open, "sfx/gate", "sfx_gate", (P, -8.0), -3.0, "Fare gate flaps retracting")
    add("gate_flap_close", gate_flap_close, "sfx/gate", "sfx_gate", (P, -7.0), -3.0, "Fare gate flaps closing")
    for s in ("tile", "concrete", "rubber", "metal", "escalator"):
        for i in range(1, 7):
            add(f"footstep_{s}_{i}", (lambda s=s, i=i: make_footstep(s, i)), "sfx/footsteps", "sfx_footstep",
                (P, -7.0), -3.0, f"Footstep on {s}, variation {i}", bitrate=64)
    add("escalator_step_on", escalator_step_on, "sfx/footsteps", "sfx_footstep", (P, -7.0), -3.0, "Stepping onto an escalator")
    add("ticket_machine_beep", ticket_beep, "sfx/ticket", "sfx_ui_world", (P, -9.0), -3.0, "Ticket machine button beep", bitrate=64)
    add("ticket_machine_confirm", ticket_confirm, "sfx/ticket", "sfx_ui_world", (P, -9.0), -3.0, "Ticket machine confirmation", bitrate=64)
    add("ticket_machine_error", ticket_error, "sfx/ticket", "sfx_ui_world", (P, -9.0), -3.0, "Ticket machine error buzz", bitrate=64)
    add("coin_drop", coin_drop, "sfx/ticket", "sfx_ui_world", (P, -8.0), -3.0, "Coins dropping into the change tray", bitrate=64)
    add("ticket_machine_print", ticket_print, "sfx/ticket", "sfx_ui_world", (P, -10.0), -3.0, "Thermal ticket printing and cut", bitrate=64)
    add("ui_click_soft", ui_click_soft, "sfx/ui", "ui", (P, -10.0), 0.0, "Soft UI click", bitrate=64, spatial="2d")
    add("ui_hover_soft", ui_hover_soft, "sfx/ui", "ui", (P, -16.0), 0.0, "Very soft hover tick", bitrate=64, spatial="2d")
    add("ui_notification_chime", ui_notification_chime, "sfx/ui", "ui", (P, -9.0), 0.0, "Two-note notification chime", bitrate=64, spatial="2d")
    add("ui_success_chime", ui_success_chime, "sfx/ui", "ui", (P, -9.0), 0.0, "Rising three-note success chime", bitrate=64, spatial="2d")
    add("ui_error_soft", ui_error_soft, "sfx/ui", "ui", (P, -11.0), 0.0, "Soft falling error tones", bitrate=64, spatial="2d")
    add("phone_notification", phone_notification, "sfx/ui", "ui", (P, -9.0), 0.0, "Phone message ping", bitrate=64, spatial="2d")
    add("pa_chime", pa_chime, "sfx/pa", "sfx_pa", (P, -8.0), -3.0, "Platform PA two-tone attention chime", bitrate=64)
    for k, fn in zip("abcd", (distant_train_a, distant_train_b, distant_train_c, distant_train_d)):
        add(f"distant_train_rumble_{k}", fn, "sfx/train", "sfx_train", (L, -27.0), -3.0, "Train passing in another tunnel, heard through walls", spatial="2d")
    add("wind_gust_tunnel_air_push", wind_push, "sfx/train", "sfx_train", (P, -6.0), -3.0, "Air pushed ahead of an arriving train (long)", spatial="2d")
    add("wind_gust_tunnel_air_push_short", wind_push_short, "sfx/train", "sfx_train", (P, -8.0), -3.0, "Smaller tunnel air push (short)", spatial="2d")
    add("train_arrive_platform", train_arrive_platform, "sfx/train", "sfx_train", ("none",), 0.0,
        "Train approaching, braking and stopping at the platform (~25 s, ends at rest; continue with train_idle_platform_loop)", bitrate=112, spatial="2d")
    add("train_depart_platform", train_depart_platform, "sfx/train", "sfx_train", ("none",), 0.0,
        "Door chime, doors close, brake release, traction whine, train leaves into the tunnel (~21 s)", bitrate=112, spatial="2d")
    add("train_pass_through_a", lambda: train_pass_through("pass_a"), "sfx/train", "sfx_train", ("none",), 0.0,
        "Non-stopping train passing through the station at speed (~24 s)", bitrate=112, spatial="2d")
    add("train_pass_through_b", lambda: train_pass_through("pass_b"), "sfx/train", "sfx_train", ("none",), 0.0,
        "Slower non-stopping pass-through (~30 s)", bitrate=112, spatial="2d")
    add("busker_loop", busker_loop, "sfx/music", "music", (L, -24.0), -3.0,
        "Busker fingerpicking a plucked-guitar arpeggio (Am-F-C-G) in a reverberant hall, 20 s loop", loop=True, spatial="3d")
    return R


REGISTRY = None


def registry():
    global REGISTRY
    if REGISTRY is None:
        REGISTRY = _reg()
    return REGISTRY
