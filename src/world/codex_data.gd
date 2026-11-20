class_name CodexData
## Text for the codex and the contextual hints. Creature pages open on your
## first kill; everything else opens the first time it happens to you.
## Relics and zones are built from Balance so they never drift from the game.

const CATS := ["creature", "hazard", "explosive", "relic", "zone"]
const CAT_NAMES := {"creature": "CREATURES", "hazard": "HAZARDS", "explosive": "EXPLOSIVES", "relic": "RELICS", "zone": "ZONES"}

const CREATURES := [
	{"id": "crawler", "name": "Burrow Crawler",
		"text": "Clings to floors, walls and ceilings and goes wherever it hears noise: drilling, blasts and lures. Once it sees you it gives chase, and it will chew through soft sediment to reach you (never basalt).\n\nFalling rock and blasts stun it. Water drowns it. Without sight or fresh noise it loses interest after a while.\n\nTip: a lure pulls it off a chase. Lead it under loose rock or into a flooded hole."},
	{"id": "breaker", "name": "Breaker",
		"text": "A heavier crawler that goes for the ground instead of you. When it sees you under a roof it braces and gnaws: dust rains over your head for a few seconds, then the roof comes down.\n\nWhile it gnaws it is planted and takes double damage. Bolted rock can't be gnawed, and a stun breaks its grip.\n\nFound in the Forgotten Engine and the Drowned Aqueducts."},
	{"id": "sentry", "name": "Ruin Sentry",
		"text": "A turret left by the old builders. Its eye is cyan while dormant, pulses amber with a rising beep when it spots you, then turns red and fires a burst of slow bolts you can dodge.\n\nTake cover during the warning. Break it with the drill or a charge, destroy its exposed power module, or drop rock on it."},
	{"id": "brute", "name": "Shielded Brute",
		"text": "A big, slow walker behind a tall front plate. Drill and blast damage from the front mostly glances off. Its back is soft, and it turns slowly.\n\nFalling rock, lava, gas and water ignore the plate. If it charges into rock it can't break, it stuns itself and the plate drops.\n\nIt smashes through soft rock, steps up one-cell ledges and falls off edges, but it can't climb."},
	{"id": "flier", "name": "Flier",
		"text": "A rare moth-drone. It hunts like a crawler, by sight, noise and lures, but it flies: shafts, caverns and open water don't stop it.\n\nIt's fragile and never tunnels."},
	{"id": "burrower", "name": "Burrower",
		"text": "A blind, armoured mole-worm. It hears drilling and blasts from twice as far as a crawler, and feels you through rock when you're close.\n\nRock is no shelter: it chews through sediment, rubble, cracked rock and basalt, leaving a tunnel. The rock cracks and spills dust before it breaks through. It won't dig alloy, bedrock, ore, gas sacs, or rock holding back water or lava.\n\nStay quiet and it loses you."},
	{"id": "eater", "name": "Bomb-eater",
		"text": "A squat scavenger that smells explosives you've placed: charges, sticky charges, remote charges and mines. It walks over and swallows them. Drill rockets are safe.\n\nA moment after swallowing one, its belly starts pulsing red and it comes for you. When the countdown ends it blows, wherever it is, and the blast is bigger than a charge.\n\nKill it before it eats, or run. Out-climb it, or cut it off with water, lava or a collapse."},
	{"id": "spore", "name": "Spore Pod",
		"text": "A slow, drifting puffball. It doesn't bite. It floats up beside you, swells, and bursts into a cloud of gas. Killing it bursts it too.\n\nIf a blast or a fireball kills it, the gas goes up at once as a fireball: good next to a crawler, bad next to you."},
	{"id": "eel", "name": "Eel",
		"text": "A pale, frilled hunter of flooded places. In water it's fast and bites hard, and you're slow there.\n\nOut of water it flops along, bites weakly and takes double damage, and soon turns back to dry out.\n\nFight it on dry ground, or drain its pool and leave it stranded."},
	{"id": "slag", "name": "Slag Salamander",
		"text": "A lizard of cooling slag from The First Civilization. It lives in lava and climbs out to hunt. Lava and steam don't hurt it.\n\nOut of lava it cools, slows, and heads back. Water or a cryo canister quenches it into a block of rock, with aetherite inside."},
]

const HAZARDS := [
	{"id": "collapse", "name": "Collapse",
		"text": "Loose rock with nothing under it falls a moment after you dig it out. Basalt that loses its anchor drops as a boulder.\n\nFalling rock hurts you, and it stuns or crushes anything it lands on. That works in your favour too."},
	{"id": "sand", "name": "Sand",
		"text": "Drilled sediment and blasted rubble leave loose sand behind. It falls into any room below and slides into mounds you can walk over.\n\nDig under a pile and it follows. Sand that fills a gap blocks water."},
	{"id": "water", "name": "Water",
		"text": "Water flows downhill into any open space. Breach a pool's wall and it drains through your tunnels.\n\nYou move slowly in it. Crawlers drown in it. Poured onto lava, it hisses into steam and crusts the lava into rock."},
	{"id": "lava", "name": "Lava",
		"text": "A slow, heavy fluid that keeps creeping long after a breach. It burns on touch.\n\nWhere it meets water, both are used up: the lava crusts into drillable rock and the water boils off as steam."},
	{"id": "steam", "name": "Steam",
		"text": "Boiled water rising off lava. Thick steam scalds you and lifts you up. It thins out over time."},
	{"id": "gas", "name": "Gas",
		"text": "Breaking a gas sac starts a hissing vent, then a lingering cloud that burns anything inside it, you included.\n\nAny explosion touching a vent or cloud sets it off as a big fireball."},
	{"id": "pressure", "name": "Pressure",
		"text": "The mine wakes up. A meter rises with time spent in deeper zones and with your noise: drilling a little, blasts a lot. It eases off when you head back to shallower ground.\n\nEach tier brings warned events: tremors that bring a ceiling down, gas seeping from the rock, and crawler swarms that come for the noise."},
]

const EXPLOSIVE_TEXT := {
	"charge": "Thrown with a bounce and a roll, then it blows. The red ring shows the blast.",
	"sticky": "Sticks where it lands: rock, ceilings, and foes. Then it blows.",
	"rocket": "Shot from your arm, it bores straight through rock the drill could cut, leaving a tunnel you fit through. It blows when its time runs out, or at once on a foe or anything it can't cut. A new drill grows back.",
	"remote": "Throw it, then press again to set it off whenever you like.",
	"mine": "Laid at your feet. It arms once you step away, and the next thing to come near sets it off, you included. Any blast that reaches it sets it off too.",
}

## id -> line. Shown once per save, in the strip under the top HUD.
const HINTS := {
	"drill": "Hold DRILL to dig. Aim up or down to dig that way.",
	"ladder": "Climb ladders with UP. JUMP again in mid-air for a jet burst.",
	"ore": "Ore goes in your rack. Take the lift up to sell it.",
	"full": "Rack full. Better ore now swaps in for your cheapest. Sell whenever you like.",
	"heat": "Drill running hot. Ease off to let it cool.",
	"overheat": "Overheated. Wait for it to cool.",
	"diag": "Aim up and sideways to drill a step and climb it.",
	"bedrock": "This rock can't be dug. Find a way around.",
	"tier": "Too hard for your drill. Upgrade it, or go around.",
	"scaffold": "Breaking rock fills SCAF. LADDER raises a ladder from your feet to the ceiling.",
	"lure": "USE with nothing nearby throws a LURE. Crawlers go to the noise.",
	"collapse": "Rock with nothing under it falls. Mind what you dig out.",
	"sand": "Sand slides. Dig under it and it follows.",
	"water": "Water flows downhill into any open space.",
	"lava": "Lava burns. Keep your distance.",
	"gas": "Gas burns, and any blast sets it off.",
	"explosive": "CHARGE throws your explosive. Mind the red ring!",
	"backup": "The second CHARGE button uses your backup explosive.",
	"x_sticky": "Sticky charges stick to rock, ceilings and foes.",
	"x_rocket": "Rockets bore straight ahead, then blow.",
	"x_remote": "Press again to set off your remote charge.",
	"x_mine": "Mines arm once you step away. Anything that comes near sets them off.",
	"relic": "Relics last for this run only.",
	"lift": "The lift takes you up with your haul. Die down here and the haul is lost.",
	"outpost": "Walk up to a counter to use it.",
	"contracts": "Contracts pay extra for meeting their goals.",
	"demo": "Buy explosives and blast upgrades here.",
	"missions": "Missions are fixed maps with their own goal. Free to start.",
	"codex": "New codex entries can be read from the pause menu or the title screen.",
	"t_eater": "A bomb-eater swallowed your explosive and came back with it.",
	"t_slam": "A brute that charges into rock it can't break stuns itself, and its plate drops.",
	"t_plate": "A brute's plate stops your drill. Get behind it, or bring the roof down.",
	"t_quench": "A salamander quenched by water sets into stone, with aetherite inside.",
	"t_spore": "A spore pod bursts into gas. A blast would have set it alight.",
}


static func creature(id: String) -> Dictionary:
	for e: Dictionary in CREATURES:
		if e["id"] == id:
			return e
	return {}


## Every page in a category, as {id, name, text}. Codex ids are "cat:id".
static func entries(cat: String) -> Array:
	var out: Array = []
	match cat:
		"creature":
			out = CREATURES.duplicate()
		"hazard":
			out = HAZARDS.duplicate()
		"explosive":
			for kind: String in Balance.EXPLOSIVE_ORDER:
				var x: Dictionary = Balance.EXPLOSIVES[kind]
				out.append({"id": kind, "name": String(x["name"]).capitalize(), "text": String(EXPLOSIVE_TEXT.get(kind, x["desc"]))})
		"relic":
			for r: Dictionary in Balance.RUN_RELICS:
				out.append({"id": r["id"], "name": r["name"], "text": String(r["desc"]) + "\n\nLasts for the run it is found in.", "color": r["color"]})
		"zone":
			for i in Balance.STRATUM_NAMES.size():
				out.append({"id": str(i), "name": String(Balance.STRATUM_NAMES[i]).capitalize(), "text": String(ZONE_TEXT[i]) if i < ZONE_TEXT.size() else ""})
	return out


static func entry(key: String) -> Dictionary:
	var parts := key.split(":")
	if parts.size() != 2:
		return {}
	for e: Dictionary in entries(parts[0]):
		if String(e["id"]) == parts[1]:
			return e
	return {}


static func is_key(key: String) -> bool:
	return not entry(key).is_empty()


const ZONE_TEXT := [
	"The first layer under the outpost: dry sediment and old workings, with ladders left by earlier crews. Deeper down the ladders run out.",
	"Damp tunnels threaded with glowing fungus. Spore pods drift here.",
	"The buried machine halls of the builders. Breakers gnaw the ceilings.",
	"Flooded channels and cisterns, where breakers work the roofs.",
	"Glittering caverns of crystal, far below the outpost.",
	"A city older than the mine, reached by a one-way descent under the Engine. Lava runs through it.",
]
