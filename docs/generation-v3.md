# Generation v3 and the 0.5 changes

0.5 turns Ruin Digger into a dig-first game on a wider world. This document
covers the world shape, the dig-first route, the fairness model that replaced
"walkable without digging", and the numbers measured. Generation v2
(`docs/generation-v2.md`) still describes the planner, chamber archetypes,
landmarks and water rules, which v3 builds on.

## World shape

The map is 128×236 cells (was 72×214). All layout numbers are in `Balance`.

```
              +---- core column (72 wide) ----+
              |  0  Dustworks                 |
              |  1  Spore Veins               |
   +----------+==== bedrock shelf ============+----------+
   |  3  Drowned Aqueducts   ||   4  Crystal Hollows     |
   +---------- 2  Forgotten Engine (vault) --------------+
```

* The Dustworks and Spore Veins sit in a central column. Everything beside
  that column is solid, protected bedrock.
* Under the Spore Veins is the **bedrock shelf**. It is open only at its
  far-west and far-east ends. Each **gate** is an authored ladder shaft with a
  landing above and a protected lift station at the top of a wing.
* The west gate drops into the **Drowned Aqueducts**. The east gate drops
  into the **Crystal Hollows**. A bedrock divider separates the wings.
* Both wings open downward into the **Forgotten Engine vault**, which spans
  the full width and holds the relic chamber near its centre. Either wing is a
  fair way to the relic.

The zone id is the stratum id stored per cell in `TerrainGrid`. It drives
tiles, ambient light, parallax, music, water tint and every generation budget
(`Balance.GEN_*` arrays are indexed by zone).

### The two wings

| | Drowned Aqueducts (west) | Crystal Hollows (east) |
|---|---|---|
| Rock | Level courses of dressed stone | Steep ribs of hard, faceted rock |
| Caves | Long, low, level galleries | Tall cracks and steep hollows |
| Chambers | Halls and terraces | Fissures, halls, often a cathedral |
| Signature | 2–3 **aqueduct channels**: long flooded stone troughs with ore on the bed and a cracked block low in one end wall | **Hanging galleries** of loose shards, 3–5 geodes, many loose ceilings |
| Water | 3–5 pockets, floodgate, cistern, flooded machinery | 0–1 pockets |
| Ore | Cobalt, some aetherite | Cobalt and aetherite |

Measured over 100 mines: the Aqueducts hold 3.7× the water of the Hollows
(7,373 vs 1,990 units), the Hollows are harder rock (55% vs 43% basalt) and
have taller open runs (5.9 vs 4.4 cells).

## Dig-first routes

The Dustworks keeps its ladders: it is the tutorial zone. Below it the player
mostly cuts their own way. A vertical route section is built in one of four
styles, chosen per zone by `Balance.GEN_SHAFT_STYLE`:

| Style | What is carved | How you get back up |
|---|---|---|
| ladder | 2-wide shaft with a full ladder | Climb |
| ledges | Open shaft with plank scaffolds one jump apart | Jump |
| open | Bare drop | Rubble Ladder, or cut steps into the wall |
| plug | Nothing: a column of cracked rock | Drill down, then ladder up your own bore |

Other rules:

* Corridors get **plugs**: short walls of cracked rock the player drills
  through. Cracked rock is the visual tell for "the route continues here".
* Shafts beside unbreakable walls, and the alloy-lined relic approach, use
  ledges, because alloy and bedrock cannot be cut into steps.
* Deep fissure ropes are frayed: only the top third remains.
* Authored structures keep their ladders: the gate shafts, ruins, landmarks.

### Rubble Ladder

Breaking rock fills the scaffold meter (sediment 1, basalt 2, +1 for ore;
capacity 40, upgradable to 160). LADDER spends it: 2 to activate plus 1 per
cell, building straight up from the feet cell to the first solid cell. It
passes one-way platforms and existing ladders for free. If energy runs short it
builds as far as it can from the bottom.

## Fairness model (`DigCheck`)

"The route is walkable without digging" no longer makes sense, so
`src/gen/dig_check.gd` replaces it. It models a player with **starting gear**:

* walk, fall, 3-cell jump, ladders, one-way platforms (as `RouteCheck`)
* tunnel sideways through diggable rock
* dig the floor out and drop one cell
* cut a one-cell step up into a wall (staircase digging)
* with `allow_ladder`: raise a Rubble Ladder through open space, but only where
  diggable rock is within 3 cells and never taller than one starting meter

Digging straight up is not a move. Costs are seconds: dig time with the Mk.I
drill plus travel time. Ladder energy is priced as the time to earn it back.

Every generated mine must pass, and the tests check all of it:

1. **Completable:** spawn → relic door within `FAIR_DIG_BUDGET_DOWN` (150 s),
   and door → surface lift within `FAIR_DIG_BUDGET_UP` (200 s).
2. **Both wings reachable:** each gate's lift station can be reached.
3. **No softlock traps:** every cell the player can get into can reach the
   surface lift (reverse reachability over the same moves).
4. **0 repairs:** the repair fallback exists but must never run.

The trap audit found real problems during development, each now fixed in the
generator:

* One-cell-wide slivers of rock between two unbreakable walls. `_seal_slivers`
  turns them into wall.
* An alloy-lined relic approach built as a bare drop. It now uses scaffolds.

### Deviation from the plan

The plan asked for the softlock check to assume **zero** ladder energy. That
proved too strict: energy is renewable wherever there is rock to drill, and a
zero-energy rule marked ordinary open shafts as traps. The check instead
allows a ladder only where diggable rock is in reach, so pits walled entirely
by unbreakable material are still caught.

## Measured results

Linux desktop, Godot 4.6.3 headless. Sweeps use `tests/gen_report.tscn`.

| Metric (mean) | v0.4.0 (72×214) | v0.5.0 (128×236) |
|---|---|---|
| Combos valid / repaired | 500 / 0 | see README for the final sweep |
| Softlock trap cells | not audited (the audit did not exist) | 0 |
| Ladder cells below the Dustworks | 176 | 99, of which 34 are the two gate shafts |
| Deep route needing digging | 0% | 15% |
| Dig time, spawn → relic door | 31 s | 39 s |
| Time, relic door → surface (with ladders) | – | 76 s |
| Chambers / landmarks | 9.5 / 5.7 | 15.4 / 9.9 |
| Ore value | 10,733 | 17,800 |
| Generation time | 590 ms | 1,020 ms (max 1,200 ms) |

Per unit of deep area the ladder density fell by roughly 85–90%: the deep
world is about 3.3× larger and has fewer than half the ladder cells once the
authored gate shafts are set aside. The raw count missed the plan's "80% fewer
cells" target, because the world grew.

Live physics step on the larger world, in the flooded Aqueducts: median
1.4 ms, p95 1.8 ms. Render time was not measurable (software GL in the build
sandbox). **Nothing was measured on a phone.**

## Limitations

* Generation takes about 1.0 s on desktop, up from 0.6 s. It runs on the main
  thread, so expect a longer loading pause on a phone. Not measured on device.
* `DigCheck` is a conservative model, not a proof. It does not track which
  cells a path has already dug, and it ignores jets, wall jumps, charges and
  upgrades (all of which only help the player).
* Player-built ladders cannot be removed by drilling (the plan suggested they
  could). Blasts and falling rock still destroy them.
* The vault's ruins are optional side rooms now; none is forced onto the
  route.
* Each wing biome reuses existing mechanics (water, loose rock, geodes) with
  new art and layout. Neither adds a brand-new hazard type.
* The d-pad shares one size slider with the stick.
