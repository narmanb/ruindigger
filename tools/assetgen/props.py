"""Procedural props, ore, pickups and hazard sprites."""
from __future__ import annotations

import json
import math

from canvas import Canvas, save_png, shade, mix
from palette import STRATA

CELL = 16


def ore(cell: Canvas, color, light, seed_rng, kind="cluster"):
    c = Canvas(CELL, CELL)
    if kind == "cluster":
        pts = [(8, 7, 3.2), (5, 9, 2.2), (11, 9, 2.0), (8, 11, 1.8)]
    else:
        pts = [(8, 8, 3.6)]
    for (x, y, r) in pts:
        c.polygon([(x, y - r), (x + r * 0.8, y), (x, y + r), (x - r * 0.8, y)], color)
        c.polygon([(x, y - r), (x + r * 0.4, y - r * 0.2), (x, y + r * 0.3), (x - r * 0.4, y - r * 0.2)], light)
        c.set(x, y - r + 1, shade(light, 1.3))
    c.sparkle(8, 8, 6, (light[0], light[1], light[2], 70))
    return c


def gas_pocket(stratum, i, n):
    c = Canvas(CELL, CELL)
    t = i / max(1, n)
    ph = math.sin(t * math.tau)
    warn = stratum["accent"]
    # bulbous sac
    for (x, y, r) in ((6, 9, 4.0), (10, 8, 4.4), (8, 12, 3.6)):
        c.ellipse(x, y, r, r, (40, 60, 40, 200))
        c.ellipse(x, y - 0.6, r - 0.8, r - 0.8, (60, 92, 58, 235))
        c.ellipse(x - 1, y - 1.4, r - 2.0, r - 2.2, (96, 138, 84, 210))
    # warning shimmer
    a = int(90 + 90 * (0.5 + 0.5 * ph))
    for (x, y) in ((6, 9), (10, 8), (8, 12)):
        c.sparkle(x, y, 3, (warn[0], warn[1], warn[2], a))
    c.outline((18, 26, 16), 200)
    return c


def fossil(stratum, i, n):
    c = Canvas(CELL, CELL)
    bone = (216, 206, 178)
    c.ellipse(8, 8, 4.4, 3.4, (40, 34, 26, 180))
    # spine
    for k in range(5):
        c.ellipse(4 + k * 2, 8, 1.4, 1.4, bone)
    # ribs
    for k in range(4):
        x = 5 + k * 2
        c.line(x, 8, x - 2, 4, bone)
        c.line(x, 8, x - 2, 12, bone)
    c.outline((26, 22, 16), 210)
    return c


def ladder(stratum, i, n):
    c = Canvas(CELL, CELL * 2)
    rail = (150, 118, 74)
    dark = (86, 66, 40)
    c.vline(2, 0, c.h - 1, dark)
    c.vline(3, 0, c.h - 1, rail)
    c.vline(12, 0, c.h - 1, rail)
    c.vline(13, 0, c.h - 1, dark)
    for y in range(3, c.h, 6):
        c.rect(3, y, 10, 2, rail)
        c.hline(3, 12, y + 1, dark)
    return c


def support(stratum, i, n):
    """Wooden ceiling support prop, 2 cells wide."""
    c = Canvas(CELL * 2, CELL)
    wood = (122, 88, 52)
    dark = (72, 50, 28)
    c.rect(0, 2, CELL * 2, 5, wood)
    c.hline(0, CELL * 2 - 1, 2, shade(wood, 1.25))
    c.hline(0, CELL * 2 - 1, 6, dark)
    for x in (3, CELL * 2 - 6):
        c.vline(x, 2, CELL - 1, dark)
        c.vline(x + 1, 2, CELL - 1, wood)
    c.set(1, 3, shade(wood, 1.3))
    return c


def relic(stratum, i, n):
    c = Canvas(CELL * 2, CELL * 2)
    t = i / max(1, n)
    ph = math.sin(t * math.tau)
    core = (255, 214, 122)
    glow = (255, 176, 64)
    # base plinth
    c.rect(4, 22, 24, 6, (60, 52, 74))
    c.hline(4, 27, 22, (92, 80, 110))
    # floating shard
    yoff = int(ph * 2)
    cy = 12 + yoff
    c.polygon([(16, cy - 8), (23, cy), (16, cy + 8), (9, cy)], core)
    c.polygon([(16, cy - 8), (19, cy), (16, cy + 4), (13, cy)], shade(core, 1.2))
    c.sparkle(16, cy, 9, (glow[0], glow[1], glow[2], 90))
    c.sparkle(16, cy, 5, (core[0], core[1], core[2], 130))
    # ring
    for a in range(0, 360, 30):
        r = math.radians(a)
        x = 16 + math.cos(r) * 10
        y = cy + math.sin(r) * 5
        c.set(int(x), int(y), (glow[0], glow[1], glow[2], 200))
    c.outline((30, 22, 44), 200)
    return c


def charge(stratum, i, n):
    c = Canvas(CELL, CELL)
    c.rect(5, 4, 6, 8, (198, 62, 52))
    c.rect(6, 5, 4, 6, (240, 96, 78))
    c.hline(5, 10, 4, (255, 168, 140))
    c.hline(5, 10, 11, (120, 30, 26))
    for y in (3, 12):
        c.rect(6, y, 4, 1, (60, 58, 66))
    c.set(8, 2, (255, 220, 120))
    c.outline((26, 20, 22), 220)
    return c


def elevator(stratum, i, n):
    """Extraction lift platform, 3x4 cells."""
    c = Canvas(CELL * 3, CELL * 4)
    steel = (128, 138, 152)
    dark = (64, 72, 84)
    warm = (255, 176, 64)
    # frame
    c.rect(0, 0, CELL * 3, 6, dark)
    c.rect(2, 2, CELL * 3 - 4, 3, steel)
    for x in range(2, CELL * 3 - 2, 8):
        c.vline(x, 6, CELL * 4 - 1, dark)
        c.vline(x + 1, 6, CELL * 4 - 1, steel)
    # platform
    c.rect(0, CELL * 4 - 8, CELL * 3, 8, steel)
    c.hline(0, CELL * 3 - 1, CELL * 4 - 8, shade(steel, 1.3))
    c.hline(0, CELL * 3 - 1, CELL * 4 - 1, dark)
    for x in range(1, CELL * 3 - 1, 5):
        c.vline(x, CELL * 4 - 7, CELL * 4 - 2, shade(dark, 0.9))
    # hazard stripes
    for k in range(0, CELL * 3, 8):
        c.line(k, CELL * 4 - 8, k + 4, CELL * 4 - 5, (232, 176, 48))
    # lamp
    c.ellipse(CELL * 1.5, 4, 4, 3, shade(warm, 0.5))
    c.ellipse(CELL * 1.5, 4, 2.4, 1.8, warm)
    c.sparkle(CELL * 1.5, 4, 7, (warm[0], warm[1], warm[2], 70))
    return c


def workbench(stratum, i, n):
    c = Canvas(CELL * 3, CELL * 2)
    wood = (122, 88, 52)
    dark = (68, 48, 28)
    c.rect(0, 8, CELL * 3, 5, wood)
    c.hline(0, CELL * 3 - 1, 8, shade(wood, 1.3))
    c.hline(0, CELL * 3 - 1, 12, dark)
    for x in (2, CELL * 3 - 4):
        c.rect(x, 13, 3, CELL * 2 - 13, dark)
    # tools on top
    c.rect(4, 4, 8, 4, (150, 158, 170))
    c.rect(5, 5, 6, 2, (200, 208, 220))
    c.rect(16, 3, 3, 5, (176, 108, 255))
    c.rect(24, 5, 9, 3, (198, 62, 52))
    c.set(27, 4, (255, 168, 140))
    return c


def vent(stratum, i, n):
    c = Canvas(CELL, CELL)
    for k in range(4):
        c.hline(2, CELL - 3, 3 + k * 3, (70, 62, 58))
        c.hline(2, CELL - 3, 4 + k * 3, (40, 36, 34))
    c.rect(0, 0, CELL, 2, (54, 48, 44))
    c.rect(0, CELL - 2, CELL, 2, (54, 48, 44))
    return c


def make_sheet(out_dir, name, builders, cell_w, cell_h, frames=1):
    sheet = Canvas(cell_w * frames, cell_h * len(builders))
    meta = {"cell": [cell_w, cell_h], "rows": {}}
    for r, (key, fn) in enumerate(builders):
        for i in range(frames):
            sheet.blit(fn(i, frames), 0 if frames == 1 else i * cell_w, r * cell_h)
        meta["rows"][key] = r
    save_png(f"{out_dir}/{name}.png", sheet)
    with open(f"{out_dir}/{name}.json", "w") as fh:
        json.dump(meta, fh, indent=1)


def build(out_dir: str) -> dict:
    d = STRATA["dustworks"]
    s = STRATA["spore_veins"]
    f = STRATA["forgotten_engine"]

    ore_rows = []
    for key, stratum, kind in (
        ("ore_copper", d, "cluster"), ("ore_amber", d, "cluster"),
        ("ore_spore", s, "cluster"), ("ore_quartz", s, "cluster"),
        ("ore_void", f, "cluster"), ("ore_relic_dust", f, "cluster"),
    ):
        base = stratum["crystal"][0]
        light = stratum["crystal"][1]
        ore_rows.append((key, (lambda b, l: (lambda i, n: ore(Canvas(CELL, CELL), b, l, None, "cluster")))(base, light)))

    # props and hazards, animated variants where useful
    prop_rows = [
        ("fossil", lambda i, n: fossil(d, i, n)),
        ("gas", lambda i, n: gas_pocket(s, i, n)),
        ("charge", lambda i, n: charge(d, i, n)),
        ("vent", lambda i, n: vent(d, i, n)),
    ]
    make_sheet(out_dir, "ore_sheet", ore_rows, CELL, CELL, frames=1)
    make_sheet(out_dir, "prop_sheet", prop_rows, CELL, CELL, frames=4)
    make_sheet(out_dir, "relic_sheet", [("relic", lambda i, n: relic(f, i, n))], CELL * 2, CELL * 2, frames=6)
    make_sheet(out_dir, "elevator_sheet", [("lift", lambda i, n: elevator(d, i, n))], CELL * 3, CELL * 4, frames=1)
    make_sheet(out_dir, "bench_sheet", [("bench", lambda i, n: workbench(d, i, n))], CELL * 3, CELL * 2, frames=1)
    make_sheet(out_dir, "ladder_sheet", [("ladder", lambda i, n: ladder(d, i, n))], CELL, CELL * 2, frames=1)
    make_sheet(out_dir, "support_sheet", [("support", lambda i, n: support(d, i, n))], CELL * 2, CELL, frames=1)
    return {"ok": True}
