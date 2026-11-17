# Handoff: state of Ruin Digger (read this first in a new session)

Last updated at version **0.17.1** (Android code 31). **`main` is the
up-to-date branch** (merged with `feature/fun-pass` at 0.9.0 on 2026-11-16).

## Branches
- `main`: the current game. The owner wants it to always be the most
  up-to-date branch.
- **Workflow:** do the work on the session's own branch, then merge it into
  `main` after every update (versioned or docs-only) and push both. Merge,
  never force-push. If the session's rules only allow pushing its own branch,
  ask the owner before pushing `main`.
- `feature/fun-pass`: where 0.7.0-0.9.0 were built. Its files match `main` at
  0.9.0. No longer the working branch.
- `feature/first-civilization`: the deep stage work (0.6.x), included in `main`.
- `finish-0.5`, `ccr-79c19570-j1j312`: old history. Never modify, force-push or
  merge without the owner asking.
- `main` also holds the original 0.1 top-down build in its history (tag
  `v0.1.0`); the 0.9.0 merge replaced its files.
- No pull requests unless asked.

## How the owner works (follow these)
- **Every update gets a new version** in `project.godot`
  (`config/version`), `export_presets.cfg` (`version/name`, and
  `version/code` +1), and a new top `## x.y.z` entry in `CHANGELOG.md`.
  Patch number for fixes, minor number for features. The `save` suite fails if
  these disagree. Docs-only commits need no bump.
- After pushing, give the owner the Actions page link and do not wait for the
  build. CI uploads the APK unzipped as `RuinDigger-<version>.apk`:
  https://github.com/narmanb/ruindigger/actions?query=branch%3Amain
- Plain language. Say what was and was not tested. **Nothing has ever been
  measured on a phone**; only desktop (headless and xvfb).
- Commit trailers per the session's attribution instructions. Never put model
  IDs in commits or code.
- `AGENTS.md` rules are binding (terrain only via `TerrainGrid`, tuning in
  `Balance`, typed GDScript, generator pass order, `DigCheck` fairness, art
  only via `tools/assetgen`).

## Tests
`TEST_TIMEOUT=1500 ./tools/run_tests.sh` runs these suites: terrain, physics,
save, ui, gen, game, lava, deep and fun. Also run `cargo`, `water_live` and
`structures` separately. All are green at 0.17.1. Run one section of the fun suite with `suite=fun only=roamers|roamers_b|roamers_c|charges|drops`
(add more names in `FunPass.run`); loop it to chase an intermittent failure.
Note: `t._frames(n)` waits on
physics ticks; headless runs space idle `_process` frames out more, so a test
of something updated in `_process` should poll with a cap, not wait a fixed n. Wrap Godot in `timeout`: a
parse error makes a headless run hang. The screenshot harness is
`tests/shot.gd`; useful args include `deep=1`, `at=lm:<kind or NAME>`,
`decor=<kind>`, `sandtest=1`, `kitdemo=1`, `pourtest=1|2`,
`drill_left=1 stopat=N back=N`, `touch_mode=1`, `gadget_bar_open=0`,
`allrelics=1`, `cargo_open=1 [cargo_end=1]`,
`--resolution 1846x852` (the owner's phone ratio).

## What exists (newest first)
- **0.17.1** (fixes from the owner's first phone playtest, which was on an
  explosives-era build): `Crawler._falls` (a crawler with nothing to cling to
  drops; long drops hurt, last_hit "fall"), `WaterSim.update_drops` displaces a
  droplet out of any blocked cell, sand included (it used to check solid rock
  only), and the drill rocket uses the drill sheet and leaves the arm
  (`Player.drill_regrow`). **This was pushed without "[skip ci]"**: its APK
  includes everything up to here.
- The owner noticed a drill rocket flew over a crawler (the rocket flies at
  chest height, a crawler is low). They said it may not be a problem and not
  to worry about it for now.
- **0.17.0:** Eel and Slag salamander, both on `src/enemies/pool_dweller.gd`
  (a Crawler that swims in cells where `in_pool(c)` holds, crawls outside
  them, and heads home after `dry_limit`). `eel.gd`: pool = water, dries out
  (last_hit "dry"). `slag.gd`: pool = lava, `quench()` turns it into a HARD
  cell with aetherite (last_hit "quench"; called for water in its cell and
  from `Mine.cryo_burst`). `roamer_cells()` returns 7 lists (…, eels, slags).
  **Crawler change:** `_step` now waits for a due re-plan while chasing
  (routes used to be renewed only when they ran out), and
  `Crawler._finish_approach(goal)` walks the last cells to the goal for
  enemies that can enter it (Flier, PoolDweller). Screenshot arg: `pooldemo=1`.
- **0.16.0:** Burrower (`src/enemies/burrower.gd`: a Crawler whose `walkable`
  includes rock it can chew; the chewing is in `_step` / `_chew`), Bomb-eater
  (`bomb_eater.gd`: eats `Mine.mines` / `Mine.remotes`, `eats_bombs` makes
  mines ignore it), Spore pod (`spore_pod.gd`: a Flier that bursts into a gas
  vent, or a fireball if a blast killed it). `Mine.spawn_kin(kind, cell)`;
  `roamer_cells()` now returns [brutes, fliers, burrowers, eaters, spores].
  Burrower and eater sheets share the crawler's frame layout. Screenshot arg:
  `kin=burrower,eater,spore`.
- **0.15.0:** Shielded Brute (`src/enemies/brute.gd`, its own pixel-space
  walker, not a Crawler) and Flier (`src/enemies/flier.gd`, a Crawler whose
  `walkable` is any open cell). Placed at runtime by `Mine.roamer_cells()` /
  `_spawn_roamers()` from a seeded stream: the generator is untouched. Art:
  `gen_brute` / `gen_flier` in `tools/assetgen/gen_sprites.py`. `Crawler` now
  has per-kind vars (`max_hp`, `speed_*`, `bite`, `sight`). `Mine.noise` calls
  `hear` on anything that has it. Screenshot args: `brute=N [brute_state=S]`,
  `flier=N`.
- **0.13.0:** explosives and the Demolitions counter.
  - Data: `Balance.EXPLOSIVES` / `EXPLOSIVE_ORDER` / `DEMO_UPGRADES`.
  - Save (`Progress`, VERSION 2): `explosives` (stock by type), `demo`
    (upgrade levels), `slots` ([main, backup]). Version 1 saves migrate in
    `from_dict` (Charge Rack -> capacity, Sticky upgrade refunded).
    `charge_rack` and `sticky` are no longer upgrade tracks.
  - Run: `Game.run["slots"]`, `["charges"]` (main slot ammo), `["charges2"]`
    (backup). Helpers `Game.slot_kind/slot_ammo/has_explosive`.
  - Input: `charge` and `charge2` -> `Player.use_explosive(slot, ay)`.
  - `Hazards.Charge` (flags `sticky`, `remote`), `Hazards.Rocket`,
    `Hazards.ProxMine`; every blast goes through `Mine.charge_blast`.
  - Touch: `TouchControls.default_buttons(two)`; both slot buttons share the
    "charge" layout offset. Outpost: `_demolitions_panel`.
  - Screenshot args: `slots=charge,rocket`, `screen=outpost panel=demolitions`.
- **0.12.0:** three map relics. Dowsing Rod (`Mine._dowse` writes a second
  "sensed" layer, `Minimap.sense_img/sense_tex`, drawn under the explored
  map in the minimap, pause map and survey map), Greedy Lamp
  (`src/world/ore_compass.gd`, a ring of arrows in the glow layer, plus
  `Mine._greedy_light` and `Pressure._mult`), Cartographer's Eye
  (`Mine.reveal_zone`, from `_zone_reached` and `Mine.on_relic_taken`, which
  `RunRelic.take` now calls for effects that start at once).
- **0.11.0:** four more run relics. Fault Line (`Mine.fault_line`, called from
  `Mine.explode` for charges), Pressure Valve (`Pressure.vent`), Dust Cloak
  (`Mine.raise_dust` / `Mine.cloaked`, checked in `Crawler._sees_player` and
  the chase timer), Slag Heart (`Mine._slag_heart`, from `_heat_feedback`). A
  relic entry with `"deep": true` is only offered in The First Civilization
  (`ZoneFinds.relics(..., deep)` and `Game.unowned_relic_id(id, deep_ok)`).
- **0.10.0:** six new run relics (Echo Drill, Overdrive, Hard Hat, Blood
  Bargain, Glutton's Sack, Spare Parts). Hooks: `Mine.drill_cell` (echo),
  `Player._update_drill` (overdrive), `Mine.rock_damage_mult` (hard hat, also
  replaces the plating maths), `Game.bargain_pay_for` (bargain, needs
  `run["hull_frac"]` set on extraction), `Mine.cargo_cap` and
  `Mine._glutton_rattle` (glutton), `Mine._zone_reached` (spares; also keeps
  `run["zones_seen"]`).
- **0.9.1:** no duplicate relics (`Game.unowned_relic_id`, applied when relics
  spawn) and Iron Spine no longer stacks.
- **0.9.0:**
  - Breaker enemy (`src/enemies/breaker.gd`). It gnaws the roof over you and takes double damage while gnawing.
  - Shear charges and anchor bolts (`Mine.shear_blast`, `Mine.fire_bolt`, `Mine.anchored`).
  - A four-button gadget toolbar and a KIT row in the HUD.
  - Owner's note: not very interested in shears and bolts. Don't invest more unless asked.
- **0.8.0:**
  - Sand flies as grains (`src/terrain/sand_drops.gd`) and lands as granular piles that sit on the visible ground. Piles are drawn per pixel column in `TerrainView.draw_sand`. Collision is one segment chain per row.
  - The zone name, music and light follow the player, with a 3-row margin past borders (`Mine.presented_zone`).
  - Water is one colour everywhere.
  - The CARGO button was removed; the status panel's CARGO row opens the manifest.
- **0.7.x:**
  - HUD and touch redesign (`src/ui/hud_skin.gd`, `hud.gd`, `touch_controls.gd`), with a retractable toolbar.
  - Feet planted on the visible ground (`TerrainView.surface_depth` skips the dark outline row).
  - Lure pips.
  - Charge Rack and Sticky Charges upgrades.
  - Sand physics (`SandSim`; Settings > Sand physics Off/Low/Normal/High).
  - The fun pass: ore graded by depth, a 60-slot rack that swaps cheap ore for better, orders, the pressure meter and its events, lures, dive modifiers, gadgets (sonar, cryo; magnet, plating, coolant), run relics and relic choice pairs.
  - The Ancient Descent Platform redrawn as a grand gate.
- **0.6.x:**
  - The First Civilization deep stage (one-way descent from the Forgotten Engine) with lava, steam, the Thermal Plant puzzle and the Transit Gate.
  - Furnished vaults: colossi, furnaces, conduits, husks, rails, archive.
- Plan and history: `docs/plans/fun-pass-plan.md` (with its build log),
  `docs/primordial-vault-status.md`, `CHANGELOG.md`.

## Run relic plan (agreed with the owner)
- **Batch B: done in 0.11.0.** Sand piles do not slow the player and crawlers
  ignore sand, so Sand Strider was replaced by Dust Cloak (owner's choice).
- **Batch C: done in 0.12.0.** Greedy Lamp's arrows ring the digger instead of
  sitting at the screen edge (so they never fight the HUD); the owner has not
  seen it yet and may want edge arrows instead. The relic plan is complete.
- **Dropped or held:** Hot Core (hurt you while drilling: rejected), Gnaw Ward
  (replaced by Hard Hat), Anchor Charm (held: the owner is unsure about bolts),
  "greater" relics (wait until the pool is bigger).
- The owner likes relic pairs being a lucky find. Making them easier to find
  (sonar or map marks) is a "maybe later".

## Enemy plan (agreed with the owner)
- **Batch 1: done in 0.15.0** (shielded brute, flier).
- **Batch 2: done in 0.16.0** (burrower, bomb-eater, spore pod).
- **Batch 3: done in 0.17.0** (eel, slag salamander). The enemy plan is complete.
- Frequencies the owner asked for: brute uncommon but met several times a run;
  flier and bomb-eater rare; the rest tied to their zones.
- Show the owner a screenshot of each new enemy next to the digger.
- 0.14.0 to 0.17.0 were pushed with "[skip ci]" (the owner was still testing
  the 0.13.0 APK). The next push the owner wants a build for must not skip CI.

## Explosives follow-ups (0.13.0 built the plan; these are what is left)
- The owner has not played 0.13.0 yet. Prices, carry limits, rocket life and
  speed, mine timings and the upgrade multipliers are first guesses in `Balance`.
- 0.14.0 added QUICK FUSE, ROCKET DRIVE, MINE SENSOR and BLAST SHIELDING
  (`Balance.DEMO_UPGRADES`, applied in `Mine.spawn_charge/spawn_rocket/
  mine_trigger/explode`) and mine chaining (`Mine._chain_mines`). The owner
  did not want more than one remote charge out. Crawlers do not avoid mines,
  on purpose (owner agreed).
- The owner had not played 0.13.0 when 0.14.0 was pushed, so 0.14.0 was pushed
  with "[skip ci]": the newest APK is 0.13.0 until the next normal push.
- "Kit shop": buying extra lures. The owner is not keen on shears and bolts.
- Not done: the counter's slot buttons show 4-letter names only (the
  full name and description appear once a type is in a slot).

## Open items and ideas the owner liked
- **Zone guardians:** one optional boss arena per zone, beaten by using that zone's terrain against it. Proposed: start with Dustworks and Spore Veins. This was my top recommendation. The owner asked for details, then chose breakers first.
- **Physics puzzle vaults:** templates checked by a solver, guarding rare relics.
- **Choice rooms and a trader.**
- **Crawlers and breakers walk through sand piles** instead of over them.
- **A purple liquid** would be its own substance (an optional third fluid), never tinted water.
- **Vault signs** in the deep stage have no lore. The owner said lore isn't needed yet.
- **Unbuyable kit:** shears, bolts and lures can't be bought or upgraded yet.
- **Owner's earlier feedback still to apply when it comes:** HUD button tweaks, and pressure and rack tuning after playtests.
