# Ruin Digger

[![CI](https://github.com/narmanb/ruindigger/actions/workflows/ci.yml/badge.svg)](https://github.com/narmanb/ruindigger/actions/workflows/ci.yml)

A top-down, destructible-terrain mining roguelite built in **Godot 4.6**.
Android-first, landscape, touch and gamepad ready.

You are a salvage digger dropped onto a buried ruin. Cut a way down through
soil, basalt and alloy, pull ore out of the rock, find the sealed relic
chamber, and get back to the lift before the gas, the collapse and the things
already living down there finish you first.

```
  surface cab -- lift / extraction
      |
      |  the spine shaft (always carved, always open)
      |
      +-- ore seams on the diggable frontier
      +-- gas pockets (vent them, don't drill them)
      +-- sealed treasure vaults (breach the door for the good ore)
      |
  bedrock-sealed relic chamber -- one doorway, carved by the generator
```

## Playing it

| Action | Keyboard | Gamepad | Touch |
| --- | --- | --- | --- |
| Move | `A`/`D` or arrows | left stick / d-pad | left half, drag |
| Jump | `Space` / `K` | A | JUMP button |
| Drill | `J` / `L` (hold) | X / RB | DRILL button |
| Charge | `B` / `I` | B / LB | CHARGE button |
| Interact | `E` / `Enter` | Y | on-screen prompt |
| Pause | `Esc` / `P` | Start | pause icon |
| Map | `Tab` | Back | minimap |
| Restart | `R` | - | - |

**The loop.** Drill down, bank ore, don't die. Cargo you are carrying is only
banked when you extract at the lift, so the interesting decision is always
"one more seam, or go up?" Charging a wall with the demo charge is fast and
loud, and may bring the ceiling down on you. Gas pockets detonate when their
cell is breached. Sentries and crawlers use grid pathfinding through the
tunnels *you* carve, so your own mining shapes the threat.

**Winning.** Take the relic from its chamber, then extract at the lift. Your
banked ore becomes credits and permanent upgrades at the outpost.

## Project layout

```
src/autoload/     Balance, GameState, SaveManager, Fx, Audio, InputSetup
src/gen/          WorldGen    -- seeded, deterministic, guaranteed-navigable
src/terrain/      TerrainGrid (data + flood fill), TerrainRenderer (chunked)
src/player/       Player      -- movement, drilling, cargo, damage
src/enemies/      GridPathfinder, BurrowCrawler, RuinSentry
src/hazards/      CollapseSystem, DemoCharge
src/world/        Mine        -- assembles one run from a seed
src/ui/           Title, HUD, Minimap, Outpost, Settings, ResultScreen, Touch
src/tests/        Headless suites (see below)
tools/assetgen/   Procedural art/audio generator (no third-party assets)
tools/run_tests.sh
```

### World generation guarantees

`WorldGen.generate(seed, w, h)` is deterministic and enforces its invariants
structurally rather than hoping they hold:

1. The spine shaft and both cabs are carved first and never intersected by
   later random carving.
2. The relic chamber is sealed in bedrock with exactly one carved doorway.
3. The guaranteed route is carved *after* every destructive step.
4. Ore and gas are only placed on solid rock bordering reachable space, so
   every reward is obtainable for every seed.
5. Connectivity is verified and repaired as a final safety net.
6. Gas is cleared from the critical path.

`src/tests/sweep.gd` proves this across 120 seeds.

## Running

Requires Godot 4.6.3 (headless is fine for tests).

```bash
godot --headless --import                            # first time only
godot --headless res://src/tests/test_runner.tscn    # unit tests
./tools/run_tests.sh                                 # every suite
godot                                                # play it
```

### Test suites

| Suite | What it covers |
| --- | --- |
| `test_runner.tscn` | 69 unit tests: terrain, mining, ore, radius damage, pathfinder, gen |
| `sweep.tscn` | 120 seeds x every generation invariant |
| `objective.tscn` | Full win: relic pickup, extraction, reward banking, save mutation |
| `playthrough.tscn` | Soak: real Mine scene driven by simulated input for thousands of frames |
| `scenes.tscn` | Every shipped script and scene loads and builds |

`tools/run_tests.sh` runs them all and exits non-zero if any fail.

## Android

`export_presets.cfg` ships an Android preset (`com.ruindigger.game`,
immersive landscape, arm64 + armv7). CI builds the APK and uploads it as an
artifact on every run. To export locally you need the Godot export templates,
a JDK, and the Android SDK configured in the editor.

```bash
godot --headless --export-debug "Android" build/android/ruin_digger.apk
```

### CI

`.github/workflows/ci.yml` runs two jobs:

- **test** — installs Godot 4.6.3, imports the project and runs
  `tools/run_tests.sh`. Fails the build on any red suite.
- **android** — installs JDK 21 + Android SDK 36, installs the matching Godot
  export templates, exports a signed debug APK, then verifies the signature
  with `apksigner` and the manifest with `aapt` before uploading the APK as a
  build artifact.

Godot auto-generates its own debug keystore on first export, so CI needs no
signing secrets. Two setup details are easy to get wrong and both fail
*silently*: `project.godot` must set
`rendering/textures/vram_compression/import_etc2_astc=true`, and EditorSettings
must point at the SDK and JDK.

## Assets

All art and audio in `assets/` is generated by `tools/assetgen/`, so the
project has no third-party asset dependencies and every sprite is reproducible
from source.
