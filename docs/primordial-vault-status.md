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
| D3 geothermal power puzzle | Not started unless a section below says otherwise. |
| D4 atmosphere, artifacts, defenders | Not started. |
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
* **Rendering.** `src/fx/lava_renderer.gd`: visible cells only; a churning body
  with a bright, crusted surface; additive heat glow; steam puffs drawn in
  front of the player. The minimap shows lava.
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
