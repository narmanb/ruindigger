"""Procedural enemy sprites: Burrow Crawler and Ruin Sentry."""
from __future__ import annotations

import json
import math

from canvas import Canvas, save_png, shade, mix
from palette import CRAWLER as K, SENTRY as S

W, H = 24, 20


def _leg(c, x, y, ang, col, len_=5, w=2):
    a = math.radians(ang)
    x1 = x + math.cos(a) * len_
    y1 = y + math.sin(a) * len_
    steps = max(1, int(max(abs(x1 - x), abs(y1 - y))))
    for i in range(steps + 1):
        t = i / steps
        c.ellipse(x + (x1 - x) * t, y + (y1 - y) * t, w * 0.5, w * 0.5, col)
    c.ellipse(x1, y1, 1.4, 1.4, shade(col, 1.3))


def crawler_frame(i: int, n: int, attack: bool = False) -> Canvas:
    c = Canvas(W, H)
    t = i / max(1, n)
    ph = math.sin(t * math.tau)
    cy = 12
    cx = 12
    # segmented carapace
    for seg in range(4):
        sx = cx - 6 + seg * 3.5
        r = 4.2 - abs(seg - 1.4) * 0.55
        c.ellipse(sx, cy - abs(seg - 1.4) * 0.6, r, r * 0.82, K["shell_dk"])
        c.ellipse(sx, cy - 0.8 - abs(seg - 1.4) * 0.6, r - 0.8, r * 0.6, K["shell"])
        c.ellipse(sx, cy - 1.6 - abs(seg - 1.4) * 0.6, r - 1.6, r * 0.32, K["shell_lt"])
    # head
    c.ellipse(cx + 8, cy - 1, 3.6, 3.0, K["shell"])
    c.ellipse(cx + 8, cy - 2, 2.6, 1.8, K["shell_lt"])
    # mandibles
    for s in (-1, 1):
        _leg(c, cx + 10, cy + s * 1.5, 10 * s - 10, K["leg"], 4, 2)
    # legs
    for j, lx in enumerate((-5, -1.5, 2.5, 6)):
        swing = math.sin(t * math.tau + j * 1.3) * 4
        _leg(c, cx + lx, cy + 2, 70 + swing, K["leg"], 6, 2)
        _leg(c, cx + lx, cy + 2, 110 - swing, K["leg"], 6, 2)
    # glowing eyes
    ec = K["eye"] if not attack else shade(K["eye"], 1.4)
    c.ellipse(cx + 9, cy - 1, 1.5, 1.5, ec)
    c.set(cx + 9, cy - 1, K["eye_lt"])
    c.sparkle(cx + 9, cy - 1, 3, (ec[0], ec[1], ec[2], 90))
    # tail
    _leg(c, cx - 7, cy, 190, K["shell_dk"], 5, 3)
    c.outline(K["outline"], 230)
    return c


def sentry_frame(i: int, n: int, firing: bool = False) -> Canvas:
    c = Canvas(W, H)
    t = i / max(1, n)
    ph = math.sin(t * math.tau)
    cx, cy = 12, 11
    # mounting bracket + column
    c.rect(cx - 4, cy + 5, 9, 4, S["body_dk"])
    c.rect(cx - 5, cy + 8, 11, 3, shade(S["body_dk"], 0.8))
    for rx in range(cx - 4, cx + 5, 3):
        c.set(rx, cy + 6, shade(S["body_lt"], 1.2))
    # core body
    c.polygon([(cx - 6, cy + 5), (cx + 6, cy + 5), (cx + 5, cy - 4), (cx - 5, cy - 4)], S["body"])
    c.polygon([(cx - 5, cy + 4), (cx + 5, cy + 4), (cx + 4, cy - 3), (cx - 4, cy - 3)], S["body_lt"])
    # head dome
    c.ellipse(cx, cy - 6, 5.0, 4.0, S["body"])
    c.ellipse(cx, cy - 7, 3.6, 2.6, S["body_lt"])
    # sensor eye
    ec = S["panel"] if not firing else shade(S["panel"], 1.5)
    c.ellipse(cx, cy - 6, 2.2, 2.2, shade(ec, 0.6))
    c.ellipse(cx, cy - 6, 1.3, 1.3, ec)
    c.sparkle(cx, cy - 6, 4, (ec[0], ec[1], ec[2], 110))
    # shoulder cannons
    for s in (-1, 1):
        bx = cx + s * 7
        c.rect(bx - 2, cy - 6, 4, 4, S["barrel"])
        c.rect(bx - 1, cy - 5, 2, 2, shade(S["barrel"], 1.3))
        c.rect(bx - 2, cy - 3, 6 if s > 0 else 6, 2, S["barrel"])
        if firing:
            c.ellipse(bx + s * 6, cy - 2, 3, 2.4, (S["panel_lt"][0], S["panel_lt"][1], S["panel_lt"][2], 200))
            c.ellipse(bx + s * 7, cy - 2, 1.6, 1.4, S["panel_lt"])
    # exposed power module (weak point) - pulses
    pm = shade(S["panel"], 0.7 + 0.5 * (0.5 + 0.5 * ph))
    c.rect(cx - 2, cy + 1, 4, 3, shade(S["body_dk"], 0.85))
    c.rect(cx - 1, cy + 2, 2, 1, pm)
    c.blend(cx - 1, cy + 2, (pm[0], pm[1], pm[2], 200))
    # circuit lines
    for k in range(3):
        y = cy - 2 + k
        c.hline(cx - 4, cx + 4, y, (S["circuit"][0], S["circuit"][1], S["circuit"][2], 60), blend=True)
    c.outline(S["outline"], 230)
    return c


ANIMS = {"crawler_walk": (6, crawler_frame, False), "crawler_attack": (4, crawler_frame, True),
         "sentry_idle": (4, sentry_frame, False), "sentry_fire": (3, sentry_frame, True)}


def build(out_dir: str) -> dict:
    rows = []
    for name, (n, fn, flag) in ANIMS.items():
        rows.append((name, n, fn, flag))
    total = max(n for _, n, _, _ in rows)
    sheet = Canvas(total * W, len(rows) * H)
    meta = {"cell": [W, H], "anims": {}}
    for r, (name, n, fn, flag) in enumerate(rows):
        for i in range(n):
            frame = fn(i, n, flag) if name.startswith("crawler") or name.startswith("sentry") else fn(i, n)
            sheet.blit(frame, i * W, r * H)
        meta["anims"][name] = {"row": r, "frames": n}
    save_png(f"{out_dir}/enemy_sheet.png", sheet)
    with open(f"{out_dir}/enemy_sheet.json", "w") as fh:
        json.dump(meta, fh, indent=1)
    return meta
