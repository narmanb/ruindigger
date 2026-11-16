# Handoff: state of Ruin Digger (read this first in a new session)

Last updated at version **0.11.0** (Android code 24). **`main` is the
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
`structures` separately. All are green at 0.11.0. Wrap Godot in `timeout`: a
parse error makes a headless run hang. The screenshot harness is
`tests/shot.gd`; useful args include `deep=1`, `at=lm:<kind or NAME>`,
`decor=<kind>`, `sandtest=1`, `kitdemo=1`, `pourtest=1|2`,
`drill_left=1 stopat=N back=N`, `touch_mode=1`, `gadget_bar_open=0`,
`allrelics=1`, `cargo_open=1 [cargo_end=1]`,
`--resolution 1846x852` (the owner's phone ratio).

## What exists (newest first)
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
- **Batch C (next, 0.12.0):** Dowsing Rod (water pockets show on the minimap through
  rock within ~20 cells, tinted as "sensed"; the minimap already shows water you
  have seen), Greedy Lamp (edge-of-screen arrows to the nearest unseen,
  reachable ore within ~30 cells, coloured by ore; cost: smaller light and
  faster pressure; needs the UI layout checks), Cartographer's Eye (zones you
  have visited are fully drawn on the map).
- **Dropped or held:** Hot Core (hurt you while drilling: rejected), Gnaw Ward
  (replaced by Hard Hat), Anchor Charm (held: the owner is unsure about bolts),
  "greater" relics (wait until the pool is bigger).
- The owner likes relic pairs being a lucky find. Making them easier to find
  (sonar or map marks) is a "maybe later".

## Open items and ideas the owner liked
- **Zone guardians:** one optional boss arena per zone, beaten by using that zone's terrain against it. Proposed: start with Dustworks and Spore Veins. This was my top recommendation. The owner asked for details, then chose breakers first.
- **Physics puzzle vaults:** templates checked by a solver, guarding rare relics.
- **Choice rooms and a trader.**
- **Crawlers and breakers walk through sand piles** instead of over them.
- **A purple liquid** would be its own substance (an optional third fluid), never tinted water.
- **Vault signs** in the deep stage have no lore. The owner said lore isn't needed yet.
- **Unbuyable kit:** shears, bolts and lures can't be bought or upgraded yet.
- **Owner's earlier feedback still to apply when it comes:** HUD button tweaks, and pressure and rack tuning after playtests.
