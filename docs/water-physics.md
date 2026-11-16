# Water physics expansion

Built from `ccr-79c19570-j1j312` at `daf2c65`, in the isolated branch
`codex/water-physics-expansion`. Neither the original work branch nor `main` is
merged or rewritten. To return to the previous game, check out
`ccr-79c19570-j1j312` (or the exact commit `daf2c65`).

## What changed

WaterSim still owns every water unit and feeds the existing density-field
renderer. Pools, attached waterfall lips, sheets and the water shader remain.
`WaterMotion` records volume-weighted direction from actual cell transfers and
swept falling droplets. Full stationary water creates no current. The sparse
field decays over 0.16 seconds; solid cells mask it immediately. Body sampling
averages six points, so a thin jet contacts only part of a tall character.

`WaterPressure` estimates connected upstream height only at freely draining
side outlets. It visits at most 512 wet cells per water tick and 256 per region;
large reservoirs receive a conservative local estimate. One-cell shallow
pockets spill normally. Deep lower breaches emit horizontal droplets, subtracting
their actual volume from the adjacent source. More supplied openings release
more water; refill and falling head limit the surge. Submerged outlets use normal
cell transfers rather than free jets. Equal submerged pools exert no sustained
push. This is a gameplay approximation, not a general pressure solver: it does
not model pressurized pipes or siphons through submerged passages.

The player blends a capped current into ordinary movement and swimming targets.
Ground contact and drill/ladder grip provide resistance. Jump and swim controls
remain available. Exceptional flows can exceed normal swimming speed slightly;
ordinary flows remain resistible. Crawlers accumulate bounded grid drift from
strong flow and cannot be carried through intact rock. Anchored sentries stay
anchored.

`Debris` keeps the existing pooled particle tier, adds at most 96 lightweight
fragments, and owns at most 24 `WaterProp` rigid bodies. Sediment, basalt, rubble,
cracked walls and alloy have different persistent-fragment chances; gas leaves
no persistent solid debris. Fragments expire after 90 seconds and never become
terrain or pay ore. Stone and scrap can occasionally survive a mined tile as a
larger prop. Wood crates and sealed canisters float; stone and metal sink and
resist currents. Props collide with terrain and one another, respond to blasts,
and can strike enemies when moving fast. They pass through characters so they
cannot obstruct lifts or narrow required paths; the normal drill clears them.
A final seeded placement pass adds up to 12 environmental props without changing
the generator's existing RNG sequence or carving any new terrain.

`WaterErosion` checks exposed faces beside moving water, waits 1.8 seconds of
exposure and then chips sediment, gravel and cracked walls. Calm pools and weak
trickles do not erode. Basalt, alloy, gas and bedrock are immune. All damage goes
through `Mine.damage_cell`, preserving ore credit, normal particles, gas and
support-loss/collapse hooks. A separate `F_WATER_SAFE` flag protects generated
route bodies and standing surfaces while keeping those cells drillable. The
existing protected/no-rubble zones also resist erosion. A round-robin edit
budget prevents one long-lived face from starving the other faces.

Directional spray reuses pooled particles. Existing cracks show accumulated
wear; the existing break and collapse sounds/telegraphs remain. No new sound
assets or controls were added.

## Accounting and budgets

- Existing water tick: 0.06 s; active-cell budget: 2400; droplets: at most 900.
- Flow history: at most 4096 cells. Head queries: 512 nodes/tick, 256/region.
- Erosion: 384 moving cells scanned per 0.12 s, at most 512 exposure entries and
  4 damage calls per pass, including partial damage. Tracked faces recheck their
  four immediate neighbors when discovery scanning omits them; unrelated water
  cannot reset ongoing exposure. Catch-up after a long frame
  is capped; cascades still use the existing collapse telegraph and budgets.
- Fragments: 96, nonblocking and drawn by one node. Meaningful props: 24,
  including the initial environmental props. Physics sleeps settled props and
  water/blasts wake them; no unbounded per-tile rigid bodies.
- Droplets sweep in at most 4 px increments and deposit only through contiguous
  open cells. A full landing retains any unplaced volume in the droplet until
  nearby space becomes available. Solid displacement can still squeeze out
  water when all immediate outlets are blocked; that legacy loss is explicitly
  counted in `WaterSim.lost`. Droplets overwritten by falling terrain are
  displaced into an immediate open neighbor, or counted as squeezed out if all
  four neighbors are solid, so hidden droplets cannot permanently use up slots.
- Corrected a lateral-flow edge case that could send a unit to the second side
  after the source had already emptied into the first side.
- `Mine.water_diagnostics()` reports active cells, droplets, motion cells,
  pressure work/discharge, props, fragments, exposure, edits and water losses.
  These counters do not add anything to the shipped HUD.

## Verification and reproduction

Use Godot 4.6.3:

```bash
./tools/run_tests.sh
# Physics fixtures, a 1200-frame finite-reservoir stress run, CPU timings:
godot --headless res://tests/test_runner.tscn -- suite=physics
# Focused live mining-reward and real rigid-body float/sink integration:
godot --headless res://tests/test_runner.tscn -- suite=water_live
# Visual demonstration (requires a display; add xvfb-run if installed):
godot --rendering-driver opengl3 res://tests/shot.tscn -- \
  screen=mine seed=7 waterfall=1 physics=1 frames=180 out=/tmp/water.png
```

The automated physics fixtures cover head versus reservoir area, breach width,
calm water, strong directional flow, narrow contact, swimmer resistance,
conservation, swept barriers, debris caps, float/sink forces, blasts, immunity,
sustained wear, fair erosion scheduling and once-only ore credit. The live mine
also checks actual rigid-body buoyancy and the normal erosion reward pathway.
The generation sweep checks deterministic terrain/prop placement, reserved-path
safety and all original route invariants with zero repair fallbacks.

Visual captures were made with GL Compatibility on Mesa llvmpipe using the
installed Xorg dummy display. This establishes rendering availability and allows
inspection of continuous streams; it is not phone/Retroid GPU performance data.

Android export was attempted. This workspace lacks the Godot 4.6.3 Android debug
and release templates and Android SDK platform-tools/build-tools (including adb
and apksigner), and has no Java SDK path configured in Godot editor settings.
No APK was produced locally. The repository's existing CI workflow runs all
suites, installs the SDK/templates and exports signed debug Android and Linux
artifacts; no CI success is claimed without observing it.

## Practical limits

A bounded head search can underestimate a large/complex upstream reservoir.
Backpressure is approximated by the outlet's wetness; submerged pressure
networks, water displacement by props and granular sediment redeposition are
not implemented. Fragments are cosmetic physical scatter, not new solid tiles.
Props deliberately cannot block characters. There are four restrained prop
shapes, using procedural pixel-style drawing and existing colors.

Synthetic flood timings measure water simulation CPU only and are reported with
the handoff test results. They exclude rendering, the rest of the mine and real
device thermals. Android landscape touch and gamepad layouts/actions are
unchanged, but hardware feel and sustained 60 fps still need on-device testing.

## Recorded validation (2026-11-09)

The original branch passed its five suites before editing: terrain 32, save 11,
UI 17, generation 1252 (60 seeds, zero repairs), gameplay 50.

The final full run passed 1,595 checks: terrain 32, physics 49, save 11, UI 17,
generation 1432 (60 seeds, zero repairs), gameplay 54.

The expanded suite adds water physics, live erosion/prop checks, safe seeded
placement and route-support safeguards. The independent code review identified
two edge cases: terrain overwriting airborne droplets, and false erosion
recovery when a crowded flow scan omitted a face. Both have focused regression
coverage and were corrected. No minor review findings were deferred.

On the shared Linux runner, a seeded 1200-frame flood of 77,760 units measured
7.47 ms mean water-update CPU time, 16.02 ms p95 and 44.94 ms maximum. Peak counts
were 790 droplets, 512 head-search nodes per tick and 854 motion cells, with zero
water loss. These measurements include host contention and exclude the rest of
the mine and rendering; the worst spikes mean this is not evidence of a steady
60 fps game on a phone.

A 360-frame GL Compatibility demo with 15 props, moving water and active erosion
made 45 erosion damage calls. On Mesa llvmpipe software rendering at 640x360,
median frame time was 62.67 ms (p95 80.23 ms), and median physics time was 6.95 ms
(p95 37.23 ms). Those are software-renderer/shared-runner measurements, not a
mobile GPU result. The demo's loss counter includes the fixture replacing
pre-existing generated terrain/water before the measurement window; the closed
finite-reservoir test separately requires zero loss during simulation.

Run the same visual profile with `profile=1` added to the screenshot command.
The Android/Retroid hardware performance and touch/gamepad checks remain open.
