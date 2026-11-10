"""Synthesised sound effects and ambient loops (original, deterministic)."""
from __future__ import annotations

import os
import wave

import numpy as np

from art_common import ROOT

SR = 22050
OUT = os.path.join(ROOT, "assets", "sfx")
rng = np.random.default_rng(1234)


def t_(d):
    return np.arange(int(SR * d)) / SR


def env(n, a=0.005, r=0.1, curve=2.0):
    e = np.ones(n)
    na = max(1, int(a * SR))
    nr = max(1, int(r * SR))
    e[:na] = np.linspace(0, 1, na)
    if nr < n:
        e[-nr:] *= np.linspace(1, 0, nr) ** curve
    return e


def expdec(n, k):
    return np.exp(-np.arange(n) / SR * k)


def noise(n):
    return rng.uniform(-1, 1, n)


def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y


def lp_fast(x, cutoff):
    """One-pole lowpass via scipy-free vectorised trick (approx with moving avg)."""
    k = max(1, int(SR / cutoff / 2))
    c = np.convolve(x, np.ones(k) / k, mode="same")
    return c


def hp(x, cutoff):
    return x - lp_fast(x, cutoff)


def sq(f, t):
    return np.sign(np.sin(2 * np.pi * f * t))


def write(name, x, gain=0.8):
    os.makedirs(OUT, exist_ok=True)
    x = np.asarray(x, np.float64)
    peak = np.max(np.abs(x)) or 1.0
    x = x / peak * gain
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def loopify(x, fade=0.02):
    n = int(fade * SR)
    head = x[:n].copy()
    x = x[:-n].copy() if n else x
    x[:n] = x[:n] * np.linspace(0, 1, n) + x[-n:] * 0  # soft start
    x[-n:] = x[-n:] * np.linspace(1, 0, n) + head * np.linspace(0, 1, n)
    return x


def drill(base, grit, metal=0.0, d=0.6):
    t = t_(d)
    trem = 0.75 + 0.25 * np.sin(2 * np.pi * 28 * t)
    w = np.sin(2 * np.pi * base * t + 2 * np.sin(2 * np.pi * 7 * t)) * 0.5
    w += sq(base * 2, t) * 0.12
    g = hp(noise(len(t)), 600) * grit
    clank = np.zeros(len(t))
    if metal:
        for k in range(int(d * 18)):
            p = int(rng.integers(0, len(t) - 800))
            ring = np.sin(2 * np.pi * rng.uniform(1800, 2600) * t_(0.03)) * expdec(int(SR * 0.03), 120)
            clank[p:p + len(ring)] += ring * metal
    x = (w + g) * trem + clank
    return loopify(x)


def impact(freq, noise_amt, dec, d=0.18, pitch_drop=0.5):
    t = t_(d)
    f = freq * (1 - pitch_drop * t / d)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * expdec(len(t), dec)
    x += lp_fast(noise(len(t)), 2500) * noise_amt * expdec(len(t), dec * 1.4)
    return x


def crunch(d=0.35, bright=3000, grains=26):
    t = t_(d)
    x = np.zeros(len(t))
    for k in range(grains):
        p = int(rng.integers(0, int(len(t) * 0.7)))
        g = lp_fast(noise(int(SR * 0.02)), rng.uniform(bright * 0.4, bright)) * expdec(int(SR * 0.02), 140)
        x[p:p + len(g)] += g * rng.uniform(0.3, 1.0)
    x += impact(90, 0.6, 18, d) * 0.8
    return x * env(len(t), 0.001, d * 0.6)


def chime(notes, d=0.5, step=0.06):
    t = t_(d)
    x = np.zeros(len(t))
    for i, f in enumerate(notes):
        p = int(i * step * SR)
        n = len(t) - p
        tt = np.arange(n) / SR
        tone = (np.sin(2 * np.pi * f * tt) + 0.35 * np.sin(2 * np.pi * f * 2.76 * tt) * expdec(n, 20)) * expdec(n, 7)
        x[p:] += tone
    return x


def sweep(f0, f1, d, wave_="sin"):
    t = t_(d)
    f = np.linspace(f0, f1, len(t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) if wave_ == "sin" else np.sign(np.sin(ph))


def pad_loop(chords, dur_each, root_noise=0.05, bright=0.3, name="amb"):
    """Slow evolving pad. chords: list of lists of frequencies."""
    parts = []
    for ch in chords:
        t = t_(dur_each)
        x = np.zeros(len(t))
        for i, f in enumerate(ch):
            det = 1 + 0.003 * (i - 1)
            x += np.sin(2 * np.pi * f * det * t + np.sin(2 * np.pi * 0.2 * t) * 0.5)
            x += bright * np.sin(2 * np.pi * f * 2.001 * t) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.11 * t + i))
        e = np.minimum(1, np.minimum(t / 1.5, (dur_each - t) / 1.5))
        parts.append(x * np.clip(e, 0, 1))
    # overlap-add with 1.5 s crossfade
    n_each = int(dur_each * SR)
    hop = int((dur_each - 1.5) * SR)
    total = hop * len(parts)
    out = np.zeros(total + n_each)
    for i, p in enumerate(parts):
        out[i * hop:i * hop + n_each] += p
    # wrap tail into head for seamless loop
    tail = out[total:]
    out = out[:total]
    out[:len(tail)] += tail
    out += lp_fast(noise(len(out)), 400) * root_noise
    return out


def main():
    write("drill_soft", drill(170, 0.55))
    write("drill_hard", drill(260, 0.35, metal=0.5))
    write("drill_metal", drill(520, 0.2, metal=1.0))
    write("drill_idle", loopify(np.sin(2 * np.pi * 90 * t_(0.5)) * 0.3 + hp(noise(int(SR * 0.5)), 2000) * 0.05), 0.4)
    write("hit_soft", impact(140, 1.0, 30, 0.12))
    write("hit_hard", impact(320, 0.6, 40, 0.12) + chime([1400], 0.12) * 0.15)
    write("hit_metal", impact(900, 0.2, 35, 0.2, 0.1) + chime([2100, 3170], 0.2, 0.0) * 0.4)
    write("break_soft", crunch(0.3, 2200, 22))
    write("break_hard", crunch(0.45, 4200, 40))
    write("ore", chime([988, 1319, 1976], 0.6, 0.05), 0.6)
    write("ore_rare", chime([784, 1175, 1568, 2349], 0.9, 0.07), 0.6)
    write("pickup", chime([1319, 1760], 0.25, 0.04), 0.5)
    write("jump", sweep(220, 520, 0.12, "sq") * env(int(SR * 0.12), 0.002, 0.08) * 0.4 + hp(noise(int(SR * 0.12)), 3000) * 0.2 * expdec(int(SR * 0.12), 30), 0.5)
    write("jet", hp(noise(int(SR * 0.3)), 900) * env(int(SR * 0.3), 0.01, 0.2) + sweep(120, 260, 0.3) * 0.3, 0.55)
    write("land", impact(110, 0.8, 35, 0.12), 0.5)
    write("step", impact(180, 0.6, 80, 0.05), 0.25)
    write("hurt", sweep(600, 180, 0.25, "sq") * env(int(SR * 0.25), 0.002, 0.15) * 0.5 + crunch(0.25) * 0.4, 0.7)
    write("death", sweep(400, 60, 1.0, "sq") * env(int(SR * 1.0), 0.01, 0.8) * 0.5 + crunch(1.0, 2000, 60), 0.8)
    boom = lp_fast(noise(int(SR * 1.2)), 600) * expdec(int(SR * 1.2), 3.5) + impact(55, 0.0, 4, 1.2, 0.6) * 1.2 + crunch(1.2, 3000, 50) * 0.5
    write("explode", boom, 0.95)
    write("fuse", np.sin(2 * np.pi * 1760 * t_(0.05)) * env(int(SR * 0.05), 0.001, 0.03), 0.4)
    write("throw", hp(noise(int(SR * 0.15)), 2500) * env(int(SR * 0.15), 0.01, 0.1), 0.35)
    hiss = hp(noise(int(SR * 1.0)), 3500) * (0.8 + 0.2 * np.sin(2 * np.pi * 9 * t_(1.0)))
    write("gas_hiss", loopify(hiss), 0.45)
    write("gas_warn", np.concatenate([sweep(300, 900, 0.5) * 0.4 + hp(noise(int(SR * 0.5)), 3000) * np.linspace(0, 1, int(SR * 0.5))]), 0.6)
    whoomp = lp_fast(noise(int(SR * 0.9)), 900) * env(int(SR * 0.9), 0.05, 0.7) + sweep(80, 200, 0.9) * env(int(SR * 0.9), 0.05, 0.6)
    write("ignite", whoomp, 0.9)
    al = np.concatenate([sq(660, t_(0.18)), sq(880, t_(0.18))] * 3) * 0.5
    write("alarm", lp_fast(al, 3000), 0.55)
    write("sentry_warn", sweep(500, 1400, 0.6, "sq") * 0.3 * (np.sin(2 * np.pi * 16 * t_(0.6)) > 0), 0.5)
    write("sentry_shot", sweep(1800, 300, 0.16, "sq") * env(int(SR * 0.16), 0.001, 0.12) * 0.5, 0.5)
    write("sentry_die", sweep(900, 50, 0.8, "sq") * env(int(SR * 0.8), 0.001, 0.6) * 0.4 + crunch(0.8, 4000) * 0.6, 0.8)
    scr = sweep(900, 1500, 0.35) * (1 + 0.6 * np.sin(2 * np.pi * 40 * t_(0.35))) * env(int(SR * 0.35), 0.02, 0.2)
    write("crawler_alert", scr + hp(noise(int(SR * 0.35)), 2000) * 0.3, 0.5)
    write("crawler_hit", impact(260, 1.0, 40, 0.15) + sweep(700, 400, 0.15) * 0.3, 0.6)
    write("crawler_die", crunch(0.5, 2000) + sweep(800, 200, 0.5) * env(int(SR * 0.5), 0.01, 0.4) * 0.4, 0.7)
    write("crawler_bite", impact(400, 1.0, 50, 0.1), 0.6)
    rum = lp_fast(noise(int(SR * 1.6)), 180) * env(int(SR * 1.6), 0.3, 0.8) * (1 + 0.4 * np.sin(2 * np.pi * 6 * t_(1.6)))
    write("rumble", rum, 0.9)
    write("rubble", crunch(0.4, 1800, 30), 0.7)
    write("lift_hum", loopify(np.sin(2 * np.pi * 70 * t_(1.0)) * 0.6 + sq(140, t_(1.0)) * 0.08 + hp(noise(SR), 3000) * 0.04), 0.5)
    write("lift_ding", chime([1047, 1319], 0.9, 0.18), 0.6)
    write("ui_click", impact(1200, 0.1, 120, 0.04, 0.0), 0.35)
    write("ui_confirm", chime([880, 1320], 0.25, 0.05), 0.45)
    write("ui_deny", sweep(220, 160, 0.18, "sq") * env(int(SR * 0.18), 0.002, 0.1), 0.4)
    write("ui_buy", chime([660, 990, 1320, 1980], 0.6, 0.05), 0.55)
    write("relic", chime([523, 659, 784, 1047, 1319, 1568], 1.6, 0.11), 0.7)
    write("overheat", sweep(1200, 400, 0.4) * 0.4 + hp(noise(int(SR * 0.4)), 4000) * 0.5 * env(int(SR * 0.4), 0.01, 0.3), 0.55)

    # ambient loops (A minor-ish drones, original)
    def m(n):
        return 440.0 * 2 ** ((n - 69) / 12)

    write("amb_dust", pad_loop([[m(45), m(52), m(57)], [m(43), m(50), m(55)], [m(41), m(48), m(57)], [m(43), m(50), m(59)]], 6.0, 0.08, 0.25), 0.35)
    write("amb_spore", pad_loop([[m(42), m(49), m(54), m(61)], [m(40), m(47), m(56)], [m(45), m(52), m(57), m(64)], [m(44), m(51), m(59)]], 6.5, 0.04, 0.4), 0.33)
    write("amb_engine", pad_loop([[m(36), m(43), m(51)], [m(37), m(44), m(52)], [m(36), m(42), m(51)], [m(34), m(41), m(49)]], 5.0, 0.1, 0.5), 0.35)
    write("amb_outpost", pad_loop([[m(48), m(55), m(64)], [m(45), m(52), m(60)], [m(53), m(57), m(65)], [m(50), m(55), m(62)]], 5.5, 0.02, 0.3), 0.33)
    write("amb_aqueduct", pad_loop([[m(38), m(45), m(53), m(57)], [m(41), m(48), m(55)], [m(36), m(43), m(52), m(55)], [m(43), m(50), m(57)]], 7.0, 0.07, 0.2), 0.33)
    write("amb_crystal", pad_loop([[m(49), m(56), m(61), m(68)], [m(47), m(54), m(63)], [m(52), m(59), m(64), m(71)], [m(51), m(58), m(66)]], 6.0, 0.02, 0.6), 0.3)


if __name__ == "__main__":
    main()
