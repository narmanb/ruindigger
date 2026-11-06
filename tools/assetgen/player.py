"""Procedural player exosuit sprites for RUIN DIGGER.

Draws a small mining exosuit: oversized drill arm, glowing backpack, visored
helmet, hydraulic legs. All animation frames are composed from one parametric
drawing routine so the character stays perfectly consistent between poses.

Sheet layout: rows = animation, columns = frame. A JSON sidecar records the
frame rect of every animation so the runtime can build AtlasTextures.
"""
from __future__ import annotations

import json
import math

from canvas import Canvas, save_png, shade, mix, clamp8
from palette import PLAYER as P
from rng import Rng

W, H = 20, 24


def _px(c, x, y, col):
    c.set(int(x), int(y), col)


def _limb(c, x0, y0, x1, y1, col, w=3):
    """A chunky rounded limb between two joints."""
    steps = max(1, int(max(abs(x1 - x0), abs(y1 - y0))))
    for i in range(steps + 1):
        t = i / steps
        x = x0 + (x1 - x0) * t
        y = y0 + (y1 - y0) * t
        c.ellipse(x, y, w * 0.5, w * 0.5, col)


def _boot(c, x, y, col, dark):
    c.rect(x - 2, y - 2, 6, 3, col)
    c.hline(x - 2, x + 3, y + 1, dark)
    c.set(x - 2, y - 2, shade(col, 1.25))
    c.set(x + 3, y - 2, shade(col, 1.15))


def _backpack(c, x, y, glow_pulse):
    c.rect(x, y, 5, 9, P["metal_dk"])
    c.rect(x + 1, y + 1, 3, 7, P["metal"])
    c.vline(x, y + 1, y + 8, shade(P["metal_lt"], 1.0))
    for i in range(3):
        gy = y + 2 + i * 3
        c.set(x + 2, gy, shade(P["glow"], 1.0 + glow_pulse))
        c.blend(x + 1, gy, (P["glow"][0], P["glow"][1], P["glow"][2], 120))
        c.blend(x + 3, gy, (P["glow"][0], P["glow"][1], P["glow"][2], 90))


def _helmet(c, cx, cy, visor_f, lean=0):
    ox = int(lean)
    # neck / collar
    c.rect(cx - 3 + ox, cy + 3, 7, 2, P["metal_dk"])
    # helmet shell
    c.ellipse(cx + ox, cy, 4.6, 4.2, P["shell"])
    c.ellipse(cx + ox, cy - 1, 4.0, 3.2, P["shell_lt"])
    c.rect(cx - 4 + ox, cy, 9, 3, P["shell"])
    c.hline(cx - 4 + ox, cx + 4 + ox, cy + 3, P["shell_dk"])
    # crest / lamp
    c.rect(cx - 1 + ox, cy - 5, 3, 2, P["metal"])
    c.set(cx + ox, cy - 5, shade(P["metal_lt"], 1.3))
    # visor
    vc = shade(P["visor"], 0.85 + visor_f * 0.4)
    c.rect(cx - 3 + ox, cy, 6, 3, vc)
    c.rect(cx - 2 + ox, cy, 4, 1, shade(P["visor_lt"], 0.9 + visor_f * 0.3))
    c.set(cx - 3 + ox, cy + 2, shade(vc, 0.7))
    c.set(cx + 2 + ox, cy + 2, shade(vc, 0.7))
    # respirator
    c.rect(cx - 2 + ox, cy + 4, 4, 2, P["metal_dk"])
    for i in range(3):
        c.set(cx - 1 + ox + i, cy + 5, P["rubber"])


def _drill(c, cx, cy, angle_deg, spin, hot):
    """Oversized drill arm rotating about the shoulder pivot."""
    a = math.radians(angle_deg)
    ux, uy = math.cos(a), math.sin(a)
    px_, py_ = -uy, ux
    L = 11
    tipx, tipy = cx + ux * L, cy + uy * L
    # upper arm / housing
    _limb(c, cx, cy, cx + ux * 5, cy + uy * 5, P["metal"], 4)
    _limb(c, cx, cy, cx + ux * 5, cy + uy * 5, P["metal_lt"], 2)
    # barrel
    _limb(c, cx + ux * 5, cy + uy * 5, tipx, tipy, P["drill"], 3)
    for i in range(4):
        t = 0.55 + i * 0.12
        bx, by = cx + ux * (L * t), cy + uy * (L * t)
        col = shade(P["drill"], 0.75 + 0.25 * ((i + spin) % 2))
        c.ellipse(bx + px_ * 2, by + py_ * 2, 1.2, 1.2, col)
        c.ellipse(bx - px_ * 2, by - py_ * 2, 1.2, 1.2, col)
    # bit
    c.ellipse(tipx, tipy, 2.2, 2.2, P["drill_tip"])
    c.ellipse(tipx, tipy, 1.2, 1.2, shade(P["drill_tip"], 1.2))
    if hot > 0:
        for _ in range(2):
            c.sparkle(int(tipx + px_ * 2), int(tipy + py_ * 2), 2,
                      (P["glow"][0], P["glow"][1], P["glow"][2], int(120 * hot)))


def _torso(c, cx, cy, lean, chest_lift=0):
    ox = int(lean)
    # hips
    c.rect(cx - 4 + ox, cy + 6, 9, 3, P["shell_dk"])
    # chest
    c.polygon([
        (cx - 4 + ox, cy + 7), (cx + 4 + ox, cy + 7),
        (cx + 5 + ox, cy + 1 - chest_lift), (cx - 3 + ox, cy + 1 - chest_lift),
    ], P["shell"])
    c.polygon([
        (cx - 3 + ox, cy + 6), (cx + 3 + ox, cy + 6),
        (cx + 4 + ox, cy + 2 - chest_lift), (cx - 2 + ox, cy + 2 - chest_lift),
    ], P["shell_lt"])
    # hazard stripe
    for i in range(-4, 5):
        if (i + 1) % 2 == 0:
            c.set(cx + i + ox, cy + 5, P["rubber"])
    # shoulder pad
    c.ellipse(cx + 4 + ox, cy + 2, 3.0, 2.4, P["metal"])
    c.ellipse(cx + 4 + ox, cy + 1, 2.2, 1.6, P["metal_lt"])
    # chest lamp
    c.set(cx - 2 + ox, cy + 3, shade(P["visor"], 1.2))
    c.blend(cx - 2 + ox, cy + 3, (P["visor"][0], P["visor"][1], P["visor"][2], 150))


def _draw(c: Canvas, cfg: dict):
    """Compose a full frame from joint parameters."""
    lean = cfg.get("lean", 0.0)
    bob = cfg.get("bob", 0)
    hip_y = 14 + bob
    cx = 9
    _backpack(c, 1, 6 + bob, cfg.get("glow", 0.0))

    # legs (two segments each: hip->knee->foot)
    for side, (kdx, kdy, fdx, fdy) in (
        ("back", cfg["leg_back"]),
        ("front", cfg["leg_front"]),
    ):
        col = P["metal_dk"] if side == "back" else P["metal"]
        lcol = P["metal"] if side == "back" else P["metal_lt"]
        hx = cx - 2 + lean
        kx, ky = hx + kdx, hip_y + kdy
        fx, fy = kx + fdx, ky + fdy
        _limb(c, hx, hip_y, kx, ky, col, 3)
        _limb(c, kx, ky, fx, fy, col, 3)
        # hydraulic piston highlight
        _limb(c, hx, hip_y + 1, kx, ky, lcol, 1)
        _boot(c, fx, fy, P["rubber"], P["outline"])

    _torso(c, cx, hip_y - 6, lean, cfg.get("chest", 0))
    _helmet(c, cx + 1, hip_y - 11 + cfg.get("head", 0), cfg.get("visor", 0.5), lean * 0.5)
    _drill(c, cx + 4 + lean, hip_y - 5, cfg.get("drill_angle", 20),
           cfg.get("spin", 0), cfg.get("hot", 0.0))


def _base_cfg():
    return {
        "lean": 0.0, "bob": 0, "glow": 0.0, "head": 0, "visor": 0.4,
        "chest": 0, "spin": 0, "hot": 0.0, "drill_angle": 22,
        "leg_back": (-1, 4, -1, 4),
        "leg_front": (2, 4, 1, 4),
    }


def _frame(kind: str, i: int, n: int) -> dict:
    cfg = _base_cfg()
    t = i / max(1, n)
    ph = math.sin(t * math.tau)
    if kind == "idle":
        cfg["bob"] = 1 if ph > 0.2 else 0
        cfg["head"] = 1 if ph > 0.5 else 0
        cfg["glow"] = 0.15 + 0.15 * ph
        cfg["visor"] = 0.35 + 0.2 * ph
        cfg["drill_angle"] = 24 + 3 * ph
    elif kind == "run":
        sw = math.sin(t * math.tau)
        sw2 = math.sin(t * math.tau + math.pi)
        cfg["lean"] = 1.5
        cfg["bob"] = 1 if abs(sw) > 0.7 else 0
        cfg["leg_back"] = (int(-2 + sw * 3), 4, int(-2 + sw * 2), 4)
        cfg["leg_front"] = (int(2 + sw2 * 3), 4, int(2 + sw2 * 2), 4)
        cfg["drill_angle"] = 20 + 6 * sw
        cfg["glow"] = 0.3
    elif kind == "jump":
        cfg["leg_back"] = (-3, 2, -2, 3)
        cfg["leg_front"] = (1, 2, 2, 2)
        cfg["lean"] = 1.0
        cfg["drill_angle"] = -12 + i * 14
        cfg["visor"] = 0.7
        cfg["glow"] = 0.5
    elif kind == "fall":
        cfg["leg_back"] = (-2, 3, -3, 4)
        cfg["leg_front"] = (3, 3, 2, 4)
        cfg["drill_angle"] = 34 + i * 6
        cfg["visor"] = 0.55
        cfg["glow"] = 0.35
    elif kind == "drill":
        cfg["drill_angle"] = 8
        cfg["lean"] = 2.5
        cfg["spin"] = i % 2
        cfg["hot"] = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(t * math.tau))
        cfg["bob"] = 1 if i % 2 else 0
        cfg["leg_back"] = (-2, 4, -2, 4)
        cfg["leg_front"] = (2, 4, 1, 4)
        cfg["glow"] = 0.6
        cfg["visor"] = 0.8
    elif kind == "hurt":
        cfg["lean"] = -2.5 + i
        cfg["head"] = -1
        cfg["drill_angle"] = 48
        cfg["visor"] = 1.0
        cfg["leg_back"] = (-3, 4, -3, 4)
        cfg["leg_front"] = (3, 4, 3, 4)
        cfg["glow"] = 0.1
    return cfg


ANIMS = {
    "idle": 4, "run": 8, "jump": 2, "fall": 2, "drill": 4, "hurt": 2,
}


def build(out_dir: str) -> dict:
    total_cols = max(ANIMS.values())
    sheet = Canvas(total_cols * W, len(ANIMS) * H)
    meta = {"cell": [W, H], "anims": {}}
    for r, (kind, n) in enumerate(ANIMS.items()):
        for i in range(n):
            c = Canvas(W, H)
            _draw(c, _frame(kind, i, n))
            c.outline(P["outline"], 235)
            sheet.blit(c, i * W, r * H)
        meta["anims"][kind] = {"row": r, "frames": n}
    save_png(f"{out_dir}/player_sheet.png", sheet)
    with open(f"{out_dir}/player_sheet.json", "w") as fh:
        json.dump(meta, fh, indent=1)
    return meta
