# AGENTS.md

Repository guidance for agents working on **Ruin Digger**.

## What this is

A top-down destructible-terrain mining roguelite in **Godot 4.6.3**, targeting
Android (landscape) with desktop as a dev target. GDScript only, no GDExtension,
no third-party assets (everything in `assets/` is produced by `tools/assetgen/`).

## Build / test commands

```bash
godot --headless --import          # regenerate .godot/ after adding assets
./tools/run_tests.sh               # all 5 suites; non-zero exit on failure
godot                              # play locally
```

`tools/run_tests.sh` honours `GODOT=/path/to/godot` and `TEST_TIMEOUT=<seconds>`.
Each suite is a scene that calls `get_tree().quit(0|1)`, so CI fails on a red suite.

Suites: `test_runner` (unit), `sweep` (120 seeds x generation invariants),
`objective` (full win path), `playthrough` (soak with synthetic input),
`scenes` (every script/scene loads and builds).

## Android export

Locally validated with JDK 21, Android SDK platform 36 + build-tools 36.0.0 and
Godot export templates for 4.6.3:

```bash
godot --headless --export-debug "Android" build/android/ruin_digger.apk
```

Two non-obvious requirements, both of which fail *silently* otherwise:

1. `rendering/textures/vram_compression/import_etc2_astc=true` must be set in
   `project.godot`. Without it the Android exporter refuses with an empty
   "configuration errors" message.
2. EditorSettings needs all three of `export/android/debug_keystore`,
   `..._debug_keystore_user` and `..._debug_keystore_pass`, plus
   `android_sdk_path` and `java_sdk_path`. A partial keystore triple is ignored.
   CI writes these in the "Configure editor settings" step.

Godot's Android exporter defaults to `targetSdk 36`, so the installed platform
and build-tools must be >= that or it logs "Could not find version of build
tools that matches Target SDK" and falls back.

## World generation invariants

`src/gen/world_gen.gd` is order-sensitive. If you touch it, keep this ordering:
the spine shaft and both cabs are carved first and never intersected; the relic
chamber is sealed in bedrock with one doorway; the guaranteed route is carved
*after* every destructive pass; ore/gas only go on solid rock bordering
reachable space; connectivity is verified and repaired last. `sweep.gd` is the
regression net — run it after any change here.

## Conventions

- Tabs for indentation (Godot default), typed GDScript (`var x: float = 0.0`).
- Autoloads: `Balance`, `GameState`, `SaveManager`, `Fx`, `Audio`, `InputSetup`.
- Balance numbers live in `Balance` (`src/autoload/balance.gd`), not inline.
- `Fx.register_root()` / `Fx.clear_root()` bracket a mine's lifetime; `Mine`
  calls `clear_root()` in `_exit_tree()` so pooled particles are not reported as
  leaked RIDs at shutdown.
- Headless test suites will log "leaked RIDs at exit" if they instantiate a Mine
  and quit mid-frame. That is a harness artifact, not a game bug; the shipped
  game exits clean.
