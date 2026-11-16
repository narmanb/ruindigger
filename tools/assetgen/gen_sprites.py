"""Character, enemy, prop and pickup sprites (palette-index pixel art)."""
from __future__ import annotations

import json
import math

import numpy as np

from art_common import OUT, Canvas, P, hexc, save, sheet, to_image

META: dict = {}

# --------------------------------------------------------------------------
# Player: 32x32 frames, facing right, feet at y=30, body centred at x=16.
# Drill arm is a separate sheet attached at a per-frame shoulder point.
# --------------------------------------------------------------------------
FW = FH = 32


def draw_leg(c: Canvas, hx, hy, ang_thigh, ang_shin, back=False):
    """Two-segment leg from hip (hx,hy). Angles in radians from straight down."""
    sh = "steel1" if back else "steel2"
    th = 5
    kx = hx + math.sin(ang_thigh) * th
    ky = hy + math.cos(ang_thigh) * th
    fx = kx + math.sin(ang_shin) * 5
    fy = ky + math.cos(ang_shin) * 5
    c.line(hx, hy, kx, ky, P(sh), 3)
    c.line(kx, ky, fx, fy, P("shell1" if back else "shell2"), 3)
    c.px(round(kx), round(ky), P("steel3" if not back else "steel2"))
    # boot
    bx, by = round(fx), round(fy)
    c.rect(bx - 2, by - 1, 5, 2, P("boot1" if back else "boot2"))
    c.rect(bx - 2, by + 1, 6, 1, P("boot0"))
    if not back:
        c.px(bx + 2, by - 1, P("boot3"))


def draw_body(c: Canvas, ox, oy, lean=0, squash=0, hurt=False, blink=False):
    """Torso + helmet + backpack. (ox,oy) is the hip centre."""
    tx = ox + lean
    ty = oy - 9 + squash
    # backpack (behind, to the left)
    c.rect(tx - 9, ty - 1, 5, 9, P("steel1"))
    c.rect(tx - 9, ty - 1, 5, 1, P("steel3"))
    c.rect(tx - 8, ty + 2, 3, 4, P("pack1"))
    c.rect(tx - 8, ty + 3, 2, 2, P("pack2"))
    c.px(tx - 8, ty + 3, P("pack3"))
    c.line(tx - 8, ty - 2, tx - 9, ty - 6, P("steel2"))  # antenna
    c.px(tx - 9, ty - 7, P("red2"))
    # torso shell: boxy armoured chest
    c.rect(tx - 5, ty, 11, 9, P("shell2"))
    c.rect(tx - 4, ty - 1, 9, 1, P("shell2"))
    c.rect(tx - 5, ty + 7, 11, 2, P("shell1"))
    c.rect(tx - 4, ty, 8, 1, P("shell4"))
    c.rect(tx - 5, ty + 1, 2, 5, P("shell3"))
    c.rect(tx + 5, ty + 1, 1, 6, P("shell1"))
    # shoulder pad
    c.rect(tx + 1, ty - 1, 5, 3, P("shell3"))
    c.rect(tx + 2, ty - 1, 3, 1, P("shell4"))
    # hazard stripe chest plate
    for i in range(5):
        c.px(tx - 2 + i, ty + 4, P("hazard1") if i % 2 == 0 else P("hazard0"))
        c.px(tx - 2 + i, ty + 5, P("hazard0") if i % 2 == 0 else P("hazard1"))
    # belt
    c.rect(tx - 5, ty + 8, 11, 1, P("steel1"))
    c.px(tx + 1, ty + 8, P("gold3"))
    # neck collar
    c.rect(tx - 3, ty - 2, 7, 2, P("steel2"))
    c.rect(tx - 3, ty - 2, 7, 1, P("steel4"))
    # helmet
    hx, hy = tx - 1, ty - 10 + (1 if squash > 0 else 0)
    c.ellipse(hx - 4, hy, 12, 10, P("shell2"))
    c.ellipse(hx - 3, hy + 1, 6, 3, P("shell4"))
    c.rect(hx - 4, hy + 7, 12, 2, P("shell1"))
    c.rect(hx - 4, hy + 8, 12, 1, P("ink0"))
    # visor
    vc = "red" if hurt else "visor"
    c.rect(hx + 1, hy + 3, 6, 4, P(vc + "1"))
    c.rect(hx + 2, hy + 3, 5, 2, P(vc + "2"))
    if not blink:
        c.px(hx + 5, hy + 3, P(vc + "3"))
        c.px(hx + 6, hy + 4, P("white0"))
    # helmet lamp
    c.px(hx + 2, hy, P("lamp2"))
    c.px(hx + 3, hy, P("lamp1"))
    return (tx + 3, ty + 3)  # shoulder point


def player_frame(kind: str, t: float):
    c = Canvas(FW, FH)
    hipx, hipy = 16, 20
    lean = 0
    squash = 0
    legs = (0.0, 0.0, 0.0, 0.0)
    hurt = False
    blink = False
    if kind == "idle":
        squash = 1 if t >= 0.5 else 0
        blink = abs(t - 0.75) < 0.01
        legs = (0.15, -0.05, -0.15, 0.05)
    elif kind == "run":
        a = t * math.tau
        lean = 1
        hipy -= int(round(abs(math.sin(a)) * 1.5))
        legs = (math.sin(a) * 0.9, math.sin(a) * 0.9 - max(0, math.cos(a)) * 1.1,
                -math.sin(a) * 0.9, -math.sin(a) * 0.9 - max(0, -math.cos(a)) * 1.1)
    elif kind == "jump":
        legs = (0.6, -0.4, -0.3, -0.9)
        hipy -= 1
    elif kind == "fall":
        legs = (0.3, 0.5, -0.4, 0.2)
        lean = -1 if t > 0.5 else 0
    elif kind == "land":
        squash = 3
        hipy += 2
        legs = (0.9, -0.9, -0.9, 0.9)
    elif kind == "wall":
        legs = (0.6, 0.2, -0.2, 0.6)
        lean = -1
    elif kind == "hurt":
        hurt = True
        lean = -2
        legs = (0.5, 0.3, -0.5, -0.2)
    elif kind == "climb":
        a = t * math.tau
        legs = (math.sin(a) * 0.6, -0.8 + math.sin(a) * 0.5, -math.sin(a) * 0.6, -0.8 - math.sin(a) * 0.5)
    # back leg first
    draw_leg(c, hipx - 1, hipy, legs[2], legs[3], back=True)
    shoulder = draw_body(c, hipx, hipy, lean, squash, hurt, blink)
    draw_leg(c, hipx + 1, hipy, legs[0], legs[1], back=False)
    c.outline()
    return c, shoulder


def gen_player():
    anims = [("idle", 4), ("run", 8), ("jump", 1), ("fall", 2), ("land", 1), ("wall", 1), ("hurt", 1), ("climb", 4)]
    frames = []
    shoulders = []
    meta = {}
    for name, n in anims:
        meta[name] = [len(frames), n]
        for i in range(n):
            cv, sh = player_frame(name, i / n)
            frames.append(cv.rgba())
            shoulders.append(list(sh))
    save(to_image(sheet(frames, FW, FH, 8)), "player.png")
    META["player"] = {"fw": FW, "fh": FH, "cols": 8, "anims": meta, "shoulders": shoulders}


def gen_drill():
    """Drill arm pointing right; 4 spin frames x (idle, active). Pivot at (3,8)."""
    frames = []
    for active in (0, 1):
        for f in range(4):
            c = Canvas(24, 16)
            # upper arm + hydraulic piston
            c.rect(0, 6, 7, 5, P("steel2"))
            c.rect(0, 6, 7, 1, P("steel4"))
            c.rect(1, 10, 6, 1, P("steel1"))
            ext = (f % 2) if active else 0
            c.line(1, 5, 8 + ext, 5, P("steel4"))
            c.px(1, 5, P("steel1"))
            # drill housing
            c.rect(7, 4, 4, 9, P("shell2"))
            c.rect(7, 4, 4, 1, P("shell4"))
            c.rect(7, 12, 4, 1, P("shell0"))
            c.px(9, 6, P("hazard1"))
            c.px(9, 10, P("hazard1"))
            # cone bit
            pts = [(11, 4), (22, 8), (22, 9), (11, 13)]
            c.poly(pts, P("steel3"))
            for k in range(4):
                x = 12 + ((k * 3 + f) % 10)
                hgt = int(4.5 * (1 - (x - 11) / 11.0))
                c.line(x, 8 - hgt, x + 1, 9 + hgt, P("steel1"))
            c.line(11, 5, 20, 8, P("steel4"))
            if active:
                c.px(22, 8, P("gold4"))
                c.px(23, 8, P("lamp2"))
            c.outline()
            frames.append(c.rgba())
    save(to_image(sheet(frames, 24, 16, 4)), "drill.png")
    META["drill"] = {"fw": 24, "fh": 16, "pivot": [3, 8]}


# --------------------------------------------------------------------------
# Burrow Crawler: 32x20, segmented armoured burrower, faces right.
# --------------------------------------------------------------------------
def crawler_frame(kind, t):
    c = Canvas(32, 20)
    a = t * math.tau
    lunge = 3 if kind == "attack" else 0
    segs = 5
    base_y = 13
    for i in range(segs):
        x = 4 + i * 5 + (lunge * i // 4)
        wave = math.sin(a + i * 1.2) * (1.2 if kind == "walk" else 0.4)
        y = base_y + round(wave) - (1 if i == segs - 1 else 0)
        r = 4 if i not in (0,) else 3
        # legs
        lp = math.sin(a * 2 + i * 1.7)
        c.line(x, y + 2, x - 1 + round(lp * 2), 18, P("chit1"))
        c.line(x + 2, y + 2, x + 3 - round(lp * 2), 18, P("chit0"))
        c.ellipse(x - r, y - r, r * 2 + 2, r * 2, P("chit2"))
        c.ellipse(x - r + 1, y - r, r * 2, r, P("chit3"))
        c.px(x - 1, y - r, P("chit4"))
        c.px(x, y + r - 1, P("flesh1"))
        if i < segs - 1:
            c.px(x + r, y, P("flesh2"))
            c.px(x - 1, y - 1, P("teal4"))
    hx = 4 + (segs - 1) * 5 + lunge + 3
    hy = base_y - 2 + round(math.sin(a + segs * 1.2) * 0.4)
    c.ellipse(hx - 4, hy - 4, 9, 9, P("chit2"))
    c.ellipse(hx - 3, hy - 4, 6, 3, P("chit4"))
    # mandibles
    open_ = 2 if kind == "attack" else (1 if t > 0.5 else 0)
    c.line(hx + 4, hy - 1, hx + 7, hy - 1 - open_, P("bone3"))
    c.line(hx + 4, hy + 2, hx + 7, hy + 2 + open_, P("bone3"))
    c.px(hx + 4, hy + 1, P("flesh3"))
    # glowing eyes
    eye = "red" if kind in ("attack", "alert") else "eye"
    c.px(hx + 1, hy - 1, P(eye + "2"))
    c.px(hx + 2, hy - 1, P(eye + "1"))
    c.px(hx + 2, hy, P(eye + "2"))
    if kind == "hurt":
        a2 = c.arr()
        a2[a2 > 0] = P("white0")
        c.set_arr(a2)
    c.outline()
    return c.rgba()


def gen_crawler():
    frames = []
    meta = {}
    for name, n in [("walk", 4), ("alert", 2), ("attack", 2), ("hurt", 1), ("stun", 2)]:
        meta[name] = [len(frames), n]
        for i in range(n):
            k = "idle" if name == "stun" else name
            frames.append(crawler_frame(k, i / n))
    save(to_image(sheet(frames, 32, 20, 4)), "crawler.png")
    META["crawler"] = {"fw": 32, "fh": 20, "cols": 4, "anims": meta}


# --------------------------------------------------------------------------
# Ruin Sentry: 24x24 base (mounted on floor), separate head with eye states.
# --------------------------------------------------------------------------
def gen_sentry():
    frames = []
    # 0: base
    c = Canvas(24, 24)
    c.poly([(3, 23), (5, 14), (18, 14), (20, 23)], P("ruin2"))
    c.rect(5, 14, 14, 2, P("ruin4"))
    c.rect(3, 21, 18, 3, P("ruin1"))
    for x in (7, 11, 15):
        c.px(x, 18, P("cyan2"))
    c.rect(9, 9, 6, 6, P("steel1"))
    c.outline()
    frames.append(c.rgba())
    # 1..4: head states dormant, warn, fire, dead
    for state in ("dormant", "warn", "fire", "dead"):
        c = Canvas(24, 24)
        c.ellipse(4, 3, 16, 13, P("ruin3"))
        c.ellipse(5, 3, 12, 6, P("ruin4"))
        c.rect(4, 11, 16, 3, P("ruin1"))
        c.rect(14, 7, 10, 3, P("ruin2"))  # barrel
        c.rect(14, 7, 10, 1, P("ruin5"))
        c.rect(22, 6, 2, 5, P("ruin1"))
        col = {"dormant": "cyan1", "warn": "gold3", "fire": "red2", "dead": "ink1"}[state]
        hi = {"dormant": "cyan2", "warn": "gold4", "fire": "red3", "dead": "ink1"}[state]
        c.ellipse(8, 5, 7, 7, P("ink0"))
        c.ellipse(9, 6, 5, 5, P(col))
        c.px(10, 7, P(hi))
        if state == "dead":
            c.line(6, 4, 16, 13, P("ink0"))
        c.outline()
        frames.append(c.rgba())
    # 5: power module canister
    c = Canvas(24, 24)
    c.rect(7, 4, 10, 18, P("ruin2"))
    c.rect(7, 4, 10, 2, P("ruin4"))
    c.rect(7, 20, 10, 2, P("ruin1"))
    c.rect(9, 7, 6, 11, P("cyan1"))
    c.rect(10, 8, 2, 9, P("cyan2"))
    c.px(10, 9, P("cyan3"))
    for y in (10, 14):
        c.rect(9, y, 6, 1, P("ruin1"))
    c.line(3, 22, 7, 18, P("steel1"), 2)
    c.outline()
    frames.append(c.rgba())
    # 6: dead module
    a = frames[-1].copy()
    g = a[..., :3].mean(axis=2, keepdims=True) * 0.5
    a[..., :3] = np.where(a[..., 3:4] > 0, g, 0).astype(np.uint8)
    frames.append(a)
    save(to_image(sheet(frames, 24, 24, 7)), "sentry.png")


# --------------------------------------------------------------------------
# Small sprites
# --------------------------------------------------------------------------
def gen_items():
    out = {}
    # ore pickups 10x10
    for name, rp in [("copper", "copper"), ("cobalt", "cobalt"), ("aether", "aether"), ("fossil", "bone"), ("scrap", "steel")]:
        c = Canvas(10, 10)
        if name == "fossil":
            c.line(1, 7, 8, 2, P(rp + "2"), 2)
            c.ellipse(0, 6, 4, 4, P(rp + "3"))
            c.ellipse(6, 0, 4, 4, P(rp + "3"))
        elif name == "copper":
            c.ellipse(1, 2, 8, 7, P(rp + "2"))
            c.ellipse(2, 2, 5, 3, P(rp + "3"))
            c.px(3, 3, P(rp + "4"))
            c.px(6, 7, P(rp + "1"))
        else:
            c.poly([(5, 0), (8, 4), (5, 9), (2, 4)], P(rp + "2"))
            c.poly([(5, 0), (8, 4), (5, 5)], P(rp + "3"))
            c.px(5, 2, P(rp + "4"))
            c.poly([(1, 5), (3, 6), (2, 9)], P(rp + "1"))
        c.outline()
        out[name] = c.rgba()
    # ore overlays in rock: 16x16, 4 variants each
    ovl = []
    for rp in ["copper", "cobalt", "aether", "bone"]:
        for v in range(4):
            r = np.random.default_rng(70 + v + len(ovl))
            c = Canvas(16, 16)
            n = 3 if rp != "bone" else 1
            if rp == "bone":
                # fossil fragment: vertebra / rib
                if v % 2 == 0:
                    for k in range(3):
                        x = 3 + k * 4
                        c.rect(x, 6, 3, 4, P("bone2"))
                        c.px(x, 6, P("bone3"))
                        c.px(x + 1, 5, P("bone2"))
                        c.px(x + 1, 10, P("bone1"))
                else:
                    c.line(3, 12, 8, 4, P("bone2"), 2)
                    c.line(8, 4, 13, 5, P("bone2"), 2)
                    c.px(8, 4, P("bone3"))
                    c.ellipse(2, 11, 4, 4, P("bone3"))
            else:
                for k in range(n):
                    x = r.integers(2, 11)
                    y = r.integers(2, 11)
                    s = r.integers(3, 6)
                    if rp == "copper":
                        c.ellipse(x, y, s, s - 1, P(rp + "2"))
                        c.px(x + 1, y, P(rp + "4"))
                        c.px(x + s - 1, y + s - 2, P(rp + "1"))
                    else:
                        c.poly([(x + s // 2, y - 1), (x + s, y + s // 2), (x + s // 2, y + s + 1), (x, y + s // 2)], P(rp + "2"))
                        c.poly([(x + s // 2, y - 1), (x + s, y + s // 2), (x + s // 2, y + s // 2)], P(rp + "3"))
                        c.px(x + s // 2, y, P(rp + "4"))
            c.outline(P("ink1"))
            ovl.append(c.rgba())
    save(to_image(sheet(ovl, 16, 16, 4)), "ore_overlay.png")
    # gas sac overlay 16x16 x 2 frames (pulse)
    gas = []
    for f in range(2):
        c = Canvas(16, 16)
        s = 11 + f
        o = (16 - s) // 2
        c.ellipse(o, o + 1, s, s - 1, P("gas2"))
        c.ellipse(o + 2, o + 2, s - 6, 3, P("gas3"))
        c.px(o + 3, o + 3, P("gas4"))
        c.line(o + 2, o + s - 3, o + s - 3, o + 4, P("gas1"))
        c.line(o + 5, o + s - 2, o + s - 2, o + 7, P("gas1"))
        c.outline(P("ink1"))
        gas.append(c.rgba())
    save(to_image(sheet(gas, 16, 16, 2)), "gas_sac.png")
    # charge 10x10 x 2 (blink)
    ch = []
    for f in range(2):
        c = Canvas(10, 10)
        c.rect(1, 3, 8, 6, P("red1"))
        c.rect(1, 3, 8, 1, P("red2"))
        c.rect(3, 3, 1, 6, P("hazard0"))
        c.rect(6, 3, 1, 6, P("hazard0"))
        c.rect(4, 1, 2, 2, P("steel3"))
        c.px(5, 0, P("red3") if f else P("ink1"))
        c.outline()
        ch.append(c.rgba())
    save(to_image(sheet(ch, 10, 10, 2)), "charge.png")
    # projectile 8x8
    c = Canvas(8, 8)
    c.ellipse(1, 2, 6, 4, P("red2"))
    c.ellipse(2, 3, 4, 2, P("red3"))
    c.px(4, 3, P("white0"))
    save(to_image(c.rgba()), "bolt.png")
    # relic 16x20: crystal heart in golden cage
    frames = []
    for f in range(4):
        c = Canvas(16, 20)
        c.rect(3, 17, 10, 3, P("gold1"))
        c.rect(4, 16, 8, 1, P("gold2"))
        off = [0, -1, -1, 0][f]
        c.poly([(8, 2 + off), (13, 9 + off), (8, 16 + off), (3, 9 + off)], P("cyan1"))
        c.poly([(8, 2 + off), (13, 9 + off), (8, 9 + off)], P("cyan2"))
        c.poly([(8, 4 + off), (10, 9 + off), (8, 13 + off), (6, 9 + off)], P("cyan3"))
        c.px(7, 6 + off, P("white0"))
        c.line(2, 9 + off, 8, 1 + off, P("gold3"))
        c.line(14, 9 + off, 8, 1 + off, P("gold2"))
        c.line(2, 9 + off, 8, 17 + off, P("gold2"))
        c.line(14, 9 + off, 8, 17 + off, P("gold1"))
        c.outline()
        frames.append(c.rgba())
    save(to_image(sheet(frames, 16, 20, 4)), "relic.png")
    save(to_image(sheet([out[k] for k in ["copper", "cobalt", "aether", "fossil", "scrap"]], 10, 10, 5)), "pickups.png")
    # chunk particles 4x4 (grey shaded, tinted at runtime)
    parts = []
    for v in range(4):
        c = Canvas(4, 4)
        shapes = [[(0, 0, 3, 3)], [(0, 1, 4, 2), (1, 0, 2, 4)], [(0, 0, 2, 2)], [(1, 1, 3, 3)]][v]
        for (x, y, w, h) in shapes:
            c.rect(x, y, w, h, P("steel4"))
        c.px(0 if v != 3 else 1, 0 if v != 3 else 1, P("white0"))
        parts.append(c.rgba())
    save(to_image(sheet(parts, 4, 4, 4)), "chunks.png")


def radial(size, falloff=2.0, steps=0):
    ys, xs = np.mgrid[0:size, 0:size] + 0.5
    d = np.sqrt((xs - size / 2) ** 2 + (ys - size / 2) ** 2) / (size / 2)
    v = np.clip(1 - d, 0, 1) ** falloff
    if steps:
        v = np.floor(v * steps) / steps
    img = np.zeros((size, size, 4), np.uint8)
    img[..., :3] = 255
    img[..., 3] = (v * 255).astype(np.uint8)
    return img


def gen_fx():
    save(to_image(radial(64, 1.6, 6)), "glow.png")
    save(to_image(radial(256, 1.3)), "light.png")
    save(to_image(radial(16, 1.0, 3)), "dot.png")
    # puff (dust) 16x16 x 4 shrinking frames
    frames = []
    for f in range(4):
        r = np.random.default_rng(f)
        img = np.zeros((16, 16, 4), np.uint8)
        for k in range(5 - f):
            cx, cy = r.integers(4, 12, 2)
            rad = 5 - f + r.random()
            ys, xs = np.mgrid[0:16, 0:16]
            m = (xs - cx) ** 2 + (ys - cy) ** 2 < rad * rad
            img[m] = (255, 255, 255, 200 - f * 40)
        frames.append(img)
    save(to_image(sheet(frames, 16, 16, 4)), "puff.png")
    # ring for blast telegraph 64x64
    ys, xs = np.mgrid[0:64, 0:64] + 0.5
    d = np.sqrt((xs - 32) ** 2 + (ys - 32) ** 2)
    img = np.zeros((64, 64, 4), np.uint8)
    img[(d > 29) & (d < 31.5)] = (255, 255, 255, 255)
    img[(d > 26) & (d <= 29) & (((xs + ys) // 3) % 2 == 0)] = (255, 255, 255, 90)
    save(to_image(img), "ring.png")


def gen_props():
    """World props: ladder, platform, lift cage, beams, lamps, decor."""
    props = {}
    # ladder 16x16 (wood) and metal
    for name, rp in [("ladder_wood", "wood"), ("ladder_metal", "steel")]:
        c = Canvas(16, 16)
        c.rect(2, 0, 2, 16, P(rp + "2"))
        c.rect(12, 0, 2, 16, P(rp + "2"))
        c.rect(2, 0, 1, 16, P(rp + "3"))
        c.rect(12, 0, 1, 16, P(rp + "3"))
        for y in (3, 11):
            c.rect(4, y, 8, 2, P(rp + "3"))
            c.rect(4, y + 1, 8, 1, P(rp + "1"))
        props[name] = c
    # platform plank 16x16 (top 5 px)
    c = Canvas(16, 16)
    c.rect(0, 0, 16, 4, P("wood3"))
    c.rect(0, 0, 16, 1, P("wood4"))
    c.rect(0, 3, 16, 1, P("wood1"))
    c.px(3, 1, P("steel3"))
    c.px(12, 1, P("steel3"))
    c.line(2, 4, 7, 9, P("wood1"), 1)
    c.line(13, 4, 8, 9, P("wood1"), 1)
    props["platform"] = c
    # support beam 16x32 (wooden mine frame post)
    c = Canvas(16, 32)
    c.rect(5, 0, 5, 32, P("wood2"))
    c.rect(5, 0, 1, 32, P("wood3"))
    c.rect(9, 0, 1, 32, P("wood1"))
    for y in (6, 20):
        c.rect(4, y, 7, 2, P("steel1"))
        c.px(7, y, P("steel3"))
    c.outline()
    props["beam"] = c
    # hanging lantern 8x16
    c = Canvas(8, 16)
    c.line(4, 0, 4, 5, P("steel1"))
    c.rect(1, 6, 6, 8, P("rust1"))
    c.rect(2, 7, 4, 6, P("lamp2"))
    c.rect(3, 8, 2, 3, P("lamp3"))
    c.rect(1, 6, 6, 1, P("rust3"))
    c.rect(1, 13, 6, 1, P("rust2"))
    c.outline()
    props["lantern"] = c
    # roots hanging 16x16 x3
    for v in range(3):
        r = np.random.default_rng(300 + v)
        c = Canvas(16, 16)
        for k in range(3):
            x = r.integers(1, 15)
            ln = r.integers(5, 15)
            y = 0
            for i in range(ln):
                c.px(x, y, P("wood1") if i < ln - 2 else P("wood2"))
                y += 1
                if r.random() < 0.3:
                    x += r.integers(-1, 2)
            c.px(x, y, P("wood3"))
        props[f"roots{v}"] = c
    # pebbles/tufts on floors 16x8
    c = Canvas(16, 8)
    c.ellipse(2, 4, 5, 4, P("boot2"))
    c.ellipse(8, 5, 4, 3, P("boot3"))
    c.px(3, 4, P("bone2"))
    props["pebbles"] = c
    # bones on floor 16x8
    c = Canvas(16, 8)
    c.line(2, 6, 12, 5, P("bone2"), 2)
    c.ellipse(10, 2, 5, 5, P("bone3"))
    c.px(11, 3, P("ink0"))
    c.outline(P("ink1"))
    props["bones"] = c
    # mushrooms (spore) 16x16 x3, caps glow separately
    for v in range(3):
        c = Canvas(16, 16)
        r = np.random.default_rng(400 + v)
        for k in range(2 + v % 2):
            x = r.integers(2, 12)
            hgt = r.integers(4, 10)
            capw = r.integers(4, 7)
            c.rect(x, 16 - hgt, 2, hgt, P("bone2"))
            c.ellipse(x - capw // 2 + 1, 16 - hgt - 3, capw, 4, P("fung3" if v != 1 else "cyan2"))
            c.px(x, 16 - hgt - 3, P("fung4" if v != 1 else "cyan3"))
        c.outline()
        props[f"shroom{v}"] = c
    # hanging tendrils (spore) 16x16
    for v in range(2):
        c = Canvas(16, 16)
        r = np.random.default_rng(450 + v)
        for k in range(2):
            x = r.integers(2, 14)
            ln = r.integers(7, 15)
            for i in range(ln):
                c.px(x + round(math.sin(i * 0.6 + k) * 1.2), i, P("teal3"))
            c.px(x, ln, P("teal4"))
        props[f"tendril{v}"] = c
    # hanging cables (engine) 16x16
    for v in range(2):
        c = Canvas(16, 16)
        x0, x1 = (1, 14) if v == 0 else (3, 9)
        sag = 9 if v == 0 else 13
        for i in range(x1 - x0 + 1):
            tt = i / (x1 - x0)
            y = int(round(4 * sag * tt * (1 - tt)))
            c.px(x0 + i, y, P("ink1"))
            c.px(x0 + i, y + 1, P("steel1"))
        if v == 1:
            c.px(x1, 1, P("cyan3"))
        props[f"cable{v}"] = c
    # pipe segment 32x10 (rusted)
    c = Canvas(32, 10)
    c.rect(0, 2, 32, 6, P("rust2"))
    c.rect(0, 2, 32, 1, P("rust3"))
    c.rect(0, 7, 32, 1, P("rust1"))
    for x in (6, 22):
        c.rect(x, 1, 3, 8, P("steel2"))
        c.px(x + 1, 1, P("steel4"))
    c.outline()
    props["pipe"] = c
    # crate 16x16
    c = Canvas(16, 14)
    c.rect(1, 1, 14, 12, P("wood2"))
    c.rect(1, 1, 14, 1, P("wood4"))
    c.line(2, 2, 13, 11, P("wood1"))
    c.line(13, 2, 2, 11, P("wood1"))
    c.rect(1, 12, 14, 1, P("wood0"))
    c.outline()
    props["crate"] = c
    # supply cache (charges) 20x14
    c = Canvas(20, 14)
    c.rect(1, 3, 18, 10, P("steel2"))
    c.rect(1, 3, 18, 2, P("hazard1"))
    for x in range(2, 18, 3):
        c.px(x, 4, P("hazard0"))
    c.rect(8, 7, 4, 3, P("red2"))
    c.rect(1, 12, 18, 1, P("steel0"))
    c.outline()
    props["cache"] = c
    # lift cage 32x40
    c = Canvas(32, 40)
    c.rect(2, 0, 28, 4, P("shell2"))
    c.rect(2, 0, 28, 1, P("shell4"))
    for x in range(4, 30, 3):
        c.px(x, 2, P("hazard0"))
    c.rect(2, 36, 28, 4, P("steel2"))
    c.rect(2, 36, 28, 1, P("steel4"))
    c.rect(2, 4, 2, 32, P("steel1"))
    c.rect(28, 4, 2, 32, P("steel1"))
    for y in range(8, 36, 6):
        c.line(4, y, 28, y, P("steel0"))
    c.rect(14, 4, 4, 3, P("lamp2"))
    c.outline()
    props["lift"] = c
    # cable wheel / headframe top 48x16
    c = Canvas(48, 20)
    c.ellipse(16, 2, 16, 16, P("steel1"))
    c.ellipse(19, 5, 10, 10, P("ink1"))
    c.ellipse(22, 8, 4, 4, P("steel3"))
    for a in range(0, 360, 60):
        c.line(24, 10, 24 + 7 * math.cos(math.radians(a)), 10 + 7 * math.sin(math.radians(a)), P("steel2"))
    c.rect(0, 15, 48, 5, P("rust2"))
    c.rect(0, 15, 48, 1, P("rust3"))
    c.outline()
    props["wheel"] = c
    # relic chamber door 32x48 frames x4 (opening)
    for f in range(4):
        c = Canvas(32, 48)
        c.rect(0, 0, 32, 48, P("ruin1"))
        c.rect(0, 0, 32, 3, P("ruin4"))
        open_px = f * 6
        for side in (0, 1):
            x = 3 - open_px if side == 0 else 16 + open_px
            w = 13
            c.rect(x, 3, w, 45, P("ruin3"))
            c.rect(x, 3, w, 1, P("ruin5"))
            c.rect(x + (w - 2 if side == 0 else 1), 3, 1, 45, P("ruin2"))
            for y in range(8, 46, 9):
                c.rect(x + 2, y, w - 4, 1, P("ruin2"))
            c.px(x + (w - 3 if side == 0 else 2), 24, P("cyan2" if f < 3 else "gold3"))
        a = c.arr()
        a[:, :3] = np.where(a[:, :3] > 0, P("ruin0"), 0)
        a[:, 29:] = np.where(a[:, 29:] > 0, P("ruin0"), 0)
        c.set_arr(a)
        props[f"door{f}"] = c
    # pedestal 32x16
    c = Canvas(32, 16)
    c.poly([(4, 16), (8, 4), (24, 4), (28, 16)], P("ruin3"))
    c.rect(6, 2, 20, 3, P("ruin5"))
    c.rect(12, 8, 8, 2, P("cyan2"))
    c.outline()
    props["pedestal"] = c
    # warning sign 12x12
    c = Canvas(12, 12)
    c.poly([(6, 0), (11, 10), (0, 10)], P("hazard1"))
    c.rect(5, 3, 2, 4, P("hazard0"))
    c.px(5, 8, P("hazard0"))
    c.px(6, 8, P("hazard0"))
    c.outline()
    props["sign"] = c
    # skull fossil set-piece decal 48x32
    c = Canvas(48, 32)
    c.ellipse(4, 6, 26, 20, P("bone2"))
    c.ellipse(6, 7, 18, 9, P("bone3"))
    c.poly([(26, 14), (46, 18), (44, 24), (26, 24)], P("bone2"))
    for x in range(28, 44, 3):
        c.poly([(x, 24), (x + 2, 24), (x + 1, 28)], P("bone3"))
    c.ellipse(12, 11, 7, 6, P("ink0"))
    c.px(14, 13, P("gold3"))
    c.ellipse(22, 18, 4, 3, P("ink0"))
    c.outline(P("ink1"))
    props["skull"] = c
    names = list(props.keys())
    meta = {}
    # pack into a simple shelf atlas
    W = 256
    x = y = rowh = 0
    placements = []
    for n in names:
        cv = props[n]
        if x + cv.w > W:
            x = 0
            y += rowh + 1
            rowh = 0
        placements.append((n, x, y, cv))
        meta[n] = [x, y, cv.w, cv.h]
        x += cv.w + 1
        rowh = max(rowh, cv.h)
    H = y + rowh + 1
    atlas = np.zeros((H, W, 4), np.uint8)
    for (n, px_, py_, cv) in placements:
        atlas[py_:py_ + cv.h, px_:px_ + cv.w] = cv.rgba()
    save(to_image(atlas), "props.png")
    META["props"] = meta


def main():
    gen_player()
    gen_drill()
    gen_crawler()
    gen_sentry()
    gen_items()
    gen_fx()
    gen_props()
    with open(f"{OUT}/sprites_meta.json", "w") as f:
        json.dump(META, f, indent=1)


if __name__ == "__main__":
    main()
