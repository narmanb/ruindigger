# The First Civilization (Primordial Vault): status

The zone's working title in the spec is "The Primordial Vault". Its name in the
game is **THE FIRST CIVILIZATION**. Both mean the same stage.

**Spec:** `RuinDigger_Primordial_Vault_Implementation_Spec.md` (owner-supplied)
**Branch:** `feature/first-civilization`, based on `finish-0.5` @ `7449710`
**Do not touch:** `main`, `finish-0.5`, `ccr-79c19570-j1j312`

## Phase status

| Phase | Status |
|---|---|
| D0 baseline | Done. All suites passed on `7449710` before any change (terrain 32, physics 49, save 15, ui 71, gen 4344, game 111, water_live 4). |
| D1 giant deep map + one-way extraction | **Done and tested** (see below). |
| D2 lava, reaction, steam, cooled rock | **Done and tested** (see "D2" below). |
| D3 geothermal power puzzle | **Done and tested** (see "D3" below). |
| D4 atmosphere, artifacts, defenders | **Partly done**: the First Light artifact (below). Lore, guardians and balance not started. |
| D5 third fluid, optimisation | Not started. |

## D1: what exists

* **Separate stage.** `Game.run["stage"]` is `"mine"` or `"deep"`.
  `Mine.generate_stage()` is the stage factory; `Mine` itself is
  stage-agnostic. The deep map is built by `src/gen/first_civ_generator.gd`
  (`FirstCivGenerator`), 200×120 cells (`Balance.DEEP_W/H`), seed derived from
  the run seed by `FirstCivGenerator.deep_seed()`.
* **Sixth biome identity** (`Balance.Z_FIRST = 5`, `BIOME_COUNT = 6`): tiles in
  atlas slots 21–25 (soft, hard, loose, bedrock, ancient composite drawn for
  ALLOY cells), back wall, two parallax rows (the colossal machine), ambience
  `amb_first`, light, water tint, minimap colours. `ZONE_COUNT` is still 5: it
  counts zones of the main mine.
* **Entrance.** `MineGenerator._ancient_descent()` places an Ancient Descent
  Platform room in the Forgotten Engine. It runs after every other pass with
  its own RNG and only replaces plain dry rock, so existing seeds are otherwise
  unchanged (the main gen suite's 4,344 checks still pass).
* **One-way descent.** USE on the platform opens `src/ui/descent_prompt.gd`
  ("ONE-WAY DESCENT — NO RETURN UNTIL THE EXIT IS FOUND"), paused, with STAY
  focused. DESCEND runs `Mine.begin_descent()` then `Game.descend()`, which
  keeps the same `Game.run` (cargo, relic, finds, charges, scaffold, kills,
  time, contract, seed) and carries hull as `run["hp"]`. `start_run()` is not
  called again.
* **No way back.** The deep stage has no lift and no descent platform; the
  arrival shaft ends in bedrock.
* **Transit Gate.** `Entities.TransitGate` near the bottom. First USE wakes it,
  second USE leaves: `Mine.extract_gate()` → `Game.end_run(true)`. The result
  records `deep`, `deep_exit`, `deep_bonus` (`Balance.DEEP_EXIT_BONUS`).
  `gate.powered` exists for D3 to drive; in D1 it is always true.
* **Depth.** `run["depth_offset"]` (236 cells) is added to depth read-outs and
  `max_depth`.
* **Generation.** Three regions by depth (arrival structures, thermal plant,
  lower transit), 6–8 great vaults with hanging colonnades, 7–11 buried
  monoliths, link tunnels with cracked-rock plugs, two straight transit
  tunnels, premium ore, water pockets and cooling basins, crawlers and ceiling
  sentries.
* **Fairness.** One-way rule: every cell the player can get into must still be
  able to reach the gate (`DigCheck` with ladders, `escape_set(gate)`); any
  that cannot is sealed. Arrival → gate must cost ≤ `DEEP_DIG_BUDGET` seconds.

## Tests actually run (Linux, Godot 4.6.3 headless)

`TEST_TIMEOUT=900 ./tools/run_tests.sh` on the D1 commit:

| Suite | Result |
|---|---|
| terrain | 32 / 32 |
| physics | 49 / 49 |
| save | 15 / 15 |
| ui | 71 / 71 |
| gen (60 seeds) | 4344 / 4344, 0 repairs |
| game | 111 / 111 |
| deep (60 seeds; new) | 1297 / 1297, 0 repairs, 0 trap cells sealed |
| water_live | 4 / 4 |

The `deep` suite (`tests/deep_stage.gd`) covers: map size and biome, arrival
and gate floors, no lifts, dig budget, zero cut-off cells, no sealed pockets,
no overlaps, guardians in open space, no unsupported basalt, water at rest,
determinism; the entrance in every mine (in the Engine, protected floor,
reachable, can walk away); and a live run through descent → arrival → gate →
results with cargo, relic, hull, depth and credits verified, plus abandoning in
the deep stage.

**Not done:** the 500-combination main sweep was not rerun; no deep sweep
beyond 60 seeds; no APK built; nothing run on a phone or the Retroid.
Deep generation takes about 520–630 ms on desktop.

## Known gaps in D1

* The descent room is sealed behind a cracked wall with a short approach
  corridor. It is reachable by digging, but nothing points the player to it
  beyond the map marker once seen.
* Lore signs are short labels only. No keepsake or artifact for the zone yet.
* Tools: `tests/deep_dump.tscn` renders a deep map;
  `tests/shot.tscn ... deep=1` screenshots the deep stage.

## D2: what exists

* **Storage.** `TerrainGrid.lava` (`PackedByteArray`, 0..`LAVA_MAX`) beside
  `water`, with `get_lava`/`set_lava` and JSON round-trip.
* **`src/terrain/lava_sim.gd` (`LavaSim`).** Bounded active-cell lava
  (`LAVA_BUDGET` cells per step). It flows on a slow tick (`LAVA_TICK` 0.24 s;
  water is 0.06 s), falls up to `LAVA_FALL` per step, and creeps sideways only
  down a real slope (`LAVA_SPREAD_MIN`), so it rests as a mound. Lava never
  enters a cell that holds water; it stops at the water's face.
* **Reaction.** Runs on the fast tick (`LAVA_REACT_TICK`) so a pour cannot run
  off between lava steps. Each lava cell reacts once per tick with every wet
  face it touches, boiling up to `LAVA_REACT_UNITS` of water per face, which
  becomes steam. When a lava cell has absorbed `LAVA_SOLIDIFY_AT` cooling it
  crusts into ordinary drillable basalt (no ore) through `set_mat`, so
  collision, visuals and water displacement update. A film thinner than
  `LAVA_ROCK_MIN` hardens away as slag, and the spot stays cold.
* **Accounting.** Nothing is created: `lava now + lava_frozen + lava_lost`
  equals the starting lava, and `water now + water_boiled (+ WaterSim.lost)`
  equals the starting water. Both are tested.
* **Safety.** `keep_out` cells (the arrival and gate halls, from
  `data["lava_keep_out"]`) are never entered and never crusted. An
  `occupied` callback (player, enemies, props) defers a crust until the cell
  is clear.
* **`src/terrain/steam_field.gd` (`SteamField`).** An ephemeral gas field: it
  rises, slides along ceilings toward the nearest way up
  (`STEAM_VENT_SCAN`), decays proportionally (`STEAM_KEEP`, `STEAM_DECAY`)
  and is hard-capped at `STEAM_MAX_CELLS`. Dense steam scalds lightly
  (`STEAM_DAMAGE` every `STEAM_INTERVAL`) and lifts. It never ignites gas.
* **Runtime (`Mine`).** Lava and steam run only in the deep stage. Lava burns
  `LAVA_BURN_DAMAGE` every `LAVA_BURN_INTERVAL` (never instant), slows
  wading (`LAVA_SLOW`), hurts enemies, and a "HEAT WARNING" toast appears
  within `LAVA_WARN_CELLS`. New rock throws dust, sparks and a hiss.
* **Rendering.** `src/fx/lava_renderer.gd` uses the same metaball technique as
  water: visible lava cells are drawn as soft shapes into an off-screen density
  buffer, and `src/fx/lava_composite.gdshader` thresholds it into one smooth
  molten body (no cell edges) with a bright skin, deeper red below and
  drifting crust plates with glowing seams. Lava's soft ramps are wider than
  water's (rounder edges), resting surfaces bulge slowly, pours are thick
  rounded streams, and display levels are eased because lava moves in steps.
  The body sits behind the rock tiles. Additive heat glow; steam puffs in front
  of the player. The minimap shows lava.
* **Generation.** Shallow lava pits in lower-vault floors, sealed lava pockets,
  and 2–3 **quench pairs** (a sealed water cistern over a lava pocket with a
  cracked divider: drill it to build a crust). Generated lava never touches
  water and is settled at generation.
* **Fairness.** `DigCheck` treats lava as passable at `T_LAVA` seconds per
  cell (wading out of a pit is survivable, so a pit is never a trap), so a
  guaranteed route avoids it whenever another exists.

### D2 tests (suite `lava`, plus additions to `deep`)

* Water spreads much further than lava in the same 3 s; lava conserves, comes
  to rest and keeps a slope; a huge lake never steps more than the budget.
* Breaching a reservoir drains it through the hole (conserved); keep-out cells
  are never entered.
* Contact makes basalt gradually (not on the first touch); accounting balances
  for lava and water; each contact is reacted once per step; steam appears;
  the rock is drillable with no ore.
* A splash only flashes to steam; a lake over lava does not convert at once;
  sustained contact builds a crust over still-molten lava.
* A breached cistern over a lava channel leaves a lasting crust across most
  columns; the plume is visible, bounded and clears within 20 s; the crust
  persists.
* Lava poured into a wet shaft plugs it with rock.
* No rock forms in a keep-out cell or on an actor; a deferred crust forms once
  the actor leaves.
* Steam rises, follows a ceiling to a chimney, stays under the cap and
  dissipates.
* Deep generation (60 seeds): lava and quench pairs exist, never touch water,
  are absent from the halls, and are at rest. Live run: standing in lava burns
  one burn at a time on a fair cadence; a poured cistern crusts live lava.

### D2 results (run on this commit)

`TEST_TIMEOUT=900 ./tools/run_tests.sh`: terrain 32/32, physics 49/49, save
15/15, ui 71/71, gen 4344/4344 (0 repairs), game 111/111, lava 33/33,
deep 1542/1542 (0 repairs). `water_live` 4/4. Screenshots of a lava pit and of
a breached quench pair were checked; in the live breach 7 rock cells formed,
about 540 water units boiled off, and steam peaked at about 40 cells.

### Known gaps after D2

* Released lava that settles across a tunnel stays molten. The player can dig
  around it or quench it, but the fairness audit only covers the generated
  layout, not every possible player-made flood.
* Steam pressure in sealed vents and steam-driven machines are D3 work.
* No performance measurement on a phone. Lava and steam work is bounded by
  `LAVA_BUDGET` and `STEAM_MAX_CELLS`.

## D3: what exists

* **Thermal Plant hall** (`FirstCivGenerator._thermal_plant`, pass 4b): a
  36×12 composite hall in the thermal-plant region, joined into the route chain
  through its single door, which faces the middle of the map. Along the hall,
  from the far wall to the door: a **lava tank** over the **heat intake** basin,
  the heat valve console, the **Thermal Engine** (a low block you can hop
  over), the coolant valve console, a **water tank** over the **coolant**
  basin, then the walkway. Each tank holds 21 cells, 3.5× what its basin
  needs (`PLANT_HEAT_NEED`, `PLANT_COOL_NEED`).
* **Valves** (`Entities.Valve`): USE opens the tank floor so the fluid pours
  into the basin; USE again closes it (the closed floor displaces whatever
  fluid is in it). Labels read "OPEN/CLOSE HEAT VALVE" and "... COOLANT
  VALVE".
* **Engine** (`Entities.ThermalEngine`): measures both basins every
  `PLANT_CHECK` s. When both inputs have held for `PLANT_SPINUP` s it comes
  online and sets `gate.powered`. Lamps on its face (heat, coolant, power) and
  a turning rotor show the state, with toasts "HEAT INPUT: READY/LOST",
  "COOLANT: READY/INSUFFICIENT", "THERMAL ENGINE ONLINE / STALLED".
* **Gate.** Unpowered, the Transit Gate refuses and says which inputs are
  missing. Powered, the first USE wakes it and the second leaves. The HUD
  compass points to "PLANT" until the engine is online, then to "GATE". The
  minimap and full map mark the plant.
* **Recoverable by design.** Water reaching the heat intake only crusts its
  surface; the lava beneath still counts, and the crust is drillable. Valves
  can be closed. Lava is kept out of the coolant basin (`lava_keep_out`).
  Tanks are sealed containers the trap audit leaves alone.

### D3 tests

* Every deep seed: a plant with one engine and two valves; tanks hold over 3×
  the need; basins start empty; both consoles are reachable from the arrival,
  and the gate is reachable from them.
* First 12 seeds, headless fluid run: opening both valves powers the engine;
  water spilled on the heat intake crusts its surface; the lava under the
  crust still meets the need; drilling the crust out keeps it working.
* Live: the gate starts unpowered and explains why; the player uses both
  consoles; the engine comes online; the gate wakes and the run extracts with
  everything banked once.

### D3 results (run on this commit)

`TEST_TIMEOUT=1200 ./tools/run_tests.sh`: terrain 32/32, physics 49/49, save
15/15, ui 71/71, gen 4344/4344 (0 repairs), game 111/111, lava 33/33,
deep 1898/1898 (60 deep seeds, 0 repairs). `water_live` 4/4. Screenshots of
the plant cold and powered were checked.

### Known gaps after D3

* The power network is the plant alone. There is no separate transmission
  step (exposing a buried conduit); the spec lists that as optional.
* There is one plant per map, so variety comes from where it sits and the
  route to it, not from different puzzle layouts.
* Releasing lava with the valve is safe. Drilling into a sealed lava pocket
  elsewhere can still flood a tunnel, which the player has to dig around or
  quench.

## Next smallest tasks (D4, then D5)

1. ~~D4: unique artifact~~ done: **First Light** (`KEEPSAKES[5]`, 250 CR),
   one per deep map, on a dry standing cell in the lower transit level that is
   reachable and leads on to the gate (`FirstCivGenerator._place_first_light`).
   The main mine still places exactly one keepsake per zone (`ZONE_COUNT`).
2. D4: more archaeological signs or short records in vaults; a guardian that
   patrols powered corridors and stalls when the engine is offline.
3. D4: review reward balance (`DEEP_EXIT_BONUS`, premium ore density).
4. D5: the optional third fluid (Aetheric Slurry / Thermal Gel). Write the
   interaction table first.
5. Measure FPS and frame times on an Android device / Retroid Pocket 5 in the
   deep stage with active lava and steam; tune `LAVA_BUDGET` and
   `STEAM_MAX_CELLS` if needed.
6. Build the APK and confirm CI on this branch (not done yet).

## Final results on the branch head

`TEST_TIMEOUT=1200 ./tools/run_tests.sh`: terrain 32/32, physics 49/49, save
15/15, ui 71/71, gen 4344/4344 (0 repairs), game 111/111, lava 33/33,
deep 1958/1958 (60 deep seeds, 0 repairs). Also `water_live` 4/4,
`cargo` 19/19, `structures` 13/13. Version 0.6.0 (code 15).

## 0.6.1: foundering crust, floating water, more fluids

* `LavaSim._founder()`: reaction-made rock (`crust`) sinks one cell per lava
  step through lava or water (the liquid swaps up), unless `_held()`: attached
  to non-crust rock within `CRUST_CANTILEVER` cells, or a run wedged between
  rock on both sides no wider than `CRUST_MAX_SPAN`. Landed crust becomes
  ordinary rock. Never sinks from under or onto an actor; bounded by
  `CRUST_SINK_BUDGET`.
* `WaterSim._open()` excludes lava cells and droplets land on lava, so water
  rests on lava instead of sinking through it (no effect in the main mine,
  which has no lava).
* `LAVA_SOLIDIFY_AT` 64 (one cell of water per block), `STEAM_PER_UNIT`
  0.16, `STEAM_MAX_CELLS` 700.
* Generation: `DEEP_WATER_POCKETS` [4,7], `DEEP_LAVA_POCKETS` [6,10],
  `DEEP_LAVA_PITS` 0.8, `DEEP_QUENCH_PAIRS` [3,5], new `DEEP_SLUICE_PAIRS`
  [2,4] (lava over a water pool with a cracked divider).
* Tests (suite `lava`, 41): a wide lake founders, keeps reacting and makes a
  lot of rock; a narrow channel bridges over molten lava; lava over water pours
  down, sinks as rock and raises a big plume, with accounting balanced. Ran
  three times in a row to check stability. Deep suite checks sluices exist.
* Results: `TEST_TIMEOUT=1200 ./tools/run_tests.sh`: terrain 32/32, physics
  49/49, save 15/15, ui 71/71, gen 4344/4344 (0 repairs), game 111/111,
  lava 41/41, deep 1958/1958 (0 repairs).

## 0.6.2: lava into water spreads, slag, steam out of water

Reported on device: lava falling into a pool stacked into a pillar in the
middle and used up most of the water.

* `LavaSim.flow_step`: a lava cell with at least `LAVA_SINK_MIN` units swaps
  down with a water cell (`_swap_with_water`, carries its cooling with it), and
  lava resting under lava spreads sideways under water onto a supported cell.
  Counted in `swapped`.
* Cooling need is proportional: `LAVA_SOLIDIFY_AT * clamp(lava / LAVA_MAX,
  0.25, 1)`, so a thin film crusts with little water.
* `_react` never boils more than the cell still needs (`need - cool`), however
  many wet faces it has. In the `lava` pour test, water used per lava unit fell
  from about 1.8 to 1.4.
* `_founder`: unheld crust also drops through open air (the boulder system
  now leaves crust to `LavaSim`); a thin lava film (< `LAVA_ROCK_MIN`) holds it.
* `_crust`: lava under `LAVA_ROCK_MIN` (40) becomes **slag** (`slag[c]`); a
  cell becomes rock only once a full cell's worth has gathered there. Formed
  rock still goes through `_place_rock` and founders as before.
* `_founder`: crust that lands on a pile slumps diagonally into liquid if the
  side is open, so sunk rock builds a mound, not a column.
* `SteamField`: steam made under water rises to the surface, and steam cells
  that end up submerged keep rising; `_open` excludes water cells.
* `Hazards.Collapse._lava_owned`: masses containing `LavaSim.crust` cells are
  not telegraphed as boulders (they were shaking dust and the screen while
  sinking). `Mine` emits no dust puff for rock formed under water.
* `tests/shot.gd pourtest=1|2` builds a chamber in the deep stage (lava over a
  pool / water over a lava pool), drills the divider and prints the stats.
  Watched both in a desktop render (xvfb, software GL): the lava stream crusts
  at the surface, the rock sinks and piles into a spread mound on the floor,
  and most of the pool is left.
* New `lava` checks: the pour test's rock covers at least 4 of 6 floor
  columns and is at most 5 high; at least a fifth of the pool is left (34% in
  practice); no unheld crust hangs over open space. 44/44, run three times.
* Results on the final 0.6.2 code: `TEST_TIMEOUT=1500 ./tools/run_tests.sh`
  terrain 32/32, physics 49/49, save 15/15, ui 71/71, gen 4344/4344
  (0 repairs), game 111/111; then rerun after the last lava edits: lava 44/44,
  deep 1958/1958, game 111/111, physics 49/49, `water_live` 4/4,
  `structures` 13/13, `cargo` 19/19. Version 0.6.2 (code 17).
