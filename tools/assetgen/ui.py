"""Procedural UI art: 9-slice panels, buttons, and icon glyphs."""
from __future__ import annotations

import json
import math

from canvas import Canvas, save_png, shade, mix
from palette import UI

PANEL = 24  # 9-slice corner size


def panel(kind: str) -> Canvas:
    c = Canvas(PANEL * 2, PANEL * 2)
    fill = UI["panel"]
    lt = UI["panel_lt"]
    edge = UI["panel_edge"]
    if kind == "amber":
        edge = UI["amber"]
    elif kind == "cyan":
        edge = UI["cyan"]
    elif kind == "violet":
        edge = UI["violet"]
    elif kind == "red":
        edge = UI["red"]

    c.fill((fill[0], fill[1], fill[2], 236))
    # inner gradient sheen
    for y in range(c.h):
        t = y / (c.h - 1)
        c.hline(0, c.w - 1, y, (int(fill[0] + (lt[0] - fill[0]) * t * 0.5),
                                int(fill[1] + (lt[1] - fill[1]) * t * 0.5),
                                int(fill[2] + (lt[2] - fill[2]) * t * 0.5), 236))
    # border
    c.rect(0, 0, c.w, 2, edge)
    c.rect(0, c.h - 2, c.w, 2, shade(edge, 0.6))
    c.rect(0, 0, 2, c.h, shade(edge, 0.85))
    c.rect(c.w - 2, 0, 2, c.h, shade(edge, 0.6))
    # corner accents
    for (cx, cy) in ((2, 2), (c.w - 5, 2), (2, c.h - 5), (c.w - 5, c.h - 5)):
        c.rect(cx, cy, 3, 3, shade(edge, 1.25))
    # scanline texture
    for y in range(3, c.h - 3, 3):
        c.hline(3, c.w - 4, y, (0, 0, 0, 18), blend=True)
    return c


def button(state: str) -> Canvas:
    c = Canvas(PANEL * 2, PANEL * 2)
    if state == "normal":
        base, edge = (36, 44, 58), UI["panel_edge"]
    elif state == "hover":
        base, edge = (52, 66, 86), UI["amber"]
    else:  # pressed
        base, edge = (24, 30, 40), shade(UI["amber"], 0.7)
    c.fill((base[0], base[1], base[2], 240))
    c.rect(0, 0, c.w, 3, shade(edge, 1.1))
    c.rect(0, c.h - 3, c.w, 3, shade(edge, 0.55))
    c.rect(0, 0, 3, c.h, shade(edge, 0.9))
    c.rect(c.w - 3, 0, 3, c.h, shade(edge, 0.55))
    for y in range(4, c.h - 4, 4):
        c.hline(4, c.w - 5, y, (255, 255, 255, 8), blend=True)
    return c


def icon(name: str) -> Canvas:
    c = Canvas(16, 16)
    w = UI["text"]
    if name == "health":
        c.polygon([(8, 14), (2, 8), (2, 5), (5, 3), (8, 5), (11, 3), (14, 5), (14, 8)], UI["red"])
        c.set(5, 5, shade(UI["red"], 1.5))
    elif name == "heat":
        c.polygon([(8, 1), (12, 8), (10, 14), (6, 14), (4, 8)], UI["amber"])
        c.polygon([(8, 5), (10, 9), (9, 13), (7, 13), (6, 9)], shade(UI["amber"], 1.5))
    elif name == "cargo":
        c.polygon([(8, 14), (2, 8), (2, 5), (5, 3), (8, 5), (11, 3), (14, 5), (14, 8)], UI["violet"])
        c.rect(4, 6, 8, 3, shade(UI["violet"], 1.3))
    elif name == "charge":
        c.rect(5, 4, 6, 9, UI["red"])
        c.rect(6, 5, 4, 7, shade(UI["red"], 1.35))
        c.rect(6, 3, 4, 1, (70, 70, 80))
    elif name == "depth":
        c.polygon([(8, 14), (3, 8), (13, 8)], UI["cyan"])
        c.polygon([(8, 2), (3, 7), (13, 7)], shade(UI["cyan"], 0.6))
    elif name == "lift":
        c.rect(4, 2, 8, 10, UI["amber"])
        c.rect(6, 4, 4, 6, shade(UI["amber"], 0.4))
        c.rect(3, 12, 10, 2, shade(UI["amber"], 1.3))
    elif name == "ore":
        c.polygon([(8, 1), (13, 8), (8, 15), (3, 8)], UI["amber"])
        c.polygon([(8, 3), (11, 8), (8, 12), (5, 8)], shade(UI["amber"], 1.5))
    elif name == "pause":
        c.rect(4, 3, 3, 10, w)
        c.rect(9, 3, 3, 10, w)
    elif name == "play":
        c.polygon([(4, 2), (14, 8), (4, 14)], w)
    elif name == "gear":
        c.circle(8, 8, 6, w)
        c.circle(8, 8, 3, UI["panel"])
        for a in range(0, 360, 45):
            r = math.radians(a)
            c.rect(8 + math.cos(r) * 6 - 1, 8 + math.sin(r) * 6 - 1, 2, 2, w)
    elif name == "home":
        c.polygon([(8, 2), (15, 8), (1, 8)], w)
        c.rect(4, 8, 8, 6, w)
        c.rect(7, 10, 3, 4, UI["panel"])
    return c


def build(out_dir: str) -> dict:
    names = ["panel", "amber", "cyan", "violet", "red"]
    sheet = Canvas(PANEL * 2 * len(names), PANEL * 2)
    for i, n in enumerate(names):
        sheet.blit(panel(n), i * PANEL * 2, 0)
    save_png(f"{out_dir}/panel_sheet.png", sheet)

    btns = ["normal", "hover", "pressed"]
    bsheet = Canvas(PANEL * 2 * len(btns), PANEL * 2)
    for i, s in enumerate(btns):
        bsheet.blit(button(s), i * PANEL * 2, 0)
    save_png(f"{out_dir}/button_sheet.png", bsheet)

    icons = ["health", "heat", "cargo", "charge", "depth", "lift", "ore", "pause", "play", "gear", "home"]
    isheet = Canvas(16 * len(icons), 16)
    for i, n in enumerate(icons):
        isheet.blit(icon(n), i * 16, 0)
    save_png(f"{out_dir}/icon_sheet.png", isheet)

    meta = {"panel_corner": PANEL, "panels": {n: i for i, n in enumerate(names)},
            "buttons": {s: i for i, s in enumerate(btns)}, "icons": {n: i for i, n in enumerate(icons)}}
    with open(f"{out_dir}/ui.json", "w") as fh:
        json.dump(meta, fh, indent=1)
    return meta
