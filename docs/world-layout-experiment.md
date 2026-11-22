# World layout experiment (same map size)

Branch: `experiment/world-layout-same-size`, started from `main` at `8216549`
(0.21.0 + a docs-only commit). `main` is untouched. Brief:
"RuinDigger World Layout Redesign Plan" (owner, 2026-11-22).

## Phase 0: baseline

- **Tests at the start point:** the full suite (terrain, physics, save, ui,
  gen x60, game, lava, deep, fun, plus cargo, water_live, structures) passed
  on 0.21.0 (`b1e7196`) on 2026-11-22; `8216549` only adds a docs file.
- **Sweep:** `godot --headless res://tests/gen_report.tscn -- seeds=125
  out=build/layout/base/report.csv` (500 seed x contract combinations).
  Numbers: see "Baseline vs experiment" below.
- **Maps:** `gen_dump` PNGs for seeds 7, 1000, 8919, 42, 31337, 77777 in
  `build/layout/base/` (not committed; regenerate with the command in the file
  header of `tests/gen_dump.gd`).
- **New report columns** (test-only, `GenMetrics.layout_use`): `open_cells`,
  `playable_cells` (not bedrock), `flank_open` / `flank_playable` (open /
  non-bedrock cells in the old upper margins x < 28 or x >= 100, above the
  shelf), `bedrock_pct`, `optional_chambers`.
- **Not measured:** real play time on a phone. The DigCheck seconds are a
  model of digging and climbing, not a stopwatch.

What the maps show: the Dustworks and Spore Veins live in a 72-cell column
(x 28..99). Beside them, two 26-cell bands of bedrock run from the surface down
to the shelf: about 7,400 cells, a quarter of the map, that nobody can enter.
The lower wings and the Engine vault already use the full width.

```text
 bedrock | Dustworks  (72 wide)  | bedrock
 bedrock | Spore Veins           | bedrock
 ======== bedrock shelf, two gates =======
 Drowned Aqueducts |#| Crystal Hollows
 ---------- Forgotten Engine ------------
```

## Phase 1: three sketches

### A. Side pockets
Keep the column. Cut 2-4 fixed-size pockets (one or two per side per zone)
into the bedrock margins, each joined to the column by one tunnel.
- Changes: extra zone rectangles per pocket, void claims with holes.
- Good: smallest change to routes; pockets are obvious "side trips".
- Bad: the margins stay mostly bedrock; pockets read as bolted-on rooms;
  zone lookups by rectangle need a list per zone.

### B. Full-width upper zones, anchors kept (recommended)
Widen the Dustworks and Spore Veins to nearly the full map width (x 6..121),
as wide as the wings below. Keep a thin bedrock shell at the edges. Keep every
authored anchor exactly where it is today: the surface lift room, the timber
shaft, the relay station, both shelf gates and the relic chamber stay at their
current coordinates (they are placed relative to the old column, which becomes
the "anchor column"). The new width is ordinary Dustworks / Spore Veins rock:
the cave noise, worm burrows, chamber planner, landmarks, water pockets, gas,
ore veins and crawlers can all use it, because they already work from the zone
rectangles.
- Changes: `ZONE_RECTS` for zones 0 and 1, the flank void claims, the shelf
  claim width, a new `Balance.UPPER_X0/X1`; anchor code switches from
  `CORE_X0/X1` to explicit anchor constants (same numbers as today).
- Route network: the planner gets one optional "side cavern" slot per flank in
  each upper zone, and the Spore Veins backbone may pick a flank chamber, so
  some seeds route the trunk out to one side and back (a real alternative,
  not a forced detour: the chamber planner already gives consecutive backbone
  chambers a second connection).
- Good: uses the dead quarter of the map with systems that already exist;
  the entry is unchanged; the deep half is untouched.
- Bad: per-zone budgets (ore veins, crawlers, gas, pockets) are counts, so
  they spread thinner over more rock. Decision: raise the two upper zones'
  ore and crawler counts by ~25% (not the 60% area increase), then compare
  `ore_value` and crawler counts with the baseline.
- Risks: anchors and the shelf gates assume a 72-wide column (kept by
  pinning them); the planner may still crowd the centre (check where chambers
  land); flank caves next to the outer bedrock shell could create traps
  (DigCheck `traps` must stay 0).

### C. Rearranged macro layout
Move the wing split higher (wings start under the Dustworks), or put the Spore
Veins side by side with the Dustworks.
- Good: the biggest change in feel.
- Bad: moves every anchor, the shelf, the gates, the station math and the
  zone row constants at once; most tests and the "familiar entry" goal are at
  risk. That is the giant rewrite the brief says to avoid. Possible later, as
  its own experiment, if B isn't enough.

### Recommendation
**B.** It is the smallest change that turns wasted space into real,
explorable space, uses the existing cave, chamber and landmark systems, keeps
the start and the deep half familiar, and is easy to undo (the branch).

### Future settlement space (not built)
With B, each upper flank has room for a stable 20 x 8 footprint well away from
the shaft. A future Molefolk village could claim one in `GenSpace` as an
`anchor`, the same way the relay station does. Nothing is reserved yet.

## Phases 2-4: what was built

- `Balance.UPPER_X0/X1` (6, 122): the Dustworks and Spore Veins rectangles span
  them. `CORE_X0/X1` (28, 100) stay as the **anchor column**: the lift room,
  timber shaft, relay station, shelf gates, relic and route centre use them,
  so all of those are exactly where they were.
- Bedrock claims (`flank_w`, `flank_e`, `shelf`) follow the new width. Worm
  burrows: one extra in each side region. Landmarks placed "by rows only" and
  the fossil band use the full upper width.
- `LayoutPlanner._flanks`: each upper zone tries for one optional chamber in
  each side region (halls/terraces/fissures; never on the backbone).
  `MineGenerator._flank_links`: Spore Veins side caverns tunnel to the shelf
  gate on their side, a second way down to that wing.
- Budgets stay per zone (ore veins back to the original counts; Spore Veins
  crawlers 5 -> 6). Ore value rises ~7% from the extra rooms' wall seams.
- Bugs found on the way (both affect normal mines too):
  - `_connect_secret` (survey post passages) cut through other features'
    sealed water walls. Seed 861598 / quiet drained a floodgate reservoir and
    took 10.7 s to settle. It now stops at sealed walls.
  - Run relic choice pairs were only tried at the first relic spot; the wider
    layout often put that in a cramped burrow (1 of 8 test maps had a pair).
    The pair now goes to the first picked spot with room, or the best-ranked
    other spot with room replaces the first pick.
- Debug helpers: `RD_LEAK=1` (where each water feature escapes before
  settling), `RD_NEAR=x,y` in gen_dump (landmarks/chambers near a cell),
  `RD_CELL` now also traces after each landmark.

## Baseline vs experiment (500 seed x contract combinations each)

| Metric (mean) | Baseline (`8216549`) | Experiment |
|---|---|---|
| invalid or repaired | 0 | 0 |
| traps | 0 | 0 |
| bedrock share of the map | 31.2% | 9.7% |
| open cells | 6,447 | 8,183 (+27%) |
| open cells in the old side margins | 0 | 1,502 |
| chambers (optional) | 15.5 (10.0) | 19.4 (13.8) |
| side caverns / gate links | 0 / 0 | 4.6 / 2.0 |
| loops / branches | 3.5 / 14.7 | 5.5 / 18.5 |
| DigCheck spawn -> relic door | 37.6 s | 37.3 s |
| DigCheck climb back up | 78.2 s | 75.2 s |
| first reward (cells from spawn) | 25.3 | 30.3 |
| ore value | 17,912 | 19,157 (+7%) |
| crawlers | 14.6 | 15.2 |
| water units | 20,296 | 21,949 |
| generation ms mean / max | 1,209 / 3,572 | 1,490 / 2,350 |

Desktop numbers (this container, headless). Not measured on a phone.
The quickest route is as quick as before; the gain is space and options.

Before/after maps for seeds 7, 1000, 8919, 42, 31337 and 77777 are made with
`gen_dump` (see the build folder notes above); a sheet was sent to the owner.

## For the playtest (owner's questions from the brief)
Does the start feel familiar but less cramped? Do you want to go and look at
the sides? Are the side caverns worth it or dead ends? Can you still go down
fast? Is it easy to find the way back? Does it feel bigger? Is layout the
bigger issue, or does it still need a larger world?
