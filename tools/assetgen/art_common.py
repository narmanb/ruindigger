"""Shared helpers for Ruin Digger's deterministic pixel-art generator.

Everything here is pure numpy/PIL. Images are built as palette-index canvases
(0 = transparent) so drawing stays crisp, then mapped to RGBA at export time.
"""
from __future__ import annotations

import math
import os

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "gen")


def hexc(h: str, a: int = 255) -> tuple:
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


# --------------------------------------------------------------------------
# Global palette. Index 0 is transparent. Named ramps are dark -> light.
# --------------------------------------------------------------------------
PALETTE: list = [(0, 0, 0, 0)]
NAMES: dict = {}


def ramp(name: str, colors: list) -> list:
    idx = []
    for i, c in enumerate(colors):
        NAMES[f"{name}{i}"] = len(PALETTE)
        idx.append(len(PALETTE))
        PALETTE.append(hexc(c) if isinstance(c, str) else c)
    NAMES[name] = idx
    return idx


def P(name: str) -> int:
    return NAMES[name]


ramp("ink", ["#0b0910", "#17131d"])
ramp("shell", ["#5a2a10", "#9c4f18", "#d8771e", "#f5a23a", "#ffd47e"])
ramp("steel", ["#23262f", "#3f4552", "#646c7b", "#939cab", "#cfd6de"])
ramp("visor", ["#0f3c52", "#1f7ea0", "#45c7e8", "#a6f6ff", "#ffffff"])
ramp("pack", ["#0e4a34", "#22a067", "#6dffb3", "#d6ffe9"])
ramp("boot", ["#20160f", "#3b2a1d", "#5c4330", "#86684c"])
ramp("hazard", ["#1a1410", "#f2c230"])
ramp("chit", ["#1b1820", "#34303d", "#4f4a5a", "#6f6a7c", "#9690a3"])
ramp("flesh", ["#4a1a2a", "#8a2f45", "#c95468", "#f08a95"])
ramp("eye", ["#6b2600", "#ff8a1e", "#ffe28a"])
ramp("ruin", ["#120e1a", "#241c33", "#3a2f52", "#574a78", "#7c6ca6", "#a99ad0"])
ramp("cyan", ["#0a3a44", "#18a0b0", "#4ff0ff", "#c8ffff"])
ramp("red", ["#3a0710", "#a1142c", "#ff3b4e", "#ffb0b8"])
ramp("gold", ["#4b2a06", "#9a5f10", "#e3a521", "#ffe07a", "#fff6cf"])
ramp("copper", ["#3d1a0a", "#8a3d17", "#d4702c", "#ffab5e", "#ffe2b8"])
ramp("cobalt", ["#06203d", "#1453a0", "#2e9bf0", "#8fd7ff", "#e6fbff"])
ramp("aether", ["#2a0838", "#6b1a8f", "#c03df0", "#f29cff", "#fff0ff"])
ramp("bone", ["#4a3e2c", "#8a7a5c", "#c8b98f", "#efe5c4"])
ramp("gas", ["#2b3a06", "#5f7d0f", "#a6c51f", "#e2f56a", "#fbffd0"])
ramp("wood", ["#24150b", "#432814", "#6b4423", "#946234", "#bf8a4f"])
ramp("rust", ["#2a120a", "#5c2a14", "#8f4520", "#bf6a34"])
ramp("leaf", ["#13261a", "#24472b", "#3f6e3a", "#6c9b4d"])
ramp("lamp", ["#5c3a10", "#ffb347", "#ffe9a8", "#ffffff"])
ramp("fung", ["#1d0f2b", "#4d1f6b", "#8f3fbf", "#d17cff", "#f7d6ff"])
ramp("teal", ["#071b1e", "#0f3b3e", "#1d6a66", "#36a58f", "#7ef2c9"])
ramp("white", ["#ffffff"])


def palette_rgba() -> np.ndarray:
    return np.array(PALETTE, dtype=np.uint8)


# --------------------------------------------------------------------------
# Canvas
# --------------------------------------------------------------------------
class Canvas:
    def __init__(self, w: int, h: int):
        self.w, self.h = w, h
        self.img = Image.new("L", (w, h), 0)
        self.d = ImageDraw.Draw(self.img)

    # primitives take palette indices
    def rect(self, x, y, w, h, c):
        if w <= 0 or h <= 0:
            return
        self.d.rectangle([x, y, x + w - 1, y + h - 1], fill=c)

    def px(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.img.putpixel((int(x), int(y)), c)

    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.img.getpixel((int(x), int(y)))
        return 0

    def line(self, x0, y0, x1, y1, c, width=1):
        self.d.line([x0, y0, x1, y1], fill=c, width=width)

    def ellipse(self, x, y, w, h, c):
        self.d.ellipse([x, y, x + w - 1, y + h - 1], fill=c)

    def poly(self, pts, c):
        self.d.polygon([(float(a), float(b)) for a, b in pts], fill=c)

    def arr(self) -> np.ndarray:
        return np.array(self.img, dtype=np.uint8)

    def set_arr(self, a: np.ndarray):
        self.img = Image.fromarray(a.astype(np.uint8), "L")
        self.d = ImageDraw.Draw(self.img)

    def outline(self, c=None, diag=False):
        """Add a 1px outline around all non-transparent pixels."""
        c = P("ink0") if c is None else c
        a = self.arr()
        m = a > 0
        n = np.zeros_like(m)
        n[1:, :] |= m[:-1, :]
        n[:-1, :] |= m[1:, :]
        n[:, 1:] |= m[:, :-1]
        n[:, :-1] |= m[:, 1:]
        if diag:
            n[1:, 1:] |= m[:-1, :-1]
            n[:-1, :-1] |= m[1:, 1:]
            n[1:, :-1] |= m[:-1, 1:]
            n[:-1, 1:] |= m[1:, :-1]
        a[n & ~m] = c
        self.set_arr(a)

    def blit(self, other: "Canvas", x: int, y: int):
        a = self.arr()
        b = other.arr()
        h, w = b.shape
        for yy in range(h):
            ty = y + yy
            if ty < 0 or ty >= self.h:
                continue
            for xx in range(w):
                tx = x + xx
                if 0 <= tx < self.w and b[yy, xx]:
                    a[ty, tx] = b[yy, xx]
        self.set_arr(a)

    def flip_h(self) -> "Canvas":
        c = Canvas(self.w, self.h)
        c.set_arr(self.arr()[:, ::-1])
        return c

    def rgba(self) -> np.ndarray:
        return palette_rgba()[self.arr()]


def to_image(rgba: np.ndarray) -> Image.Image:
    return Image.fromarray(rgba.astype(np.uint8), "RGBA")


def save(img: Image.Image, name: str):
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, name))


def sheet(frames: list, fw: int, fh: int, cols: int | None = None) -> np.ndarray:
    """frames: list of RGBA arrays (fh, fw, 4) -> sheet RGBA."""
    cols = cols or len(frames)
    rows = math.ceil(len(frames) / cols)
    out = np.zeros((rows * fh, cols * fw, 4), np.uint8)
    for i, f in enumerate(frames):
        r, c = divmod(i, cols)
        out[r * fh:(r + 1) * fh, c * fw:(c + 1) * fw] = f
    return out


# --------------------------------------------------------------------------
# Noise (tileable)
# --------------------------------------------------------------------------
def tnoise(w: int, h: int, cell: int, seed: int) -> np.ndarray:
    r = np.random.default_rng(seed)
    gx, gy = max(1, w // cell), max(1, h // cell)
    g = r.random((gy, gx))
    xs = np.arange(w) / (w / gx)
    ys = np.arange(h) / (h / gy)
    x0 = np.floor(xs).astype(int)
    y0 = np.floor(ys).astype(int)
    fx = xs - x0
    fy = ys - y0
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    x1 = (x0 + 1) % gx
    y1 = (y0 + 1) % gy
    x0 %= gx
    y0 %= gy
    a = g[np.ix_(y0, x0)]
    b = g[np.ix_(y0, x1)]
    c = g[np.ix_(y1, x0)]
    d = g[np.ix_(y1, x1)]
    FX = fx[None, :]
    FY = fy[:, None]
    return (a * (1 - FX) + b * FX) * (1 - FY) + (c * (1 - FX) + d * FX) * FY


def fbm(w: int, h: int, base: int, octaves: int, seed: int) -> np.ndarray:
    total = np.zeros((h, w))
    amp = 1.0
    norm = 0.0
    cell = base
    for o in range(octaves):
        total += amp * tnoise(w, h, max(2, cell), seed + o * 101)
        norm += amp
        amp *= 0.5
        cell //= 2
    return total / norm


def worley(w: int, h: int, n: int, seed: int):
    """Tileable worley: returns (f1, f2, id) arrays."""
    r = np.random.default_rng(seed)
    pts = r.random((n, 2)) * [w, h]
    ys, xs = np.mgrid[0:h, 0:w]
    best1 = np.full((h, w), 1e9)
    best2 = np.full((h, w), 1e9)
    ids = np.zeros((h, w), int)
    for i, (px, py) in enumerate(pts):
        dx = np.abs(xs - px)
        dy = np.abs(ys - py)
        dx = np.minimum(dx, w - dx)
        dy = np.minimum(dy, h - dy)
        d = np.sqrt(dx * dx + dy * dy)
        closer = d < best1
        best2 = np.where(closer, best1, np.minimum(best2, d))
        ids = np.where(closer, i, ids)
        best1 = np.where(closer, d, best1)
    return best1, best2, ids


BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0


def quantize(v: np.ndarray, levels: int, dither: float = 0.6) -> np.ndarray:
    """Map v in [0,1] to integer levels with ordered dithering."""
    h, w = v.shape
    b = np.tile(BAYER4, (h // 4 + 1, w // 4 + 1))[:h, :w]
    q = np.floor(np.clip(v, 0, 0.9999) * levels + (b - 0.5) * dither)
    return np.clip(q, 0, levels - 1).astype(int)


def mix(c1, c2, t):
    return tuple(int(round(c1[i] * (1 - t) + c2[i] * t)) for i in range(4))
