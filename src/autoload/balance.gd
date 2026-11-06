extends Node
## Central tuning sheet. Every gameplay number that a designer might want to
## tweak lives here (see README "Balance").

const CELL := 16

# --- Player movement (pixels, seconds) ---
const RUN_SPEED := 152.0
const GROUND_ACCEL := 2000.0
const AIR_ACCEL := 1350.0
const GROUND_FRICTION := 2200.0
const GRAVITY := 960.0
const MAX_FALL := 430.0
const JUMP_VELOCITY := 318.0        # ~3.3 cells
const JUMP_CUT := 0.45              # velocity kept when jump released early
const JET_VELOCITY := 250.0         # air burst (one per airtime)
const COYOTE_TIME := 0.1
const JUMP_BUFFER := 0.12
const WALL_SLIDE_SPEED := 70.0
const WALL_JUMP_PUSH := 150.0
const WALL_JUMP_VELOCITY := 285.0
const WALL_JUMP_LOCK := 0.13
const LADDER_SPEED := 125.0
const INVULN_TIME := 1.0
const FALL_DAMAGE_SPEED := 9999.0   # no fall damage: we want digging down to feel free

# --- Drill ---
const DRILL_TICK := 0.085           # seconds between impact ticks
const DRILL_POWER := [4.2, 5.8, 7.8, 10.5]   # hp per second by drill level
const DRILL_ENEMY_DPS := 75.0
const DRILL_HITSTUN := 0.3          # enemies hit by the drill can't attack for this long
const DRILL_KNOCKBACK := true
const HEAT_CAPACITY := [100.0, 145.0, 200.0, 270.0]
const HEAT_PER_SEC := 8.5          # while drilling soft material
const HEAT_COOL_PER_SEC := [30.0, 36.0, 44.0, 55.0]
const HEAT_COOL_DELAY := 0.35
const HEAT_RECOVER_FRACTION := 0.35 # overheated drill unlocks below this

# --- Materials: hp, required drill tier, heat multiplier ---
# Keys are Cell.* ids (see src/terrain/cell.gd)
const MATERIAL := {
	1: {"name": "Sediment", "hp": 1.0, "tier": 0, "heat": 1.0},
	2: {"name": "Basalt", "hp": 4.0, "tier": 0, "heat": 1.6},
	3: {"name": "Loose rubble", "hp": 0.55, "tier": 0, "heat": 0.6},
	4: {"name": "Ruin alloy", "hp": 12.0, "tier": 3, "heat": 2.4},
	5: {"name": "Bedrock", "hp": 9999.0, "tier": 99, "heat": 0.0},
	6: {"name": "Gas sac", "hp": 0.8, "tier": 0, "heat": 0.5},
	7: {"name": "Cracked wall", "hp": 1.6, "tier": 0, "heat": 1.0},
}

# --- Ore & loot ---
# id -> name, value, colour (hex), units dropped
const ORE := {
	1: {"name": "Copper", "value": 6, "color": "ffab5e", "drops": 2},
	2: {"name": "Cobalt", "value": 15, "color": "5fc0ff", "drops": 2},
	3: {"name": "Aetherite", "value": 38, "color": "e070ff", "drops": 2},
	4: {"name": "Fossil", "value": 22, "color": "efe5c4", "drops": 1},
	5: {"name": "Scrap", "value": 4, "color": "b8c4d4", "drops": 1},
}
const CARGO_CAPACITY := [16, 24, 34, 46]
const PICKUP_MAGNET_RADIUS := 34.0
const RELIC_BONUS := 260

# --- Hull ---
const HULL := [100.0, 130.0, 165.0, 210.0]

# --- Upgrades: cost per next level (index = current level) ---
const UPGRADES := {
	"drill": {"name": "DRILL HEAD", "costs": [120, 280, 560],
		"desc": ["Mk.I tungsten bit", "Mk.II +38% bore speed", "Mk.III +86% bore speed", "Mk.IV cuts ruin alloy"]},
	"heat": {"name": "HEAT SINK", "costs": [100, 240, 480],
		"desc": ["Stock radiator", "+45% heat capacity", "+100% capacity, faster cooling", "+170% capacity, cryo vents"]},
	"cargo": {"name": "CARGO RACK", "costs": [90, 220, 450],
		"desc": ["16 ore units", "24 ore units", "34 ore units", "46 ore units"]},
	"hull": {"name": "HULL PLATING", "costs": [110, 260, 520],
		"desc": ["100 hull", "130 hull", "165 hull", "210 hull"]},
}
const CHARGE_PRICE := 25
const CHARGES_FREE := 2
const CHARGES_MAX := 6

# --- Demolition charge ---
const CHARGE_FUSE := 2.2
const CHARGE_RADIUS_CELLS := 3.2
const CHARGE_TILE_DAMAGE := 7.0     # at centre; linear falloff to 45% at edge
const CHARGE_ENTITY_DAMAGE := 70.0
const CHARGE_SELF_DAMAGE := 26.0    # max to the player (reduced self-damage)
const CHARGE_THROW := Vector2(150, -165)

# --- Gas ---
const GAS_TELEGRAPH := 1.3
const GAS_CLOUD_TIME := 9.0
const GAS_CLOUD_RADIUS := 44.0
const GAS_DPS := 9.0
const GAS_IGNITE_RADIUS := 78.0
const GAS_IGNITE_DAMAGE := 55.0
const GAS_IGNITE_TILE_DAMAGE := 3.5

# --- Collapse ---
const COLLAPSE_TELEGRAPH := 0.75
const COLLAPSE_MAX_FALLING := 28
const COLLAPSE_MAX_CASCADE := 18
const RUBBLE_PLAYER_DAMAGE := 14.0
const RUBBLE_ENEMY_DAMAGE := 34.0
const RUBBLE_SENTRY_DAMAGE := 80.0
const RUBBLE_STUN := 3.0

# --- Water (cellular, levels 0..WATER_MAX per cell) ---
const WATER_MAX := 64              # fine resolution so lakes level out flat
const WATER_TICK := 0.06            # simulation step
const WATER_BUDGET := 2400          # max cell updates per step
const WATER_GRAVITY := 0.35         # gravity multiplier while submerged
const WATER_MAX_FALL := 90.0
const WATER_SPEED := 0.72           # run speed multiplier while submerged
const WATER_SWIM := 175.0           # upward stroke on jump while submerged
const WATER_COOLING := 2.5          # drill cools this much faster in water
const WATER_CRAWLER_DPS := 7.0      # crawlers hate water
const WATER_DROP_UNITS := 3         # volume carried by one falling droplet
const WATER_EMIT_PER_TICK := 16     # max units a free-falling cell sheds per tick
const WATER_MAX_DROPS := 900        # beyond this, falling water moves cell-to-cell
const WATER_DROP_GRAVITY := 820.0
const WATER_DROP_MAX_FALL := 420.0

# --- Unsupported basalt ---
const BOULDER_MAX_CELLS := 36       # bigger basalt masses are treated as bedded in
const BOULDER_TELEGRAPH := 0.7
const BOULDER_PLAYER_DAMAGE := 28.0
const BOULDER_ENEMY_DAMAGE := 90.0

# --- Burrow Crawler ---
const CRAWLER_HP := 38.0
const CRAWLER_SPEED_PATROL := 1.6   # cells / s
const CRAWLER_SPEED_CHASE := 3.4
const CRAWLER_SIGHT := 9            # cells
const CRAWLER_HEARING := 8          # drill noise radius in cells
const CRAWLER_FORGET := 4.0         # s without sight/noise before giving up
const CRAWLER_DAMAGE := 12.0
const CRAWLER_WINDUP := 0.4         # visible rear-up before every bite
const CRAWLER_ATTACK_COOLDOWN := 1.1
const CRAWLER_REPATH := 0.45
const CRAWLER_TUNNEL_TIME := 1.6    # s to chew one sediment cell
const CRAWLER_PATH_RADIUS := 22
const CRAWLER_CAP := 16

# --- Ruin Sentry ---
const SENTRY_HP := 55.0
const SENTRY_RANGE := 11            # cells
const SENTRY_WARN := 0.9
const SENTRY_REWARN := 0.5
const SENTRY_BURST := 3
const SENTRY_BURST_GAP := 0.18
const SENTRY_COOLDOWN := 1.5
const SENTRY_FORGET := 2.0
const SENTRY_BOLT_SPEED := 150.0
const SENTRY_BOLT_DAMAGE := 12.0
const POWER_MODULE_HP := 14.0

# --- World generation ---
const MAP_W := 72
const MAP_H := 214
const STRATUM_ROWS := [2, 72, 142]  # row where each stratum begins
const STRATUM_NAMES := ["DUSTWORKS", "SPORE VEINS", "FORGOTTEN ENGINE"]
const METERS_PER_CELL := 2.0

const CONTRACTS := [
	{"id": "survey", "name": "STANDARD SURVEY", "desc": "Recover the relic. Balanced seams and threats.",
		"ore": 1.0, "crawlers": 1.0, "gas": 1.0, "bonus": 1.0},
	{"id": "rich", "name": "RICH SEAMS", "desc": "+40% ore, but the burrows are restless.",
		"ore": 1.4, "crawlers": 1.5, "gas": 1.0, "bonus": 1.1},
	{"id": "gas", "name": "GAS FIELD", "desc": "Volatile pockets everywhere. Bring charges.",
		"ore": 1.15, "crawlers": 0.8, "gas": 2.2, "bonus": 1.25},
	{"id": "quiet", "name": "QUIET DIG", "desc": "Few crawlers, thinner veins, smaller bonus.",
		"ore": 0.8, "crawlers": 0.45, "gas": 0.8, "bonus": 0.75},
]


func drill_power(level: int) -> float:
	return DRILL_POWER[clampi(level, 0, DRILL_POWER.size() - 1)]


func heat_capacity(level: int) -> float:
	return HEAT_CAPACITY[clampi(level, 0, HEAT_CAPACITY.size() - 1)]


func heat_cooling(level: int) -> float:
	return HEAT_COOL_PER_SEC[clampi(level, 0, HEAT_COOL_PER_SEC.size() - 1)]


func cargo_capacity(level: int) -> int:
	return CARGO_CAPACITY[clampi(level, 0, CARGO_CAPACITY.size() - 1)]


func hull(level: int) -> float:
	return HULL[clampi(level, 0, HULL.size() - 1)]


func ore_color(id: int) -> Color:
	if ORE.has(id):
		return Color(ORE[id]["color"])
	return Color.WHITE


func stratum_of_row(row: int) -> int:
	if row >= STRATUM_ROWS[2]:
		return 2
	if row >= STRATUM_ROWS[1]:
		return 1
	return 0
