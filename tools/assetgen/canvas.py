"""Deterministic offline pixel-art canvas and PNG writer.

Stdlib only. No AI image generation, no external assets: every pixel produced by
this module is authored procedurally from code, so the output is original work.
"""
from __future__ import annotations

import math
import struct
import zlib


def clamp8(v) -> int:
    v = int(round(v))
    return 0 if v < 0 else (255 if v > 255 else v)


def rgba(c, a: int = 255):
    if len(c) == 4:
        return (c[0], c[1], c[2], c[3])
    return (c[0], c[1], c[2], a)


def shade(color, factor: float, alpha=None):
    """factor > 1 brightens toward white, < 1 darkens toward black."""
    r, g, b = color[0], color[1], color[2]
    a = color[3] if len(color) == 4 else 255
    if factor >= 1.0:
        f = factor - 1.0
        r = r + (255 - r) * f
        g = g + (255 - g) * f
        b = b + (255 - b) * f
    else:
        r *= factor
        g *= factor
        b *= factor
    if alpha is not None:
        a = alpha
    return (clamp8(r), clamp8(g), clamp8(b), clamp8(a))


def mix(c1, c2, t: float):
    """Linear blend between two colours."""
    a1 = c1[3] if len(c1) == 4 else 255
    a2 = c2[3] if len(c2) == 4 else 255
    return (
        clamp8(c1[0] + (c2[0] - c1[0]) * t),
        clamp8(c1[1] + (c2[1] - c1[1]) * t),
        clamp8(c1[2] + (c2[2] - c1[2]) * t),
        clamp8(a1 + (a2 - a1) * t),
    )


def luminance(color) -> float:
    return (color[0] * 0.299 + color[1] * 0.587 + color[2] * 0.114) / 255.0


class Canvas:
    """A simple RGBA raster canvas with the handful of primitives we need."""

    def __init__(self, w: int, h: int, bg=(0, 0, 0, 0)):
        self.w = int(w)
        self.h = int(h)
        self.data = bytearray(self.w * self.h * 4)
        if len(bg) == 4 and bg[3] != 0:
            self.fill(bg)

    # -- raw access ---------------------------------------------------------
    def _idx(self, x: int, y: int) -> int:
        return (y * self.w + x) * 4

    def get(self, x: int, y: int):
        if x < 0 or y < 0 or x >= self.w or y >= self.h:
            return (0, 0, 0, 0)
        i = self._idx(x, y)
        d = self.data
        return (d[i], d[i + 1], d[i + 2], d[i + 3])

    def set(self, x: int, y: int, color) -> None:
        x = int(x)
        y = int(y)
        if x < 0 or y < 0 or x >= self.w or y >= self.h:
            return
        c = rgba(color)
        i = self._idx(x, y)
        self.data[i] = clamp8(c[0])
        self.data[i + 1] = clamp8(c[1])
        self.data[i + 2] = clamp8(c[2])
        self.data[i + 3] = clamp8(c[3])

    def blend(self, x: int, y: int, color) -> None:
        x = int(x)
        y = int(y)
        if x < 0 or y < 0 or x >= self.w or y >= self.h:
            return
        c = rgba(color)
        sa = c[3]
        if sa == 0:
            return
        i = self._idx(x, y)
        d = self.data
        if sa == 255:
            d[i], d[i + 1], d[i + 2], d[i + 3] = c[0], c[1], c[2], 255
            return
        a = sa / 255.0
        da = d[i + 3] / 255.0
        oa = a + da * (1 - a)
        if oa <= 0:
            return
        for k in range(3):
            d[i + k] = clamp8((c[k] * a + d[i + k] * da * (1 - a)) / oa)
        d[i + 3] = clamp8(oa * 255)

    def fill(self, color) -> None:
        c = rgba(color)
        row = bytes((c[0], c[1], c[2], c[3])) * self.w
        for y in range(self.h):
            i = self._idx(0, y)
            self.data[i:i + self.w * 4] = row

    # -- shapes ------------------------------------------------------------
    def rect(self, x, y, w, h, color, blend=False):
        fn = self.blend if blend else self.set
        for yy in range(int(y), int(y + h)):
            for xx in range(int(x), int(x + w)):
                fn(xx, yy, color)

    def hline(self, x0, x1, y, color, blend=False):
        if x1 < x0:
            x0, x1 = x1, x0
        for x in range(int(x0), int(x1) + 1):
            (self.blend if blend else self.set)(x, int(y), color)

    def vline(self, x, y0, y1, color, blend=False):
        if y1 < y0:
            y0, y1 = y1, y0
        for y in range(int(y0), int(y1) + 1):
            (self.blend if blend else self.set)(int(x), y, color)

    def line(self, x0, y0, x1, y1, color, thickness=1, blend=False):
        x0, y0, x1, y1 = int(round(x0)), int(round(y0)), int(round(x1)), int(round(y1))
        dx, dy = abs(x1 - x0), abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx - dy
        half = thickness // 2
        while True:
            if thickness <= 1:
                (self.blend if blend else self.set)(x0, y0, color)
            else:
                for oy in range(-half, half + 1):
                    for ox in range(-half, half + 1):
                        (self.blend if blend else self.set)(x0 + ox, y0 + oy, color)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 > -dy:
                err -= dy
                x0 += sx
            if e2 < dx:
                err += dx
                y0 += sy

    def ellipse(self, cx, cy, rx, ry, color, blend=False):
        fn = self.blend if blend else self.set
        if rx <= 0 or ry <= 0:
            return
        for y in range(int(cy - ry), int(cy + ry) + 1):
            for x in range(int(cx - rx), int(cx + rx) + 1):
                nx = (x - cx) / rx
                ny = (y - cy) / ry
                if nx * nx + ny * ny <= 1.0:
                    fn(x, y, color)

    def circle(self, cx, cy, r, color, blend=False):
        self.ellipse(cx, cy, r, r, color, blend)

    def polygon(self, points, color, blend=False):
        fn = self.blend if blend else self.set
        if len(points) < 3:
            return
        ys = [p[1] for p in points]
        ymin, ymax = int(math.floor(min(ys))), int(math.ceil(max(ys)))
        n = len(points)
        for y in range(ymin, ymax + 1):
            xs = []
            for i in range(n):
                x1, y1 = points[i]
                x2, y2 = points[(i + 1) % n]
                if y1 == y2:
                    continue
                if min(y1, y2) <= y < max(y1, y2):
                    t = (y - y1) / (y2 - y1)
                    xs.append(x1 + (x2 - x1) * t)
            xs.sort()
            for i in range(0, len(xs) - 1, 2):
                for x in range(int(math.ceil(xs[i])), int(math.floor(xs[i + 1])) + 1):
                    fn(x, y, color)

    def sparkle(self, x, y, r, color, blend=True):
        """Diamond shaped glow used for crystals and emissive accents."""
        for dy in range(-r, r + 1):
            span = r - abs(dy)
            for dx in range(-span, span + 1):
                a = int(color[3] * (1.0 - (abs(dx) + abs(dy)) / float(r + 1)))
                (self.blend if blend else self.set)(x + dx, y + dy, (color[0], color[1], color[2], a))

    # -- post processing ----------------------------------------------------
    def outline(self, color, alpha=255, diagonal=False):
        src = bytes(self.data)
        w, h = self.w, self.h
        offsets = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        if diagonal:
            offsets += [(-1, -1), (1, -1), (-1, 1), (1, 1)]
        for y in range(h):
            for x in range(w):
                i = (y * w + x) * 4
                if src[i + 3] > 40:
                    continue
                for ox, oy in offsets:
                    nx, ny = x + ox, y + oy
                    if nx < 0 or ny < 0 or nx >= w or ny >= h:
                        continue
                    j = (ny * w + nx) * 4
                    if src[j + 3] > 140:
                        self.set(x, y, (color[0], color[1], color[2], alpha))
                        break

    def bevel(self, light_f=1.35, dark_f=0.6, strength=1):
        """Cheap directional bevel: brighten the top-left, darken bottom-right."""
        w, h = self.w, self.h
        src = bytes(self.data)
        for y in range(h):
            for x in range(w):
                i = (y * w + x) * 4
                if src[i + 3] < 40:
                    continue
                c = (src[i], src[i + 1], src[i + 2], src[i + 3])
                up = src[((y - 1) * w + x) * 4 + 3] if y > 0 else 0
                left = src[(y * w + x - 1) * 4 + 3] if x > 0 else 0
                down = src[((y + 1) * w + x) * 4 + 3] if y < h - 1 else 0
                right = src[(y * w + x + 1) * 4 + 3] if x < w - 1 else 0
                if (up < 40 or left < 40) and strength:
                    self.set(x, y, shade(c, light_f))
                elif (down < 40 or right < 40) and strength:
                    self.set(x, y, shade(c, dark_f))

    def grain(self, rng, amount=0.08):
        w, h = self.w, self.h
        for y in range(h):
            for x in range(w):
                i = (y * w + x) * 4
                if self.data[i + 3] == 0:
                    continue
                f = 1.0 + rng.uniform(-amount, amount)
                self.data[i] = clamp8(self.data[i] * f)
                self.data[i + 1] = clamp8(self.data[i + 1] * f)
                self.data[i + 2] = clamp8(self.data[i + 2] * f)

    def blit(self, other: "Canvas", ox=0, oy=0):
        for y in range(other.h):
            for x in range(other.w):
                c = other.get(x, y)
                if c[3] == 0:
                    continue
                self.blend(ox + x, oy + y, c)

    def sub(self, x, y, w, h) -> "Canvas":
        out = Canvas(w, h)
        for yy in range(h):
            for xx in range(w):
                out.set(xx, yy, self.get(x + xx, y + yy))
        return out

    def flip_h(self) -> "Canvas":
        out = Canvas(self.w, self.h)
        for y in range(self.h):
            for x in range(self.w):
                out.set(self.w - 1 - x, y, self.get(x, y))
        return out

    def to_bytes(self) -> bytes:
        return bytes(self.data)


def save_png(path: str, canvas: Canvas) -> None:
    w, h = canvas.w, canvas.h
    stride = w * 4
    raw = bytearray()
    data = canvas.data
    for y in range(h):
        raw.append(0)  # filter: none
        raw += data[y * stride:(y + 1) * stride]
    comp = zlib.compress(bytes(raw), 9)

    def chunk(tag: bytes, payload: bytes) -> bytes:
        return (struct.pack(">I", len(payload)) + tag + payload
                + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", comp)
    png += chunk(b"IEND", b"")
    with open(path, "wb") as fh:
        fh.write(png)
