# Test checklist (0.13 to 0.21)

Everything added since the owner's last real playtest. Interactive version (marks saved on the phone, copy-a-report button): https://claude.ai/artifact/WHJmABidQrHtW6vt9N5PrM

FIRST = most worth testing.

## Before you start (0.21.0)
Install RuinDigger-0.21.0.apk over the old one. Your save, credits and upgrades carry over.

- [ ] **The title screen says v0.21.0**: Top-left corner.
- [ ] **Turn on Settings > Record performance** (FIRST): Leave it on for the session. After a long dive, tap COPY PERFORMANCE REPORT on the results screen and paste it to me.
- [ ] **Settings shows Game feel intensity on Normal**: Off / Subtle / Normal / Strong, with a one-line note under it. Check it fits your screen.

## Game feel (0.21.0)
Try Subtle, Normal and Strong. You can switch from Pause > Settings during a dive and it changes at once.

- [ ] **Drill sediment, then basalt** (FIRST): Sediment: a light flick of the arm and dusty puffs. Basalt: a firmer knock, chunky chips and sparks.
- [ ] **Drill bedrock or alloy**: Sparks and a hard shove, no chips, nothing breaks. It should read as "can't cut this".
- [ ] **Drill for 10 minutes straight** (FIRST): Still pleasant? No jitter, no headache, aiming feels the same. Which level do you like best?
- [ ] **Aim and targets feel unchanged**: The drill tip never looks like it's hitting a different cell than the one that breaks.
- [ ] **A charge next to you, one at the screen edge, one far away**: Next to you shakes like before; at the edge, less; far off screen, none.
- [ ] **Shear charge vs charge vs bomb-eater blast**: The shear charge looks smaller, the bomb-eater blast bigger, with an extra fireball.
- [ ] **A ceiling collapse or a boulder landing**: Dust where it lands and one short knock, not a buzzing camera. The warning dust before it still shows.
- [ ] **A long fall onto a floor**: A quick squash of the sprite and a puff. Controls aren't delayed and fall damage is the same.
- [ ] **Breach a pocket of water under pressure**: One splash in the jet's direction (and a small knock), then quiet while it keeps running.
- [ ] **Screen shake slider at 0, Game feel on Strong**: Nothing shakes at all, even in a big blast.
- [ ] **Low effects on, Game feel on Strong**: Fewer particles, but warnings still show: crumbling-ceiling dust, gas vent puffs.
- [ ] **Reduced flashing on, Game feel on Strong**: Blasts and gas fireballs no brighter than with Reduced flashing on before.

## Hints, codex, run summary (0.20.0)
To see hints as a new player would, tap Settings > RESET HINTS.

- [ ] **Hints show one at a time, under the top HUD** (FIRST): Never over your digger or the touch buttons. When zoomed in a lot, they drop to the bottom middle.
- [ ] **No hints while you're being hurt or chased**: They wait for a calm moment.
- [ ] **Fill your rack**: The hint says better ore swaps in for your cheapest, and that you don't have to leave.
- [ ] **Settings > Hints off, then RESET HINTS**: Off means no hints. Reset brings them back.
- [ ] **Open the Codex from the title screen and from Pause**: Tabs for creatures, hazards, explosives, relics, zones, records and hints all work by touch.
- [ ] **Kill a creature you haven't killed before** (FIRST): A "CODEX: ... added" notice appears; its page opens only after the kill.
- [ ] **Records tab after a few dives**: The numbers look right (dives, kills, best haul, explosives used, longest dive).
- [ ] **Die on purpose (to gas, a crawler, anything)** (FIRST): The results screen says what killed you, where, when, and what hurt you in the last 10 seconds.
- [ ] **Extract normally**: It says how long it took and the damage you took, plus NEW RECORD when you beat one.

## Mission: The Dry Dock (0.20.0)
Opens at the Missions terminal once you've finished The Sunken Lake.

- [ ] **The Dry Dock appears after the Sunken Lake**: 400 CR reward.
- [ ] **Open a hopper** (FIRST): In the service tunnel (HOPPERS sign), stand on a grate, drill up into the plug, step off. The sand pours down into the pit.
- [ ] **Fill the pit** (FIRST): The compass shows DOCK %. One hopper isn't enough. Does the pour look good, or too sudden?
- [ ] **The sand pocket over the tunnel**: Dig up into the ceiling near the ladder drop and it buries the tunnel. Fair, or annoying?
- [ ] **Walk across the full pit to the lift**: No snagging on the sand heap; the lift is online; the reward pays.

## Bomb-eater and ladders (0.20.0)

- [ ] **Leave a charge, mine or remote near a bomb-eater**: It eats charges, sticky charges, remotes and mines. Never a drill rocket.
- [ ] **After it eats** (FIRST): About 1 second normal, then its belly pulses red faster and faster, it chases you, and it blows after about 7 seconds wherever it is.
- [ ] **Let it chase you up a ladder**: It climbs. Does it look OK?
- [ ] **Blow up the middle of a ladder**: The part above falls in pieces and is gone; the part below stays. If you're on the top part you fall too.
- [ ] **Dig out the floor under a sand pile**: The sand falls into the hole (it used to hang in the air).
- [ ] **Drill up under sand, then step aside**: The sand carries on falling once you move.

## Diagonal drilling (0.19.0)

- [ ] **Drill with the stick up and to one side** (FIRST): It cuts a step and hops you up. Keep holding to climb a staircase.
- [ ] **Settings > Diagonal drill button (DIAG)**: The button appears; holding it drills up the way you face. The layout editor can move it.

## Missions and the lake (0.18)

- [ ] **The Sunken Lake: fill to 100%**: Less water than before, but still enough. The lift stays dry in its alcove when full.
- [ ] **High Water**: Opens after the lake plus 130 m on a contract. Deeper bed, more eels, the mine wakes.

## Enemies and fixes (0.15 to 0.17.1)

- [ ] **Shielded brute**: Taller than you. The plate stops your drill from the front; get behind it, drop rock on it, or let it charge into rock and stun itself.
- [ ] **Flier (rare)**: Crosses open shafts and caverns; fragile.
- [ ] **Burrower**: Comes for noise through rock; the rock cracks and dusts before it breaks through. Stay quiet and it loses you.
- [ ] **Spore pod (Spore Veins)**: Floats up, swells, bursts into gas. Killed by a blast, it goes up as a fireball.
- [ ] **Eel**: Fast in water, weak on land. Drain its pool.
- [ ] **Slag salamander (First Civilization)**: Lives in lava; water or cryo turns it to stone with aetherite inside.
- [ ] **A crawler loses its rock**: It falls instead of hanging in the air; a long fall hurts or kills it.
- [ ] **Fire a drill rocket**: It's your drill; the arm is bare for a moment and a new one grows back.

## Explosives (0.13 to 0.14)

- [ ] **The Demolitions counter**: Buy types, pick a main and a backup slot, buy upgrades (rack, power, radius, fuse, bore, sensor, shield).
- [ ] **Two explosive buttons side by side**: With a backup packed, the button splits in two. Easy to hit both?
- [ ] **A blast reaching a proximity mine**: The mine goes off too, armed or not.

## Overall (all)

- [ ] **A long session** (FIRST): Any stutter, heat or battery drain? If so, send the performance report.
- [ ] **Touch controls**: Too many buttons? Anything hard to reach? Note which.
- [ ] **Is it fun?**: What did you enjoy most, and what felt like a chore?
