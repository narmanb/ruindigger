#!/usr/bin/env python3
"""Render generated PNGs as plain-text colour-mapped art.

Each pixel becomes one character: the letter encodes hue family, case encodes
brightness. This survives log capture where ANSI colour does not, so generated
art can be reviewed from the terminal.
"""
from __future__ import annotations

import os
import struct
import sys
import zlib

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def read_png(path):
    with open(path, "rb") as fh:
        data = fh.read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a png"
    pos = 8
    w = h = None
    idat = b""
    while pos < len(data):
        ln = struct.unpack(">I", data[pos:pos + 4])[0]
        tag = data[pos + 4:pos + 8]
        payload = data[pos + 8:pos + 8 + ln]
        if tag == b"IHDR":
            w, h, depth, ctype = struct.unpack(">IIBB", payload[:10])
            assert depth == 8 and ctype == 6, f"unsupported png {depth}/{ctype}"
        elif tag == b"IDAT":
            idat += payload
        pos += 12 + ln
    raw = zlib.decompress(idat)
    stride = w * 4
    px = []
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        f = raw[p]
        p += 1
        line = bytearray(raw[p:p + stride])
        p += stride
        if f == 1:
            for i in range(4, stride):
                line[i] = (line[i] + line[i - 4]) & 255
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif f == 3:
            for i in range(stride):
                a = line[i - 4] if i >= 4 else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 255
        elif f == 4:
            for i in range(stride):
                a = line[i - 4] if i >= 4 else 0
                b = prev[i]
                c = prev[i - 4] if i >= 4 else 0
                pp = a + b - c
                pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        prev = line
        px.append([(line[x * 4], line[x * 4 + 1], line[x * 4 + 2], line[x * 4 + 3])
                   for x in range(w)])
    return w, h, px


def char_for(r, g, b, a):
    if a < 30:
        return "."
    mx, mn = max(r, g, b), min(r, g, b)
    sat = (mx - mn) / 255.0
    lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
    if lum < 0.10:
        return "#"
    if sat < 0.14:
        ch = "n"
    else:
        if r >= g and r >= b:
            ch = "y" if g > b + 25 else ("m" if b > g + 25 else "r")
        elif g >= r and g >= b:
            ch = "c" if b > r + 25 else "g"
        else:
            ch = "b"
    if lum > 0.86:
        return "@"
    if lum > 0.5:
        return ch.upper()
    if lum > 0.25:
        return ch
    return ch


def show(path, max_w=150):
    w, h, px = read_png(path)
    step = max(1, (w + max_w - 1) // max_w)
    print(f"--- {os.path.basename(path)}  ({w}x{h}) step={step} ---")
    for y in range(0, h, step):
        line = ""
        for x in range(0, w, step):
            r, g, b, a = px[y][x]
            line += char_for(r, g, b, a)
        print(line)
    print()


if __name__ == "__main__":
    for arg in sys.argv[1:]:
        show(arg if os.path.isabs(arg) else os.path.join(ROOT, arg))
