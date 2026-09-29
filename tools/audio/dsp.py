"""Shared DSP helpers for the Underground Sim audio generator.

Everything that has to loop is built to be *periodic by construction*: noise is made in the
frequency domain over exactly N samples, filters are applied circularly, reverbs are circular
convolutions and events are placed with wrap-around.  A loop therefore has identical statistics
(and a continuous waveform) across its seam without any audible crossfade.  ``crossfade_loop``
is provided for material that cannot be made periodic (e.g. long stochastic renders).
"""
from __future__ import annotations

import subprocess
import zlib
from pathlib import Path

import numpy as np
from scipy import signal
from scipy.ndimage import minimum_filter1d, uniform_filter1d

SR = 44100


# --------------------------------------------------------------------------------------
# misc
# --------------------------------------------------------------------------------------
def rng_for(name: str, seed: int = 0) -> np.random.Generator:
    return np.random.default_rng(zlib.crc32(name.encode()) * 7 + 1000003 * seed)


def db2lin(d):
    return 10.0 ** (np.asarray(d) / 20.0)


def lin2db(x):
    return 20.0 * np.log10(np.maximum(np.asarray(x), 1e-12))


def nsamp(seconds: float, sr: int = SR) -> int:
    return int(round(seconds * sr))


def rms(x):
    return float(np.sqrt(np.mean(np.square(x)))) + 1e-20


def norm_rms(x, target=1.0):
    return x * (target / rms(x))


# --------------------------------------------------------------------------------------
# periodic (frequency domain) noise
# --------------------------------------------------------------------------------------
def lp_mag(f, fc, order=2):
    return 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order))


def hp_mag(f, fc, order=2):
    return 1.0 / np.sqrt(1.0 + (fc / f) ** (2 * order))


def bp_mag(f, lo, hi, order=2):
    return hp_mag(f, lo, order) * lp_mag(f, hi, order)


def spec_noise(n: int, rng, mag_fn=None, sr: int = SR, unit_rms: bool = True):
    """Gaussian noise of exactly ``n`` samples (periodic) with amplitude spectrum ``mag_fn(f_hz)``."""
    f = np.fft.rfftfreq(n, 1.0 / sr)
    f[0] = f[1] if len(f) > 1 else 1.0
    mag = np.ones_like(f) if mag_fn is None else mag_fn(f)
    X = (rng.standard_normal(len(f)) + 1j * rng.standard_normal(len(f))) * mag
    X[0] = 0
    if n % 2 == 0:
        X[-1] = X[-1].real
    x = np.fft.irfft(X, n)
    return x / (rms(x)) if unit_rms else x


def pink(n, rng, lo=20.0, hi=None, sr=SR):
    hi = hi or sr * 0.45
    return spec_noise(n, rng, lambda f: f ** -0.5 * bp_mag(f, lo, hi, 2), sr)


def brown(n, rng, lo=15.0, hi=None, sr=SR):
    hi = hi or sr * 0.45
    return spec_noise(n, rng, lambda f: f ** -1.0 * bp_mag(f, lo, hi, 2), sr)


def band_noise(n, rng, lo, hi, order=2, slope=0.0, sr=SR):
    """Band limited periodic noise; ``slope`` = spectral tilt exponent for amplitude (f**slope)."""
    return spec_noise(n, rng, lambda f: (f / 1000.0) ** slope * bp_mag(f, lo, hi, order), sr)


def fft_filter(x, mag_fn, sr=SR):
    """Zero-phase circular filtering of a periodic signal (axis 0)."""
    n = x.shape[0]
    f = np.fft.rfftfreq(n, 1.0 / sr)
    f[0] = f[1]
    m = mag_fn(f)
    X = np.fft.rfft(x, axis=0)
    if x.ndim == 2:
        m = m[:, None]
    return np.fft.irfft(X * m, n, axis=0)


def pfilt(x, sos):
    """Causal IIR filtering of a periodic signal: filter three tiled copies, keep the middle."""
    n = x.shape[0]
    t = np.concatenate([x, x, x], axis=0)
    y = signal.sosfilt(sos, t, axis=0)
    return y[n:2 * n]


def butter_sos(kind, fc, order=2, sr=SR):
    fc = np.asarray(fc, dtype=float)
    return signal.butter(order, fc / (sr / 2.0), btype=kind, output="sos")


def lowpass(x, fc, order=2, sr=SR, periodic=False):
    sos = butter_sos("lowpass", min(fc, sr * 0.49), order, sr)
    return pfilt(x, sos) if periodic else signal.sosfilt(sos, x, axis=0)


def highpass(x, fc, order=2, sr=SR, periodic=False):
    sos = butter_sos("highpass", fc, order, sr)
    return pfilt(x, sos) if periodic else signal.sosfilt(sos, x, axis=0)


def bandpass(x, lo, hi, order=2, sr=SR, periodic=False):
    sos = butter_sos("bandpass", [lo, min(hi, sr * 0.49)], order, sr)
    return pfilt(x, sos) if periodic else signal.sosfilt(sos, x, axis=0)


def peaking_sos(f0, q, gain_db, sr=SR):
    """RBJ peaking EQ as a single biquad sos."""
    A = 10 ** (gain_db / 40)
    w0 = 2 * np.pi * f0 / sr
    al = np.sin(w0) / (2 * q)
    b = [1 + al * A, -2 * np.cos(w0), 1 - al * A]
    a = [1 + al / A, -2 * np.cos(w0), 1 - al / A]
    return signal.tf2sos(b, a)


def resonator_sos(f0, q, sr=SR):
    """Constant-peak-gain 2nd-order band-pass biquad (RBJ)."""
    w0 = 2 * np.pi * f0 / sr
    al = np.sin(w0) / (2 * q)
    b = [al, 0, -al]
    a = [1 + al, -2 * np.cos(w0), 1 - al]
    return signal.tf2sos(b, a)


def smooth_random(n, rng, rate_hz, sr=SR, order=3):
    """Periodic smooth random curve with unit std, bandwidth ~ rate_hz."""
    return spec_noise(n, rng, lambda f: lp_mag(f, rate_hz, order) * hp_mag(f, rate_hz * 0.03, 1), sr)


def mod_gain(n, rng, rate_hz, depth_db, sr=SR):
    """Smooth random gain curve (linear) fluctuating about +-depth_db."""
    z = smooth_random(n, rng, rate_hz, sr)
    return 10 ** (depth_db * z / 20.0)


def periodic_sines(n, rng, freqs_cycles, amps, sr=SR):
    """Sum of sinusoids with an integer number of cycles per loop (perfectly periodic)."""
    t = np.arange(n) / n
    out = np.zeros(n)
    for c, a in zip(freqs_cycles, amps):
        out += a * np.sin(2 * np.pi * c * t + rng.uniform(0, 2 * np.pi))
    return out


# --------------------------------------------------------------------------------------
# envelopes / events
# --------------------------------------------------------------------------------------
def interp_env(n, times, values, sr=SR, kind="linear"):
    """Piecewise envelope defined at ``times`` (seconds) sampled at n samples."""
    t = np.arange(n) / sr
    times = np.asarray(times, dtype=float)
    values = np.asarray(values, dtype=float)
    if kind == "linear":
        return np.interp(t, times, values)
    from scipy.interpolate import PchipInterpolator
    return PchipInterpolator(times, values, extrapolate=True)(np.clip(t, times[0], times[-1]))


def env_ar(n, attack, decay, sr=SR, curve=1.0):
    """Attack / exponential decay envelope of n samples; decay is the 60 dB time."""
    t = np.arange(n) / sr
    a = np.clip(t / max(attack, 1e-5), 0, 1)
    d = np.exp(-6.9078 * t / max(decay, 1e-4))
    return (a ** curve) * d


def add_at(buf, ev, pos, gain=1.0, wrap=False):
    """Add event ``ev`` (1-d or 2-d [n,ch]) into ``buf`` at sample ``pos``.  ``wrap`` for loops."""
    if isinstance(ev, (list, tuple)):
        for e in ev:
            add_at(buf, e, pos, gain, wrap)
        return
    n = buf.shape[0]
    m = ev.shape[0]
    pos = int(pos)
    if wrap:
        pos %= n
        first = min(m, n - pos)
        buf[pos:pos + first] += gain * ev[:first]
        rest = m - first
        while rest > 0:
            k = min(rest, n)
            buf[:k] += gain * ev[m - rest:m - rest + k]
            rest -= k
    else:
        if pos >= n:
            return
        k = min(m, n - pos)
        if pos < 0:
            ev = ev[-pos:]
            k = min(ev.shape[0], n)
            pos = 0
        buf[pos:pos + k] += gain * ev[:k]


def pan_gains(p):
    """Equal-power pan, p in [-1, 1]. Returns (l, r)."""
    a = (np.clip(p, -1, 1) + 1) * np.pi / 4
    return np.cos(a), np.sin(a)


def to_stereo(x, p=0.0):
    l, r = pan_gains(p)
    return np.stack([x * l, x * r], axis=-1)


def decorrelated_stereo(x, rng, amount=0.6, sr=SR):
    """Cheap widening for a mono source: mix with a short-delay, allpass-phased copy."""
    d1 = int(rng.uniform(0.0007, 0.0013) * sr)
    d2 = int(rng.uniform(0.0011, 0.0019) * sr)
    l = x + amount * np.roll(x, d1)
    r = x - amount * np.roll(x, d2)
    return np.stack([l, r], axis=-1) / np.sqrt(1 + amount ** 2)


# --------------------------------------------------------------------------------------
# reverb
# --------------------------------------------------------------------------------------
_BANDS = [(20, 250), (250, 1000), (1000, 4000), (4000, 20000)]


def make_ir(rt60, rng, sr=SR, predelay=0.012, band_mult=(1.15, 1.0, 0.75, 0.45), n_early=14,
            early_span=0.06, early_gain=0.6, length=None, lf_cut=60.0, stereo=True):
    """Synthetic room impulse response: early reflections + frequency dependent exponential tail."""
    length = length or (rt60 * 1.15 + predelay + early_span)
    n = nsamp(length, sr)
    chans = 2 if stereo else 1
    out = np.zeros((n, chans))
    t = np.arange(n) / sr
    for c in range(chans):
        tail = np.zeros(n)
        for (lo, hi), m in zip(_BANDS, band_mult):
            nz = spec_noise(n, rng, lambda f: bp_mag(f, lo, hi, 2), sr, unit_rms=True)
            tail += nz * np.exp(-6.9078 * np.maximum(t - predelay, 0) / (rt60 * m))
        # onset ramp: reverb builds in quickly
        tail *= np.clip((t - predelay) / 0.012, 0, 1)
        tail = highpass(tail, lf_cut, 2, sr)
        # early reflections
        for k in range(n_early):
            tk = predelay + early_span * (rng.random() ** 1.3) + 0.002 * k
            i = int(tk * sr)
            if i < n - 4:
                g = early_gain * rng.choice([-1, 1]) * (0.5 + 0.5 * rng.random()) / (1 + 2.5 * tk / early_span)
                tail[i] += g * np.sqrt(np.mean(tail ** 2)) * 6.0
        out[:, c] = tail
    out /= np.sqrt(np.sum(out ** 2, axis=0, keepdims=True))
    return out if stereo else out[:, 0]


def reverb(x, ir, wet=0.3, dry=1.0, circular=False, tail=True):
    """Convolution reverb.  x: (n,) or (n, ch); ir: (m,) or (m, 2).  ``wet`` is a linear gain on
    the unit-energy IR output (so wet=1 means the reverberant field has the same RMS as a white
    dry signal).  ``circular`` = wrap the tail (seamless loops).  Returns stereo if the IR is."""
    x2 = x if x.ndim == 2 else x[:, None]
    ir2 = ir if ir.ndim == 2 else ir[:, None]
    n = x2.shape[0]
    m = ir2.shape[0]
    nout = n if (circular or not tail) else n + m - 1
    nfft = n if circular else int(2 ** np.ceil(np.log2(n + m)))
    if circular and m > n:
        ir2 = ir2[:n]
    X = np.fft.rfft(x2, nfft, axis=0)
    H = np.fft.rfft(ir2, nfft, axis=0)
    ch_out = max(x2.shape[1], ir2.shape[1])
    Y = np.zeros((nout, ch_out))
    for c in range(ch_out):
        xc = X[:, min(c, X.shape[1] - 1)]
        hc = H[:, min(c, H.shape[1] - 1)]
        y = np.fft.irfft(xc * hc, nfft)
        Y[:, c] = y[:nout]
    dry_sig = np.zeros((nout, ch_out))
    for c in range(ch_out):
        dry_sig[:x2.shape[0], c] = x2[:, min(c, x2.shape[1] - 1)]
    out = dry * dry_sig + wet * Y
    return out if out.shape[1] > 1 else out[:, 0]


# --------------------------------------------------------------------------------------
# loudness (ITU-R BS.1770-4) and limiting
# --------------------------------------------------------------------------------------
def _kweight_sos(sr):
    # stage 1: high shelf
    G, Q, fc = 3.999843853973347, 0.7071752369554196, 1681.974450955533
    A = 10 ** (G / 40.0)
    w0 = 2 * np.pi * fc / sr
    alpha = np.sin(w0) / (2 * Q)
    cw = np.cos(w0)
    b0 = A * ((A + 1) + (A - 1) * cw + 2 * np.sqrt(A) * alpha)
    b1 = -2 * A * ((A - 1) + (A + 1) * cw)
    b2 = A * ((A + 1) + (A - 1) * cw - 2 * np.sqrt(A) * alpha)
    a0 = (A + 1) - (A - 1) * cw + 2 * np.sqrt(A) * alpha
    a1 = 2 * ((A - 1) - (A + 1) * cw)
    a2 = (A + 1) - (A - 1) * cw - 2 * np.sqrt(A) * alpha
    s1 = np.array([[b0 / a0, b1 / a0, b2 / a0, 1.0, a1 / a0, a2 / a0]])
    # stage 2: high pass
    Q2, fc2 = 0.5003270373238773, 38.13547087602444
    w0 = 2 * np.pi * fc2 / sr
    alpha = np.sin(w0) / (2 * Q2)
    cw = np.cos(w0)
    b0 = (1 + cw) / 2
    b1 = -(1 + cw)
    b2 = (1 + cw) / 2
    a0 = 1 + alpha
    a1 = -2 * cw
    a2 = 1 - alpha
    s2 = np.array([[b0 / a0, b1 / a0, b2 / a0, 1.0, a1 / a0, a2 / a0]])
    return np.vstack([s1, s2])


def lufs(x, sr=SR):
    """Integrated loudness (gated). Falls back to ungated for clips shorter than one 400 ms block."""
    x = np.asarray(x, dtype=np.float64)
    if x.ndim == 1:
        x = x[:, None]
    sos = _kweight_sos(sr)
    y = signal.sosfilt(sos, x, axis=0)
    blk = int(0.4 * sr)
    hop = int(0.1 * sr)
    z = y ** 2
    n = z.shape[0]
    if n < blk:
        ms = np.mean(z, axis=0).sum()
        return -0.691 + 10 * np.log10(ms + 1e-20)
    c = np.cumsum(np.vstack([np.zeros((1, z.shape[1])), z]), axis=0)
    starts = np.arange(0, n - blk + 1, hop)
    ms = ((c[starts + blk] - c[starts]) / blk).sum(axis=1)
    l = -0.691 + 10 * np.log10(ms + 1e-20)
    keep = l > -70
    if not keep.any():
        return -70.0
    rel = -0.691 + 10 * np.log10(ms[keep].mean() + 1e-20) - 10
    keep = l > max(rel, -70)
    if not keep.any():
        return -70.0
    return float(-0.691 + 10 * np.log10(ms[keep].mean() + 1e-20))


def peak_db(x):
    return float(lin2db(np.max(np.abs(x)) + 1e-12))


def true_peak_db(x, sr=SR):
    y = signal.resample_poly(x, 4, 1, axis=0)
    return float(lin2db(np.max(np.abs(y)) + 1e-12))


def limit(x, ceiling_db=-1.0, look=0.004, sr=SR, wrap=False):
    """Look-ahead peak limiter (smooth min-filtered gain).  ``wrap`` for loops."""
    c = db2lin(ceiling_db)
    pk = np.max(np.abs(x), axis=1) if x.ndim == 2 else np.abs(x)
    g = np.minimum(1.0, c / np.maximum(pk, 1e-9))
    w = max(1, int(look * sr))
    mode = "wrap" if wrap else "nearest"
    g = minimum_filter1d(g, 2 * w + 1, mode=mode)
    g = uniform_filter1d(g, 2 * w + 1, mode=mode)
    return x * (g[:, None] if x.ndim == 2 else g)


def normalize(x, lufs_target=None, peak_target=None, ceiling_db=-1.0, sr=SR, wrap=False):
    """Scale to an integrated loudness target *or* a sample-peak target, then limit to the ceiling."""
    if lufs_target is not None:
        g = lufs_target - lufs(x, sr)
        y = x * db2lin(g)
    else:
        y = x * db2lin(peak_target - peak_db(x))
    return limit(y, ceiling_db, sr=sr, wrap=wrap)


# --------------------------------------------------------------------------------------
# dynamics (light compressor for PA / speech)
# --------------------------------------------------------------------------------------
def compress(x, thresh_db=-24, ratio=3.0, attack=0.005, release=0.08, makeup_db=0.0, sr=SR):
    env = np.abs(x)
    a = np.exp(-1.0 / (attack * sr))
    r = np.exp(-1.0 / (release * sr))
    # envelope follower (vectorised through lfilter on rectified signal is not exact; use two-pass)
    e = signal.lfilter([1 - r], [1, -r], env)
    e = np.maximum(e, signal.lfilter([1 - a], [1, -a], env))
    ed = lin2db(e + 1e-9)
    over = np.maximum(ed - thresh_db, 0)
    gr = -over * (1 - 1 / ratio)
    return x * db2lin(gr + makeup_db)


def soft_clip(x, drive=1.0):
    return np.tanh(x * drive) / np.tanh(drive)


# --------------------------------------------------------------------------------------
# resampling, looping, IO
# --------------------------------------------------------------------------------------
def resample_to(x, sr_in, sr_out=SR, periodic=False):
    """Polyphase resample; ``periodic`` treats the signal as a loop (no edge effects at the seam)."""
    if sr_in == sr_out:
        return x.astype(np.float64)
    from math import gcd
    g = gcd(sr_in, sr_out)
    up, down = sr_out // g, sr_in // g
    if periodic:
        n = x.shape[0]
        y = signal.resample_poly(np.concatenate([x, x, x], axis=0), up, down, axis=0)
        m = n * up // down
        return y[m:2 * m]
    return signal.resample_poly(x, up, down, axis=0)


def crossfade_loop(x, xfade, sr=SR):
    """Turn a non-periodic render of length N+xfade into a seamless loop of length N by fading
    the excess tail into the head with an equal-power crossfade."""
    L = nsamp(xfade, sr)
    n = x.shape[0] - L
    y = x[:n].copy()
    t = np.linspace(0, np.pi / 2, L)
    fin, fout = np.sin(t), np.cos(t)
    if x.ndim == 2:
        fin, fout = fin[:, None], fout[:, None]
    y[:L] = x[:L] * fin + x[n:n + L] * fout
    return y


def loop_seam_error(x):
    """Ratio between the step across the loop seam and the typical sample-to-sample step."""
    d = np.abs(x[0] - x[-1])
    typ = np.mean(np.abs(np.diff(x, axis=0)), axis=0)
    return float(np.mean(d / (typ + 1e-9)))


def save_ogg(path, x, sr=SR, bitrate=96, quality=None):
    """Encode float array (n,) or (n, ch) to Ogg Vorbis with ffmpeg/libvorbis."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    x = np.asarray(x, dtype=np.float32)
    ch = 1 if x.ndim == 1 else x.shape[1]
    cmd = ["ffmpeg", "-nostdin", "-y", "-loglevel", "error", "-f", "f32le", "-ar", str(sr), "-ac", str(ch),
           "-i", "pipe:0", "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact",
           "-c:a", "libvorbis"]
    cmd += ["-q:a", str(quality)] if quality is not None else ["-b:a", f"{bitrate}k"]
    cmd += [str(path)]
    p = subprocess.run(cmd, input=np.ascontiguousarray(np.clip(x, -1.0, 1.0)).tobytes(), capture_output=True)
    if p.returncode != 0:
        raise RuntimeError(p.stderr.decode()[-500:])


def load_ogg(path, sr=SR):
    """Decode to float32 (n, ch) at native channel count."""
    import json
    pr = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
                         "stream=channels,sample_rate", "-of", "json", str(path)], capture_output=True)
    info = json.loads(pr.stdout)["streams"][0]
    ch = int(info["channels"])
    p = subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-i", str(path), "-f", "f32le", "-ar", str(sr),
                        "-ac", str(ch), "pipe:1"], capture_output=True)
    a = np.frombuffer(p.stdout, dtype=np.float32).reshape(-1, ch)
    return a


def spectrogram_png(x, path, sr=SR, width=1400, height=300, fmin=30, fmax=16000, hop_s=None):
    """Scratch QA image: log-frequency spectrogram (top) + RMS envelope in dB (bottom, 40 dB range)."""
    from PIL import Image, ImageDraw
    if x.ndim == 2:
        x = x.mean(axis=1)
    dur = len(x) / sr
    x = np.concatenate([x, np.zeros(4096)])
    hop = max(256, int(len(x) / width))
    nfft = 4096 if dur > 3 else 2048
    n_frames = max(1, (len(x) - nfft) // hop + 1)
    win = np.hanning(nfft)
    idx = np.arange(nfft)[None, :] + hop * np.arange(n_frames)[:, None]
    S = np.abs(np.fft.rfft(x[idx] * win, axis=1)) ** 2
    f = np.fft.rfftfreq(nfft, 1 / sr)
    edges = np.geomspace(fmin, fmax, height + 1)
    out = np.zeros((height, n_frames))
    for i in range(height):
        m = (f >= edges[i]) & (f < edges[i + 1])
        if not m.any():
            m = np.argmin(np.abs(f - np.sqrt(edges[i] * edges[i + 1])))
            out[i] = S[:, m]
        else:
            out[i] = S[:, m].mean(axis=1)
    L = 10 * np.log10(out + 1e-14)
    L = np.clip((L - (L.max() - 85)) / 85, 0, 1)
    img = np.uint8(L[::-1] * 255)
    im = Image.fromarray(img).resize((width, height))
    frame = int(0.05 * sr)
    n_env = width
    seg = len(x) // n_env
    env = np.array([np.sqrt(np.mean(x[i * seg:(i + 1) * seg] ** 2) + 1e-14) for i in range(n_env)])
    envdb = 20 * np.log10(env + 1e-9)
    top = envdb.max()
    canvas = Image.new("L", (width, height + 110), 0)
    canvas.paste(im, (0, 0))
    d = ImageDraw.Draw(canvas)
    for k in range(0, 41, 10):
        y = height + 105 - int(100 * k / 40)
        d.line([(0, y), (width, y)], fill=60)
    pts = [(i, height + 105 - int(100 * np.clip((envdb[i] - (top - 40)) / 40, 0, 1))) for i in range(n_env)]
    d.line(pts, fill=255)
    for fq in (100, 1000, 10000):
        y = int(height - height * np.log(fq / fmin) / np.log(fmax / fmin))
        d.line([(0, y), (12, y)], fill=255)
    for sec in range(0, int(dur) + 1, 5):
        xx = int(width * sec / dur)
        d.line([(xx, height), (xx, height + 8)], fill=255)
    canvas.save(path)
