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
| D2 lava, reaction, steam, cooled rock | See the section for D2 below, if present; otherwise not started. |
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
