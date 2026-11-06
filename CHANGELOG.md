# Changelog

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
