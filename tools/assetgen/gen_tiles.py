"""Terrain atlas generator.

Atlas layout (terrain_atlas.png, 2048x1024):
  8x4 grid of 256x256 blocks, one per (material, stratum), at block_slot():
  soft/hard/loose of stratum s at s*3 + 0/1/2, bedrock at 15 + s, alloy at 20.
  Strata: 0 Dustworks, 1 Spore Veins, 2 Forgotten Engine, 3 Drowned
  Aqueducts, 4 Crystal Hollows.
  Inside a block: 16x16 tiles of 16px. tile index = mask * 16 + variant,
  where mask = N|E<<1|S<<2|W<<3 (bit set = that side is exposed to open space)
  and variant = (cell_x % 4) + (cell_y % 4) * 4 (seamless 64px texture window).
"""
from __future__ import annotations

import numpy as np

from art_common import fbm, hexc, quantize, save, tnoise, to_image, worley

T = 16
TEX = 64

RAMPS = {
    ("soft", 0): ["#2a170c", "#553219", "#7d4c25", "#a46a33", "#c98f4a", "#ecc07a"],
    ("hard", 0): ["#18141a", "#38302f", "#544a45", "#71665c", "#948775", "#c4b79e"],
    ("loose", 0): ["#2b1b10", "#5a3c22", "#86603a", "#ad8754", "#cfae73", "#f2dca4"],
    ("soft", 1): ["#071517", "#112d2c", "#1b4842", "#266457", "#3d8a72", "#78c9a4"],
    ("hard", 1): ["#0a0e19", "#1a2233", "#27344a", "#384b63", "#52687f", "#86a2b6"],
    ("loose", 1): ["#0b1b1b", "#1f3a37", "#2f5650", "#477a6a", "#69a088", "#a9dabd"],
    ("soft", 2): ["#0d0913", "#231b2c", "#352a40", "#4a3c56", "#64536f", "#9582a0"],
    ("hard", 2): ["#07050c", "#17111f", "#251b30", "#362844", "#4b3a5c", "#7a6694"],
    ("loose", 2): ["#100c16", "#2a2033", "#3e3149", "#56465f", "#73617a", "#a593ae"],
    ("bedrock", 0): ["#040306", "#0e0c13", "#191620", "#25212e", "#332e40", "#4a4459"],
    ("bedrock", 1): ["#020608", "#0a1418", "#122027", "#1b2e37", "#284150", "#3d5b6b"],
    ("bedrock", 2): ["#050309", "#100a17", "#1a1124", "#261a33", "#352648", "#4d3a66"],
    ("alloy", 0): ["#0b0812", "#1f182d", "#332947", "#4b3e66", "#6c5b8f", "#a090cc"],
    # Drowned Aqueducts: wet slate and pale dressed stone
    ("soft", 3): ["#070d17", "#12233a", "#1c3653", "#2c4a66", "#44698a", "#7fa6c4"],
    ("hard", 3): ["#0a1018", "#1c2a38", "#2d4155", "#44607a", "#648aa6", "#a3c6dc"],
    ("loose", 3): ["#0b1420", "#20344a", "#33506b", "#4d7391", "#739cb8", "#b4d6e8"],
    ("bedrock", 3): ["#02050a", "#08111c", "#0f1c2b", "#18293b", "#24394f", "#38536c"],
    # Crystal Hollows: dark violet rock shot through with bright facets
    ("soft", 4): ["#120716", "#2a1230", "#41204a", "#5a2d5c", "#7c4480", "#b47ab8"],
    ("hard", 4): ["#0f0818", "#261538", "#3f2459", "#5f3a82", "#8a5fb0", "#d1a8f0"],
    ("loose", 4): ["#160a1c", "#33183e", "#522a62", "#77428c", "#a56cc0", "#e4bbf5"],
    ("bedrock", 4): ["#06030a", "#110818", "#1c0f27", "#291838", "#3a244d", "#553a6b"],
}
BLOCKS = list(RAMPS.keys())   # order fixes each block's texture seed: append only
STRATA = 5
ATLAS_COLS = 8


def block_slot(key):
    """Where a block sits in the atlas (must match TerrainView.block_index)."""
    mat, s = key
    if mat == "alloy":
        return 20
    if mat == "bedrock":
        return 15 + s
    return s * 3 + ["soft", "hard", "loose"].index(mat)


MOSS = ["#1e5b3a", "#3fa060", "#7fe08a"]
ALGAE = ["#0f3d4a", "#1f7f8c", "#5fd0d8"]


def rgb_ramp(cols):
    return np.array([hexc(c) for c in cols], dtype=np.uint8)


def emboss(h, k=4.0):
    gx = np.roll(h, -1, 1) - np.roll(h, 1, 1)
    gy = np.roll(h, -1, 0) - np.roll(h, 1, 0)
    return np.clip(0.5 - (gx + gy) * k, 0, 1)


def tex_soft(stratum, seed):
    r = np.random.default_rng(seed)
    n = fbm(TEX, TEX, 16, 4, seed)
    warp = fbm(TEX, TEX, 32, 2, seed + 7)
    ys = np.arange(TEX)[:, None] * np.ones((1, TEX))
    bands = 0.5 + 0.5 * np.sin(2 * np.pi * (ys / TEX * 3) + 4.0 * warp)
    fine = fbm(TEX, TEX, 8, 2, seed + 5)
    v = 0.22 + 0.42 * n + 0.12 * bands + 0.2 * fine
    lv = quantize(v, 4) + 1  # 1..4
    # pebbles / inclusions
    for _ in range(14):
        x, y = r.integers(0, TEX, 2)
        w = r.integers(2, 4)
        hh = r.integers(1, 3)
        for yy in range(hh):
            for xx in range(w):
                lv[(y + yy) % TEX, (x + xx) % TEX] = 4
        for xx in range(w):
            lv[(y + hh) % TEX, (x + xx) % TEX] = 1
        lv[y % TEX, x % TEX] = 5
    for _ in range(30):
        x, y = r.integers(0, TEX, 2)
        lv[y, x] = 1
    extra = []
    if stratum == 1:  # mycelium threads
        for _ in range(5):
            x, y = r.integers(0, TEX, 2)
            for i in range(r.integers(8, 20)):
                lv[y % TEX, x % TEX] = 5
                x += 1
                y += r.integers(-1, 2)
    if stratum == 2:  # scrap glints
        for _ in range(10):
            x, y = r.integers(0, TEX, 2)
            extra.append((x, y, hexc("#9fb0c8")))
            extra.append(((x + 1) % TEX, y, hexc("#5d6a80")))
    if stratum == 3:  # silt laid down in level bands, with pale shell flecks
        lv = np.clip(lv + (np.arange(TEX)[:, None] % 8 == 0).astype(int) * -1, 1, 5)
        for _ in range(12):
            x, y = r.integers(0, TEX, 2)
            extra.append((x, y, hexc("#bfe0f0")))
    if stratum == 4:  # crystal grit
        for _ in range(16):
            x, y = r.integers(0, TEX, 2)
            extra.append((x, y, hexc("#f0c8ff")))
            extra.append(((x + 1) % TEX, (y + 1) % TEX, hexc("#7fe8ff")))
    if stratum == 0:  # tiny roots
        for _ in range(4):
            x, y = r.integers(0, TEX, 2)
            for i in range(r.integers(4, 9)):
                lv[y % TEX, x % TEX] = 1
                y += 1
                x += r.integers(-1, 2)
    return lv, extra


def tex_ashlar(seed):
    """Dressed stone courses (Drowned Aqueducts): 8px rows, staggered joints."""
    r = np.random.default_rng(seed + 1)
    lv = np.zeros((TEX, TEX), int)
    n = fbm(TEX, TEX, 16, 3, seed + 3)
    for row in range(TEX // 8):
        y0 = row * 8
        x = int(r.integers(0, 6))
        start = x
        while x < start + TEX:
            w = int(r.integers(9, 15))
            tone = int(r.integers(2, 5))
            for xx in range(x, min(x + w, start + TEX)):
                for yy in range(y0, y0 + 8):
                    v = tone + (1 if n[yy, xx % TEX] > 0.62 else 0) - (1 if n[yy, xx % TEX] < 0.34 else 0)
                    lv[yy, xx % TEX] = int(np.clip(v, 1, 5))
                lv[y0, xx % TEX] = min(5, tone + 1)       # lit top edge
                lv[y0 + 7, xx % TEX] = 0                  # mortar joint
            lv[y0:y0 + 8, x % TEX] = 0
            x += w
    extra = []
    for _ in range(6):   # damp streaks
        x, y = r.integers(0, TEX, 2)
        for i in range(int(r.integers(3, 7))):
            extra.append((x, (y + i) % TEX, hexc("#1f7f8c")))
    return lv, extra


def tex_hard(stratum, seed):
    if stratum == 3:
        return tex_ashlar(seed)
    f1, f2, ids = worley(TEX, TEX, 13 if stratum != 4 else 9, seed)
    r = np.random.default_rng(seed + 1)
    base = r.random(ids.max() + 1) * 0.35 + 0.35
    hmap = -f1 / 10.0 + 0.15 * fbm(TEX, TEX, 16, 3, seed + 3)
    lit = emboss(hmap, 3.0)
    v = base[ids] * 0.55 + lit * 0.45
    lv = quantize(v, 4) + 1
    edge = (f2 - f1) < 1.1
    lv[edge] = 0
    hi = ((f2 - f1) >= 1.1) & ((f2 - f1) < 2.2) & (lit > 0.5)
    lv[hi] = np.minimum(lv[hi] + 1, 5)
    extra = []
    if stratum == 2:
        for _ in range(8):
            x, y = r.integers(0, TEX, 2)
            extra.append((x, y, hexc("#c08cff")))
    if stratum == 4:  # faceted crystal: hard light on one side of every cell
        lv = np.where((lit > 0.62) & (lv > 0), np.minimum(lv + 1, 5), lv)
        for _ in range(14):
            x, y = r.integers(0, TEX, 2)
            extra.append((x, y, hexc("#ffffff")))
            extra.append(((x + 1) % TEX, y, hexc("#7fe8ff")))
    return lv, extra


def tex_loose(stratum, seed):
    f1, f2, ids = worley(TEX, TEX, 46, seed)
    r = np.random.default_rng(seed + 2)
    base = r.random(ids.max() + 1) * 0.4 + 0.4
    v = base[ids] * (1.15 - f1 / 6.0)
    lv = quantize(np.clip(v, 0, 1), 4) + 1
    lv[(f2 - f1) < 1.0] = 0
    extra = []
    if stratum == 4:  # loose crystal shards catch the light
        lv = np.where(lv >= 3, np.minimum(lv + 1, 5), lv)
        for _ in range(18):
            x, y = r.integers(0, TEX, 2)
            extra.append((x, y, hexc("#ffffff")))
    return lv, extra


def tex_bedrock(stratum, seed):
    f1, f2, ids = worley(TEX, TEX, 6, seed)
    r = np.random.default_rng(seed + 4)
    base = r.random(ids.max() + 1) * 0.3 + 0.3
    lit = emboss(-f1 / 14.0 + 0.2 * fbm(TEX, TEX, 16, 3, seed), 4.0)
    v = base[ids] * 0.5 + lit * 0.5
    lv = quantize(v, 4) + 1
    lv[(f2 - f1) < 1.3] = 0
    return lv, []


def tex_alloy(stratum, seed):
    r = np.random.default_rng(seed)
    lv = np.full((TEX, TEX), 3)
    noise = quantize(fbm(TEX, TEX, 16, 2, seed), 2, 0.9)
    for py in range(4):
        for px in range(4):
            x0, y0 = px * 16, py * 16
            kind = r.integers(0, 4)
            blk = lv[y0:y0 + 16, x0:x0 + 16]
            blk[:, :] = 2 + noise[y0:y0 + 16, x0:x0 + 16]
            blk[0, :] = 5
            blk[:, 0] = 4
            blk[1, 1:15] = 4
            blk[15, :] = 1
            blk[:, 15] = 1
            blk[14, 1:15] = 2
            for (rx, ry) in [(2, 2), (13, 2), (2, 13), (13, 13)]:
                blk[ry, rx] = 5
                blk[ry + 1, rx] = 1
            if kind == 0:  # vent slats
                for sy in range(5, 12, 2):
                    blk[sy, 4:12] = 0
                    blk[sy + 1, 4:12] = 4
            elif kind == 1:  # circuit groove
                blk[8, 3:13] = 1
                blk[4:9, 3] = 1
                blk[8:12, 12] = 1
                blk[9, 3:13] = 4
            elif kind == 2:  # inset panel
                blk[4, 4:12] = 1
                blk[4:12, 4] = 1
                blk[11, 4:12] = 4
                blk[4:12, 11] = 4
    return lv, []


TEXFN = {"soft": tex_soft, "hard": tex_hard, "loose": tex_loose, "bedrock": tex_bedrock, "alloy": tex_alloy}


def rough_1d(seed, maxv):
    n = tnoise(TEX, 1, 6, seed)[0]
    return np.clip(np.floor(n * (maxv + 1)), 0, maxv).astype(int)


def make_block(key, bi):
    mat, stratum = key
    seed = 1000 + bi * 77   # bi = position in BLOCKS (stable), not the atlas slot
    lv, extra = TEXFN[mat](stratum, seed)
    ramp = rgb_ramp(RAMPS[key])
    tex = ramp[np.clip(lv, 0, 5)]
    for (x, y, c) in extra:
        tex[y % TEX, x % TEX] = c
    rough = {
        "N": rough_1d(seed + 11, 2), "S": rough_1d(seed + 12, 1),
        "E": rough_1d(seed + 13, 2), "W": rough_1d(seed + 14, 2),
    }
    if mat == "alloy":
        rough = {k: np.zeros(TEX, int) for k in rough}
    block = np.zeros((256, 256, 4), np.uint8)
    moss = rgb_ramp(ALGAE if stratum == 3 else MOSS)
    moss_p = {1: 0.8, 3: 0.3}.get(stratum, 0.0)
    rr = np.random.default_rng(seed + 99)
    for mask in range(16):
        N, E, S, W = bool(mask & 1), bool(mask & 2), bool(mask & 4), bool(mask & 8)
        for var in range(16):
            vx, vy = var % 4, var // 4
            tile = tex[vy * 16:(vy + 1) * 16, vx * 16:(vx + 1) * 16].copy()
            lvt = lv[vy * 16:(vy + 1) * 16, vx * 16:(vx + 1) * 16]
            solid = np.ones((T, T), bool)
            for t in range(T):
                if N:
                    solid[:rough["N"][vx * 16 + t], t] = False
                if S:
                    d = rough["S"][vx * 16 + t]
                    if d:
                        solid[T - d:, t] = False
                if W:
                    solid[t, :rough["W"][vy * 16 + t]] = False
                if E:
                    d = rough["E"][vy * 16 + t]
                    if d:
                        solid[t, T - d:] = False
            rad = 3.5 if mat != "alloy" else 1.5
            ys, xs = np.mgrid[0:T, 0:T] + 0.5
            for (a, b, cx, cy) in [(N, W, rad, rad), (N, E, T - rad, rad), (S, W, rad, T - rad), (S, E, T - rad, T - rad)]:
                if a and b:
                    inq = ((xs < rad) if cx < 8 else (xs > T - rad)) & ((ys < rad) if cy < 8 else (ys > T - rad))
                    solid[inq & (((xs - cx) ** 2 + (ys - cy) ** 2) > rad * rad)] = False
            # padded solidity to find boundaries
            pad = np.ones((T + 2, T + 2), bool)
            pad[1:-1, 1:-1] = solid
            if N:
                pad[0, :] = False
            if S:
                pad[-1, :] = False
            if W:
                pad[:, 0] = False
            if E:
                pad[:, -1] = False
            up = ~pad[:-2, 1:-1]
            dn = ~pad[2:, 1:-1]
            lf = ~pad[1:-1, :-2]
            rt = ~pad[1:-1, 2:]
            boundary = solid & (up | dn | lf | rt)
            inner = solid & ~boundary
            # inner highlight / shadow rings
            r1_up = inner & np.roll(boundary & up, 1, 0)
            r1_dn = inner & np.roll(boundary & dn, -1, 0)
            r1_lf = inner & np.roll(boundary & lf, 1, 1)
            r1_rt = inner & np.roll(boundary & rt, -1, 1)
            r2_up = inner & np.roll(r1_up, 1, 0) & ~r1_up
            lvl = np.clip(lvt.copy(), 0, 5)
            lvl = np.where(r2_up, np.maximum(lvl, 4), lvl)
            lvl = np.where(r1_lf, np.maximum(lvl, 4), lvl)
            lvl = np.where(r1_rt, np.minimum(lvl, 2), lvl)
            lvl = np.where(r1_dn, 1, lvl)
            lvl = np.where(r1_up, 5, lvl)
            out = ramp[lvl]
            # keep authored extras (glints) that the ring pass did not overwrite
            keep = ~(r1_up | r1_dn | r1_lf | r1_rt | r2_up)
            out[keep] = tile[keep]
            # spore moss on upward faces
            if moss_p > 0 and mat in ("soft", "hard", "loose"):
                mz = r1_up | (boundary & up)
                for yy, xx in zip(*np.nonzero(mz)):
                    if rr.random() < moss_p:
                        out[yy, xx] = moss[1 if (xx + var) % 3 else 2]
                        if yy + 1 < T and solid[yy + 1, xx] and rr.random() < 0.4:
                            out[yy + 1, xx] = moss[0]
            out[boundary] = ramp[0]
            if mat == "alloy":
                out[boundary & up] = ramp[4]
            out[~solid] = (0, 0, 0, 0)
            idx = mask * 16 + var
            tx, ty = (idx % 16) * T, (idx // 16) * T
            block[ty:ty + T, tx:tx + T] = out
    return block


def make_cracks():
    """3 damage stages x 4 variants, 16px each -> 64x48."""
    out = np.zeros((48, 64, 4), np.uint8)
    dark = np.array(hexc("#07050a", 235), np.uint8)
    lite = np.array(hexc("#ffffff", 70), np.uint8)
    for v in range(4):
        r = np.random.default_rng(500 + v)
        cx, cy = 6 + r.integers(0, 5), 6 + r.integers(0, 5)
        branches = [r.random() * 6.28 + i * 2.1 for i in range(5)]
        lines = []
        for bi, ang in enumerate(branches):
            pts = []
            x, y = float(cx), float(cy)
            for step in range(9):
                ang += r.normal(0, 0.45)
                x += np.cos(ang)
                y += np.sin(ang)
                pts.append((int(round(x)), int(round(y)), step))
            lines.append(pts)
        for stage in range(3):
            lim = [3, 6, 9][stage]
            nb = [2, 4, 5][stage]
            tile = np.zeros((16, 16, 4), np.uint8)
            tile[cy, cx] = dark
            for pts in lines[:nb]:
                for (x, y, s) in pts:
                    if s < lim and 0 <= x < 16 and 0 <= y < 16:
                        tile[y, x] = dark
                        if 0 <= x + 1 < 16 and 0 <= y + 1 < 16 and tile[y + 1, x + 1, 3] == 0:
                            tile[y + 1, x + 1] = lite
            if stage == 2:
                for (dx, dy) in [(0, 1), (1, 0), (1, 1)]:
                    tile[min(15, cy + dy), min(15, cx + dx)] = dark
            out[stage * 16:(stage + 1) * 16, v * 16:(v + 1) * 16] = tile
    return out


def make_backwalls():
    """Per stratum 64x64 seamless back-wall shown behind dug tunnels -> 320x64."""
    out = np.zeros((64, 64 * STRATA, 4), np.uint8)
    for s in range(STRATA):
        lv, _ = tex_soft(s, 4000 + s)
        ramp = rgb_ramp(RAMPS[("soft", s)])
        tex = ramp[np.clip(lv, 0, 5)].astype(float)
        tex[..., :3] *= 0.34
        if s == 2:  # faint ancient panel seams behind slag
            tex[::16, :, :3] *= 0.6
            tex[:, ::16, :3] *= 0.6
        tex[..., 3] = 255
        out[:, s * 64:(s + 1) * 64] = tex.astype(np.uint8)
    return out


def make_alloy_glow():
    """Emissive circuit traces matching alloy panel kinds (white, tinted in engine)."""
    out = np.zeros((64, 64, 4), np.uint8)
    r = np.random.default_rng(1000 + BLOCKS.index(("alloy", 0)) * 77)
    for py in range(4):
        for px in range(4):
            kind = r.integers(0, 4)
            x0, y0 = px * 16, py * 16
            if kind == 1:
                out[y0 + 8, x0 + 4:x0 + 12] = (255, 255, 255, 200)
                out[y0 + 5:y0 + 8, x0 + 3] = (255, 255, 255, 140)
            if kind == 0:
                out[y0 + 7, x0 + 5:x0 + 11:2] = (255, 255, 255, 120)
    return out


def main():
    atlas = np.zeros((1024, 256 * ATLAS_COLS, 4), np.uint8)
    for bi, key in enumerate(BLOCKS):
        slot = block_slot(key)
        bx, by = slot % ATLAS_COLS, slot // ATLAS_COLS
        atlas[by * 256:(by + 1) * 256, bx * 256:(bx + 1) * 256] = make_block(key, bi)
    save(to_image(atlas), "terrain_atlas.png")
    save(to_image(make_cracks()), "cracks.png")
    save(to_image(make_backwalls()), "backwalls.png")
    save(to_image(make_alloy_glow()), "alloy_glow.png")
    return [f"{m}:{s}" for (m, s) in BLOCKS]


if __name__ == "__main__":
    print(main())
