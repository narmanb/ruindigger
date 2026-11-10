# Changelog

## 0.5.0 (in progress, not released: see docs/PHASE4_HANDOFF.md)
- **Wider world.** The Dustworks and Spore Veins now sit above an unbreakable bedrock shelf. Trek to its far-west or far-east end to descend: west into the Drowned Aqueducts (flooded stone channels, floodgates, cisterns), east into the Crystal Hollows (tall cracks, geodes, hanging shards). Both wings meet in the Forgotten Engine vault, where the relic is. A lift station waits at each wing entrance.
- **Dig-first.** Below the Dustworks most generated ladders are gone. Route sections are bare drops, plank scaffolds or plugs of cracked rock you drill through.
- **Rubble Ladder.** Breaking rock fills a scaffold meter; LADDER raises a ladder from your feet up to the first solid block. New Scaffold Hopper upgrade.
- **Fairness.** A new dig-aware check proves every mine can be finished with starting gear, that both wings are reachable, and that there is no spot you cannot climb out of. It found and fixed real trap pockets.
- **Camera** zooms in (1.4× by default, adjustable 1.0–1.8×) and looks ahead of you.
- **Touch controls:** floating stick, fixed stick or 8-way d-pad; stick size and dead zone; a layout editor to drag every control anywhere.
- **Full-screen map:** tap the minimap for a paused survey map with pinch/wheel zoom, panning, zone names and landmark names.
- Fix: the Spore Veins relay lift could be left hanging in mid-air when a route shaft cut through its floor (7.5% of mines). Lift floors are now protected, and a test checks every lift.
- New generated art and ambience for both new biomes.

## 0.4.0
- Generation v2 (see `docs/generation-v2.md`). Mines are planned: 8–11 chambers in distinct shapes (timber works, halls, slumped terraces, fissures with rope ladders, a cathedral with a lake, twin and stacked alloy ruins). The route runs through some of them, and the rest are optional side caverns linked by branches and loops.
- New landmarks: floodgate reservoir (breach the outlet to flood the chamber below), flooded machinery, hanging gallery of loose boulders, survey post, gas vent cluster, twin cistern. Every mine has a meaningful water encounter in the Spore Veins.
- Geological ore: chamber-wall seams, fault veins, a fossil band, and hint cells that lead into richer pockets. Crawlers are placed by role (guards, patrols, wanderers).
- Water features are sealed and their basins checked for leaks, so the mine starts calm. Generation never needs its repair fallback across a 500-combo sweep.
- Tools: `tests/gen_report.tscn` sweep + metrics, richer `gen_dump` overlays, screenshot harness `at=lm:<kind>` / `at=ch:<archetype>`.

## 0.3.1
- Fix: the settings panel opened off-screen (top-left) on both the title screen and the pause menu. It now centres itself and shrinks its list on short screens. The pause layout hides while settings is open. A regression test was added.
- Water: puddles on a floor run toward the nearest edge and pour over it quickly, instead of dribbling for seconds. Lip cells over a drop draw as a stream attached to the pool, not a hanging lump. Droplets from the same spout are bridged, so thin trickles draw as one continuous thread. Faster pours (24 units per tick).

## 0.3.0
- New liquid renderer (`src/fx/water_renderer.gd`). Water cells and droplets draw as soft shapes into an off-screen density buffer, and a shader thresholds it into one smooth liquid surface. No cell seams; pools flow into waterfalls seamlessly; streams merge. It adds depth shading, a surface highlight, waves and caustics.
- Water sits behind the rock tiles, so its edges always meet rock cleanly. A faint masked copy in front of the player, plus a blue tint, makes swimmers look submerged.
- Tunnel back-walls and cave decor moved to their own layer behind the water.

## 0.2.2
- Water polish from on-device video. No more wedge-shaped spout under drain holes, no light band through a pool above its drain, and entering water now splashes instead of puffing smoke.
- Unstable ceilings telegraph: loose rubble held by a thin layer trickles dust, and a toast warns when a ceiling starts to give way.

## 0.2.1
- Smooth water. Free-falling water now leaves the grid as droplets with gravity and momentum, so it pours in continuous streams, arcs off ledges, splashes and merges back into the pool.
- Pools draw a blended, continuous surface. Levels ease instead of stepping, and a shader adds rolling waves and caustic shimmer.

## 0.2.0
- Movement is about 35% faster with snappier acceleration and faster ladders.
- Drill fixes: drilling up now reaches the ceiling of a 2-cell tunnel. The drill bites and holds you while you tunnel up or cling to walls.
- Crawlers: the drill does twice the damage, every hit staggers and shoves them, bites have a visible 0.4 s wind-up, they show a health bar, and water hurts them.
- New physics: flowing cellular water (sealed flooded pockets, lakes, swimming, drill cooling) and falling basalt boulders that drop when nothing anchors or supports them.
- Richer generation: worm tunnels, an abandoned rail tunnel, crystal geodes, hanging boulder traps, flooded treasure pockets, a lake, and basalt stabilisation.
- New tests: water, boulders, upward drilling, drill combat, boulder crush, flooding and swimming. Generation also checks water at rest and no unsupported basalt.

## 0.1.0 (first playable)
- New from-scratch implementation. No code was carried over from earlier attempts in this repository.
- Deterministic asset pipeline (`tools/assetgen`): terrain atlas (13 material/stratum blocks × 16 edge masks × 16 texture windows), crack stages, ore/gas overlays, back walls, player/drill/crawler/sentry/relic sprites, props, three-stratum parallax, outpost skyline, 46 synthesised SFX and four ambient loops.
- Chunked destructible terrain: authoritative grid, incremental redraw, greedy-merged per-chunk physics, one-way platforms, additive emissive layer.
- Seeded three-stratum mine with a timber shaft, relay lift, ruin halls, sealed relic chamber, three set pieces, a guaranteed route, and a traversal proof checked in both directions.
- Player: run, variable jump, coyote time and buffer, air jet, wall slide and wall jump, ladders, drill with aim assist and heat, demolition charges.
- Burrow Crawler (noise, sight, bounded BFS, tunnelling, stun) and Ruin Sentry (warn → burst → cooldown, power module, rubble kill).
- Gas vents and clouds with ignition, telegraphed ceiling collapse with a bounded cascade.
- Outpost hub with upgrades (drill, heat sink, cargo, hull), contracts and a supply locker. Results screen, pause with full map, settings, multi-touch controls, gamepad and keyboard.
- Test suites (terrain, save, UI layout, a 60-seed generation sweep, gameplay integration), plus CI for tests, a debug APK and a Linux build.
