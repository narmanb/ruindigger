#!/usr/bin/env python3
"""RUIN DIGGER offline asset generator.

Runs with the Python standard library only. Every sprite, tile, background and
sound is authored procedurally from code in this directory, so the repository
ships no third-party or AI-generated art. Output is byte-for-byte reproducible
for a given version of the generator.

Usage:
    python3 tools/assetgen/generate.py            # write into assets/
    python3 tools/assetgen/generate.py --check    # verify assets exist
"""
from __future__ import annotations

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import backgrounds
import enemies
import fx
import player
import props
import terrain
import ui
import audio

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ASSETS = os.path.join(ROOT, "assets")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="only verify that assets exist")
    ap.add_argument("--out", default=ASSETS)
    args = ap.parse_args()

    expected = [
        "tiles/terrain_atlas.png", "tiles/terrain_atlas.json",
        "sprites/player_sheet.png", "sprites/player_sheet.json",
        "sprites/enemy_sheet.png", "sprites/enemy_sheet.json",
        "sprites/ore_sheet.png", "sprites/prop_sheet.png",
        "sprites/relic_sheet.png", "sprites/elevator_sheet.png",
        "sprites/bench_sheet.png", "sprites/ladder_sheet.png",
        "sprites/support_sheet.png",
        "ui/panel_sheet.png", "ui/button_sheet.png", "ui/icon_sheet.png", "ui/ui.json",
        "fx/fx_sheet.png", "fx/fx_sheet.json",
        "font/font.png", "font/font.fnt",
        "bg/bg.json",
    ]
    for s in backgrounds.STRATUM_ORDER if hasattr(backgrounds, "STRATUM_ORDER") else []:
        pass
    from palette import STRATUM_ORDER
    for n in STRATUM_ORDER:
        for layer in ("far", "mid", "near"):
            expected.append(f"bg/bg_{n}_{layer}.png")

    if args.check:
        missing = [e for e in expected if not os.path.exists(os.path.join(args.out, e))]
        if missing:
            print("MISSING ASSETS:")
            for m in missing:
                print("  -", m)
            return 1
        print(f"OK: all {len(expected)} expected assets present")
        return 0

    os.makedirs(os.path.join(args.out, "tiles"), exist_ok=True)
    os.makedirs(os.path.join(args.out, "sprites"), exist_ok=True)
    os.makedirs(os.path.join(args.out, "ui"), exist_ok=True)
    os.makedirs(os.path.join(args.out, "bg"), exist_ok=True)
    os.makedirs(os.path.join(args.out, "fx"), exist_ok=True)
    os.makedirs(os.path.join(args.out, "font"), exist_ok=True)
    os.makedirs(os.path.join(args.out, "audio"), exist_ok=True)

    print("[assetgen] terrain ...")
    terrain.build(os.path.join(args.out, "tiles"))
    print("[assetgen] player ...")
    player.build(os.path.join(args.out, "sprites"))
    print("[assetgen] enemies ...")
    enemies.build(os.path.join(args.out, "sprites"))
    print("[assetgen] props ...")
    props.build(os.path.join(args.out, "sprites"))
    print("[assetgen] backgrounds ...")
    backgrounds.build(os.path.join(args.out, "bg"))
    print("[assetgen] ui ...")
    ui.build(os.path.join(args.out, "ui"))
    print("[assetgen] fx + font ...")
    fx.build_fx(os.path.join(args.out, "fx"))
    fx.build_font(os.path.join(args.out, "font"))
    print("[assetgen] audio ...")
    audio.build(os.path.join(args.out, "audio"))

    missing = [e for e in expected if not os.path.exists(os.path.join(args.out, e))]
    if missing:
        print("ERROR: generator finished but assets are missing:")
        for m in missing:
            print("  -", m)
        return 1
    print(f"[assetgen] done. {len(expected)} assets written to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
