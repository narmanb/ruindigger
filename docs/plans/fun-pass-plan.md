# Fun pass: from digging simulator to game

Status: **S1, S2, S3, S5, S6 built.** Partly built: S4 (lures, drowning,
steam, terrain kills) and S7 (run relics as rare loot; no puzzle vaults yet).
All on branch `feature/fun-pass`, version 0.7.0. See "Build log" at the end.
S8 not started. Written after playing 0.6.3 and the
owner's notes. Every segment below is independent enough to ship on its own;
we do not have to do it all, or in one go.

## The problem

The loop today is: dig, fill the rack, go home. The physics are good, but the
mine never pushes back and you never have to choose between two things you
want. Ore is the only reward, and it is only ever a number.

What the game already has to build on (checked in the code):

* Ore: copper 6, cobalt 15, aetherite 38, fossil 22, scrap 4 (`Balance.ORE`).
  Cargo is 16/24/34/46 units. When the rack is full, ore stays on the ground
  and cannot be picked up (`entities.gd`, the `room` check).
* Upgrades: drill, heat, cargo, hull, scaffold (`Balance.UPGRADES`), all
  "bigger number" upgrades. Four contracts that only change multipliers.
* Enemies: crawlers (hear noise, chase, tunnel through sediment), sentries.
  Rubble already stuns and damages them.
* Hazards: gas, collapse, boulders, water, and in the deep stage lava and
  steam. Charges. Keepsakes (one per zone). A relic and a lift to extract.

## Design pillars

1. **Greed vs. safety.** Deeper ore is worth much more, and the mine gets
   angrier the longer you stay.
2. **The terrain is the weapon**, for you and against you.
3. **Every run is different**: different gear, different modifiers, different
   orders, different finds.
4. **Always something to do next** within the next minute or two.

## Segments

Sizes are rough (S = a session, M = two or three, L = more). Each segment ends
with tests, screenshots where visual, a changelog entry and a version bump, as
for 0.6.x. Nothing here has been tried on a phone.

### S1. Loot economy (S)

* **Bigger rack.** Starting capacity 16 -> **60**; upgrades roughly
  60 / 90 / 130 / 180. Ore drops stay as they are, so a rack fills slowly
  enough that you choose when to leave. Upgrade prices rebalanced to match.
* **Swap up when full.** If the rack is full and you touch ore worth more
  than the cheapest thing you carry, one unit of the cheapest is dropped
  (as a loose pickup you can still grab if you change your mind) and the new
  ore goes in. Toast: "SWAPPED COPPER FOR AETHERITE". Ore worth no more than
  your cheapest is left alone. Keepsakes stay in their own pouch.
* **Depth pays.** Ore value gets a per-zone multiplier (roughly x1.0, 1.3,
  1.7, 2.2, 3.0, and x4 in The First Civilization), and each deeper zone gets
  one new high-tier ore with its own colour, so going down is visibly richer.
  All numbers live in `Balance`.
* Cargo manifest and results screen show the multiplier and any swaps.

Risk: old saves hold the old capacity table. Capacity is computed from the
upgrade level, so a save keeps working; the owner's current upgrade levels
simply buy a bigger rack.

### S2. Orders: short-term goals (S to M)

* Each dive offers **2 or 3 orders**, generated from what the map really
  contains: "bring back 6 cobalt", "reach 300 m", "take a keepsake", "kill 3
  crawlers with rubble", "find the sealed door", "survive a gas ignition".
* Progress shows on the HUD; finishing one pays credits and sometimes a
  one-run perk. They are optional, and failing one costs nothing.
* The generator only offers an order the map can satisfy (enough of that ore,
  a reachable depth, a door that exists). A test checks this over many seeds,
  as for the keepsakes.

### S3. Pressure: the mine wakes up (M)

* A visible **pressure** meter rises with time spent in the current zone, with
  depth, and with noise (drilling, charges). It never rises while you are at
  the lift or in a safe room.
* Each tier adds a *telegraphed* event, tuned in `Balance`: more gas pockets
  venting, more ceiling collapses, a crawler wave that comes to the noise, and
  in deeper zones rising water or surging lava from known reservoirs.
* Leaving or banking at a lift relieves it, so the choice is "one more vein or
  go home". Rich zones build pressure faster.
* Must stay fair: every event has a warning (sound, shake, HUD flash), and
  none can soft-lock a map (checked against `DigCheck`).

### S4. The terrain is a weapon (M)

For you:

* **Lures.** A throwable pinger makes noise on purpose; crawlers already
  investigate noise, so you can pull them under a loose ceiling, into a
  flooded pit or above lava.
* **Shear charge.** A charge that only cuts supports, to drop a ceiling where
  you choose, and **anchor bolts** that hold a ceiling you must dig under.
* Enemies take real damage from rubble, drowning (crawlers in deep water),
  lava, steam and gas ignition, with a toast when the terrain gets a kill
  (feeds the orders from S2).

Against you:

* Sentries and a new **breaker** enemy that drills your supports, plus guards
  that flood or ignite pockets they stand beside. Counter-play for each is
  environmental: seal, drain, bait.
* Existing hazards get an owner. A collapse that was triggered by an enemy
  reads differently from one you caused.

### S5. Dive modifiers (S to M)

* Before a dive you pick **one or two modifiers**, each with a reward
  multiplier: Flooded (more water, ore x1.5), Gas Field, Brittle (more
  collapses), Hot (lava reaches higher zones), Blackout (dark, lamps matter),
  Swarm, Quiet. The four contracts become modifier bundles.
* Modifiers are generator parameters, so they reuse the existing `GEN_*`
  budgets and are covered by the same fairness sweep.

### S6. Gadgets and drill abilities (M)

* Two **gadget slots** per run, filled in the outpost and by finds in the mine.
  Candidates: thermal lance (melts rock, builds heat), ore magnet, freeze
  canister (turns water to ice or cools lava to rock on demand), shaped
  charge, anchor bolts, pump (moves water), sonar ping (reveals ore and
  hazards nearby).
* Upgrade tree changes from "+x%" to unlocking gadgets and tier effects, so
  two runs with different gear play differently.
* Start with three gadgets, not seven. Add more only if they earn their keep.

### S7. Procedural physics vaults and rare loot (L)

Free-form puzzle generation is not realistic. **Template puzzles with
randomised parameters, verified by simulation**, is. The plant puzzle in 0.6.0
already works this way: its test solves the puzzle in the real sim.

* A library of 5 or 6 templates, each a small authored layout with random
  size, position, orientation and difficulty:
  * **Drain:** a sealed water chamber over the door; open the right cell.
  * **Bridge:** a lava gap; bring water to build crust.
  * **Keystone:** cut the right supports to drop a slab onto a plate.
  * **Flood-lift:** fill a shaft so a crate floats to a ledge.
  * **Heat gate:** warm or chill a valve (builds on the Thermal Plant).
  * **Counterweight:** drop a loaded cart to open a door.
* Each template ships with a solver (or scripted solve) that must succeed in
  the real simulation on every seed in the test sweep, and a "break it"
  check (failure is recoverable, never a soft lock).
* **Rare loot** behind them, in tiers: caches of ore, **relics that change the
  run** (e.g. "ore magnet range x2", "lava burns you at half rate"), and
  unique keepsakes. Rarer tiers need harder templates.

### S8. Mid-run choices and set pieces (L)

* **Choice rooms:** a vault door with two rewards (take one, the other seals),
  a risky shortcut, a shrine that trades hull for charges, a trader.
* **Zone guardians:** one set-piece fight per zone, built around that zone's
  terrain (flood the Aqueducts' guardian, drop the Engine's ceiling on its
  guardian). Killing it drops a unique relic.
* Biggest single payoff for progression, and the most design work.

## Suggested order

1. **First batch (about one release): S1 + S2 + S3.** Bigger rack and depth
   pay, orders to chase, and a clock that makes you choose. This alone should
   change how a dive feels.
2. **Second batch: S4 + S5.** Environmental combat and modifiers, which
   multiply replay value and reuse generation work already done.
3. **Third batch: S6.** Gadgets, which gives S4 and S7 more to work with.
4. **Later: S7 and S8.** These need the most design; do them once the earlier
   systems exist to attach rewards to.

## Open questions for the owner

1. S1: is 60 the right starting rack, or do you want it even higher? Should
   dropped ore from a swap stay pickup-able, or vanish?
2. S3: should reaching the lift fully reset pressure, or only lower it?
   Should pressure carry into the next dive (as a "bounty")?
3. S6: any gadgets you definitely want, or definitely don't?
4. Should the main mine and The First Civilization share all of this, or
   should some systems (pressure events, guardians) be deep-stage only?
5. Do you want save compatibility with current progress kept at all costs,
   or is a reset acceptable if it makes the economy cleaner?

## Constraints we keep

* Terrain stays on `TerrainGrid`; gameplay damage goes through
  `Mine.damage_cell`; tuning numbers live in `Balance`.
* New generation stays deterministic, on its own RNG stream, and keeps
  "invalid or repaired: 0" and the `DigCheck` fairness rules.
* Art and audio only via `tools/assetgen`.
* Every segment lands with tests, and nothing is claimed about phone
  performance until it has been measured on a phone.


## Build log (0.7.0, feature/fun-pass)

Built without the owner's answers to the open questions; these defaults were
chosen and are easy to change in `Balance`:

1. Rack 60 / 90 / 130 / 180. Swapped-out ore drops as a pickup (it does not
   vanish).
2. Extraction ends the run in this game, so pressure has no "bank at a lift"
   reset. It eases while you are above your deepest zone, and half of it
   carries into The First Civilization. It does not carry between dives.
3. Gadgets (S6) use one active slot and one passive slot, chosen free at
   the Supply Locker. There is nothing to buy yet. The lure is separate: a
   free consumable thrown with USE when nothing is nearby.
4. Everything applies to both the main mine and The First Civilization.
   Modifiers change generation only in the main mine; BRITTLE and BLACKOUT
   also apply in the deep stage.
5. Existing saves keep working. Rack size comes from the cargo upgrade
   level, so current upgrades buy the bigger rack.

What is in each segment:

* **S1:** `Balance.ore_key/ore_value/ore_label` pack ore + grade into a cargo
  key (grade-0 keys equal the old ids). `Mine.spawn_ore` grades new drops by
  zone. `Mine.collect` swaps; `Game.can_take` gates the magnet.
* **S2:** `src/world/orders.gd`. HUD `OrdersPanel`, manifest section and
  results lines. Enemies record `last_hit`, and `Orders.TERRAIN_SOURCES`
  decides what counts as a terrain kill.
* **S3:** `src/world/pressure.gd` (own RNG stream). Mine noise feeds it.
  Tremors go through the existing collapse telegraph, gas through
  `GasSystem.vent_at`, swarms through `Mine.spawn_crawler`.
* **S4 (part):** `Hazards.Lure`, `Crawler.lure()`, `Player.throw_lure()`,
  enemy steam scald, drowning attributed to water. Not built: shear charge,
  anchor bolts, the breaker enemy, enemy-triggered hazards.
* **S5:** `Balance.MODIFIERS`, `Game.modded_contract/modifier_pay`, contract
  board grid, results line. FLOODED scales pocket counts, fills every pocket
  and basin, and tries placement harder (pocket count alone was capped by
  space).

* **S6:** `Balance.GADGETS`, `Game.loadout` and the run's `loadout` and
  `gadget_cd`. New input action `gadget`, plus a touch button. Mine
  `use_gadget`, `sonar`, `cryo_burst`, `has_passive`. `Hazards.Cryo` and
  `Hazards.SonarPing`. `LavaSim.quench` crusts lava with the normal
  accounting. Passives hook into the pickup magnet, rubble and boulder
  damage, and drill heat.

* **S7 (part):** `Balance.RUN_RELICS`. `ZoneFinds.relics` places them for both
  generators (entity data only, seeded, reachable with a way out, dry,
  separated from keepsakes). `RunRelic` entity, `Game.has_relic`, and effect
  hooks in drill noise, ore drops, lava and steam burns, pressure, gadget
  cooldown and hull. Puzzle vaults (the template library) are not built.

Tests: suite `fun` (in `run_tests.sh`) covers all of the above. A one-off
sweep of 90 maps (each modifier x 15 seeds) gave 0 invalid or repaired.
Not measured on a phone.
