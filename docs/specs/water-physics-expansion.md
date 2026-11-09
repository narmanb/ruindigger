# RUIN DIGGER: Water Physics & Environmental Interaction Expansion

**Project:** [narmanb/ruindigger](https://github.com/narmanb/ruindigger)  
**Target:** Godot 4.6.x / GDScript / Android-first, landscape, touch and gamepad  
**Primary features:** (1) water pressure, (2) directional currents, (4) erosion, (5) debris, floating objects and movable props  
**Purpose:** Implementation brief for a coding agent such as Codex or Claude

---

## 1. Assignment and decision-making authority

Expand RuinDigger's existing water and destructible-terrain mechanics into a **coherent, interactive physics ecosystem**. Water should have meaningful motion and force; moving water should reshape susceptible terrain; drilling should sometimes leave convincing rubble; and selected debris/props should float, sink, tumble, be carried by currents and respond to the environment.

**Do not replace the existing water visuals merely to satisfy this spec.** The current flowing sheets, waterfalls, connected streams, surface appearance and water interactions are features the player likes. Preserve and build upon their appearance wherever possible.

**You are explicitly authorized to examine the repository and choose better implementation approaches** than those proposed below. The suggested algorithms, data structures, thresholds and file locations are guidance, **not mandatory architecture**. If investigation reveals a simpler, more performant, more robust or more Godot-idiomatic approach, use it. Preserve the intended behavior, compatibility and performance, and explain significant departures in your handoff. Likewise, adjust the suggested order if the codebase makes another sequence safer.

This is a request to **implement** the features, not merely produce a design proposal, if you have the repository and an editing environment. Do the work on an appropriate feature branch or pull request; do not silently overwrite a more recent work branch. Make sensible game-design decisions without stopping for routine approval. Clearly disclose any unimplemented portions.

### Core design principles

1. **Scale forces to actual physical circumstances.** Not every reservoir should explode outward; not every trickle should move the player.
2. **Use consistent interactions.** The same moving water can push the player, carry lightweight objects and erode weak terrain.
3. **Protect playability.** Digging should feel satisfying, not create endless chores or unavoidable damage. Water and rubble must not permanently softlock the mine.
4. **Keep mobile performance.** Use bounded simulations, local updates, pooling and distance-based detail where appropriate.
5. **Prefer emergent outcomes.** Avoid hard-coded set-piece scripts when the physical rules can produce the result themselves.
6. **Preserve current gameplay.** Drilling, mining rewards, gas, boulders, enemy behavior, relic retrieval, lifts, contracts, touch controls and upgrading must continue working.

---

## 2. Existing implementation: inspect before editing

The newer code that was inspected lives on branch **`ccr-79c19570-j1j312`**. At the time of review, **`main` was an older, structurally different implementation**, so do **not** assume that the default branch contains the water system discussed here. Verify all current branches and commits, find the latest intended playable version, and work from that. Branch names and code may have changed since this brief was prepared.

Relevant files in that newer branch include:

| File | Function in the inspected implementation |
|---|---|
| `src/terrain/water_sim.gd` | Water levels in terrain cells, active-cell updates, lateral leveling, sheet-flow seeking edges, falling droplets and deposit/splash behavior. |
| `src/fx/water_renderer.gd` | Smooth, connected water presentation using an off-screen density field and droplets. |
| `src/fx/water_composite.gdshader` | Surface, depth and caustic-like effects. |
| `src/terrain/terrain_grid.gd` | Authoritative terrain/material and water arrays, cell change signals and chunk-dirty tracking. |
| `src/terrain/terrain_view.gd` | Chunked rendering and static collision rebuilding for modified terrain. |
| `src/player/player.gd` | Drilling, player movement, underwater swimming and water-based drill cooling. |
| `src/hazards/hazards.gd` | Explosives, toxic gas, loose-rubble collapse and falling boulder behavior. |
| `src/hazards/boulders.gd` | Unsupported basalt mass detection. |
| `src/gen/mine_generator.gd` | Seeded caves, dams, water pockets, lakes, routes and set pieces. |
| `src/world/mine.gd` | Coordination of terrain edits, water, damage, enemies and events. |
| `src/autoload/balance.gd` | Gameplay tuning constants. |
| `AGENTS.md` | Local coding/build/test conventions that should be followed. |

**Observed details, not assumptions about every future revision:**

- A grid cell is 16 px; a water cell stores 0 to 64 units.
- Water settles in active cells; the inspected tuning used a 0.06-second water tick and a 2,400-cell work budget per step.
- Falling streams become droplets, with a cap of 900 simulated droplets; they can flow into and refill cells below.
- The water renderer uses soft merged shapes and a shader for a connected appearance; this is worth preserving.
- Existing swimming changes player gravity/speed and allows upward strokes.
- Loose rubble and unsupported basalt masses are already implemented, **so new drilling debris should extend or coexist with those systems without duplicating all their responsibilities**.
- `TerrainGrid` is the authoritative terrain state, and destructive gameplay normally goes through `Mine.damage_cell(...)` for ore, gas and collapse side effects.
- Terrain collision is chunk-based. Do not substitute a rigid body for every solid tile.

Read `AGENTS.md`, the current README and tests in the chosen working branch before implementation. The source is the authority where it differs from this brief.

---

## 3. Feature 1: water pressure and reservoir breaches

### Desired experience

Water pressure should be **situational**. Breaching a small or shallow pocket causes a spill or modest flow. Breaking into a deep reservoir through a lower wall can create a concentrated, forceful jet. A wide breach releases more total flow than a pinhole, but a pinhole may still make a fast narrow jet. As the water level falls, the force naturally fades.

**Do not decide whether a reservoir is powerful from its total size alone.** Important factors are:

- **Hydraulic head:** the vertical height of connected water above the breach.
- **Opening geometry:** the number and position of open cells and whether the flow can exit freely.
- **Supply and drainage:** how much connected water can reach and sustain the opening, including choke points upstream.
- **Downstream obstruction/submergence:** a free jet into open air behaves differently from two already-equalized pools connected by a passage.
- **Time:** an initially powerful surge should weaken as its head and available supply decline.

### Examples to achieve

| Situation | Intended behavior |
|---|---|
| Tiny, shallow pocket breached near its surface | Water trickles/spills; negligible gameplay knockback. |
| Moderate pocket with a side opening near the bottom | Noticeable gush; modest push if the player stands in the jet. |
| Tall connected water column behind a thin wall | Strong initial jet; player and lightweight debris may be pushed back. |
| Very large but shallow lake with a small side breach | Sustained drainage, not automatically a violent jet. |
| Reservoir level drops below the breach | Outward pressure stops or becomes ordinary residual flow. |
| Large opening widened by additional drilling | Greater discharge and possibly wider push area; no magical water creation. |
| Two similar water levels on either side of an opening | Little or no sustained pressure differential. |

### Implementation guidance (flexible)

- Consider a **bounded, cached connected-water-component / hydraulic-head approximation** triggered by breaches and significant terrain changes, instead of a full Navier–Stokes solver.
- For a candidate opening, estimate upstream free-surface height, local water supply and effective head; derive target discharge and outflow velocity. Keep the formula tunable rather than treating these suggestions as fixed physical constants.
- Give water leaving a pressured side breach a **horizontal velocity component** (and appropriate visual jet/spray). Do not limit all pressure releases to vertical waterfalls.
- Couple discharge to actual water movement: **conserve volume**. A forceful jet cannot be cosmetic while the reservoir remains unchanged, and water should not teleport past intervening rock.
- As the reservoir drains or the opening grows, recompute or invalidate the cached head/flow representation. Avoid doing expensive world-wide flood fills every frame.
- Distinguish **jet velocity** from **total momentum/discharge**. A tiny high-pressure jet can be fast but affect only a narrow area; it should not have the same whole-body knockback as a wall-sized flood.
- Consider transient breach effects (spray, audio, screen feedback) that scale with flow strength and decay naturally.
- Ensure the output integrates with existing water rendering and droplet/cell transfer rather than fighting the renderer.

**Important:** The current cellular water simulation is not a real pressure solver. The goal is a convincing, stable approximation with mass conservation and meaningful gameplay outcomes, not computationally expensive fluid dynamics.

---

## 4. Feature 2: currents, waterfalls and force on characters

### Desired experience

**Still water should not push the player.** A small falling trickle should barely matter. A narrow fast stream can exert a modest directional force, a strong waterfall can push downward, and a major flood through a confined passage can drag the player and carry loose objects.

| Water state | Player response |
|---|---|
| Still lake or settled pool | Normal swimming, no directional drift. |
| Sparse dripping or thin waterfall | Splash effects; almost no displacement. |
| Modest stream | Slight drift; easy to walk/swim against. |
| Sustained strong channel flow | Noticeable movement, but player retains control. |
| Fast waterfall/flood surge | Strong directional push, possibly temporary loss of footing, not an automatic stun lock. |

### Mechanics

- Derive a **local flow vector and intensity** from actual water transfer, pressure-driven discharge and falling-droplet momentum. A smoothed/recent flow field per active region is one possible solution.
- Avoid interpreting a full, motionless water cell as a strong current. Distinguish **quantity present** from **quantity moving**.
- Scale player force by **flow intensity, submerged/contact fraction, direction, exposed cross-section and player resistance**. Account for narrow jets versus broad water contact.
- A large amount of water funneled through a tight passage may produce stronger local flow than the same discharge through a wide pool; do not use volume alone as a force multiplier.
- Support downward waterfalls, sideways channels and changing directions as tunnels are carved.
- Blend current forces into the existing `Player` movement, swimming, jumping and wall-grip/drill-grip behavior. Avoid camera jitter or fighting direct player input every physics frame.
- Allow the player to resist ordinary flow; only exceptional floods should overpower movement temporarily. Add smoothing, maximum force/velocity clamps and brief grace where needed.
- Apply the same approximate flow system to enemies and physical debris where it makes sense, modified by individual mass/drag/buoyancy.
- If a current carries the player toward dangerous terrain, ensure hazards remain avoidable/readable rather than instantly unavoidable.

### Feedback

- Flowing foam, droplets, bubbles, splashes, directional movement of debris and audio should make strong current direction legible.
- Keep beautiful continuous water sheets and streams. Effects should react to the simulation, not substitute for it.
- Little trickles should look like little trickles.

---

## 5. Feature 4: water-driven erosion

### Desired experience

Sustained moving water should **gradually wear down vulnerable terrain**. Merely being submerged in a stationary lake should not dissolve a wall. Erosion should be an understandable process: water movement, particle shedding, visible wear, then possible breakage or collapse.

### Material behavior (initial design, tune by testing)

| Material | Reaction to flowing water |
|---|---|
| Soft sediment/soil | Erodes under sufficient sustained flow. |
| Cracked/fragile wall | Can weaken and eventually breach, depending on exposure and flow. |
| Loose rubble/gravel | May wash away or shift; coordinate with the debris system. |
| Basalt | Very resistant or fully immune in the first implementation. |
| Ruin alloy | Immune. |
| Bedrock/protected terrain | Immune. |
| Gas sac | Not necessarily eroded; preserve its intentional rupture behavior. |

### Suggested mechanics

1. Estimate **erosive exposure** on an exposed face, using a smoothed local flow magnitude and/or shear-like measure. Flow across a tile's face should matter more than nearby water sitting still.
2. Apply a per-material threshold, buildup rate and optional recovery/decay. Do not erode terrain on the first frame of a passing wave.
3. Show rising damage through particles and the existing crack/damage presentation if possible. An active waterfall might gradually undercut a sediment support.
4. When material finally breaks, use **existing terrain-damage pathways** so ore crediting, gas behavior, collapse detection, visual updates and collision rebuilding remain correct.
5. Eroded material may produce some dirt/gravel debris, according to the new debris rules. It should never create ore twice.
6. New holes redirect the water, which may erode nearby terrain and trigger existing supported-mass and falling-rubble rules.
7. Bound chain reactions and per-tick terrain edits; let cascades unfold over time instead of allowing one frame to rewrite half the map.

### Examples

- A waterfall washing over a sediment ledge slowly cuts through its edge.
- A long strong current undercuts a fragile wall or support, eventually dropping a previously supported basalt mass.
- A newly formed opening sends water down a different tunnel, potentially exposing fresh vulnerable material.
- A calm submerged wall remains intact indefinitely unless another mechanic damages it.

**Gameplay guardrail:** Preserve generator-protected structures, lift areas and guaranteed critical navigation. Dynamic cave-ins and erosion must not create unwinnable runs. Prefer natural consequences with emergency recovery or route safeguards to blanket immunity everywhere.

---

## 6. Feature 5: drilling debris, rubble, buoyancy and movable props

### A. Material-specific debris when drilling or blasting

When a player drills a wall, its material should **sometimes remain physically represented** instead of always vanishing entirely. The amount varies by material and by event. Some destroyed cells leave no persistent debris; others leave a modest pile; a few leave more. This should be somewhat varied but consistent enough to feel intentional.

| Destroyed material | Expected result |
|---|---|
| Soft sediment | Dust, small clumps, occasional lightweight dirt pile. |
| Basalt | Sharp chips, a few small rocks, occasional larger heavy chunk. |
| Loose rubble | Gravel/pebbles, sometimes a small accumulating scatter. |
| Cracked wall | Stone shards and dust; occasionally an actual stone fragment. |
| Ruin alloy | Sparks/metal shards; occasional scrap item or weighty piece where appropriate. |
| Gas pocket | Gas eruption and particles, generally little persistent solid debris. |

Separate these into **three tiers**, to preserve both performance and useful interactions:

1. **Visual-only particles:** Cheap, brief, pooled and non-colliding. Most fragments belong here.
2. **Lightweight persistent piles/fragments:** Some remain on floors, slide/settle, may be washed around and do not require individually expensive rigid-body simulation. They should generally be easy to traverse or drill through. Merge nearby piles if useful.
3. **Full physical props:** Limited larger stones, crates, canisters, barrels, abandoned equipment or salvage. They have meaningful position/velocity, collision and water interactions. Use a controlled budget.

**Do not turn ordinary drilling into mandatory cleanup.** The newly exposed tunnel should usually remain passable without drilling the material a second time. Persistent piles should not bury the player, interfere with standard controls, block ladders or make extraction inaccessible.

### B. Water interaction and buoyancy

For relevant props, define data such as approximate **mass, drag, buoyancy/density, collision size, damage threshold, material and persistence level**. Then use those characteristics consistently:

- Wood/empty crates: float, bob, rotate, travel with currents, collect at obstacles.
- Small dirt, chips and lighter rubble: sink slowly, roll/slide, possibly be washed downstream.
- Heavy stones and metal fragments: sink quickly and resist small currents.
- Hollow or sealed containers: may float despite looking metallic.
- Different objects should react differently when swept by waterfalls or blasted by explosive charges.
- Buoyant objects can bump and accumulate against terrain or each other within sensible collision and count limits.
- Water levels falling should leave the objects stranded realistically rather than teleporting them to the floor.

A lightweight approximation using tile-water sampling and limited physics bodies is acceptable. Accurate fluid displacement is not a requirement. **Do not spawn hundreds of RigidBody2D objects for every mined tile.** Prefer Godot 2D physics for a manageable number of meaningful props and lighter-weight solutions for fragments/piles.

### C. Environmental placement and discovery

Scatter a modest number of suitable props during world generation, not only as drilling byproducts. Examples:

- Old wooden crates in an abandoned miner camp.
- Small salvage containers in ruin passages.
- Stone fragments and abandoned equipment near cave-ins.
- Floating debris trapped inside flooded rooms.
- Occasional larger physical stones where the terrain can support and accommodate them.

Keep props visually consistent with their biome and the game's pixel-art direction. Start with a restrained variety, then add more if they genuinely improve play.

### D. Emergent interactions to make possible

- Drill through basalt; chips scatter and a larger stone lands at your feet.
- Break open a reservoir; small fragments are carried off while the large stone stays put.
- A wooden crate floats through the tunnel, temporarily catches on the stone and later rises over it as the water deepens.
- A current pushes a light prop toward an enemy.
- Explosions move nearby physical props and create suitable debris without runaway object counts.
- A sustained stream can transport loose sediment, possibly depositing it elsewhere **if** that can be done cheaply and without compromising paths. Full granular material simulation is optional, not required for this phase.

---

## 7. System integration: build interactions, not four unrelated effects

The desired feedback loop is:

```text
A wall is drilled / an opening forms
      ↓
Water volume and flow routes update
      ↓
Pressure release or ordinary currents emerge
      ↓
Players, enemies and physical objects respond to moving water
      ↓
Vulnerable exposed terrain erodes; loose material moves
      ↓
Terrain and support geometry change
      ↓
New flow routes, boulder collapses, debris movement, hazards
      ↓
Repeat naturally within budgets and safeguards
```

Practical integration guidance:

- Avoid independent systems each computing contradictory versions of the same water motion. If possible, expose an authoritative query such as `sample_flow(world_position)` or an equivalent local vector/intensity API.
- Couple water transfers to the existing `WaterSim` or a well-justified replacement. Preserve volume accounting and visible streaming.
- Keep water amounts, terrain edits, contact forces and visuals temporally coherent. Prevent obvious one-frame surges and jitter.
- For terrain modification, use the repo's legitimate runtime mutation/damage APIs; do not directly edit `mat`, `ore` or other backing arrays behind event handlers.
- Preserve existing collapse, boulder and explosive semantics; coordinate new debris spawn hooks so one broken cell does not spawn two conflicting sets of rubble.
- Respect protected terrain, ladders/platforms, generated routes, relic chambers and extraction lifts.
- Consider interactions with enemy movement/AI and existing gas systems, but do not require a whole gas overhaul in this task.
- Centralize designer-facing balancing values in `src/autoload/balance.gd` or the project's current equivalent.

---

## 8. Suggested staged implementation

This ordering is preferred because it makes each addition observable and testable. Change it if source inspection reveals a safer dependency order.

### Phase 0: inspect and baseline

- Confirm which branch actually contains the latest water visuals and the game build used by the player.
- Read `AGENTS.md`, `README.md`, simulation, renderer, terrain mutation, generation, player movement, hazard code and tests.
- Run the current test suite and, if possible, get a baseline Android build and gameplay performance sample.
- Write down any pre-existing failures rather than attributing them to your changes.

### Phase 1: water motion data / currents

- Add a trustworthy bounded representation or query of **local water motion** (direction, speed/intensity and amount of moving water).
- Make the player respond smoothly to currents and waterfalls; add resistance and maximum-force limits.
- Optionally apply the same current data to enemies where safe.
- Ensure still water and small trickles remain mild.
- Preserve existing water visuals and swimming.

### Phase 2: pressure-aware breaches

- Estimate connected water head, available supply and opening shape.
- Produce stronger, directed discharge when appropriate; connect it to water volume and motion data.
- Update visuals/sounds for powerful breach jets; make surge intensity decline as water drains.
- Reuse Phase 1 forces to push characters and, later, props.
- Validate conservation and geometry edge cases.

### Phase 3: material-aware drilling debris and physical props

- Add material-specific visual particles and restrained persistent debris.
- Add a small set of physics props with mass, drag and buoyancy; integrate with currents, explosions, gravity and terrain contact.
- Procedurally place some props in fitting locations.
- Cap/pool/merge/deactivate objects to protect Android performance.
- Ensure regular digging stays fast and tunnels remain passable.

### Phase 4: erosion and cascading interactions

- Add sustained-flow erosion for appropriate materials.
- Drive breakage through existing damage and collapse hooks.
- Connect erosion to debris and flow rerouting; cap cascades.
- Verify guaranteed paths and protected structures.

### Phase 5: polish and tuning

- Tune low/mid/high flow thresholds, force resistance, erosion times, debris probabilities and densities.
- Add informative sounds/FX: spray, trickle, surge, gravel movement and erosion wear.
- Examine stress scenarios, memory usage and device performance.
- Provide a clear changelog, tests, build artifacts and known limitations.

The implementation may be delivered as separate incremental commits or PRs. **Do not sacrifice stable water rendering or existing game behavior just to claim all four boxes are complete.**

---

## 9. Performance requirements

This is an **Android-first game**, intended for phones and a **Retroid Pocket 5** as well as desktop. Favor a stable, responsive play experience over full physical accuracy. Target smooth 60 fps where practical on the player's devices, and report measurements rather than claiming an untested target.

- Preserve the active-water-cell optimization; static pools should be very cheap.
- Reuse the existing droplet cap and tick budgets as baseline guardrails unless profiling supports a better configuration.
- Prefer event-driven local invalidation for new pressure/connected-component calculations. Avoid full-world rescans at physics-frame frequency.
- Restrict expensive erosion checks to wetted, exposed terrain near **active motion**, not every solid cell in the map.
- Avoid persistent rigid-body simulation for fine gravel/dust. Aggregate, pool, freeze or despawn as needed.
- Simplify far-off-screen prop behavior where it does not affect important downstream events; never silently violate persistent gameplay consequences.
- Cap simultaneous physical debris and particle emitters; use tunable limits and reasonable overflow behavior.
- Keep collision rebuilding localized and avoid multiple redundant terrain edits per frame.
- Avoid per-frame creation/destruction of expensive textures, collision bodies, data arrays and new shader resources.
- Profile worst cases: a very large reservoir breach, several moving props, waterfall-induced erosion/cave-in, and prolonged mining.
- Add debug counters or diagnostic display for active water cells, droplets, pressure-region work, active props and erosion edits if it helps tuning. These should not clutter the shipped HUD.

Suggested initial limits should be treated as **tuning candidates** rather than promises. The existing code's simulation budgets should guide choices.

---

## 10. Level generation, fairness and game feel

The existing generator has carefully designed traversal guarantees and protected structures. These are more important than realistic geology.

- Preserve seeded/deterministic map generation and existing invariant tests.
- Ensure water pockets/lakes remain valid and interesting with the new flow rules.
- Avoid spawning physical objects embedded in terrain, directly in players/enemies, or on essential access paths.
- Use modest set-piece variation to showcase physics organically: a dam near a side tunnel, a debris-filled flooded room, a fragile sediment overhang near running water, crates beside an abandoned station.
- The environment can be dangerous, but provide **readable warnings and opportunities to react**, especially for flood knockback and erosion-triggered collapses.
- Prevent irreversible blockade of the guaranteed route, ladders, lifts and relic access. Use protected geometry, non-blocking piles or recoverable debris as appropriate.
- Do not let ordinary water friction make traversal tedious. The player should feel in control in calm water and everyday small streams.
- No new required controls unless unavoidable; use existing touch/gamepad actions.
- Retain the underlying mining/extraction/upgrade loop. Do not turn the game into a water puzzle game exclusively.

---

## 11. Tests and acceptance criteria

Extend the existing suites instead of relying only on visual inspection. Use the precise commands and harnesses in the selected branch's `AGENTS.md` / README.

### Water physics tests

- [ ] Water quantity is conserved across pressure-driven openings, lateral transfer, falling droplets and re-deposit, except for documented edge-loss cases.
- [ ] Tiny shallow breach produces negligible gameplay impulse.
- [ ] Tall/deep connected reservoir produces a stronger initial outflow than an otherwise equivalent shallow one.
- [ ] A larger breach permits greater discharge when enough water is available, without creating extra water.
- [ ] A high-head but tiny jet affects a narrow area instead of knocking back everything nearby.
- [ ] Pressure/current diminishes appropriately as the level falls or the pressure differential equalizes.
- [ ] Still settled water produces approximately zero directional push.
- [ ] A light trickle produces negligible player knockback.
- [ ] Strong sideways flow pushes in the appropriate direction; waterfalls exert mainly downward force.
- [ ] Player can swim/move normally in still water; common currents remain manageable.
- [ ] Water cannot flow through intact solid terrain, protected barriers or closed gates.
- [ ] Existing water appearance is not regressed: smooth pools, sheets, continuous waterfalls and surface rendering.

### Erosion tests

- [ ] Stationary submerged sediment does not continuously erode.
- [ ] Moving water below threshold does not meaningfully erode material.
- [ ] Strong sustained water erodes exposed sediment over time.
- [ ] Non-erodible/protected materials remain intact.
- [ ] Erosion uses normal breakage hooks; ore is paid once and gas/collapse events occur normally.
- [ ] Erosion can redirect water and trigger legitimate support loss without infinite cascades.
- [ ] Generated route/lift/relic invariants remain valid across seed sweeps and representative destructive scenarios.

### Debris and props tests

- [ ] Different materials yield different categories/probabilities of debris; not every broken cell leaves a permanent pile.
- [ ] Debris visually comes from the broken surface, falls/settles, and does not spawn inside the player or solid terrain.
- [ ] Wooden/light props float; heavy stones/metal sink or resist weak currents.
- [ ] Props move in strong currents and respond reasonably to explosions and collisions.
- [ ] Drilled passages remain navigable; persistent debris cannot permanently block required routes.
- [ ] Debris/prop limits work under sustained drilling and repeated explosions.
- [ ] No duplication of ore or collectible rewards and no conflict with existing falling rubble/boulders.

### Integration and platform tests

- [ ] All existing automated tests still pass, or failures are documented with reproduction steps and justified fixes.
- [ ] Godot scripts parse; scenes load; no obvious runtime errors or resource leaks.
- [ ] Generated mine seed sweep still meets the existing generation guarantees, including zero route repair fallbacks where required by current tests.
- [ ] Android landscape touch controls, gamepad and desktop keyboard inputs still work.
- [ ] Worst-case waterfalls, flood surges, many props and erosion cascades are profiled; frame time and object counts are reported.
- [ ] Android APK / CI build succeeds if the environment is configured. If not, report the exact blocker rather than stating it was built.

A useful manual demonstration scene or reproducible seed for each feature would be appreciated, provided it doesn't create substantial throwaway complexity.

---

## 12. Deliverables for the coding agent

1. **Implemented code** on a feature branch or reviewable PR based on the correct latest game branch, with staged commits if useful.
2. **Brief technical summary** of architecture and which systems now communicate with each other.
3. **Gameplay summary** describing shallow spills, high-pressure breaches, streams, waterfalls, erosion, drilling debris and buoyant props.
4. **Relevant tests** and the actual commands/results obtained.
5. **Performance findings**, especially any Android/mobile limitations and how particle/prop budgets behave.
6. **Build or CI artifact link** for Android if available through the repository workflow; never claim an APK exists unless exported or confirmed by CI.
7. **List of remaining limitations and future ideas** only after describing what was actually completed.

### Out of scope for this pass

A full pixel-by-pixel sand simulator, advanced lava/steam chemistry, global gas-fluid simulation, fully destructible machinery, deformable soft bodies and unrestricted rigid-body terrain are **not required** here. Their future compatibility is welcome, but concentrate on the four requested features first.

### Final intent

The game should support moments like this **without special-case scripting**:

> The player drills through a sediment wall beside a reservoir. Water first seeps through a small opening; as the breach widens, a larger surge enters the tunnel and pushes the player back. The current carries small fragments of rock downstream while a heavy boulder remains. A wooden crate floats out of the chamber and lodges against an obstacle. The sustained water flow slowly undermines an adjacent sediment support, releasing a rock mass that changes the tunnel and redirects the water again.

These effects should emerge from consistent, bounded mechanics. **The objective is not a laboratory-grade fluid solver. It is a responsive, convincing, performant physics-rich mining game that feels fun on a phone or Retroid Pocket 5.**

**Agent discretion is encouraged:** after examining the latest codebase, implement a better approach than the one described here whenever there is a clear engineering or gameplay reason. The gameplay goals and regression safeguards matter more than the proposed internal design.
