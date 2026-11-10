"""Parallax backgrounds: per-stratum far/mid layers, foreground cables, outpost sky."""
from __future__ import annotations

import math

import numpy as np

from art_common import BAYER4, fbm, hexc, save, to_image

W, H = 512, 256


def col(h):
    return np.array(hexc(h), np.float64)


def fill_mask(img, mask, c, alpha=255):
    img[mask, :3] = col(c)[:3]
    img[mask, 3] = alpha


def dither_grad(h, w, top, bot):
    t = np.linspace(0, 1, h)[:, None] * np.ones((1, w))
    b = np.tile(BAYER4, (h // 4 + 1, w // 4 + 1))[:h, :w]
    steps = 6
    q = np.floor(t * steps + (b - 0.5) * 0.9) / steps
    q = np.clip(q, 0, 1)[..., None]
    out = col(top)[:3] * (1 - q) + col(bot)[:3] * q
    return out


def far_layer(stratum):
    img = np.zeros((H, W, 4), np.float64)
    r = np.random.default_rng(10 + stratum)
    ys, xs = np.mgrid[0:H, 0:W]
    if stratum == 0:
        base, dark, accent = "#2a1a12", "#1c120c", "#3d281a"
    elif stratum == 1:
        base, dark, accent = "#0d2226", "#081619", "#123238"
    elif stratum == 3:
        base, dark, accent = "#0c1a2c", "#070f1c", "#14283f"
    elif stratum == 4:
        base, dark, accent = "#1c0d26", "#110818", "#2c153a"
    else:
        base, dark, accent = "#1a1226", "#110b1a", "#251a36"
    img[..., :3] = dither_grad(H, W, base, dark)
    img[..., 3] = 255
    # distant rock pillars / shafts
    n = fbm(W, H, 64, 3, 30 + stratum)
    fill_mask(img, n > 0.62, accent)
    if stratum == 0:
        # scaffold towers
        for k in range(4):
            x0 = int(r.integers(0, W))
            w = int(r.integers(18, 30))
            for x in (x0, x0 + w):
                fill_mask(img, (np.abs(((xs - x) % W)) < 2), "#120b07")
            for y in range(0, H, 22):
                for t in range(w):
                    yy = y + (t * 22) // w
                    img[yy % H, (x0 + t) % W, :3] = col("#120b07")[:3]
                img[y:y + 2, [(x0 + t) % W for t in range(w)], :3] = col("#120b07")[:3]
    elif stratum == 1:
        # giant fungal stalks with glowing caps silhouettes
        for k in range(5):
            x0 = int(r.integers(0, W))
            wid = int(r.integers(8, 16))
            top = int(r.integers(40, 140))
            m = (((xs - x0) % W) < wid) & (ys > top)
            fill_mask(img, m, "#06120f")
            cap = (((xs - x0 - wid / 2 + W / 2) % W - W / 2) ** 2 / (wid * 2.2) ** 2 + (ys - top) ** 2 / 14 ** 2) < 1
            fill_mask(img, cap & (ys <= top + 2), "#0f3a36")
            spots = cap & ((xs * 7 + ys * 3) % 23 == 0)
            fill_mask(img, spots, "#2ab3a0")
    elif stratum == 3:
        # drowned arcades: rows of tall arches receding into the dark
        for k, (y0, span, tone) in enumerate([(70, 46, "#081320"), (150, 64, "#060e18")]):
            for x0 in range(int(r.integers(0, span)), W + span, span):
                dx = ((xs - x0 + W / 2) % W) - W / 2
                pier = np.abs(dx) < span * 0.14
                arch = (np.abs(dx) < span * 0.5) & (ys < y0 - (span * 0.36) * np.sqrt(np.clip(1 - (dx / (span * 0.5)) ** 2, 0, 1)) + 6)
                fill_mask(img, (pier | arch) & (ys > y0 - span * 0.9) & (ys < y0 + 60), tone)
            fill_mask(img, (ys >= y0 + 58) & (ys < y0 + 62), "#1b4a66")     # waterline glint
    elif stratum == 4:
        # giant crystal spires, some with a lit facet
        for k in range(9):
            x0 = int(r.integers(0, W))
            base_y = int(r.integers(120, H))
            hgt = int(r.integers(60, 170))
            wid = int(r.integers(8, 22))
            lean = float(r.uniform(-0.25, 0.25))
            t = np.clip((base_y - ys) / hgt, 0, 1)
            dx = ((xs - x0 - lean * (base_y - ys) + W / 2) % W) - W / 2
            spire = (np.abs(dx) < wid * (1 - t)) & (ys <= base_y) & (ys > base_y - hgt)
            fill_mask(img, spire, "#0d0616")
            fill_mask(img, spire & (dx > 0) & (dx < wid * (1 - t) * 0.45), "#3a1b55")
            fill_mask(img, spire & (np.abs(dx - 1) < 1) & ((ys + x0) % 9 < 5), "#c58cff")
    else:
        # distant colossal machinery: gears and vertical conduits with lights
        for k in range(3):
            cx, cy = int(r.integers(0, W)), int(r.integers(40, 200))
            R = int(r.integers(30, 60))
            dx = ((xs - cx + W / 2) % W) - W / 2
            d = np.sqrt(dx ** 2 + (ys - cy) ** 2)
            ang = np.arctan2(ys - cy, dx)
            teeth = (np.sin(ang * 12) > 0) & (d < R + 5)
            gear = ((d < R) | teeth) & (d > R * 0.35)
            fill_mask(img, gear, "#0b0712")
        for k in range(6):
            x0 = int(r.integers(0, W))
            fill_mask(img, ((xs - x0) % W) < 3, "#0e0918")
            for y in range(int(r.integers(0, 40)), H, 48):
                img[y:y + 2, x0 % W:(x0 % W) + 3, :3] = col("#6b3fd0")[:3]
    return img.astype(np.uint8)


def mid_layer(stratum):
    img = np.zeros((H, W, 4), np.float64)
    r = np.random.default_rng(50 + stratum)
    ys, xs = np.mgrid[0:H, 0:W]
    sil = {0: "#140c07", 1: "#04100e", 2: "#0a0610", 3: "#050c16", 4: "#0c0513"}[stratum]
    hi = {0: "#2e1e12", 1: "#0f2d2a", 2: "#221636", 3: "#1a3550", 4: "#3a1c52"}[stratum]
    if stratum == 0:
        # horizontal pipes & wooden cross beams
        for k in range(3):
            y0 = int(r.integers(10, H - 20))
            th = int(r.integers(5, 9))
            m = (ys >= y0) & (ys < y0 + th)
            fill_mask(img, m, sil)
            fill_mask(img, ys == y0, hi)
            for x in range(int(r.integers(0, 40)), W, 64):
                fill_mask(img, (np.abs(xs - x) < 3) & (ys >= y0 - 2) & (ys < y0 + th + 2), sil)
        for k in range(5):
            x0 = int(r.integers(0, W))
            fill_mask(img, (((xs - x0) % W) < 6), sil, 255)
            fill_mask(img, (((xs - x0) % W) == 0), hi)
    elif stratum == 1:
        # hanging roots (sinuous verticals)
        for k in range(9):
            x0 = r.integers(0, W)
            ph = r.random() * 6
            wid = r.integers(2, 6)
            off = (np.sin(ys / 23.0 + ph) * 6 + np.sin(ys / 7.0 + ph) * 1.5)
            m = np.abs(((xs - x0 - off + W / 2) % W) - W / 2) < wid
            fill_mask(img, m, sil)
            dots = m & ((ys + x0) % 31 == 0)
            fill_mask(img, dots, "#3ee0c0")
    elif stratum == 3:
        # broken channel walls and thin falls of water
        for k in range(3):
            y0 = int(r.integers(20, H - 30))
            th = int(r.integers(8, 14))
            gap0 = int(r.integers(0, W))
            m = (ys >= y0) & (ys < y0 + th) & (((xs - gap0) % W) > 70)
            fill_mask(img, m, sil)
            fill_mask(img, m & (ys == y0), hi)
            fill_mask(img, m & ((xs + y0) % 16 == 0), "#081320")
            fall = (np.abs(((xs - gap0 - 72 + W / 2) % W) - W / 2) < 2) & (ys >= y0 + th)
            fill_mask(img, fall & ((ys + xs) % 5 < 3), "#3fa8d8", 150)
    elif stratum == 4:
        # near crystal clusters hanging from above and rising from below
        for k in range(10):
            x0 = int(r.integers(0, W))
            from_top = k % 2 == 0
            hgt = int(r.integers(30, 90))
            wid = int(r.integers(5, 12))
            edge_y = 0 if from_top else H
            dist = (ys - edge_y) if from_top else (edge_y - ys)
            t = np.clip(dist / hgt, 0, 1)
            dx = ((xs - x0 + W / 2) % W) - W / 2
            shard = (np.abs(dx) < wid * (1 - t)) & (dist >= 0) & (dist < hgt)
            fill_mask(img, shard, sil)
            fill_mask(img, shard & (dx < -wid * (1 - t) * 0.4), hi)
            fill_mask(img, shard & (np.abs(dx) < 1) & (dist % 11 < 3), "#ff9af0")
    else:
        # machine frames: big rectangles with rivet lines and circuit glows
        for k in range(4):
            x0 = int(r.integers(0, W))
            w = int(r.integers(40, 90))
            y0 = int(r.integers(0, H - 60))
            h = int(r.integers(40, 120))
            m = (((xs - x0) % W) < w) & (ys >= y0) & (ys < y0 + h)
            fill_mask(img, m, sil)
            edge = m & ((((xs - x0) % W) < 2) | (ys == y0))
            fill_mask(img, edge, hi)
            trace = m & (ys == y0 + h // 2) & (((xs - x0) % W) > 6) & (((xs - x0) % W) < w - 6)
            fill_mask(img, trace, "#8a4cff")
    return img.astype(np.uint8)


def fore_layer():
    """Dark broken cables dangling in the foreground (sparse)."""
    img = np.zeros((H, W, 4), np.uint8)
    r = np.random.default_rng(99)
    for k in range(3):
        x0 = int(r.integers(0, W - 120))
        x1 = x0 + int(r.integers(60, 120))
        sag = int(r.integers(30, 80))
        for i in range(x1 - x0):
            t = i / (x1 - x0)
            y = int(4 * sag * t * (1 - t))
            for th in range(3):
                img[min(H - 1, y + th), x0 + i] = (8, 6, 10, 235)
        # broken dangling end
        if k == 1:
            for y in range(0, 90):
                xx = x1 + int(math.sin(y / 9) * 2)
                if xx < W:
                    img[y, xx:xx + 2] = (8, 6, 10, 235)
            img[90:93, x1:x1 + 3] = (255, 200, 90, 255)
    return img


def outpost_layers():
    w, h = 640, 360
    sky = np.zeros((h, w, 4), np.float64)
    # dusk gradient: deep violet top -> burnt orange horizon
    t = np.linspace(0, 1, h)[:, None]
    stops = [(0.0, "#1b1036"), (0.35, "#4a1f4f"), (0.6, "#b2483e"), (0.75, "#f39a4a"), (1.0, "#ffd58a")]
    out = np.zeros((h, 1, 3))
    for i in range(len(stops) - 1):
        a, ca = stops[i]
        b, cb = stops[i + 1]
        m = (t >= a) & (t <= b)
        u = np.where(m, (t - a) / (b - a), 0)
        out = np.where(m[..., None], (col(ca)[:3] * (1 - u[..., None]) + col(cb)[:3] * u[..., None]), out)
    bay = np.tile(BAYER4, (h // 4 + 1, w // 4 + 1))[:h, :w]
    sky[..., :3] = np.floor(out / 10 + bay[..., None] * 0.8) * 10
    sky[..., 3] = 255
    # stars
    r = np.random.default_rng(7)
    for _ in range(80):
        x, y = r.integers(0, w), r.integers(0, h // 3)
        sky[y, x, :3] = (255, 240, 220)
    # sun
    ys, xs = np.mgrid[0:h, 0:w]
    d = np.sqrt((xs - 470) ** 2 + (ys - 250) ** 2)
    sky[d < 34, :3] = col("#ffe9b0")[:3]
    sky[(d >= 34) & (d < 38) & (((xs + ys) % 2) == 0), :3] = col("#ffd08a")[:3]
    save(to_image(sky.astype(np.uint8)), "outpost_sky.png")

    # far ruined industrial skyline (tileable horizontally)
    far = np.zeros((180, w, 4), np.uint8)
    base = 180
    x = 0
    while x < w:
        bw = int(r.integers(14, 46))
        bh = int(r.integers(30, 120))
        kind = r.integers(0, 4)
        top = base - bh
        far[top:base, x:x + bw] = (74, 34, 58, 255)
        if kind == 0:  # smokestack
            sx = x + bw // 2
            far[top - 50:top, sx - 3:sx + 3] = (74, 34, 58, 255)
            far[top - 50:top - 46, sx - 4:sx + 4] = (74, 34, 58, 255)
        elif kind == 1:  # broken jagged roof
            for i in range(bw):
                jag = int(abs(math.sin(i * 1.7)) * 10)
                far[top - jag:top, min(w - 1, x + i)] = (74, 34, 58, 255)
        elif kind == 2:  # crane
            far[top - 60:top, x + 2:x + 5] = (74, 34, 58, 255)
            far[top - 60:top - 57, x:x + 60 if x + 60 < w else w] = (74, 34, 58, 255)
        # windows (few lit)
        for wy in range(top + 6, base - 6, 9):
            for wx in range(x + 3, x + bw - 3, 6):
                if r.random() < 0.08:
                    far[wy:wy + 2, wx:wx + 2] = (255, 170, 90, 255)
        x += bw + int(r.integers(0, 12))
    save(to_image(far), "outpost_far.png")

    # mid mesas / dunes
    mid = np.zeros((140, w, 4), np.uint8)
    xs1 = np.arange(w)
    ridge = 60 + 25 * np.sin(xs1 / w * math.tau * 2) + 12 * np.sin(xs1 / w * math.tau * 5 + 1)
    for xx in range(w):
        top = int(ridge[xx])
        mid[top:, xx] = (52, 22, 30, 255)
        mid[top:top + 2, xx] = (120, 52, 48, 255)
    save(to_image(mid), "outpost_mid.png")


def main():
    far = np.concatenate([far_layer(s) for s in range(5)], 0)
    mid = np.concatenate([mid_layer(s) for s in range(5)], 0)
    save(to_image(far), "bg_far.png")
    save(to_image(mid), "bg_mid.png")
    save(to_image(fore_layer()), "bg_fore.png")
    outpost_layers()


if __name__ == "__main__":
    main()
