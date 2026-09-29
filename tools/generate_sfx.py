#!/usr/bin/env python3
"""Procedural SFX test generator. Writes 44.1 kHz mono 16-bit WAVs to audio_test/."""
import subprocess
import wave
from pathlib import Path

import numpy as np

SR = 44100
OUT = Path(__file__).resolve().parent.parent / "audio_test"


def pink_noise(n, rng):
    white = rng.standard_normal(n)
    spec = np.fft.rfft(white)
    freqs = np.fft.rfftfreq(n, 1 / SR)
    freqs[0] = freqs[1]
    spec /= np.sqrt(freqs)
    out = np.fft.irfft(spec, n)
    return out / np.max(np.abs(out))


def svf_bandpass(x, cutoff, q):
    """State-variable band-pass; cutoff may be an array (Hz) for sweeps."""
    cutoff = np.broadcast_to(cutoff, x.shape)
    f = 2 * np.sin(np.pi * np.clip(cutoff, 20, SR * 0.45) / SR)
    damp = 1.0 / q
    low = band = 0.0
    out = np.empty_like(x)
    for i in range(len(x)):
        low += f[i] * band
        high = x[i] - low - damp * band
        band += f[i] * high
        out[i] = band
    return out


def one_pole_lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    out = np.empty_like(x)
    y = 0.0
    for i in range(len(x)):
        y = (1 - a) * x[i] + a * y
        out[i] = y
    return out


def env(n, attack, release, curve=2.0):
    t = np.arange(n) / SR
    dur = n / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    r = np.clip((dur - t) / max(release, 1e-4), 0, 1) ** curve
    return a * r


def bell(n, peak, width):
    """Smooth 0..1..0 bump centered at `peak` (0..1 of duration)."""
    x = np.linspace(0, 1, n)
    return np.exp(-((x - peak) ** 2) / (2 * width**2))


def norm(x, peak=0.9):
    return x / (np.max(np.abs(x)) + 1e-9) * peak


def gas_burst(seed, dur=0.55):
    rng = np.random.default_rng(seed)
    n = int(dur * SR)
    noise = pink_noise(n, rng)
    hiss = svf_bandpass(noise, np.linspace(5500, 3500, n), 0.9)
    body = svf_bandpass(noise, np.linspace(1800, 900, n), 0.7)
    thump = np.sin(2 * np.pi * np.linspace(90, 45, n) * np.arange(n) / SR)
    thump *= np.exp(-np.arange(n) / SR * 22)
    e_fast = env(n, 0.004, dur * 0.9, 2.5)
    e_body = env(n, 0.01, dur * 0.7, 2.0)
    sig = norm(hiss) * e_fast + 0.6 * norm(body) * e_body + 0.45 * thump
    return sig


def gas_hiss_loop(seed, dur=1.6):
    rng = np.random.default_rng(seed)
    n = int(dur * SR)
    noise = pink_noise(n, rng)
    wobble = 1 + 0.12 * np.sin(2 * np.pi * 3.1 * np.arange(n) / SR)
    hiss = svf_bandpass(noise, 3000 * wobble, 0.7)
    body = svf_bandpass(noise, 1100, 0.6)
    sig = norm(hiss) * 0.7 + norm(body) * 0.5
    sig = one_pole_lowpass(sig, 4500)
    fade = int(0.25 * SR)
    head, tail = sig[:fade].copy(), sig[-fade:].copy()
    ramp = np.linspace(0, 1, fade)
    sig[:fade] = head * ramp + tail * (1 - ramp)
    return sig[:-fade]


def whoosh(seed, dur=0.7, lo=500, hi=3200, peak=0.4):
    rng = np.random.default_rng(seed)
    n = int(dur * SR)
    noise = pink_noise(n, rng)
    sweep = lo + (hi - lo) * bell(n, peak, 0.22)
    sig = norm(svf_bandpass(noise, sweep, 1.2))
    sig *= bell(n, peak, 0.2) * env(n, 0.02, 0.08, 1.0)
    low = norm(svf_bandpass(noise, sweep * 0.35, 0.8)) * bell(n, peak + 0.05, 0.25)
    return sig + 0.5 * low


def blade_swing(seed, dur=0.32):
    rng = np.random.default_rng(seed)
    base = whoosh(seed, dur, lo=750, hi=2800, peak=0.45)
    base = one_pole_lowpass(base, 4000)
    n = len(base)
    t = np.arange(n) / SR
    ring = sum(
        np.sin(2 * np.pi * f * (1 + rng.uniform(-0.01, 0.01)) * t) / (i + 1)
        for i, f in enumerate([1500, 2250])
    )
    ring *= bell(n, 0.45, 0.12) * 0.12
    return base + norm(ring, 0.12)


def decay(n, rate):
    return np.exp(-np.arange(n) / SR * rate)


def thump(n, f0, f1, rate):
    freq = np.linspace(f0, f1, n)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    return np.sin(phase) * decay(n, rate)


def footstep_player(seed, dur=0.22):
    rng = np.random.default_rng(seed)
    n = int(dur * SR)
    f0 = rng.uniform(110, 150)
    body = thump(n, f0, 55, 28)
    grit = one_pole_lowpass(rng.standard_normal(n), rng.uniform(1800, 2800)) * decay(n, 45)
    click = svf_bandpass(rng.standard_normal(n), 3200, 1.5) * decay(n, 200)
    return norm(body) * 0.8 + norm(grit) * 0.55 + norm(click) * 0.2


def footstep_titan(seed, dur=1.1):
    rng = np.random.default_rng(seed)
    n = int(dur * SR)
    boom = thump(n, rng.uniform(55, 70), 24, 5.5)
    sub = thump(n, 34, 20, 3.5)
    rumble = one_pole_lowpass(pink_noise(n, rng), 220) * decay(n, 6)
    crack = one_pole_lowpass(rng.standard_normal(n), 900) * decay(n, 60)
    return norm(boom) + 0.7 * norm(sub) + 0.6 * norm(rumble) + 0.25 * norm(crack)


def impact_land(seed, dur=0.4):
    rng = np.random.default_rng(seed)
    n = int(dur * SR)
    body = thump(n, 95, 40, 14)
    dust = one_pole_lowpass(rng.standard_normal(n), 1500) * decay(n, 22)
    return norm(body) + 0.5 * norm(dust)


def impact_hard(seed, dur=0.35):
    rng = np.random.default_rng(seed)
    n = int(dur * SR)
    body = thump(n, 160, 60, 20)
    crack = svf_bandpass(rng.standard_normal(n), 2200, 0.9) * decay(n, 55)
    debris = one_pole_lowpass(rng.standard_normal(n), 3000) * decay(n, 18)
    return norm(body) * 0.8 + norm(crack) * 0.7 + 0.3 * norm(debris)


def gas_refill(seed, dur=0.28):
    rng = np.random.default_rng(seed)
    n = int(dur * SR)
    noise = pink_noise(n, rng)
    hiss = svf_bandpass(noise, np.linspace(3200, 4200, n), 0.8)
    return one_pole_lowpass(norm(hiss), 5000) * env(n, 0.03, 0.14, 1.5)


def hook_launch(seed, dur=0.45):
    rng = np.random.default_rng(seed)
    n = int(dur * SR)
    burst = svf_bandpass(pink_noise(n, rng), np.linspace(4500, 2000, n), 0.9) * decay(n, 18)
    zip_ = svf_bandpass(pink_noise(n, rng), np.linspace(900, 3800, n), 2.0)
    zip_ *= env(n, 0.005, dur * 0.8, 1.5) * 0.6
    tone = thump(n, 700, 260, 30)
    click = svf_bandpass(rng.standard_normal(n), 4500, 2.5) * decay(n, 400)
    return norm(burst) + norm(zip_) * 0.7 + 0.35 * norm(tone) + 0.4 * norm(click)


def hook_retract(seed, dur=0.55):
    rng = np.random.default_rng(seed)
    n = int(dur * SR)
    zip_ = svf_bandpass(pink_noise(n, rng), np.linspace(3800, 900, n), 2.0)
    zip_ *= env(n, 0.01, dur * 0.5, 1.2)
    t = np.arange(n) / SR
    rattle = (np.sin(2 * np.pi * 70 * t) > 0.6).astype(float)
    rattle = svf_bandpass(rattle + 0.2 * rng.standard_normal(n), 2600, 1.5) * env(n, 0.01, dur * 0.4, 1.0)
    snap_n = int(0.12 * SR)
    snap = np.zeros(n)
    snap[-snap_n:] = svf_bandpass(rng.standard_normal(snap_n), 2800, 1.5) * decay(snap_n, 50) * 1.0
    snap[-snap_n:] += thump(snap_n, 320, 120, 45) * 0.8
    return norm(zip_) * 0.8 + 0.35 * norm(rattle) + norm(snap) * 0.7


def write_wav(path, x):
    x = np.tanh(norm(x, 1.0) * 1.1)
    pcm = (x * 32767 * 0.95).astype(np.int16)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def finalize(name, x, loop=False):
    raw = OUT / f"_{name}_raw.wav"
    final = OUT / f"{name}.wav"
    write_wav(raw, x)
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", str(raw),
         "-af", "loudnorm=I=-18:TP=-2:LRA=7,highpass=f=40",
         "-ar", str(SR), "-ac", "1", "-sample_fmt", "s16", str(final)],
        check=True,
    )
    raw.unlink()
    print("wrote", final.name)


def main():
    OUT.mkdir(exist_ok=True)
    (OUT / ".gdignore").touch()
    for i in range(3):
        finalize(f"gas_burst_{i:03d}", gas_burst(100 + i, 0.5 + 0.08 * i))
        finalize(f"whoosh_{i:03d}", whoosh(200 + i, 0.6 + 0.12 * i, peak=0.35 + 0.08 * i))
    finalize("gas_hiss_loop", gas_hiss_loop(300), loop=True)
    for i in range(2):
        finalize(f"blade_swing_{i:03d}", blade_swing(400 + i, 0.3 + 0.05 * i))
    for i in range(5):
        finalize(f"footstep_player_{i:03d}", footstep_player(500 + i))
    for i in range(3):
        finalize(f"footstep_titan_{i:03d}", footstep_titan(600 + i, 1.0 + 0.1 * i))
    finalize("impact_land", impact_land(700))
    for i in range(3):
        finalize(f"impact_hard_{i:03d}", impact_hard(710 + i))
    for i in range(2):
        finalize(f"gas_refill_{i:03d}", gas_refill(800 + i, 0.25 + 0.05 * i))
    for i in range(2):
        finalize(f"hook_launch_{i:03d}", hook_launch(900 + i))
        finalize(f"hook_retract_{i:03d}", hook_retract(950 + i))


if __name__ == "__main__":
    main()
