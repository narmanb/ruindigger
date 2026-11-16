# Generation v2

Generation v2 replaces the single-route generator with a planned mine. Each
mine has chambers with their own shapes, a route through some of them, side
branches and loops, landmark set pieces, water that comes from the shape of
the terrain, and ore placed by geology. The map is still 72×214, and every
invariant from v1 still holds.

## Files

| File | Role |
|---|---|
| `src/gen/mine_generator.gd` | Runs the passes in order (see its header), plus the route A*, sealing, water settle and validation |
| `src/gen/gen_space.gd` | Footprint reservations. Rooms, anchors, landmarks, geodes and water claim a rect (plus clearance) before carving, and `overlaps()` must be empty |
| `src/gen/layout_planner.gd` | Picks chambers per stratum with archetype weights and assigns roles: backbone (on the route) or optional |
| `src/gen/chamber_carver.gd` | Gives each archetype its shape: hall, terraces (with a perched basin), fissure (rope ladder), works, cathedral (lake basin), ruin hall/twin/stacked |
| `src/gen/landmarks.gd` | Templates: floodgate reservoir, flooded machinery, hanging gallery, survey post, vent cluster, twin cistern, buried reservoir |
| `src/gen/gen_metrics.gd` | Per-mine metrics (route length, first reward, openness and run lengths per stratum, water bodies, ore by type, plan counts) |
| `tests/gen_report.gd` | Sweep over seeds × contracts. Prints min/mean/max and lists any invalid or repaired combos (exit 1) |

Tunables are in `Balance` (`GEN_*`, plus the existing ore/crawler/water values).

## Design

**Plan first, carve second.** The anchors (lift room, timber shaft, relay,
relic chamber) claim their footprints first. Then the planner places 3 chambers
in the Dustworks, 3–5 in the Spore Veins (a 26–34-wide cathedral 55% of the
time) and 2–3 ruins in the Forgotten Engine. Each chamber is carved and then
checked for traversal on its own. If a chamber fails, a fix is applied and
recorded in `plan.chamber_fixes`, which the tests require to be 0.

**Route.** The route visits the backbone chambers in depth order, then reaches
the relic by one of three approaches (maintenance shaft, gallery, direct). Each
leg is an A* search over a cost field:

* cheap through existing caves
* a penalty inside chamber footprints, grown by 3 cells, so the route uses
  their entrances instead of cutting their floors
* a penalty for turns
* protected and sealed cells are blocked

The path is split into straight runs and carved with the v1 corridor and
ladder-shaft builders, so traversal rules did not change. A corner where a
corridor turns down into a shaft gets no floor plug, and floor plugs never go
inside a chamber. That rule fixed the last repair case in the sweep.

**Branches and loops.** These are organic Catmull-Rom tunnels between chambers,
landmarks and the route. `tunnel_ok` rejects any cell that is reserved, a route
support, sealed, alloy, ladder or platform, so a branch can never break the
route or drain a water feature.

**Strata.** Each stratum has its own topology:

* **Dustworks:** sediment beds, horizontal lenses, timber works.
* **Spore Veins:** tall, open organic caves, terraces and fissures, the lake.
* **Forgotten Engine:** tight rock and rectilinear alloy ruins.

The metrics show it: Spore Veins `spacious` is about 700 cells versus about 240
in the Engine, with longer vertical runs.

**Water.** Water bodies are placed where the terrain can hold them: chamber
basins (lake, perched pool), landmark containers (floodgate reservoir,
cistern, flooded ruin, buried reservoir) and sealed pockets.

* Container walls go into `sealed`, so later passes can't open them.
* Before filling, a basin's flood is tested at its waterline (`_contained`).
  If it would leak, the waterline drops a row until the body holds.
* `_ensure_water_encounter` makes sure every mine has a non-pocket body of at
  least 20 cells in the Spore Veins. It tries floodgate → cistern → buried
  reservoir.
* The water sim settles everything before play. Films of 1–2 units are cleared
  so the mine starts calm, and any feature that ends up below 40% volume is
  dropped from the report.

Breaching a floodgate is tested live (see below).

**Ore.** Background veins in rock near open space, plus:

* seams along chamber walls
* sparse fault veins
* a fossil band in the sediment
* exposed hint cells that lead into richer hidden pockets

Ore never goes on route cells, protected cells or supports.

**Encounters.** Crawlers are placed by role first: guards in optional chambers,
patrols on backbone chambers, wanderers in natural caves. No crawler is within
26 cells of spawn, and none goes in a vent chamber. Ruins carry the sentries.
Gas never touches the route. Each contract changes the landmark odds (gas
fields always get vent clusters, rich seams always get a hanging gallery).

**Props.** Landmark props go first, then props chosen by context: crates or
canisters near water, scrap in the Engine, crates in Dustworks rooms, stones
elsewhere. The total is capped by `DEBRIS_GENERATED_CAP` (12), which is a
physics budget, so the metric always reads 12.

**RNG streams.** Topology, landmarks, water, ore, encounters and props each
have their own seeded stream, so tuning one system doesn't reshuffle the
others. Generation is fully deterministic: the test hashes the whole grid.

## Tests

The `gen` suite (60 seeds × 4 contracts) runs all v1 checks and adds:

* no footprint overlaps; 0 chamber fixes
* at least 4 distinct archetypes; at least 3 branches and 1 loop
* at least 2 new-style landmarks; landmarks never on route cells
* a Spore Veins water body of at least 20 cells; water features keep more than
  40% of their water after settling
* total ore value between 6000 and 16000; first reward within 90 cells
* no gas next to the route; no crawler within 26 of spawn
* the full-grid hash is identical across runs (determinism)

The `game` suite adds a floodgate breach on seed 7: open the outlet, run 600
frames, and check that the reservoir drains below half and the route is still
traversable both ways.

## Evidence (Linux desktop, Godot 4.6.3 headless)

500 seed × contract combos each, using the same `GenMetrics` code. The baseline
is `6b54a17`.

| Metric (mean) | Baseline | v2 |
|---|---|---|
| valid / repaired | 500 / 0 | 500 / 0 |
| route length (cells) | 224 | 274 |
| chambers / archetypes | 0 / 0 | 9.5 / 6.0 (min 4) |
| branches / loops | 0 / 0 | 7.2 / 2.6 (min 5 / 2) |
| landmarks (incl. 3 v1 set pieces) | (3 not tracked) | 5.7 (min 2) |
| water features tracked | 0 | 7.0 |
| water units | 14 628 | 10 424 |
| largest body (cells) | 48 | 41 |
| max water column | 5.7 | 7.0 |
| ore value | 10 309 | 10 733 |
| S1 spacious / S2 spacious | 650 / 292 | 699 / 240 |
| gen time ms (mean / max) | 408 / 575 | 590 / 919 |

Notes:

* There is about 30% less water in total. Most v1 water was large random
  pockets. v2 water sits in containers and basins, and leaking lakes now get
  a lower waterline instead of draining through tunnels during the settle.
* Generation is about 45% slower on desktop: roughly 180 ms more on average,
  mostly route A* and validation. Before the basin containment fix, outliers
  reached 2.9 s.
* Mobile generation time was **not** measured.

Commands:

```bash
./tools/run_tests.sh
godot --headless res://tests/test_runner.tscn -- suite=water_live
godot --headless res://tests/gen_report.tscn -- seeds=125 out=/tmp/report.csv   # 500 combos
godot --headless res://tests/gen_dump.tscn -- seed=7 out=/tmp/m.png [contract=N] [norepair] [ascii] [up] [routeband=y0,y1]
xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/shot.tscn -- screen=mine seed=7 at=lm:floodgate out=/tmp/s.png
```

Debug environment variables (no effect unless set): `RD_PROFILE=1` prints
per-pass timings, `RD_CELL=x,y` prints a cell's material after every pass,
and `RD_TRACE=1` prints water guarantee and settle diagnostics (slow).

## Limitations

* Chamber and landmark sizes, and some carve constants, are still inline in
  the carver and template code. Only weights, odds and thresholds were moved
  to `Balance`.
* Each archetype has one parametric shape. Variety comes from size, position
  and combination, not from many hand-authored templates.
* The floodgate is the only water feature with a live breach test. The other
  water features are checked only at rest.
* Play feel (difficulty, pacing) was judged from map renders and short
  screenshot runs, not from long play sessions on a device.
