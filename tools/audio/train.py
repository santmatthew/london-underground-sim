"""Moving-train one-shots (arrive / depart / pass-through), synthesised from a kinematic model.

Geometry: track along x, listener at x=0 on the platform (3.5 m from the track centre), platform
spans x in [-65, 65].  A train is modelled as three sound clusters trailing the nose (front, middle
and rear cars).  Each cluster contributes band-limited wheel/rail noise whose level follows
distance and speed, plus (for the front cluster) Doppler-shifted traction/regen whine, rail-joint
clatter locked to distance travelled and (arrival) brake squeal and air release.
"""
from __future__ import annotations

import numpy as np
from scipy import signal

from dsp import (SR, add_at, band_noise, db2lin, env_ar, highpass, interp_env, limit, lowpass, make_ir, mod_gain,
                 nsamp, pan_gains, peak_db, reverb, rms, rng_for, smooth_random, spec_noise, normalize, lufs)
from synth_common import damped_sine, noise_burst, sum_pad, wind_gust

C_SOUND = 343.0
BANDS = [(30, 110), (110, 300), (300, 800), (800, 2000), (2000, 5000), (5000, 12000)]
BAND_LEVEL = np.array([0.9, 1.0, 1.1, 1.15, 0.95, 0.55])
BAND_SPEED_EXP = np.array([0.7, 0.9, 1.1, 1.3, 1.6, 1.9])      # noise rises faster with speed at HF
BAND_DIST_EXP = np.array([0.40, 0.45, 0.5, 0.6, 0.7, 0.8])      # HF dies faster with distance
BAND_TUNNEL_LOSS_DB = np.array([8.0, 12.0, 18.0, 24.0, 30.0, 36.0])  # muffling while a cluster is inside the tunnel
BAND_PAN = np.array([0.35, 0.45, 0.65, 0.85, 1.0, 1.0])
OFFSETS = np.array([8.0, 55.0, 105.0])       # metres behind the nose: front / middle / rear cluster
WEIGHTS = np.array([1.0, 0.9, 0.75])
LAT = 3.5                                    # listener distance from the track centre line
V_REF = 12.0


def sstep(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)


def kinematics(kind, n):
    t = np.arange(n) / SR
    if kind == "arrive":
        tb, a, v0, x0 = 7.5, 0.75, 12.0, -51.0
        tau = np.maximum(t - tb, 0)
        tau = np.minimum(tau, v0 / a)
        v = np.where(t < tb, v0, np.maximum(v0 - a * (t - tb), 0))
        x = np.where(t < tb, x0 + v0 * (t - tb), x0 + v0 * tau - 0.5 * a * tau ** 2)
        return t, v, x, dict(t_brake=tb, t_stop=tb + v0 / a)
    if kind == "depart":
        t0, a, vmax, x_rest = 6.6, 1.0, 13.0, 45.0
        tau = np.maximum(t - t0, 0)
        tm = vmax / a
        v = np.minimum(a * tau, vmax)
        x = np.where(tau < tm, x_rest + 0.5 * a * tau ** 2, x_rest + 0.5 * a * tm ** 2 + vmax * (tau - tm))
        return t, v, x, dict(t_go=t0)
    if kind.startswith("pass"):
        v0 = 17.0 if kind == "pass_a" else 11.0
        x = -215.0 + v0 * t if kind == "pass_a" else -160.0 + v0 * t
        return t, np.full(n, v0), x, dict()
    raise ValueError(kind)


def _clack_pool(rng, k=8):
    pool = []
    for _ in range(k):
        e = sum_pad(damped_sine(0.25, rng.uniform(58, 85), 0.10, amp=1.5),
                    damped_sine(0.2, rng.uniform(180, 260), 0.05, amp=0.5),
                    noise_burst(0.2, rng, 250, 2600, 0.05, amp=0.9),
                    noise_burst(0.03, rng, 2500, 8000, 0.01, amp=0.3))
        pool.append(e)
    return pool


def render_moving(kind, seconds, rng, with_tones=True, tone_mode=None, squeal=False, wind=None, joint_spacing=7.5):
    """Return stereo roar part (unscaled) for the given kinematic profile."""
    n = nsamp(seconds)
    t, v, xn, info = kinematics(kind, n)
    xs = xn[:, None] - OFFSETS[None, :]                       # (n, 3) cluster positions
    r = np.sqrt(xs ** 2 + LAT ** 2)
    tunnel = sstep((np.abs(xs) - 65.0) / 15.0)                # (n, 3)
    pan = np.clip(xs / 50.0, -1, 1)
    out = np.zeros((n, 2))
    vr = np.clip(v / V_REF, 0, 2.5)
    for b, (lo, hi) in enumerate(BANDS):
        prox = (LAT / r) ** BAND_DIST_EXP[b]                   # (n, 3)
        g = WEIGHTS[None, :] * prox * 10 ** (-tunnel * BAND_TUNNEL_LOSS_DB[b] / 20.0)
        pb = pan * BAND_PAN[b]
        gl = np.sum(g * np.cos((np.clip(pb, -1, 1) + 1) * np.pi / 4), axis=1)
        gr = np.sum(g * np.sin((np.clip(pb, -1, 1) + 1) * np.pi / 4), axis=1)
        sp = vr ** BAND_SPEED_EXP[b]
        for c, gc in enumerate((gl, gr)):
            nz = band_noise(n, rng, lo, hi, 2, slope=0.0)
            slow = mod_gain(n, rng, 1.2 + 0.3 * b, 1.5)
            out[:, c] += BAND_LEVEL[b] * nz * gc * sp * slow
    # ---- rail joint clatter locked to distance travelled
    dist = xn - xn[0]
    k = np.floor(dist / joint_spacing)
    idx = np.nonzero(np.diff(k) > 0)[0]
    pool = _clack_pool(rng)
    for i in idx:
        gfront = (LAT / r[i, 0]) ** 0.6 * (1 - 0.5 * tunnel[i, 0])
        gmid = 0.7 * (LAT / r[i, 1]) ** 0.6 * (1 - 0.5 * tunnel[i, 1])
        a = (gfront + gmid) * (vr[i] ** 0.7) * 0.55
        if a < 0.004:
            continue
        e = pool[int(rng.integers(0, len(pool)))]
        # distance makes it duller
        near = np.clip((LAT / r[i, 0]) ** 0.8 * 2.0, 0, 1)
        e = near * e + (1 - near) * lowpass(e, 700, 2)
        p = np.clip(pan[i, 0], -1, 1)
        l, rr = pan_gains(p * 0.8)
        add_at(out[:, 0], e, i, a * l * rng.uniform(0.75, 1.2))
        add_at(out[:, 1], e, i, a * rr * rng.uniform(0.75, 1.2))
    # ---- traction / regen whine (front cluster), Doppler shifted, stepped pitch
    if with_tones:
        if tone_mode == "regen":
            gate = sstep((t - info["t_brake"]) / 0.6) * sstep(v / 1.4)
            f_base = 120 + 65 * (np.round(v / 0.9) * 0.9)
            amp = 0.30
        elif tone_mode == "accel":
            gate = sstep((t - info["t_go"] + 0.3) / 0.5)
            f_base = 110 + 68 * (np.floor(v / 1.7) * 1.7)
            amp = 0.34
        else:
            gate = np.zeros(n)
            f_base = np.zeros(n)
            amp = 0.0
        if amp > 0:
            k_f = int(0.05 * SR)
            f_base = signal.lfilter([1 / k_f] * k_f, [1], np.concatenate([np.full(k_f, f_base[0]), f_base]))[k_f:]
            toward = -(xs[:, 0] / r[:, 0]) * v
            dop = C_SOUND / (C_SOUND - toward)
            f = f_base * dop * (1 + 0.004 * smooth_random(n, rng, 6))
            ph = 2 * np.pi * np.cumsum(f) / SR
            tw = np.sin(ph) + 0.5 * np.sin(2 * ph + 0.7) + 0.28 * np.sin(3 * ph + 1.9) + 0.12 * np.sin(5 * ph)
            prox = (LAT / r[:, 0]) ** 0.7 * (1 - 0.6 * tunnel[:, 0])
            a_t = amp * gate * prox * np.clip(0.4 + 0.6 * np.minimum(v / 6.0, 1.0), 0, 1)
            l, rr = pan_gains(np.clip(pan[:, 0], -1, 1))
            out[:, 0] += tw * a_t * l
            out[:, 1] += tw * a_t * rr
    # ---- brake squeal
    if squeal:
        win = sstep((3.8 - v) / 1.2) * sstep(v / 0.4) * (t > info["t_brake"])
        z = smooth_random(n, rng, 4.0)
        gate = sstep((z + 0.1) / 0.6)
        f_sq = (2400 + 1500 * np.clip(v / 3.8, 0, 1)) * (1 + 0.02 * smooth_random(n, rng, 9))
        ph = 2 * np.pi * np.cumsum(f_sq) / SR
        sq = np.sin(ph) + 0.55 * np.sin(2.02 * ph + 0.4) + 0.25 * np.sin(3.01 * ph + 1.1)
        sq += 0.5 * band_noise(n, rng, 2200, 4200, 2)
        xm = xs[:, 1] + 25
        rm = np.sqrt(xm ** 2 + LAT ** 2)
        a_q = 0.10 * win * gate * (LAT / rm) ** 0.5
        l, rr = pan_gains(np.clip(xm / 50, -1, 1))
        out[:, 0] += sq * a_q * l
        out[:, 1] += sq * a_q * rr
    # ---- tunnel air push
    if wind is not None:
        w = wind_gust(wind["dur"], rng, peak_at=wind["peak_at"], strength=wind.get("strength", 1.0))
        w = w / (rms(w) + 1e-9)
        add_at(out[:, 0], w[:, 0], nsamp(wind["at"]), wind["gain"])
        add_at(out[:, 1], w[:, 1], nsamp(wind["at"]), wind["gain"])
    return out, dict(t=t, v=v, xn=xn, **info)


def station_reverb(x, rng, wet=0.35, rt=2.0):
    ir = make_ir(rt, rng, predelay=0.02, band_mult=(1.2, 1.0, 0.65, 0.35))
    return reverb(x, ir, wet=wet, tail=False)


def _hiss(dur, rng, lo, hi, decay, attack=0.02, amp=1.0):
    return noise_burst(dur, rng, lo, hi, decay, attack=attack, amp=amp)


def _idle_bed(offset_s, n):
    """Slice of the shared idle loop (same bed the platform game loop uses) so levels match."""
    from ambience import train_idle_platform_loop
    loop, _ = train_idle_platform_loop()
    loop = loop.astype(np.float64)
    idx = (np.arange(n) + int(offset_s * SR)) % len(loop)
    return loop[idx]


def scale_to_peak(x, target_db):
    return x * db2lin(target_db - peak_db(x))


def scale_shortterm(x, target_lufs, win=3.0, ceiling=-1.5):
    """Scale so the loudest ``win``-second window has the given LUFS, then peak limit."""
    w = int(win * SR)
    hop = int(0.5 * SR)
    best = -99.0
    for i in range(0, max(1, len(x) - w + 1), hop):
        best = max(best, lufs(x[i:i + w]))
    y = x * db2lin(target_lufs - best)
    return limit(y, ceiling)


# --------------------------------------------------------------------------------------
def train_arrive_platform():
    rng = rng_for("train_arrive_platform")
    secs = 25.0
    n = nsamp(secs)
    R, info = render_moving("arrive", secs, rng, tone_mode="regen", squeal=True,
                            wind=dict(dur=7.0, peak_at=0.80, at=0.4, gain=0.17, strength=0.25))
    t = info["t"]
    ts = info["t_stop"]
    # air release + brake set at standstill
    tail = np.zeros((n, 2))
    hs = _hiss(3.0, rng, 1800, 11000, 1.7, 0.03, 0.55)
    for c, gch in enumerate((1.0, 0.92)):
        add_at(tail[:, c], hs * gch, nsamp(ts - 0.15))
        add_at(tail[:, c], _hiss(1.2, rng, 2500, 10000, 0.5, 0.02, 0.22), nsamp(ts + 0.85), gch)
        add_at(tail[:, c], [damped_sine(0.4, 58, 0.16, amp=0.6), noise_burst(0.08, rng, 200, 1800, 0.03, amp=0.4)],
               nsamp(ts - 0.25), gch)
    R = R + tail * 1.0
    R = station_reverb(R, rng, wet=0.35, rt=2.0)
    R = scale_shortterm(R, -15.0)
    # idle bed fades in as the train settles
    idle = _idle_bed(4.6, n)
    fade = sstep((t - (ts - 3.0)) / 3.6)
    out = R + idle * fade[:, None]
    # gentle level bookkeeping: no end fade (ends at rest, continues into train_idle_platform_loop)
    out = limit(out, -1.5)
    return out.astype(np.float32), dict(loop=False, tail="rest")


def train_depart_platform():
    from sfx import door_chime_close_audio, door_slide_close_audio
    rng = rng_for("train_depart_platform")
    secs = 21.0
    n = nsamp(secs)
    R, info = render_moving("depart", secs, rng, tone_mode="accel", squeal=False)
    t = info["t"]
    t0 = info["t_go"]
    fore = np.zeros((n, 2))
    # contactors / brake release
    for c, gch in enumerate((1.0, 0.92)):
        add_at(fore[:, c], _hiss(2.6, rng, 1600, 10500, 1.3, 0.02, 0.5), nsamp(5.0), gch)
        add_at(fore[:, c], _hiss(0.8, rng, 2500, 10000, 0.3, 0.02, 0.25), nsamp(5.9), gch)
        for dt in (t0 - 0.35, t0 - 0.12):
            add_at(fore[:, c], [noise_burst(0.06, rng, 600, 3500, 0.02, amp=0.5),
                                damped_sine(0.1, 130, 0.04, amp=0.4)], nsamp(dt), gch * 0.7)
    R = R * 1.0 + fore
    R = station_reverb(R, rng, wet=0.35, rt=2.0)
    R = scale_shortterm(R, -16.0)
    R *= np.clip((secs - t) / 3.0, 0, 1)[:, None] ** 1.5      # gone into the tunnel
    idle = _idle_bed(25.0, n)
    idle_fade = 1 - sstep((t - (t0 - 0.6)) / 2.5)
    out = R + idle * idle_fade[:, None]
    # door sequence: chime, doors close
    chime = door_chime_close_audio()
    slide = door_slide_close_audio()
    for c in range(2):
        add_at(out[:, c], scale_to_peak(chime, -13.0), nsamp(1.0))
        add_at(out[:, c], scale_to_peak(slide, -15.0), nsamp(3.3))
    out = limit(out, -1.5)
    return out.astype(np.float32), dict(loop=False)


def train_pass_through(kind):
    rng = rng_for("train_pass_through_" + kind)
    secs = 24.0 if kind == "pass_a" else 30.0
    R, info = render_moving(kind, secs, rng, tone_mode=None,
                            wind=dict(dur=6.5, peak_at=0.82, at=0.4 if kind == "pass_a" else 1.5, gain=0.17, strength=0.25))
    R = station_reverb(R, rng, wet=0.3, rt=1.8)
    n = R.shape[0]
    R = scale_shortterm(R, -13.0)
    t = np.arange(n) / SR
    R *= np.clip(t / 0.25, 0, 1)[:, None] * np.clip((secs - t) / 2.0, 0, 1)[:, None]
    return R.astype(np.float32), dict(loop=False)
