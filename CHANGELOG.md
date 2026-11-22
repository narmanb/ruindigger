# Changelog

## 0.21.0-layout
**Experiment (branch `experiment/world-layout-same-size`): a wider upper mine, same map size.** Not on `main`. Same Android version code as 0.21.0, so you can install this over 0.21.0 and later put 0.21.0 back over it without uninstalling (your save stays).
- **The Dustworks and Spore Veins now use the whole width of the map.** They used to sit in a 72-cell column with solid bedrock on both sides, about a quarter of the map that nobody could enter. Now they are about 116 cells wide, like the wings below. The map is still 128 x 236.
- **Same entrance.** The surface lift room, the timber shaft, the relay station, both shelf gates and the relic chamber are exactly where they were.
- **Side caverns.** Each of the two upper zones tries for an optional chamber on each side, out in the new space, with its own tunnel back. The usual caves, worm burrows, landmarks, water pockets, gas, ore and crawlers spread into the new rock too.
- **A second way down.** Side caverns in the Spore Veins also tunnel to the shelf gate on their side, so you can come down the main trunk or swing out through a side cavern to that wing's gate.
- **Not inflated.** Ore and crawler counts are budgets per zone, so they spread over the wider rock instead of growing with it. The extra side caverns bring their own small ore seams, and the Spore Veins get one more crawler so the wider caves aren't empty.
- **Relic choice pairs** now go to the first relic spot with room beside it, or to the best other spot that has room (they were only ever tried at one spot, which in the wider layout was often a cramped burrow).
- **Fix (also affects normal mines):** the hidden passage from a survey post could cut through a sealed water reservoir's wall, draining it while the mine was being built and once taking 10 seconds to generate. It now stops at sealed walls.

## 0.21.0
**Game feel polish**
- **New setting: Game Feel Intensity** (Settings, under Screen shake): Off, Subtle, Normal (the default) or Strong. It controls the extras added in this update: drill recoil, impact dust, the landing bounce, and the new camera knocks. Off turns all of them off and leaves everything else as it was. Screen shake keeps its own slider; at 0 the camera never shakes, whatever this is set to. Reduced Flashing still caps flashes at Strong, and Low Effects still turns the decorative extras off.
- **The drill pushes back.** When the bit meets rock, the arm is knocked back a couple of pixels and springs back. Sediment gives a little, basalt more, and rock you can't cut (bedrock, alloy, protected walls) shoves hardest, with sparks and no chips, so it never looks like it's doing damage. Breaking through gives a last snap. Only the drawing moves: aiming, targets, dig speed and heat are exactly the same. The spring never overshoots, so the drill tip never pokes past where it really cuts, and it behaves the same at 30 and 60 FPS.
- **Rock breaks by material.** Sediment breaks with more dust and a soft puff; basalt and harder rock break into chunks. Chips while drilling are lighter on sediment and heavier on hard rock.
- **Smoother, smarter camera shake.** The shake now wobbles smoothly instead of jumping to a new random spot every frame, and it's capped. A blast's shake depends on how far it is: a charge going off next to you shakes as before, one at the edge of the screen less, and one far off screen not at all. Bigger blasts (a bomb-eater) shake a little more than small ones (a shear charge).
- **Blasts are sized.** Small blasts make a smaller burst; big ones a second fireball and more debris. At Normal and Strong a wider ring of dust and a spray of chips go with the bigger ones.
- **Rockfalls land with weight.** Rubble and boulders landing near you kick up dust and give a short knock. When a dozen blocks land at once, the camera takes one knock instead of twelve.
- **Heavy landings.** A long fall squashes the digger's sprite for a moment and puffs up dust; a really hard one gives a small knock. Fall damage and controls are unchanged.
- **Water breaches.** When a strong jet of water first bursts out near you, it splashes in the direction it's going, with a small knock. A stream that keeps running stays quiet.
- **Gas fireballs** flash a little brighter at Strong (Reduced Flashing caps it). **Kills** get a small finishing burst; a brute or a sentry also gives a small knock.
- **Effects fixes:**
  - Asking for a bigger or smaller burst of particles now actually changes the size (before, every burst was the same size, whatever was asked for).
  - A flash light reused for a new flash could be switched off early by the old flash's fade. Fixed: each light belongs to its newest flash.
  - Low Effects used to drop half of all effects at random, warnings included. Now it keeps every effect but makes each one smaller, and drops only the decorative extras. Hazard warnings (dust from a crumbling ceiling, loose basalt about to drop, a breaker gnawing, a burrower breaking through, a gas vent) always show.
  - Effects far off screen are skipped, and the decorative extras have a small budget per frame, so a big chain of explosions can't pile up hundreds of emitters.
- Not added: "hitstop" (freezing the action for a split second on a big hit). The water, sand and lava keep running in real time, and freezing them, even briefly, risked more than it added.

## 0.20.0
**The codex, hints, a run summary, the Dry Dock mission, a meaner bomb-eater, and ladders that break**
- **CODEX** (title screen and the pause menu). Tabs for Creatures, Hazards, Explosives, Relics, Zones, Records and Hints.
  - A creature's page only opens once you have killed one (a kill by falling rock, gas, water or a fall counts). Everything else opens the first time you run into it: a zone when you enter it, a hazard when you meet it, an explosive when you use it, a relic when you take it. A short "CODEX: Eel added" notice says so.
  - **Records:** dives, extractions, deaths, best depth, best haul, credits earned, kills, terrain kills, most kills in one dive, ore broken, ladders built, explosives used, longest dive, missions done with your fastest time, and pages found.
  - **Hints:** every hint you have seen, to read again.
- **Contextual hints.** Short lines for new diggers: how to drill, that ore goes in your rack, what a full rack does (better ore swaps in for your cheapest; no need to leave), drill heat, diagonal steps, rock you can't dig, sand, water, lava, gas, collapses, your explosive button, the lift, relics, and the outpost counters.
  - Each one shows **once per save**, one at a time, with about 15 seconds between them, and they wait while you are being hurt or chased.
  - They sit in a small strip under the top of the screen, away from the player and the touch buttons. If the camera is zoomed in so far that the player is up there, the strip moves to the gap between the stick and the buttons.
  - Settings: **Hints** on/off, and **RESET HINTS**. The old timed tips on your first dives are gone (the hints replace them).
  - The one-off creature messages ("THE BRUTE STUNNED ITSELF", "A SPORE POD BURST", ...) now show once per save instead of every time the game starts.
  - Enemies are not explained when you first see them: find out, then read the codex after the kill.
- **Run summary** on the results screen. After a death: what killed you, where and when ("Killed by toxic gas in Spore Veins, 3:12 in."), what hurt you in the last 10 seconds, and your damage taken by cause. After an extraction: how long it took and the damage you took. New records are called out ("NEW RECORD: BEST HAUL").
- **Mission: The Dry Dock** (opens after The Sunken Lake, 400 CR). An old dockyard: a bedrock pit cuts the dock hall's floor in two and the lift is on the far rim, with no power.
  - Three sealed sand hoppers sit above the dock. A service tunnel runs right under them; each hopper's plug is the sediment in the tunnel ceiling over a grate. Drill up into a plug (or blast it), step off the grate, and the hopper pours down its chute into the pit.
  - **Goal: fill the pit with sand.** The HUD points to it ("DOCK 37%"). One hopper is not enough. When it is full the lift powers up, and the sand is your bridge: walk across.
  - Watch where you dig: a sealed pocket of sand over the tunnel buries it if you open it. Four crawlers roam the galleries; the mine stays calm.
  - Sand keeps moving in this mission even if Sand physics is Off in Settings.
- **The bomb-eater got meaner.** It now eats any explosive you have placed that hasn't gone off: charges and sticky charges (while their fuse burns), remote charges and mines. Drill rockets are safe.
  - After swallowing one it looks normal for a second. Then its belly pulses red, faster as the end nears, and it comes for you (a bit faster than before: 5.4 cells a second; you run about 9.5). After 7 seconds it blows, **wherever it is**, near you or not.
  - Its blast is a fixed size, bigger than a charge (4.5 cells; an un-upgraded charge is 3.2), and your Demolitions upgrades don't change it.
  - Kill it before it eats, or get away: outrun it, or cut it off with water, lava or a collapse. Killed with a bomb inside, it still blows where it falls.
  - **It climbs ladders** (no other enemy does on a bare ladder): body along the ladder, head the way it is going.
- **Blasts break ladders.** Any blast (yours, gas, a bomb-eater) destroys the ladder cells it reaches, even the mine's own ladders. The part of the ladder above the blast loses its footing and tumbles down in pieces, which are gone when they land. The part below stays. If you are on the part that falls, you fall too. Drilling still leaves ladders alone.
- **Sand fixes (everywhere):**
  - Sand resting on rock now falls when you dig the rock out from under it (it used to stay hanging).
  - Sand that landed on you and stopped now carries on falling once you step away (it used to stay stuck above you).
  - Walking up a pile more than one cell tall no longer catches on a little invisible ledge between its rows.

## 0.19.0
**Diagonal drilling**
- **Aim up and forward while drilling to dig diagonally.** The drill cuts a step: the cell ahead of you at chest height, the space above it, and the headroom over you. Once the step is clear it hops you up onto it. Keep holding and you climb a staircase at 45 degrees, through sediment, rubble or basalt. It is built in, no upgrade needed.
  - Keyboard: hold the drill key with up and left or right (W + D / A, or the arrow keys). Gamepad: drill with the left stick pushed up and to one side. Touch: drill with the stick pushed up and to one side.
  - You still need ladders for sheer shafts and long climbs: a staircase needs rock to cut into, and it moves you sideways as you go up.
  - Each tick it drills three cells, so it heats the drill a little faster than drilling straight ahead.
- **Optional DIAG touch button** (Settings > Diagonal drill button; off by default). Hold it to drill diagonally up in whichever direction you are facing, with no stick needed. It sits in the bottom row of the touch controls and can be moved in the layout editor. Keyboard: U.

## 0.18.1
**Sunken Lake tuning**
- **Both lake missions now ask you to fill the bed to the top** (it was 60% and 75%). The top row of water never lies perfectly level, so 98% of the bed counts as full and shows as 100%.
- **Less water above.** The Sunken Lake had about 2.7 bed-fulls of water in the cavern; it now has about 2 (you can still skip a good half). High Water has about 1.5, so you have to drain most of it.
- **High Water's bed is deeper:** 18 rows instead of 14, so it holds about a third more.
- **The powered lift moved** out of the bed, which would now drown it, into a dry alcove cut into the east wall just above the bed's rim. A ladder climbs to it from the bed.

## 0.18.0
**Missions, the Sunken Lake, and a performance recorder**
- **A MISSIONS terminal at the outpost** (the far left, beside where you start). Missions are separate from contracts: fixed maps with their own goal, free to start, and the same map every time. Your explosives, gadgets and upgrades come with you. If you die, you lose what you were carrying, as on a contract. Each pays a reward the first time and half that on repeats.
- **Missions unlock as you go.** A mission can need earlier missions done, a depth reached on a contract dive, or a number of upgrade levels bought. The terminal shows what is still needed.
- **Mission 1: The Sunken Lake.** A Dustworks cavern, wide at the top and full of trapped water: great lakes, pools, pockets and puddles, some sealed in rock and some open like ponds. Even the dry galleries have a film of water you splash through. Below it, the cavern narrows in bedrock steps to a dry lake bed centred at the bottom, so released water runs to the middle.
  - **Goal: fill the lake bed to 60%.** Drill and blast channels so the water runs down. The HUD points to the bed and shows how full it is ("LAKE 37%").
  - When it is full enough, the lift on a ledge beside the bed powers up. Ride it out to complete the mission (300 CR).
  - The mine stays calm: no pressure in this mission. Two eels live in the biggest pools.
  - Patches of grass, reeds and moss grow on the damp floors, most of all beside the water.
- **Mission 2: The Sunken Lake: High Water** (locked). A different cavern, less water to spare, a fill mark of 75%, four eels, and the mine wakes while you work. It opens once you have completed the first and reached 130 m on a contract dive. 650 CR.
- **Splashing.** Walking through shallow water now splashes with every step, everywhere in the game.
- **Performance recorder** (Settings > Record performance; off by default). While it is on, each dive is measured: frame times, the slowest frames and what was happening at each one, how long the water, sand and lava take, and how many droplets, sand cells, enemies and falling rocks there are, every 2 seconds. It also notes your phone model, screen and settings. It only watches; it changes nothing in the game.
  - To send me a report: tap **COPY PERFORMANCE REPORT** on the results screen (or in Pause during a dive, or in Settings) and paste it into our chat. Each report is also saved as a text file on the phone.
  - A long dive's report stays small enough to paste (rows are merged after about 20 minutes).

## 0.17.1
**Fixes from the first phone playtest**
- **Crawlers no longer hang in the air.** When the rock a crawler was clinging to collapsed or was dug away, it stayed where it was, stuck. It now falls until it finds a surface again. A drop of 3 cells or more hurts it (8 damage for 3 cells, 8 more for each cell after that), so a long fall can kill it, and that counts as a terrain kill ("fell to its death"). This applies to crawlers, breakers, burrowers and bomb-eaters. Enemies that fly or swim are not affected.
- **Water droplets no longer hang over sand piles.** A droplet that ended up inside a cell more than half full of sand could not soak in and stayed there for good. It now moves to the open space beside the sand and runs off the pile. No water is lost.
- **The drill rocket is your drill.** It now looks like the digger's own drill bit, with an exhaust flame. Firing one sends the drill off your arm: the arm is bare for a moment and a new drill grows back in half a second. You can't drill until it has.

## 0.17.0
**The last two new enemies: the Eel and the Slag Salamander** (the third and final enemy batch)
- **Eel (water).** A pale eel with a cyan frilled fin and a blue glowing belly.
  - **In water it is dangerous:** fast (you are slow in water), and it bites for 18. It swims freely through deep water, and water does not hurt it.
  - **Out of water it is helpless:** it flops along slowly, bites for 6, and takes double damage. After 4 seconds out it turns back for its pool and starts to dry out; its belly light gutters.
  - **Drain its pool and it is stranded:** breach the wall or drill the floor. It dries out and dies, and that counts as a terrain kill ("left high and dry").
  - 45 hull. Up to three in the Drowned Aqueducts' pools, one in another zone's water, two in The First Civilization. Maps with less water have fewer.
- **Slag salamander (The First Civilization).** A lizard of dark crusted slag, split by glowing orange cracks.
  - It lives in lava and climbs out to hunt. Lava and steam do not hurt it. Bites for 16.
  - Out of lava for 8 seconds it cools: it slows, its cracks go dark, and it heads back.
  - **Water or a cryo canister sets it into stone.** A quarter-cell of water in its cell is enough: lure it through a puddle, or open a tank over it. It leaves a block of rock where it stood, **with aetherite in it** (drill it out). That counts as a terrain kill ("turned to stone"). It never sets into a block on top of you.
  - 50 hull. Up to four, each starting in lava.
- **All seven planned enemies are now in:** shielded brute, flier, burrower, bomb-eater, spore pod, eel and slag salamander.
- **Crawlers track you better.** A chasing crawler was meant to re-plan its route every 0.45 seconds, but it only re-planned once its current route ran out, so it would run to where you had been. It now re-plans on schedule. This applies to crawlers and breakers as well as the new enemies, so expect chases to be a little sharper.
- Fixed before release: a bomb-eater going for a bomb could freeze when it caught sight of you. It now ignores you until it has eaten.

## 0.16.0
**Three more enemies: the Burrower, the Bomb-eater and the Spore Pod** (the second of three enemy batches)
- **Burrower.** A blunt, armoured mole-worm with a steel grinding head and no eyes.
  - **It comes for noise.** It hears drilling and blasts from twice as far as a crawler. It is blind: it only notices you directly within 4 cells, through rock or not. Stop making noise and it loses you.
  - **Rock is no shelter.** Where a crawler needs an open path, a burrower chews straight through sediment, rubble, cracked rock and basalt, and leaves a tunnel behind. You see the rock crack and spill dust before it breaks through. Basalt takes it about a second per cell, sediment a third of that.
  - It never digs alloy, bedrock, protected rock, ore, gas sacs, bolted rock, or rock that is holding back water or lava.
  - 60 hull, bites for 16. One in the Spore Veins, one in the Drowned Aqueducts, two in the Crystal Hollows, two in The First Civilization.
- **Bomb-eater (rare).** A squat green scavenger with a pot belly and a huge jaw.
  - It smells a proximity mine, or a remote charge waiting for its signal, from 14 cells away. It walks to it and swallows it. Mines do not go off for it.
  - Then its belly blinks with the bomb's light and it runs at you. Beside you it beeps for 0.7 seconds and blows.
  - Killed with a bomb inside, it blows where it falls: kill it from a distance, or set your remote charge off before it gets there.
  - Without a bomb it is a weak crawler (30 hull, bites for 6). One per main mine, one in The First Civilization.
- **Spore pod (Spore Veins).** A drifting purple puffball with trailing roots and a green glow inside.
  - It floats slowly toward you and, beside you, swells for 0.9 seconds and bursts into a gas cloud. It has no bite; the burst itself does not hurt, the gas does if you stay.
  - Drilling one bursts it into gas as well.
  - **A blast or a fireball sets its gas alight at once**: a fireball instead of a cloud. That burns whatever is next to it, crawlers and other pods included, and you if you are close.
  - 12 hull. Five in the Spore Veins.
- Fixed before release: about half the time a burrower slid through solid rock without digging it. It now always chews a cell out before moving in.
- Like the brute and the flier, all three are placed on the finished map from a seeded stream after the brutes and fliers, so world generation is unchanged and existing brute and flier positions did not move.

## 0.15.0
**Two new enemies: the Shielded Brute and the Flier** (the first of three enemy batches)
- **Shielded Brute.** A hunched beetle, a little taller than you and more than twice as wide, behind a scarred steel plate that covers its whole front. Its back is soft and pale, with glowing vents.
  - **The plate stops your drill and your blasts from the front**: only 15% gets through, with sparks. Hits on its back do full damage.
  - **Ways to beat it:** jump over it and drill its back (it takes half a second to turn around); drop a ceiling on it (falling rock ignores the plate, does heavy damage and stuns it); stick a charge to its back or let a blast go off behind it; or bait its charge into basalt.
  - **It shoves** with the plate when you are in reach (24 damage, after a visible wind-up).
  - **It charges** when you are 4 to 9 cells ahead on its level: it braces for 0.7 seconds while red dashes light up along the floor, then runs. A charge goes straight through sediment, rubble and cracked rock. Charging into basalt or alloy stuns it for 2.5 seconds, and while it is stunned the plate is down.
  - It walks on floors, steps up one-cell ledges, falls off edges and smashes through sediment in its way. It cannot climb ladders or shafts. It hears drilling and blasts, like crawlers do.
  - A blast's short shock does not stagger it. Gas clouds, lava and steam get past the plate.
  - 180 hull. It drops 4 scrap and 2 cobalt.
  - **Where:** one in each zone below the Dustworks (Spore Veins, Drowned Aqueducts, Crystal Hollows, Forgotten Engine) and two in The First Civilization. Never within 30 cells of where you start.
- **Flier (rare).** A moth-drone with tattered teal wings and one amber eye. It hunts like a crawler but flies, so open shafts and caverns don't stop it. It is fragile (18 hull: one good drill hit), bites for 8, and can't dig. Two per main mine, one in The First Civilization.
- Brutes and fliers are placed on the finished map from their own seeded stream, so world generation and its fairness checks are unchanged, and a seed always gets the same ones.
- Art for both is made by the art generator, like the crawler's.

## 0.14.0
**More Demolitions upgrades, and mines that chain**
- Four new upgrades at the Demolitions counter, two levels each. The counter shows what you have now and what the next level gives.
  - **QUICK FUSE** (120 / 260 CR): demo and sticky charges go off sooner: 2.2 s, then 1.8 s, then 1.3 s.
  - **ROCKET DRIVE** (160 / 340 CR): drill rockets bore for longer before they blow: 1.6 s, then 2.1 s, then 2.6 s.
  - **MINE SENSOR** (150 / 320 CR): level 1 makes proximity mines sense foes 40% further away. Level 2 also makes your mines ignore you: they arm under your feet and you can walk over them. Their blast still hurts if you are standing close.
  - **BLAST SHIELDING** (170 / 360 CR): your own explosives hurt you 30% less, then 60% less.
- **Mines chain.** Any blast that reaches a proximity mine sets it off after its short beep, whether or not it has armed: your charges, rockets, other mines and gas fireballs. A line of mines goes off one after another.
- Crawlers still don't avoid mines, on purpose.

## 0.13.0
**Explosives and the Demolitions counter**
- **A new DEMO terminal at the outpost** (between the Contract Board and the Supply Locker). Explosives moved here from the Supply Locker, which now only handles gadgets.
- **Five explosives.** Sticky is now its own type instead of an upgrade with a toggle.
  - **Demo charge** (25 CR): bounces and rolls, then blows. As before.
  - **Sticky charge** (35 CR): sticks to the first rock, ceiling or foe it touches.
  - **Drill rocket** (45 CR): flies straight the way you face (or up / down if you aim), boring a tunnel you can walk through in sediment, rubble and basalt. It blows after 1.6 seconds, or at once on a foe or on anything it can't cut (alloy, bedrock).
  - **Remote charge** (40 CR): throw it and it waits, with no fuse. Press the same button again to set it off. One can be out at a time.
  - **Proximity mine** (35 CR): laid at your feet. It arms after a second, once you have stepped away (amber light, then blinking red). After that, the next foe to come near sets it off after a short beep. So do you, if you walk back onto it.
- **Two slots per dive.** Pick a main explosive and, if you like, a backup. The main slot comes with free units every dive (2 demo charges, or 1 of any other type); the backup only has what you buy. Bought units of types you don't pack wait at the outpost.
- **One button each, side by side.** With a backup packed, the CHARGE button splits into two half-width buttons in the same space, each with its type's icon, short name and count. No toggling. Keyboard: K / C for the main slot, H / N for the backup. Gamepad: LB / LT for the main slot, right-stick click for the backup. With no backup, the screen looks exactly as before.
- The status panel shows both slots as a short name and a count when two are packed.
- **Upgrades at the counter** (each one capped):
  - **BIGGER RACK** (3 levels): carry more of every type. This is the old Charge Rack; demo charges still go 6 / 8 / 10 / 12.
  - **BLAST POWER** (2 levels): x1.25, then x1.5 damage to rock and foes.
  - **BLAST RADIUS** (2 levels): x1.15, then x1.3 reach.
  - Power and radius apply to all five types. They don't change shear charges or gas explosions.
- **Old saves carry over.** Your Charge Rack level becomes BIGGER RACK, packed charges stay packed, and if you owned the Sticky Charges upgrade its 240 CR is paid back.
- Supply caches in the mine and the Spare Parts relic now restock your main explosive, whatever type it is. Fault Line triggers on all five types. Shear charges stick only when you have sticky charges packed.
- Fixed a misleading message: drilling alloy said "needs DRILL Mk.IV or a charge", but charges have never been able to break alloy.

## 0.12.0
**Three map relics** (the pool grows from 16 to 19). This finishes the relic plan.
- **Dowsing Rod:** water within 20 cells of you shows on the minimap and the survey map before you get there, even through solid rock. It's drawn in a paler blue than water you have actually seen (normally only about 7 cells around you), and the survey map's legend lists it as SENSED WATER. The marks update every second and clear when the water drains away.
- **Greedy Lamp:** up to four small arrows float in a ring around the digger, each pointing toward the nearest ore that is off screen (within 30 cells), in that ore's colour. Better ore draws a brighter arrow. The cost: your lamp lights a smaller area, and the mine wakes 25% faster.
  - The arrows circle the digger rather than sitting at the screen edge, so they never collide with the HUD panels or touch buttons on any phone shape.
- **Cartographer's Eye:** every zone you reach is fully drawn on your map. Taking it also draws the zones you have already visited this run. The First Civilization counts as one zone, so the whole deep map is revealed when you arrive.

## 0.11.0
**Four more run relics** (the pool grows from 12 to 16).
- **Fault Line:** when one of your charges goes off, the ceiling above it cracks across five columns, two rows deep. After about a second of dust it comes down as rubble. Blast a crawler, then let the roof finish it. It cannot crack alloy, bedrock, protected or bolted rock, and it doesn't trigger on gas explosions.
- **Pressure Valve:** when the pressure meter reaches 80, the mine vents. The meter drops by 40, and every foe within 9 cells of you is stunned for 4 seconds. It can happen again after 45 seconds.
- **Dust Cloak:** running over sand piles, drilling sand or drilling sediment raises dust for 3 seconds. Crawlers and breakers more than 3 cells away can't see you, and one that was chasing you gives up within a second. They can still hear your drilling.
- **Slag Heart (The First Civilization only):** lava doesn't burn you. Lava within about 1.5 cells of you crusts into rock, which gives you footing to climb out. Lava still slows you while you wade. This relic is never offered in the main mine.
- Sand piles turned out not to slow you down at all, and crawlers walk straight through them, so the planned "Sand Strider" would have done nothing. Dust Cloak replaces it.

## 0.10.0
**Six new run relics** (the pool grows from 6 to 12). Like the others, each lasts until the run ends and shows in the cargo manifest.
- **Echo Drill:** every fifth block you drill out also breaks the block behind it. It follows your drill's limits: it cannot cut alloy before the Mk.IV drill, bedrock or protected rock.
- **Overdrive:** when the drill overheats it keeps cutting at half power (rock and foes alike) instead of locking you out. It still vents steam while it works, and recovers normally once you let go.
- **Hard Hat:** falling rubble, boulders, tremors, breaker roof drops and shear-charge drops can't hurt you.
- **Blood Bargain:** when you extract, your ore pays extra for the hull you are missing: half your hull gone pays +50%, almost none left pays nearly double. It shows as its own line on the results screen.
- **Glutton's Sack:** +30 rack slots. While you move with ore aboard it rattles every 2.5 seconds, and crawlers nearby hear it (3 to 10 cells, louder the fuller your rack).
- **Spare Parts:** the first time you reach each zone in a run (The First Civilization counts as one), you rig up a free charge. If your charge rack is full you get a lure instead (up to 5).
- With more relics in the pool, which relic sits at a given spot on a seed has changed. Where relics are placed has not.
- Relic lines in the cargo manifest now wrap if they are too long.

## 0.9.1
**Run relic fixes**
- **No more duplicate relics.** The relic in The First Civilization is rolled from its own seed, so it could be one you already carried (a wasted find). Now a relic you already hold is swapped for one you do not.
- **Iron Spine no longer stacks.** Taking a second copy used to add another +40 hull. The bonus now applies only the first time.

## 0.9.0 (feature/fun-pass)
**The terrain is a weapon, part 2**
- **Breakers** (new enemy, in the Forgotten Engine and the Drowned Aqueducts; about one in three burrowers there). A bigger, orange burrower with a drill horn. It hunts like a crawler, but when it sees you under a roof it stops and gnaws at that roof. Dust rains above you and an arc fills around it for 3 seconds, then the roof comes down. While it gnaws it is planted and takes **double damage**. Stunning it breaks its grip. A late collapse swarm can bring one with it.
- **Shear charges** (2 per dive; R on keyboard, SHEAR on the toolbar). A small, clean cut that barely hurts anything, then the ground resting on what it cut comes down after a short dust warning. Throw one up at a ceiling to drop it on crawlers you lured underneath. Sticky charges stick these too.
- **Anchor bolts** (4 per dive; B, BOLT on the toolbar). Fire one up (or at a wall when aiming sideways) and the rock around it is pinned for 75 seconds: collapses, tremors, shear charges and breakers cannot take it. A light on the bolt dims as it works loose and blinks near the end.
- The gadget toolbar now has four buttons (gadget, LURE, SHEAR, BOLT), each showing what is left as pips. The status panel has a new **KIT** row with shear and bolt pips.

## 0.8.0 (feature/fun-pass)
From now on every build gets its own version: the last number for fixes, the middle one for new features. A test fails if the game's version, the Android build name and this changelog disagree.

**This update**
- **Sand piles reworked.** They looked like blocks spawned by code: straight sides, and floating above the ground. Now dirt flies as grains that land where they land and pile up from what fell. Piles are drawn as grainy mounds with rounded tops, sit on the visible ground, and collide where they are drawn (details under Sand piles below).
- **CARGO button removed.** Tap the CARGO row of the status panel instead (it has a small arrow); the manifest is also in Pause and on I. The objectives moved up into the space.
- **Zone changes happen where you are.** The zone name, music, lighting and banner used to follow the camera, which looks ahead when you fall or drill down, and switched the moment you touched the wavy border, so you were "in" the Forgotten Engine while still at the bottom of a wing. They now follow the digger and only switch once you are 3 rows past the border.
- **Water is one colour everywhere.** It used to take the zone's tint, so it turned purple in the Forgotten Engine and the Crystal Hollows.

**Also new since the first 0.7.0 builds**
**New HUD and touch controls**
- The in-game HUD is redrawn as one industrial interface: chamfered metal panels with bevelled rims, orange corner brackets and hazard strips, and cyan, teal, orange, yellow and red indicators.
  - Status panel: HULL, HEAT, CARGO, CHRG + LURE, SCAF, PRES, and GADG as "SONAR - READY - MAGNET".
  - Framed minimap, a depth panel with a zone gem, metal CARGO (crate icon) and pause buttons, and a framed orders list.
  - All values are live game data, as before.
- Touch controls are a 2x2 block of octagonal buttons in the bottom-right corner, with icons: LADDER (ladder) and DRILL (drill bit) on top, CHARGE (bomb, with a count badge) and JUMP (cyan double chevron) below. The movement stick is a metal ring with orange arrows; the d-pad is restyled to match.
- Lures show as cyan pips, like the charges (in the status panel and on the toolbar's LURE button).
- **USE** is a teal button beside the block. It appears only when something is in reach, showing what it will do (EXTRACT, TAKE, DESCEND...).
- **Gadget toolbar:** a metal bar above the block with your active gadget (SONAR or CRYO, with its cooldown) and LURE (with the count).
  - Tap its arrow tab to slide it off the right edge in 0.2 s. Only the tab stays, and the freed space takes no touches. Tap the tab again to bring it back.
  - Your choice is remembered between sessions.
  - Keyboard: G or V for the gadget, T for a lure.
- Panels stay inside the screen's safe area (cutouts), and the controls scale with Touch size. The layout is tested at 16:9, wider phone ratios and 16:10, at 70%, 100% and 150% size.

**Ancient Descent Platform**
- The one-way lift down to The First Civilization now looks like what it is: a grand gate twice the old size, filling its room.
  - A wide stepped deck over a glowing grate, with braziers either side.
  - Two tall pylons with cycling rune slots and hanging chains.
  - A heavy arch whose eye glyph pulses, with heat rising through the gate.
- You can use it from anywhere on the deck.

**Sand piles**
- Loose sand now **piles up**. One in three sediment cells you drill throws a few dirt grains, a collapsing ceiling comes down as scattered rubble, and charges throw loose debris. The grains fly, bounce off walls, slow in water and land where they land. What lands slides off steep sides and settles into mounds that you **walk up and over**. The drill takes a pile away in one bite.
- Piles are drawn one pixel column at a time: a curve that rises from the floor and rounds over at the top, grainy, with the odd pebble, and sitting on the visible ground line. Sand that is still falling shows as loose grains, not a block. Collision follows the drawn surface as one continuous line, so you walk on what you see.
- Sand pushes water out of its way and never fills the space you or a crawler stand in. Water and lava treat a half-full pile as ground.
- **Settings > Sand physics:** Off / Low / Normal / High. Off brings back the old behaviour: no new piles, and collapses land as square rubble blocks. With "Show FPS" on, the HUD also shows how many sand cells are moving and what the last step cost.
- Phone-friendly limits (all in `Balance`):

  | Setting | Updates per second | Cells per update |
  |---|---|---|
  | Low | 10 | 80 |
  | Normal | 20 | 160 |
  | High | 30 | 320 |

  Settled sand costs nothing. A step slower than 1.5 ms halves the next one's budget. Beyond 400 moving cells the rest settles at once. Collision for changed sand is rebuilt at most 10 times a second.
- Measured on desktop, not on a phone. A 28-block cave-in averages 0.12 ms per step (worst 0.2 ms) and settles in under 2 s on Normal. A huge 400-cell pour averages 0.7 ms (worst 1.2 ms).

**Charge upgrades**
- **CHARGE RACK** (new upgrade, 3 levels): carry up to 8, 10, then 12 charges (6 without it). Buy charges at the Supply Locker up to your rack size.
- **STICKY CHARGES** (new one-time upgrade): a charge sticks to the first rock, ceiling or foe it touches instead of bouncing and rolling. Stick one to a crawler and it rides along until it blows. If the rock it is stuck to is drilled away, it falls. Toggle sticky ON/OFF at the Supply Locker, or from the Pause menu during a run. The choice is saved.

**Feet on the ground**
- Follow-up: every tile's top edge begins with a near-black outline row that disappears against the dark cave, so the feet still looked 1 to 3 px high. The sprite now sinks onto that outline row, so the boots touch the bright ground line.
- The digger now stands on the rock you can see. Tile tops are drawn rough and rounded, which left a 1 to 4 pixel gap under the feet. The sprite now sinks onto the drawn surface under its feet, read from the tile art itself, and eases back up in the air. Collision is unchanged.

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
- **A choice:** on most maps one relic spot holds two different relics side by side. Take one and the other crumbles to dust.
- Relics carry into The First Civilization and are listed in the cargo manifest. A new order kind asks you to take one.

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
