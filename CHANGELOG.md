# Changelog

## 0.7.0 (feature/fun-pass; see docs/plans/fun-pass-plan.md)
**Loot economy**
- The ore rack holds **60** units to start (upgrades 90 / 130 / 180).
- **Deeper ore is worth more.** Ore is graded by the zone it was mined in: Spore Veins x1.3, Aqueducts and Hollows x1.7, Forgotten Engine x2.3, The First Civilization x3.5. The manifest and results show the grade (e.g. "Cobalt x1.7").
- **Swap up when full.** With a full rack, touching better ore drops one unit of your cheapest ore (it stays on the ground as a pickup) and takes the better one. Cheaper ore is left alone.

**Orders**
- Every dive comes with **3 orders**, picked from what that map really holds: bring back some cobalt, aetherite or fossils; extract a set value of ore; reach a deeper zone; recover a keepsake; kill foes with the terrain.
- Progress shows top right. Finished orders pay on extraction and are lost if you die.

**Pressure: the mine wakes up**
- A new **PRES** meter rises the longer you stay, faster in deeper zones, and with drilling and blasts. It eases off while you are above the deepest zone you reached.
- At 30 / 60 / 85 the mine goes **RUMBLING / UNSTABLE / COLLAPSING**, and events come every 42 / 26 / 15 seconds. Every event warns you first:
  - **Tremor:** a nearby ceiling dribbles dust, then comes down. Below the top tier, never directly over you.
  - **Gas:** gas seeps from the rock nearby.
  - **Swarm:** crawlers come for the noise from off screen (at most 5 alive at once).
- Half of the pressure carries into The First Civilization.

**The terrain is a weapon**
- **Lures:** 3 per dive. Press USE with nothing nearby (on touch, the USE button reads LURE) to throw a pinging beacon. Crawlers within 18 cells drop what they are doing, even a chase, and go to it. Lead them under loose rock, into deep water or into steam. Lures do not raise pressure.
- Crawlers drown in deep water and are scalded by dense steam.
- Kills by rubble, boulders, gas, lava, water, steam or floating props are **terrain kills** ("TERRAIN KILL - crushed").

**Run relics (rare loot)**
- Every map hides **2 run relics** (The First Civilization hides 1): glowing rune stones on small plinths, usually far from the spawn. Take one with USE and it changes the rest of the run:
  - **Muffled Treads:** crawlers hear your drilling at half range.
  - **Prospector's Charm:** every ore seam drops one extra unit.
  - **Ember Heart:** lava and steam burn you at half strength.
  - **Calm Stone:** the mine wakes 35% slower.
  - **Iron Spine:** +40 hull, repaired now.
  - **Quick Coil:** gadgets recharge twice as fast.
- Relics carry into The First Civilization and are listed in the cargo manifest.

**Gadgets**
- Pack one **active** and one **passive** gadget at the Supply Locker.
- Active gadgets use the new **GADGET** button (G / V on keyboard, left-stick click on a pad, and a touch button labelled with the gadget). They recharge after use.
  - **SONAR** (22 s): a ping reveals the map within 24 cells and marks ore, gas pockets and loose rock for 7 seconds, even through walls.
  - **CRYO** (28 s): a thrown canister bursts on contact. It crusts lava into rock, clears steam, freezes foes for 5 s and vents your heat if you are close.
- Passives:
  - **MAGNET:** ore is pulled in from three times as far.
  - **PLATING:** falling rock does half damage.
  - **COOLANT:** drilling builds 30% less heat.
- The HUD shows the gadget's state ("SONAR READY" or a countdown) and your passive.

**Dive modifiers**
- On the contract board you can pick up to **2 modifiers** for the next dive. Each makes the dive harder and pays a bonus on ore credits:
  - FLOODED: brimming water pockets and basins, +20%
  - BRITTLE: the mine wakes 60% faster, +25%
  - SWARM: 80% more crawlers, +30%
  - GASSY: twice the gas pockets, +20%
  - BLACKOUT: darker caves, +30%
  - DEEP VEINS: +40% ore, but the mine wakes 30% faster
- The results screen shows the modifiers and what they paid.

## 0.6.3 (feature/first-civilization)
- **The First Civilization's halls are no longer empty.** Each great vault now has a theme that sets its name and what stands in it:
  - **FIRST HALL**: seated stone colossi on plinths with faintly glowing cores; one has lost its head, which lies in the hall.
  - **HEAT WORKS**: old furnaces with glowing, flickering mouths and gauges, chimneys up to the ceiling, hot pipes along the roof.
  - **CONDUIT**: two power lines across the hall with pulses of light running along them, and blinking junction boxes.
  - **STILL HALL**: machine husks kneeling where they shut down, heads bowed; their eyes still flicker now and then.
  - **DEEP ROAD**: rails along the floor, abandoned crystal carts (some tipped over) and signal lamps.
  - **ARCHIVE**: tall racks of record slates, some still lit, some fallen, plus a supply cache.
- **Arrival hall:** the wrecked lift cage lies where it crashed, sparking, with its snapped cables hanging down the shaft.
- **Lower transit:** the long transit tunnels have rails, abandoned carts and signal lamps.
- **Transit Gate:** two pylons flank the gate. They glow dimly while the gate has no power and pulse brightly once the Thermal Plant is running.
- Vaults are themed by depth: the vault nearest the arrival is always the First Hall, the plant level leans toward Heat Works and Conduit, and the transit level toward Deep Road and Archive. Repeated themes get a numeral (for example "DEEP ROAD II").
- All of it is background scenery: it never blocks you, sits behind rock, water and lava, and only animates while on screen.

## 0.6.2 (feature/first-civilization)
- **Lava pouring into water spreads instead of stacking into a pillar.** A heavy stream of lava now sinks through the water, or spreads sideways under it along the floor, before it crusts. Thin dribbles harden into slag that builds up and only becomes a block once a full cell's worth has gathered, instead of every drop turning into its own block. New rock that lands on a pile slides off its sides into the water, so it builds a low mound.
- **Less water lost per reaction.** How much cooling a lava cell needs now depends on how much lava is in it: a thin film crusts quickly and uses little water, and a full cell still takes a full cell of water. A cell touching water on several sides no longer boils more than it needs.
- Loose crust left over open space (the water under it boiled off or drained) now drops instead of hanging in mid-air.
- **Steam no longer hangs inside water.** Steam made under water bubbles up and comes out at the surface.
- Fixed brown "dust clouds" floating in pools: freshly formed crust was mistaken for a loose boulder and shook dust off itself (and rumbled the screen) while it sank. Rock formed under water no longer gives off a dust puff.

## 0.6.1 (feature/first-civilization)
- **Crust founders.** New rock from a lava/water reaction is heavier than both liquids, so it sinks through them unless it is held at the shore (attached to rock on one side within 3 cells, or wedged across a gap of 7 or less). Fresh lava keeps meeting the water: wide pools boil for a long time, throw off big steam plumes and fill with rock from the bottom, while narrow channels still crust over into bridges.
- **Water floats on lava.** Water used to sink through lava cells and react at the bottom of the pool; now it rests on the surface, where the reaction happens.
- Each rock block now takes a full cell of water (was 48 units), and steam is denser with a higher cap (700 cells).
- **More lava and water** in The First Civilization: more water and lava pockets, more water-over-lava pairs, more lava pits, and new **sluices**: lava sealed above a water pool. Drill the divider and watch it pour down, crust, sink and boil the pool.

## 0.6.0 (in progress on feature/first-civilization; see docs/primordial-vault-status.md)
- **The First Civilization.** A new, optional, one-way stage far below the Forgotten Engine: a separate 200×120 map of great vaults, buried machines and transit tunnels built by a civilization far older than the Engine.
- Find the Ancient Descent Platform in the Engine vault. It warns you, asks you to confirm, and does not come back. Everything you carry stays at risk.
- The only way out is the Transit Gate near the bottom. Leaving through it banks the whole run plus a bonus.
- **Lava, steam and new rock.** Lava is a slow, heavy second fluid. Where water meets it, the lava crusts into drillable rock and the water flashes to steam. Breach a cistern over a lava pit to build a bridge, or plug a lava flow with water. Lava burns on contact (on a steady cadence, never instantly) and dense steam scalds.
- **Geothermal power.** The Transit Gate has no power until you restart the Thermal Plant: open the heat valve to pour lava into the intake and the coolant valve to fill the condenser. The engine's lamps, the gate and the compass tell you what is missing. Mistakes are recoverable: crusted lava can be drilled and valves can be closed again.
- **Smooth lava.** Lava is drawn as one continuous molten body (the same soft-field technique as water) instead of square cells: rounded edges, a slowly bulging surface, thick rounded pours, drifting dark crust with glowing seams.
- **First Light**: a unique keepsake found only in the lower transit level of The First Civilization (250 CR on extraction).

## 0.5.6
- Add an explicit CARGO button below the depth panel; keep Cargo Manifest in Pause and show the build version on the pause screen.
- Hold Down and press Jump to drop through a wooden platform. Lower platforms and solid rock still catch you.
- Remove periodic timber-shaft bars and unsupported or tiny ladder fragments. Keep short landings at room exits and cave walls instead of broad planks across natural caverns; retain necessary Engine maintenance scaffolds.

## 0.5.5
- Cargo manifest: tap the cargo HUD, press I, or choose CARGO MANIFEST from Pause to inspect ore icons, quantities, unit prices and the exact extraction total. The game pauses while inspecting cargo; touch and D-pad scrolling are supported.
- Five optional zone keepsakes: Miner's Token, Glowspore Sample, Engine Cog, Aqueduct Seal and Crystal Bloom. Recover each with TAKE; they use a separate pouch and pay only on successful extraction.
- Keepsakes have unique glowing markers and short descriptions in the manifest and results. Their placement is deterministic and checked for reachability and a way back to the lift.

## 0.5.4
- Add optional Touch stick vertical assist: reduce sideways drift during mostly vertical pushes, preserving deliberate diagonals. Off by default; gamepad and d-pad unchanged.

## 0.5.3
- Show a clear LADDER ATTACHED badge while climbing.
- Fix overlapping ambience fades stopping the newest track.
- Audit drill and gas sound cleanup after extraction, death and abandonment.

## 0.5.2
- Fix extraction hum continuing after leaving the mine.
- Place wooden chamber posts on their floor.
- Add an optional falling jump-to-grab ladder setting, with re-grab prevented until clear.
- Steady mostly vertical touch input while climbing; preserve deliberate sideways exits.

## 0.5.0
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
