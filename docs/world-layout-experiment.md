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
