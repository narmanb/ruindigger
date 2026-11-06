# AGENTS.md

Guidance for agents working on **Ruin Digger** (side-view destructible-terrain
mining roguelite, Godot 4.6.3, GDScript, GL Compatibility, Android-first).

## Commands
```bash
godot --headless --import      # after changing anything in assets/
./tools/run_tests.sh           # terrain, save, ui, gen (60 seeds), game. Must stay green.
godot --headless res://tests/gen_dump.tscn -- seed=N out=/tmp/m.png [norepair] [ascii]
xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/shot.tscn -- screen=mine seed=7 frames=120 out=/tmp/s.png
```
Art and audio are generated: edit `tools/assetgen/*.py`, rerun them, then re-import.
Never hand-edit `assets/gen` or `assets/sfx`.

## Rules
- `TerrainGrid` is the only mutable terrain state. Change cells through
  `set_mat`/`damage` (runtime) or `put` (generator only). Gameplay damage goes
  through `Mine.damage_cell` so ore, gas and collapse side effects fire.
- Tuning numbers go in `src/autoload/balance.gd`, not inline.
- Typed GDScript with tabs. `:=` needs a typed right-hand side: values from
  `Node`-typed `mine` refs or untyped arrays need explicit types.
- `MineGenerator` pass order is load-bearing (see its header). After touching it,
  run `./tools/run_tests.sh` and keep "seeds needing repair: 0". The route is
  carved after destructive passes, and later passes must respect `reserved` and
  `no_feature`.
- Player input for tests goes through `player.input_override` (keys:
  `x`, `y`, `drill`, `jump`, `jump_just`, `charge_just`, ...).
- Headless runs print "ObjectDB instances leaked at exit" when a suite quits with a
  live mine. That is harmless.
