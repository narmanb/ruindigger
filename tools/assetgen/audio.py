"""Procedural sound synthesis for RUIN DIGGER.

Every sound is generated from scratch as raw samples (stdlib only, no audio
libraries, no sampled commercial audio). Output is 16-bit mono PCM WAV.
"""
from __future__ import annotations

import math
import struct
import wave

from rng import Rng

SR = 22050


def _write(path, samples):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for s in samples:
            v = int(max(-1.0, min(1.0, s)) * 32000)
            frames += struct.pack("<h", v)
        w.writeframes(bytes(frames))


def _env(i, n, a=0.01, d=0.1, s=0.7, r=0.2):
    t = i / n
    if t < a:
        return t / a
    if t < a + d:
        return 1.0 - (1.0 - s) * ((t - a) / d)
    if t < 1.0 - r:
        return s
    return s * max(0.0, (1.0 - t) / r)


def _noise(rng, n):
    return [rng.uniform(-1, 1) for _ in range(n)]


def _lowpass(buf, alpha):
    out = []
    prev = 0.0
    for x in buf:
        prev = prev + alpha * (x - prev)
        out.append(prev)
    return out


def _highpass(buf, alpha):
    out = []
    prev_in = 0.0
    prev_out = 0.0
    for x in buf:
        prev_out = alpha * (prev_out + x - prev_in)
        prev_in = x
        out.append(prev_out)
    return out


def _sine(freq, t):
    return math.sin(math.tau * freq * t)


def dig_soft(seed=1):
    rng = Rng(seed)
    n = int(SR * 0.16)
    noise = _lowpass(_noise(rng, n), 0.22)
    out = []
    for i in range(n):
        t = i / SR
        e = _env(i, n, a=0.004, d=0.05, s=0.35, r=0.3)
        body = _sine(90 - 30 * (i / n), t) * 0.4
        out.append((noise[i] * 0.7 + body) * e)
    return out


def dig_rock(seed=2):
    rng = Rng(seed)
    n = int(SR * 0.22)
    noise = _highpass(_noise(rng, n), 0.6)
    out = []
    for i in range(n):
        t = i / SR
        e = _env(i, n, a=0.002, d=0.03, s=0.25, r=0.35)
        clank = (_sine(420 - 120 * (i / n), t) + 0.5 * _sine(630, t) + 0.3 * _sine(980, t))
        out.append((noise[i] * 0.35 + clank * 0.35) * e)
    return out


def dig_alloy(seed=3):
    rng = Rng(seed)
    n = int(SR * 0.26)
    noise = _highpass(_noise(rng, n), 0.75)
    out = []
    for i in range(n):
        t = i / SR
        e = _env(i, n, a=0.002, d=0.05, s=0.2, r=0.45)
        ring = (_sine(1200, t) * 0.3 + _sine(1810, t) * 0.22 + _sine(2450, t) * 0.16)
        out.append((noise[i] * 0.25 + ring) * e)
    return out


def drill_loop(seed=4):
    rng = Rng(seed)
    n = int(SR * 0.5)
    out = []
    for i in range(n):
        t = i / SR
        wob = 1.0 + 0.06 * math.sin(math.tau * 7 * t)
        buzz = 0.0
        for h in range(1, 9):
            buzz += (1.0 / h) * _sine(140 * h * wob, t)
        noise = rng.uniform(-1, 1) * 0.25
        e = 1.0 if i > 400 else i / 400
        e *= 1.0 if i < n - 800 else (n - i) / 800
        out.append((buzz * 0.35 + noise * 0.3) * e)
    return _lowpass(out, 0.5)


def explosion(seed=5):
    rng = Rng(seed)
    n = int(SR * 0.7)
    noise = _lowpass(_noise(rng, n), 0.06)
    out = []
    for i in range(n):
        t = i / SR
        e = _env(i, n, a=0.002, d=0.08, s=0.5, r=0.55)
        boom = _sine(70 * math.exp(-2.5 * t) + 28, t) * 0.9
        crack = _lowpass(_noise(rng, 1), 0.5)[0] * 0.5 * math.exp(-12 * t)
        out.append((noise[i] * 0.9 + boom + crack) * e)
    return out


def gas_hiss(seed=6):
    rng = Rng(seed)
    n = int(SR * 0.9)
    noise = _highpass(_lowpass(_noise(rng, n), 0.35), 0.5)
    out = []
    for i in range(n):
        e = _env(i, n, a=0.03, d=0.2, s=0.4, r=0.5)
        out.append(noise[i] * 0.6 * e)
    return out


def rattle(seed=7):
    rng = Rng(seed)
    n = int(SR * 1.0)
    out = []
    for i in range(n):
        t = i / SR
        e = _env(i, n, a=0.05, d=0.2, s=0.6, r=0.5)
        rumble = _lowpass(_noise(rng, 1), 0.02)[0] * 0.8
        trem = 0.6 + 0.4 * math.sin(math.tau * 18 * t)
        out.append(rumble * e * trem)
    return _lowpass(out, 0.12)


def ore_chime(seed=8):
    n = int(SR * 0.45)
    out = []
    freqs = [880, 1320, 1760]
    for i in range(n):
        t = i / SR
        e = _env(i, n, a=0.004, d=0.15, s=0.35, r=0.5)
        s = 0.0
        for k, f in enumerate(freqs):
            s += _sine(f, t) * (0.5 ** k)
        out.append(s * 0.35 * e)
    return out


def hurt(seed=9):
    n = int(SR * 0.3)
    out = []
    for i in range(n):
        t = i / SR
        e = _env(i, n, a=0.003, d=0.08, s=0.4, r=0.5)
        s = _sine(220 * math.exp(-4 * t) + 60, t) * 0.6 + _sine(330, t) * 0.2
        out.append(s * e)
    return out


def jump(seed=10):
    n = int(SR * 0.16)
    out = []
    for i in range(n):
        t = i / SR
        f = 260 + 420 * (i / n)
        e = _env(i, n, a=0.004, d=0.05, s=0.3, r=0.5)
        out.append(_sine(f, t) * 0.4 * e)
    return out


def land(seed=11):
    rng = Rng(seed)
    n = int(SR * 0.14)
    noise = _lowpass(_noise(rng, n), 0.15)
    out = []
    for i in range(n):
        t = i / SR
        e = _env(i, n, a=0.002, d=0.04, s=0.2, r=0.5)
        out.append((noise[i] * 0.7 + _sine(120, t) * 0.4) * e)
    return out


def alarm(seed=12):
    n = int(SR * 0.8)
    out = []
    for i in range(n):
        t = i / SR
        beep = 0.5 + 0.5 * math.copysign(1, math.sin(math.tau * 3 * t))
        e = _env(i, n, a=0.01, d=0.05, s=0.85, r=0.15)
        out.append(_sine(660, t) * 0.35 * e * beep)
    return out


def laser(seed=13):
    n = int(SR * 0.22)
    out = []
    for i in range(n):
        t = i / SR
        f = 1400 - 900 * (i / n)
        e = _env(i, n, a=0.002, d=0.06, s=0.4, r=0.4)
        out.append((_sine(f, t) * 0.5 + _sine(f * 1.5, t) * 0.2) * e)
    return out


def enemy_death(seed=14):
    rng = Rng(seed)
    n = int(SR * 0.5)
    noise = _lowpass(_noise(rng, n), 0.12)
    out = []
    for i in range(n):
        t = i / SR
        e = _env(i, n, a=0.002, d=0.1, s=0.4, r=0.5)
        s = noise[i] * 0.7 + _sine(300 * math.exp(-3 * t) + 50, t) * 0.5
        out.append(s * e)
    return out


def ui_click(seed=15):
    n = int(SR * 0.06)
    out = []
    for i in range(n):
        t = i / SR
        e = _env(i, n, a=0.002, d=0.02, s=0.2, r=0.6)
        out.append((_sine(900, t) * 0.3 + _sine(1400, t) * 0.15) * e)
    return out


def purchase(seed=16):
    n = int(SR * 0.6)
    out = []
    notes = [523, 659, 784, 1046]
    for i in range(n):
        t = i / SR
        idx = min(len(notes) - 1, int((i / n) * len(notes)))
        e = _env(i, n, a=0.005, d=0.05, s=0.7, r=0.2)
        out.append(_sine(notes[idx], t) * 0.3 * e)
    return out


def extract_win(seed=17):
    n = int(SR * 1.2)
    out = []
    notes = [392, 523, 659, 784, 1046]
    for i in range(n):
        t = i / SR
        idx = min(len(notes) - 1, int((i / n) * len(notes)))
        e = _env(i, n, a=0.01, d=0.1, s=0.75, r=0.25)
        s = _sine(notes[idx], t) * 0.28 + _sine(notes[idx] * 2, t) * 0.08
        out.append(s * e)
    return out


SOUNDS = {
    "dig_soft": dig_soft, "dig_rock": dig_rock, "dig_alloy": dig_alloy,
    "drill_loop": drill_loop, "explosion": explosion, "gas_hiss": gas_hiss,
    "rattle": rattle, "ore_chime": ore_chime, "hurt": hurt, "jump": jump,
    "land": land, "alarm": alarm, "laser": laser, "enemy_death": enemy_death,
    "ui_click": ui_click, "purchase": purchase, "extract_win": extract_win,
}


def build(out_dir: str) -> dict:
    import os
    os.makedirs(out_dir, exist_ok=True)
    for i, (name, fn) in enumerate(SOUNDS.items()):
        _write(f"{out_dir}/{name}.wav", fn(100 + i * 7))
    return {"count": len(SOUNDS)}
