# Ruin Digger Roadmap

Living document of planned improvements, ordered by theme. Nothing here is
committed to a release -- items move into CHANGELOG.md when they ship.

---

## Built in 0.20.0
Contextual hints, the codex with records, the run summary, and The Dry Dock.
The sections below for those are kept for reference.

---

## Contextual Hints (non-intrusive onboarding)

Small text lines that fade in the first time a player encounters something,
then never appear again. No tutorials, no menus, no "press A to continue."

- First time near water: "water flows into open space"
- First time near gas: "gas ignites near fire"
- First time overheating drill: brief overheat tip
- First time seeing ore: ore-value hint
- First time near a contract board / demolitions counter / mission terminal
- Stored in save so hints only show once per player, not once per run

Design rule: tied to the moment the info is relevant, disappears after a few
seconds, never blocks gameplay.

---

## Encounter Design (generation-driven)

Pre-designed small encounter pockets placed during generation, same footprint
system rooms and landmarks already use. Each is a deliberate layout that
showcases a specific enemy or hazard interaction.

Ideas:
- Dead-end chamber with a brute guarding a rich ore vein
- Flooded cave with eels (reward behind the water)
- Burrower nest in a pocket of soft rock
- Gas-filled room near explosive barrels or ore that sparks
- Spore pod cluster blocking a narrow passage
- Bomb-eater lurking near a placed explosive cache

Restraint: 1-2 per zone max so they feel like discoveries, not wallpaper.
Generation must respect existing fairness rules (DigCheck, GenSpace claims).

---

## Economy & Upgrade Pacing

Current upgrades are too easy to buy. The fix is more options at higher prices,
not stretching out the existing ones.

Desired curve:
- **Early upgrades** -- cheap, feel good, hook the player
- **Mid-tier upgrades** -- meaningful choices (blast radius vs. capacity?)
- **Late-tier upgrades** -- expensive aspirational goals that change playstyle

Concrete steps (when ready):
- Audit current upgrade costs vs. average credits-per-run
- Add more upgrade tiers / branches to existing tracks
- Introduce new upgrade tracks for systems that lack them
- Tune contract and mission rewards to match the new price curve
- Make sure no single run can buy everything -- progression should span many runs

---

## Touch Controls Simplification

The current button count (drill, jump, charge, charge2, interact, DIAG) works
for experienced players but may overwhelm newcomers.

Ideas:
- "Simplified controls" preset: hides DIAG and second charge slot by default
- Power users toggle extras on in settings
- Possibly auto-show buttons as players unlock the systems that use them
  (e.g. charge2 only appears after packing a backup explosive)
- Revisit button sizing and spacing based on play-test feedback

---

## Missions (fixed-seed maps, built on LakeGenerator's pattern)

Each mission makes one system the whole point of the map. Free to start,
failure loses what you carry (for now). Harder variants later (tighter budget,
pressure on, extra enemy type), like "High Water" for the lake.

Built: **The Dry Dock (sand)**, 0.20.0.

Picked for building:
- **Bull in a China Shop (brute):** a sealed vault the player cannot open.
  Lure a Shielded Brute into charging the wall. The enemy is the tool.
- **The Long Fuse (explosives):** fixed loadout of charges, remotes and mines.
  Build a chain reaction through blast-sensitive rock to open the main shaft.
  Optional score for using fewer explosives.

Considered, not picked yet:
- **Gas Works:** no explosives allowed; vent methane pockets, ignite one at
  the end.
- **Cave-In Rescue:** dig to a trapped miner without causing more collapses,
  then reach the lift together.
- **The Slag Run:** cross a lava field guarded by Slag Salamanders. Only if
  water on lava already makes stone (verify before building).
- **Salvage Dive:** collect artifacts on a deep map with a carry limit.

Order idea: lake (water), Dry Dock (sand), Long Fuse (explosives), so the
missions teach systems gradually without a tutorial.

---

## Molefolk Civilization, Reputation & Escalating Retaliation (proposed / unscheduled)

**Status:** Design concept only. Do not implement as one giant feature. Start with a
small, peaceful vertical slice and expand only after testing whether it improves
exploration. This should add personality, player choice, and systemic consequences
without turning Ruin Digger into a conventional combat game.

### Core fantasy and design rules

- Molefolk are a real, mostly peaceful underground civilization, **not enemies
  disguised as shopkeepers**. Discover them through digging: settlements, working
  mines, small camps, tunnels, and occasionally lone travelers or engineering
  crews. They have lives and routines independent of the player.
- Most Molefolk should be ordinary **civilians**: miners, builders, merchants,
  mechanics, families, and inhabitants carrying supplies or doing chores. Only
  some are guards or fighters. Their first response to danger is often to flee,
  hide, warn others, or protect someone, not immediately rush the player.
- They may be cute, slightly goofy, and useful when peaceful, yet unexpectedly
  resourceful and dangerous if the player persistently attacks them. The contrast
  is part of their identity.
- Interactions should be **optional**. Respectful players gain allies, trade
  opportunities, useful services, and occasional safe places to regroup.
  Aggressive players can rob, steal technology, or fight, but create a long-term
  enemy. Neither path should be a mandatory progression gate.
- The terrain, water, explosives, mining equipment, and player movement should
  matter more than raw attack damage. Avoid bolting on a full weapon/combat system
  just to support Molefolk.
- Avoid nonstop pursuit. Hostility should create memorable encounters and
  consequences, not erase the game's core rhythm of exploration and digging.

### Peaceful encounters and village life

- A rare/occasional generated settlement might have a small cluster of burrow
  homes, reinforced connecting tunnels, lanterns, stockpiles, shops or trading
  counters, a shared workshop, repair crews, and active miners. A settlement
  should feel discovered, not like a mandatory hub room in every level.
- Smaller sightings can be a two-mole survey team, a traveling trader, a
  miner carrying ore, a tunnel repair crew, or an isolated machine outpost.
- Ordinary residents should move between tasks and respond visibly to events.
  Examples: hauling rocks, operating pumps, fixing a wall, retreating behind a
  door, sheltering children, calling for help, or assisting a trapped friend.
  Favor a few convincing behaviors over large amounts of cosmetic simulation.
- Trade does **not** require Spelunky-style shopkeepers in regular levels.
  Purchases can happen in settlements, workshops, or from traveling merchants.
  Friendly trade should be meaningfully useful, not just a novelty.
- The player may help with small systemic problems (rescue someone, reopen a
  blocked tunnel, repair a seal, recover tools) rather than needing elaborate
  scripted dialogue/quests.

### Protect settlements from random world chaos

A major requirement: Molefolk villages must not be casually wiped out by normal
enemy pathing or unrelated procedural hazards. Their safety should be
**predictable**, especially before the player has had any meaningful interaction.

1. **Generation placement and space claims:** Reserve stable pockets using the
   project's existing generation/fairness mechanisms (e.g. GenSpace claims and
   DigCheck where appropriate). Keep initial settlements clear of dangerous
   water/lava reservoirs, gas pockets, enemy nests, major collapse risks, and
   hostile encounter placements. Validate approaches and exit routes.
2. **Believable defenses:** Reinforced walls, supported ceilings, drainage,
   sealed entrances, gates, and simple pumps should explain why the settlement
   has survived underground. NPCs can close gates and make repairs.
3. **AI and hazard protections:** Ordinary hostile wildlife should not routinely
   target or path into peaceful villages. Control nearby spawns, hazard
   propagation, and NPC vulnerability as needed so offscreen simulation does not
   kill settlements. Prefer systemic safeguards over unexplained invincibility.
4. **Meaningful player agency:** Do **not** make villages absolutely
   indestructible. If the player deliberately blows open a water barrier,
   undermines supports, drills through houses, or redirects a hazard toward
   them, the settlement can be damaged. Survivors should react, evacuate, and
   attempt repairs where feasible.
5. **Fair blame assignment:** A naturally occurring flood or an unrelated
   monster's attack must not count as the player's crime. Accidental minor
   digging/property damage should not trigger a civilization-wide vendetta.
   Deliberate repeated sabotage, theft, and attacks on residents are different.

### Reputation, warnings, crimes, and forgiveness

- Track the player's relationship/hostility with the Molefolk across a run.
  Distinguish acts such as ordinary trespass, accidental damage, repeated
  destruction, stealing, attacking, and killing civilians. Intent is imperfect
  in systemic games: use **reasonable signals** (direct hits, repeated
  targeted actions, warnings ignored, clear theft) rather than blaming the
  player for every indirect physics outcome.
- Let witnesses notice events, flee, and spread the word. This can be a simple
  delayed faction-state transition, not a full NPC communications simulation.
- Use visible feedback: suspicious looks, shouted warnings, guarded entrances,
  merchants refusing service, retreating families, wanted signs or alerts, and
  later active pursuit. Players should understand *why* hostility increased.
- An isolated mistake should be survivable. Offer warnings and chances to
  de-escalate. Persistent violence should have substantial consequences.
- Forgiveness/reconciliation can occur through long periods without new crimes,
  paying for damage, returning stolen goods, rescuing Molefolk, completing a
  helpful task, or other acts of goodwill. Severe crimes may need more effort.
  Do not force players into permanent hostile runs over accidental damage.
- Consider both **local settlement alarm** (immediate reactions) and **faction
  reputation** (later encounters) so one little disturbance does not instantly
  make every Molefolk everywhere a soldier. Exact thresholds are for playtests.
- Friendly NPCs should still have personality and may remember being helped;
  positive reputation must be as meaningful as negative reputation.

### Graduated hostility and retaliation

Suggested progression, **not fixed thresholds**:

1. **Peaceful:** Molefolk go about daily life, trade, work, and offer assistance.
2. **Suspicious/alarmed:** Witnesses warn the player, shops shut, guards appear
   near local entrances, civilians run or shelter. Minor acts remain repairable.
3. **Local defense:** A threatened settlement deploys a few armed defenders or
   desperate miners with tools. Ordinary civilians are *not* suddenly combatants.
4. **Hunting parties:** With repeated serious crimes, small specialized patrols
   track the player in later areas. They can dig alternate routes, approach
   from a wall, or coordinate flanking rather than blindly rushing straight at
   the player. Encounters remain intermittent.
5. **Engineering retaliation:** Molefolk begin building barricades, traps, and
   reinforced checkpoints along likely routes. The player might discover an
   active construction crew and disrupt it before the position is completed.
6. **Full hostility:** Occasional fortified outposts and specialized machinery
   or soldiers present the highest escalation. This is a **cap**, not a mandate
   for an infinite army or escalating health/damage forever.

- The faction's pursuit can persist toward deeper zones where it fits, but do
  not introduce constant spawn pressure. Fit frequency and difficulty to biome,
  travel routes, available resources, and the player having ways around it.
- Escalation should respond to repeat *deliberate* aggression, not merely the
  number of NPCs accidentally caught in an environmental chain reaction.
- Advanced fortifications should be **optional obstacles**, reasonably
  telegraphed, and breakable, avoidable, undermined, or disabled. Avoid sealed
  softlocks and unavoidable fights in cramped tunnels.

### Fighting *with the world*, not a conventional weapon arsenal

Ruin Digger's drill is a functional but limited direct attack. Treat that as
an identity rather than a problem to solve by adding a large list of guns.
Hostile encounters should support several approaches:

- **Outdig / outmaneuver:** Tunnel through walls, take alternate passages, or
  lure pursuit into unfavorable terrain. Enemy diggers may open their own
  routes, forcing positional decisions instead of health trading.
- **Water and pressure:** Breach a reservoir to sweep attackers into a pit,
  interrupt a patrol, or break a barricade. Experienced Molefolk engineers may
  deliberately divert water, open sluices, or flood a player's route.
- **Terrain and support failure:** Undermine a fort, remove a support, redirect
  falling debris, or trigger a controlled collapse. Prevent cheap unavoidable
  collapses, especially near protected civilian settlements.
- **Explosives and hazards:** Existing charge systems, gas, heat/lava, and other
  hazards can be clever tools (where those mechanics are actually available).
  Preserve counterplay and avoid requiring rare consumables.
- **Machinery:** Disable a generator, cut pump power, redirect an automated
  mining rig, lure an attacker into its path, or steal a useful component.
  Engineering encounters should be puzzles as much as battles.
- **Direct drill combat:** Remains a viable emergency solution, but need not
  be the most efficient or safest way to win.

Enemy variety can come from behavior and equipment: nimble tunneling scouts,
armored guards, builders repairing barriers, pump/sluice operators, and
machines—not just increasingly high HP. Give attacks warnings, cooldowns,
escape routes, and terrain counterplay. Avoid unfair offscreen flooding or
teleporting enemies into the player's face.

### Molefolk technology: friendship, trade, or theft

Molefolk should be expert underground engineers with useful **distinctive
tools** the player does not automatically have. This is a reward and
worldbuilding pillar, and provides a concrete reason to keep them friendly.

Possible items/services (ideas to test, not confirmed features):
- **Precision digging charges:** Controlled excavation with a shape or
  directional blast distinct from the player's standard explosives.
- **Temporary support beams / braces:** Stabilize passages, prevent a planned
  collapse, or protect infrastructure during a risky dig.
- **Portable pumps / water-control devices:** Drain a pocket, redirect water,
  or counter an engineered flood (subject to fluid-system feasibility).
- **Compact mechanical miners or drilling gadgets:** Short-lived assistants
  that excavate, collect a little ore, or operate a simple machine.
- **Repair or engineering services:** Fix a damaged device, reinforce a tunnel,
  recharge a specialist tool, or point out a useful route.

Good reputation could unlock merchant inventory, fair prices, workshop
services, or a rare gift. Hostile players might seize supplies from a patrol,
raid a defended workshop, or capture machinery, but stealing should carry risk
and usually cost them the safer trading route. Do not make aggression strictly
more profitable or friendship purely cosmetic. Coordinate with existing
economy and upgrade pacing; these should be choices, not mandatory power creep.

### Generation, pacing, and technical guardrails

- Start with sparse encounters; avoid a village on every floor. Vary settlement
  size and location. Respect existing generation placement rules, accessible
  routes, contracts/missions, and biome-specific hazards.
- Keep villagers safely contained to their settlement/working area unless
  explicitly traveling; avoid simulating complex civilian routines across an
  entire map when offscreen.
- Use lightweight faction state, simple behaviors, and capped patrols.
  Protect performance, especially on Android and during water/particle-heavy
  events. Limit simultaneous diggers, terrain edits, and pathfinding updates.
- Attacks, traps, floods, and construction must be telegraphed. The player
  should always have reasonable opportunities to flee, bypass, disable, or
  negotiate; surprise should not mean arbitrary punishment.
- The player should never have to murder civilians for progression, and
  indiscriminate violence should not be the assumed/default playstyle.
- Test edge cases: hazard generated near a village; accidental mining breach;
  predator enters through a player-dug hole; water simulation runs offscreen;
  Molefolk kill each other or damage their own buildings; a construction crew
  blocks the only exit; reputation increases from unintended physics events;
  late-run pursuit becomes a tedious swarm.

### Recommended phased rollout

**Phase M1 — Peaceful vertical slice**
One small, stable settlement or mining camp; a handful of noncombatant NPC
roles and basic reactions; optional trade of **one** distinctive useful tool.
Prove that discovering and interacting with them is enjoyable. No faction war.

**Phase M2 — Fair local hostility**
Warnings, panic/hiding/evacuation, local guards, a minimal reputation tracker,
clear crime feedback, and forgiveness for minor damage. Stress-test hazards
and unintended blame before adding persistent retaliation.

**Phase M3 — Limited pursuit**
One intermittent tunneling patrol/ambush type, with escape and terrain
counterplay. Evaluate whether it improves the game or interrupts exploration.

**Phase M4 — Engineering defenses**
Construction crews, disruptable checkpoints, and alternative ways to defeat
fortifications. Introduce more enemy/role variety only after encounter tests.

**Phase M5 — Systemic depth**
Expand water/terrain/machinery interactions, trading technology, repair or
reconciliation tasks, deeper-zone persistence, and balancing. Only add
features supported by actual playtests and existing technical capabilities.

**Non-goals for initial implementation:** Full civilian simulation, massive
warfare, elaborate scripted dialogue, a large weapon arsenal, guaranteed
Molefolk villages in every run, or an irreversible kill-on-sight state.

---

## Future Ideas (unscheduled)

- Optional tutorials accessible from the main menu (not required)
- Harder mission variants with pressure, deeper lakes, tighter budgets
- More relic variety and relic-driven build diversity
- Enemy encounter escalation tied to depth / zone progression
- Performance optimization pass informed by Perf recorder data
