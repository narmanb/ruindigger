# Water Physics Implementation Plan

> Execute inline with superpowers:executing-plans. User supplied an implementation brief and delegated routine design decisions.

**Goal:** Add conserved reservoir jets, shared directional currents, material debris, buoyant props and sustained erosion while preserving the liquid renderer and gameplay.

**Architecture:** Keep TerrainGrid and WaterSim authoritative. Record actual transfers and swept droplet momentum in a sparse decaying motion field. Use bounded connected wet-region head queries only at active outlets; release conserved droplets at the actual opening. Sample the same field for players, crawlers, debris and erosion. Use nonblocking lightweight fragments and a small number of terrain/prop-colliding rigid bodies that never block characters.

**Tech Stack:** Godot 4.6.3, typed tab-indented GDScript, GL Compatibility.

**Spec:** docs/specs/water-physics-expansion.md

## Global Constraints
- Base: ccr-79c19570-j1j312 at daf2c65; changes only on codex/water-physics-expansion in the linked worktree.
- Preserve the renderer, active-water budget (2400 cells/0.06s), 900-droplet cap and existing mining/collapse/reward pathways.
- Terrain damage through Mine.damage_cell; tuning in Balance; deterministic generation; seeds needing repair: 0.
- No new controls. Debris cannot obstruct characters, ladders, extraction or relic access.
- Report measured desktop costs and exact Android build/hardware limitations.

## Review Focus
- Dry cells and thin jets: contact sampling must neither push through rock nor create broad phantom forces.
- Large deltas/crowded droplets: swept motion cannot tunnel through walls or exceed caps; track all volume losses.
- Equal pools, shallow lakes and obstructed supply: reservoir area alone must not create pressure.
- Long idle periods: current history and erosion exposure decay without scanning the whole map.
- Repeated blasts/cascades: ore pays once, objects stay bounded, generated route supports remain safe.

### Task 1: Shared water motion and reservoir discharge
Files: src/terrain/water_sim.gd, new src/terrain/water_motion.gd, new src/terrain/water_pressure.gd, src/autoload/balance.gd; tests/water_physics.gd.
Interfaces: WaterSim.sample_flow(position: Vector2) -> Vector2; sample_contact(position: Vector2, half: Vector2) -> Vector2; motion stores recent volume-weighted velocity. Pressure emits from contiguous source/exit cells only.
- [x] Add failing behavior tests for still water, falling/sideways transfer, head vs area, breach width, equalization, conservation, solid barriers, droplet cap and narrow contact.
- [x] Run the new suite to observe missing functionality.
- [x] Implement bounded transfer field, connected-head approximation and swept droplets with conserved deposit.
- [x] Run physics + terrain suites; commit.

### Task 2: Character currents
Files: src/player/player.gd, src/enemies/crawler.gd, tests/water_physics.gd.
Interfaces: consume sample_contact; player smooths a capped current velocity independently of input acceleration; crawler drift respects grid collision and resets paths.
- [x] Add failing live-character tests for calm/weak/strong currents and solid collision.
- [x] Implement bounded current response preserving swim, jump and grip resistance.
- [x] Run physics and game suites; commit.

### Task 3: Debris and movable props
Files: new src/world/debris.gd, new src/world/water_prop.gd, src/world/mine.gd, src/gen/mine_generator.gd, Balance; physics suite and generation checks.
Interfaces: Debris.on_broken(cell, material, source), spawn_prop(kind, position), blast(position, radius); consume shared water samples; no ore rewards from debris.
- [x] Add failing tests for material selection, count limits, float/sink/current/blast response, nonblocking collision and deterministic safe placement.
- [x] Implement cheap bounded fragment arrays plus capped meaningful physics props; connect break/blast hooks and final seeded placement pass without consuming the existing generator RNG.
- [x] Run physics, generation and game suites; commit.

### Task 4: Erosion, feedback and validation
Files: new src/terrain/water_erosion.gd, Mine, Balance, Fx, tests, README and docs/water-physics.md.
Interfaces: WaterErosion.update(delta) consumes only moving cells and damages eligible exposed faces through Mine.damage_cell after buildup; preserve reserved supports and protected/no-rubble geometry.
- [x] Add failing tests for calm/weak flow immunity, sustained erosion, material/route immunity, once-only ore and bounded edits.
- [x] Implement exposure/recovery, normal damage and shedding feedback; add bounded flow FX/diagnostics.
- [x] Run all suites including 60 seeds, capture GL screenshots and profile a reproducible stress fixture.
- [x] Attempt available export paths; document exact artifact/build limitations and rollback steps.
- [x] Review the branch, fix material findings with regression tests, commit and package for review without merging the original branches.
