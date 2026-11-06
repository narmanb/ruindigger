"""Procedural parallax background layers and a seamless cave backdrop.

Three layers per stratum:
  far  - distant shaft structures / horizon silhouettes
  mid  - silhouetted pipes, roots, machinery
  near - foreground broken cables and debris frames
Layers are horizontally tileable so the camera can scroll indefinitely.
"""
from __future__ import annotations

import json
import math

from canvas import Canvas, save_png, shade, mix, clamp8
from palette import STRATA, STRATUM_ORDER
from rng import Rng

W, H = 512, 288


def _fade_bg(c: Canvas, top, bottom):
    for y in range(H):
        t = y / (H - 1)
        col = mix(top, bottom, t)
        c.hline(0, W - 1, y, col)


def _silhouette_hill(c, rng, y_base, amp, col, roughness=8):
    y = y_base
    pts = []
    x = 0
    while x <= W:
        pts.append((x, y))
        x += rng.randint(roughness, roughness * 3)
        y += rng.randint(-amp, amp)
        y = max(y_base - amp * 3, min(y_base + amp * 3, y))
    pts.append((W, y_base + amp * 6))
    pts.append((0, y_base + amp * 6))
    c.polygon(pts, col)


def _shaft_tower(c, rng, x, w, y0, y1, col, light):
    c.rect(x, y0, w, y1 - y0, col)
    c.vline(x, y0, y1, shade(col, 1.18))
    c.vline(x + w - 1, y0, y1, shade(col, 0.72))
    for yy in range(y0 + 6, y1, rng.randint(10, 22)):
        c.hline(x + 1, x + w - 2, yy, shade(col, 0.8))
        if rng.chance(0.5):
            c.rect(x + 2, yy + 1, 2, 2, shade(light, 1.0))
    # gantry
    if rng.chance(0.7):
        gw = rng.randint(w, w * 2)
        gy = y0 + rng.randint(4, 14)
        c.rect(x - gw // 2, gy, gw, 2, shade(col, 0.85))


def _pipe(c, rng, col, light):
    x = rng.randint(0, W)
    y = rng.randint(10, H - 40)
    w = rng.randint(40, 200)
    th = rng.randint(4, 8)
    for i in range(w):
        xx = (x + i) % W
        yy = y + int(math.sin((x + i) * 0.02) * 8)
        c.vline(xx, yy, yy + th, col)
        c.set(xx, yy, shade(light, 1.1))
        c.set(xx, yy + th, shade(col, 0.6))
    # flange rings
    for i in range(0, w, rng.randint(20, 48)):
        xx = (x + i) % W
        yy = y + int(math.sin((x + i) * 0.02) * 8)
        c.rect(xx - 1, yy - 1, 3, th + 2, shade(light, 1.0))


def _root(c, rng, col, light):
    x = rng.randint(0, W)
    y = 0
    w = rng.randint(3, 7)
    while y < H - 20:
        xx = x + int(math.sin(y * 0.05) * 12)
        c.rect(xx, y, w, 2, col)
        c.vline(xx, y, y + 1, shade(light, 1.0))
        y += 2
        if rng.chance(0.06):
            bx = xx
            for _ in range(rng.randint(6, 16)):
                bx += rng.randint(-2, 2)
                y += 1
                c.set(bx, y, col)
                c.set(bx + 1, y, shade(col, 0.8))


def _cable(c, rng, col, light):
    x0 = rng.randint(0, W)
    x1 = x0 + rng.randint(60, 200)
    y0 = rng.randint(0, 40)
    sag = rng.randint(20, 70)
    steps = abs(x1 - x0)
    for i in range(steps):
        t = i / max(1, steps)
        x = (x0 + i) % W
        y = y0 + math.sin(t * math.pi) * sag
        c.set(x, int(y), col)
        c.set(x, int(y) + 1, shade(col, 0.7))
        if i % 12 == 0:
            c.set(x, int(y) - 1, shade(light, 1.2))


def make_layer(stratum_name: str, layer: str) -> Canvas:
    st = STRATA[stratum_name]
    rng = Rng(abs(hash((stratum_name, layer))) % 0xFFFFFF)
    c = Canvas(W, H)
    if layer == "far":
        _fade_bg(c, mix(st["bg_top"], st["fog"], 0.5), st["bg_bot"])
        _silhouette_hill(c, rng, H - 90, 6, shade(mix(st["bg_top"], st["fog"], 0.75), 0.8))
        for _ in range(6):
            _shaft_tower(c, rng, rng.randint(0, W - 40), rng.randint(16, 46),
                         rng.randint(H - 150, H - 90), H, shade(mix(st["bg_top"], st["fog"], 0.9), 0.85),
                         st["accent"])
        # faint window lights
        for _ in range(40):
            c.blend(rng.randint(0, W - 1), rng.randint(H - 140, H - 30),
                    (st["accent"][0], st["accent"][1], st["accent"][2], rng.randint(25, 70)))
    elif layer == "mid":
        base = shade(mix(st["bg_top"], st["fog"], 0.6), 0.7)
        _silhouette_hill(c, rng, H - 40, 8, base)
        for _ in range(5):
            _pipe(c, rng, shade(base, 0.9), st["prop"])
        if stratum_name == "spore_veins":
            for _ in range(7):
                _root(c, rng, shade(base, 0.95), st["prop"])
        elif stratum_name == "forgotten_engine":
            for _ in range(8):
                x = rng.randint(0, W - 30)
                y = rng.randint(20, H - 60)
                c.rect(x, y, rng.randint(10, 30), rng.randint(8, 20), base)
                c.hline(x, x + 20, y, st["accent"], blend=True)
        # glow motes
        for _ in range(50):
            c.sparkle(rng.randint(0, W - 1), rng.randint(0, H - 1), rng.randint(1, 3),
                      (st["accent"][0], st["accent"][1], st["accent"][2], rng.randint(15, 45)))
    else:  # near
        base = shade(st["fog"], 0.55)
        for _ in range(4):
            _cable(c, rng, base, st["prop"])
        for _ in range(3):
            _root(c, rng, shade(base, 0.9), st["prop"])
        for _ in range(10):
            x = rng.randint(0, W)
            y = rng.randint(0, H)
            c.polygon([(x, y), (x + rng.randint(4, 12), y + 2), (x + 3, y + 8)], base)
    return c


def build(out_dir: str) -> dict:
    meta = {"size": [W, H], "layers": {}}
    for name in STRATUM_ORDER:
        for layer in ("far", "mid", "near"):
            img = make_layer(name, layer)
            save_png(f"{out_dir}/bg_{name}_{layer}.png", img)
        meta["layers"][name] = ["far", "mid", "near"]
    with open(f"{out_dir}/bg.json", "w") as fh:
        json.dump(meta, fh, indent=1)
    return meta
