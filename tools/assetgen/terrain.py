"""Procedural terrain tiles for RUIN DIGGER.

For each stratum, material and damage stage we bake one tile per *neighbour
exposure mask*. The mask is a 4 bit value: bit0 = north open, bit1 = east open,
bit2 = south open, bit3 = west open. The runtime picks the tile whose mask
matches the cell's open sides, which is what gives carved tunnels their beveled,
eroded silhouette without any per-frame geometry work.

Atlas layout (cells of TILE px):
  columns : mask(16) * VARIANTS
  rows    : one per registered (stratum, material, stage) combination
A JSON sidecar records the row index of every combination.
"""
from __future__ import annotations

import json

from canvas import Canvas, save_png, shade, mix, clamp8
from palette import STRATA, STRATUM_ORDER
from rng import Rng

TILE = 16
VARIANTS = 2
MASKS = 16
STAGES = 3  # 0 intact, 1 cracked, 2 crumbled rubble
MATERIALS = ["soil", "basalt", "alloy", "bedrock"]
BEDROCK_STAGES = 1

N, E, S, W = 1, 2, 4, 8


def _tinted(base, rng, spread=0.07):
    t = rng.uniform(-spread, spread)
    return (clamp8(base[0] * (1 + t)), clamp8(base[1] * (1 + t)), clamp8(base[2] * (1 + t)), 255)


def _speckle(c, rng, light, dark, count, size_max=2):
    for _ in range(count):
        x = rng.randint(0, c.w - 1)
        y = rng.randint(0, c.h - 1)
        col = light if rng.chance(0.5) else dark
        col = shade(col, rng.uniform(0.7, 1.15))
        for yy in range(y, min(y + rng.randint(1, size_max), c.h)):
            for xx in range(x, min(x + rng.randint(1, size_max), c.w)):
                c.blend(xx, yy, (col[0], col[1], col[2], rng.randint(110, 210)))


def _banding(c, rng, dark, light, material):
    if material in ("soil", "bedrock"):
        for _ in range(rng.randint(1, 2)):
            y = rng.randint(2, c.h - 3)
            c.hline(0, c.w - 1, y, (dark[0], dark[1], dark[2], rng.randint(55, 105)), blend=True)
            c.hline(0, c.w - 1, y + 1, (light[0], light[1], light[2], rng.randint(25, 55)), blend=True)
    else:
        for _ in range(rng.randint(1, 3)):
            x0, y0 = rng.randint(0, c.w - 1), rng.randint(0, c.h - 1)
            c.line(x0, y0, x0 + rng.randint(-8, 8), y0 + rng.randint(-5, 5),
                   (dark[0], dark[1], dark[2], rng.randint(65, 125)), blend=True)


def _cracks(c, rng, deep, level):
    for _ in range(2 if level == 1 else 5):
        x, y = rng.randint(1, c.w - 2), rng.randint(0, c.h - 1)
        for _s in range(rng.randint(4, 10)):
            c.set(x, y, (deep[0], deep[1], deep[2], 255))
            if rng.chance(0.4):
                c.set(x + 1, y, (deep[0] // 2 + 24, deep[1] // 2 + 24, deep[2] // 2 + 24, 190))
            x += rng.randint(-1, 1)
            y += rng.randint(0, 1)
            if not (0 <= x < c.w and 0 <= y < c.h):
                break


def _edge_erosion(c, rng, mask):
    """Remove a couple of pixels along each open side for a chipped outline."""
    def bite(x, y):
        if 0 <= x < c.w and 0 <= y < c.h:
            c.set(x, y, (0, 0, 0, 0))

    if mask & N:
        for _ in range(rng.randint(1, 3)):
            bite(rng.randint(0, c.w - 1), 0)
        if rng.chance(0.6):
            bite(rng.randint(0, c.w - 1), 1)
    if mask & S:
        for _ in range(rng.randint(1, 3)):
            bite(rng.randint(0, c.w - 1), c.h - 1)
    if mask & W:
        for _ in range(rng.randint(1, 3)):
            bite(0, rng.randint(0, c.h - 1))
    if mask & E:
        for _ in range(rng.randint(1, 3)):
            bite(c.w - 1, rng.randint(0, c.h - 1))
    if (mask & N) and (mask & W):
        bite(0, 0)
    if (mask & N) and (mask & E):
        bite(c.w - 1, 0)
    if (mask & S) and (mask & W):
        bite(0, c.h - 1)
    if (mask & S) and (mask & E):
        bite(c.w - 1, c.h - 1)


def _edge_lighting(c, mask, light, deep, accent, material, rng):
    """Rim light on open tops, occlusion shadow underneath."""
    if mask & N:
        for x in range(c.w):
            c.set(x, 0, shade(light, 1.12))
            c.set(x, 1, shade(mix(light, c.get(x, 1), 0.4), 1.0))
        if material != "bedrock":
            for _ in range(rng.randint(2, 5)):
                x = rng.randint(0, c.w - 1)
                c.blend(x, 2, (accent[0], accent[1], accent[2], rng.randint(20, 50)))
    if mask & S:
        for x in range(c.w):
            c.set(x, c.h - 1, shade(deep, 0.85))
            c.set(x, c.h - 2, shade(mix(deep, c.get(x, c.h - 2), 0.45), 1.0))
    if mask & W:
        for y in range(c.h):
            c.blend(0, y, (light[0], light[1], light[2], 150))
            c.blend(1, y, (deep[0], deep[1], deep[2], 40))
    if mask & E:
        for y in range(c.h):
            c.blend(c.w - 1, y, (deep[0], deep[1], deep[2], 165))
            c.blend(c.w - 2, y, (deep[0], deep[1], deep[2], 55))


def make_tile(stratum: dict, material: str, stage: int, mask: int, seed: int) -> Canvas:
    rng = Rng(seed)
    c = Canvas(TILE, TILE)
    base, light, dark, deep = stratum[material]
    accent = stratum["accent"]
    base = _tinted(base, rng)

    if stage == 2:
        for _ in range(rng.randint(8, 14)):
            x, y = rng.randint(1, TILE - 4), rng.randint(2, TILE - 4)
            col = shade(base, rng.uniform(0.5, 0.95))
            c.rect(x, y, rng.randint(2, 4), rng.randint(2, 3), col)
            c.set(x, y, shade(col, 1.35))
        for x in range(c.w):
            c.blend(x, c.h - 1, (deep[0], deep[1], deep[2], 120))
        return c

    for y in range(TILE):
        for x in range(TILE):
            f = 1.0 + rng.uniform(-0.08, 0.08)
            col = (clamp8(base[0] * f), clamp8(base[1] * f), clamp8(base[2] * f), 255)
            col = shade(col, 1.0 + (TILE / 2 - y) * 0.011)
            c.set(x, y, col)

    _banding(c, rng, dark, light, material)
    _speckle(c, rng, light, dark, rng.randint(9, 17))
    _speckle(c, rng, accent, accent, rng.randint(1, 3), 1)

    if material == "alloy":
        for ry in (3, TILE - 5):
            for rx in (3, TILE // 2, TILE - 5):
                c.set(rx, ry, shade(light, 1.2))
                c.set(rx + 1, ry, shade(deep, 1.1))
        c.hline(0, c.w - 1, TILE // 2, (deep[0], deep[1], deep[2], 90), blend=True)
    elif material == "bedrock":
        for _ in range(3):
            x0, y0 = rng.randint(0, c.w - 1), rng.randint(0, c.h - 1)
            c.line(x0, y0, x0 + rng.randint(-6, 6), y0 + rng.randint(-6, 6),
                   (accent[0], accent[1], accent[2], 110), blend=True)

    if stage == 1:
        _cracks(c, rng, deep, 1)
        for _ in range(rng.randint(3, 7)):
            c.blend(rng.randint(0, TILE - 1), rng.randint(0, TILE - 1),
                    (deep[0], deep[1], deep[2], 95))

    _edge_lighting(c, mask, light, deep, accent, material, rng)
    _edge_erosion(c, rng, mask)
    return c


def build(out_dir: str) -> dict:
    cols = MASKS * VARIANTS
    rows = []
    for stratum_name in STRATUM_ORDER:
        for material in MATERIALS:
            n_stages = BEDROCK_STAGES if material == "bedrock" else STAGES
            for stage in range(n_stages):
                rows.append((stratum_name, material, stage))

    atlas = Canvas(cols * TILE, len(rows) * TILE)
    meta = {"tile": TILE, "variants": VARIANTS, "masks": MASKS, "rows": {}}
    for r, (stratum_name, material, stage) in enumerate(rows):
        stratum = STRATA[stratum_name]
        for mask in range(MASKS):
            for v in range(VARIANTS):
                seed = (hash((stratum_name, material, stage, mask, v)) & 0xFFFFFF) or 1
                tile = make_tile(stratum, material, stage, mask, seed)
                atlas.blit(tile, (mask * VARIANTS + v) * TILE, r * TILE)
        meta["rows"][f"{stratum_name}:{material}:{stage}"] = r

    save_png(f"{out_dir}/terrain_atlas.png", atlas)
    with open(f"{out_dir}/terrain_atlas.json", "w") as fh:
        json.dump(meta, fh, indent=1)
    return meta
