extends Node
## Central balance/tuning resource. Every gameplay number that a designer might
## want to tweak lives here so tuning never requires touching gameplay scripts.

# --- Simulation ------------------------------------------------------------
const CELL := 24                 # world pixels per terrain cell
const CHUNK := 16                # cells per chunk edge
const GRAVITY := 900.0

# --- Terrain materials -----------------------------------------------------
enum Mat { EMPTY = 0, SOIL = 1, BASALT = 2, ALLOY = 3, BEDROCK = 4 }

## Base hit points per material before the drill-power multiplier applies.
const MATERIAL_HP := {
	Mat.SOIL: 1,
	Mat.BASALT: 4,
	Mat.ALLOY: 9,
	Mat.BEDROCK: 0x7FFF,       # indestructible in this slice
}

const MATERIAL_DRILL_TIME := {
	Mat.SOIL: 0.16,            # seconds of drilling per hit point
	Mat.BASALT: 0.30,
	Mat.ALLOY: 0.42,
	Mat.BEDROCK: 0.0,
}

## Which materials each drill tier can damage at all.
const DRILL_MIN_TIER := {
	Mat.SOIL: 0,
	Mat.BASALT: 0,
	Mat.ALLOY: 1,
	Mat.BEDROCK: 99,
}

const MATERIAL_NAME := {
	Mat.EMPTY: "EMPTY", Mat.SOIL: "SEDIMENT", Mat.BASALT: "BASALT",
	Mat.ALLOY: "RUIN ALLOY", Mat.BEDROCK: "BEDROCK",
}

# --- Player ----------------------------------------------------------------
const PLAYER_WALK_SPEED := 168.0
const PLAYER_ACCEL := 1400.0
const PLAYER_AIR_ACCEL := 900.0
const PLAYER_FRICTION := 1800.0
const PLAYER_JUMP_VELOCITY := -330.0
const PLAYER_MAX_FALL := 620.0
const PLAYER_COYOTE_TIME := 0.10
const PLAYER_JUMP_BUFFER := 0.10
const PLAYER_JUMP_CUT := 0.45      # velocity multiplier when jump released early
const PLAYER_HIT_INVULN := 0.85
const PLAYER_BASE_HP := 100

## Downward drill thrust while airborne (a "drill dive").
const DRILL_DIVE_VELOCITY := 260.0

# --- Drill -----------------------------------------------------------------
const DRILL_REACH := 1.35          # cells
const DRILL_TICK := 0.055          # seconds between damage applications
const DRILL_HEAT_PER_TICK := 0.075
const DRILL_HEAT_COOL := 0.42      # per second
const DRILL_OVERHEAT_LOCK := 1.4   # seconds locked out at 100% heat
const DRILL_ENEMY_DAMAGE := 7
const DRILL_KNOCKBACK := 130.0

# --- Charges ---------------------------------------------------------------
const CHARGE_FUSE := 1.25
const CHARGE_RADIUS := 3.1         # cells
const CHARGE_TILE_DAMAGE := 6
const CHARGE_ENEMY_DAMAGE := 46
const CHARGE_PLAYER_DAMAGE := 18
const CHARGE_GRACE := 0.45         # player immunity window after detonating
const CHARGE_MAX := 3

# --- Collapse / instability -------------------------------------------------
const COLLAPSE_MIN_CLUSTER := 5
const COLLAPSE_MAX_CLUSTER := 26
const COLLAPSE_TELEGRAPH := 0.85
const COLLAPSE_STEP := 0.055
const COLLAPSE_SAFE_RADIUS := 2    # cells around the lift kept stable

# --- Enemies ----------------------------------------------------------------
const CRAWLER_HP := 26
const CRAWLER_SPEED := 52.0
const CRAWLER_TUNNEL_SPEED := 0.9  # cells per second through soft soil
const CRAWLER_SIGHT := 260.0
const CRAWLER_NOISE_HEAR := 300.0
const CRAWLER_ATTACK_DAMAGE := 12
const CRAWLER_ATTACK_CD := 1.1

const SENTRY_HP := 34
const SENTRY_SIGHT := 340.0
const SENTRY_FIRE_CD := 1.7
const SENTRY_WARN_TIME := 0.55
const SENTRY_SHOT_SPEED := 250.0
const SENTRY_SHOT_DAMAGE := 11
const SENTRY_BURST := 3

const MAX_ACTIVE_ENEMIES := 14

# --- Hazards ----------------------------------------------------------------
const GAS_IGNITE_RADIUS := 1.6     # cells
const GAS_DAMAGE := 26
const GAS_TELEGRAPH := 0.9

# --- Economy ----------------------------------------------------------------
## Ore types: id -> {name, value, material, glow}
const ORE_TYPES := {
	1: {"name": "COPPER", "value": 6, "tint": Color(0.85, 0.55, 0.30)},
	2: {"name": "AMBER", "value": 10, "tint": Color(1.0, 0.78, 0.32)},
	3: {"name": "SPORE CRYSTAL", "value": 16, "tint": Color(0.35, 0.92, 0.86)},
	4: {"name": "QUARTZ", "value": 22, "tint": Color(0.72, 1.0, 0.98)},
	5: {"name": "VOID SHARD", "value": 34, "tint": Color(0.70, 0.42, 1.0)},
	6: {"name": "RELIC DUST", "value": 48, "tint": Color(1.0, 0.86, 0.45)},
}

const RELIC_VALUE := 120
const BASE_CARRY := 12
const ORE_WEIGHT := 1

# --- Upgrades ---------------------------------------------------------------
## id -> {name, desc, max_level, costs[], effect key}
const UPGRADES := {
	"drill": {
		"name": "DRILL HEAD",
		"desc": "Faster drilling, higher tier, more damage.",
		"max_level": 3,
		"costs": [45, 110, 240],
	},
	"suit": {
		"name": "SUIT CORE",
		"desc": "More hull integrity and drill heat capacity.",
		"max_level": 3,
		"costs": [40, 100, 220],
	},
	"cargo": {
		"name": "CARGO RIG",
		"desc": "Carry more ore before returning to the lift.",
		"max_level": 3,
		"costs": [35, 90, 200],
	},
	"charges": {
		"name": "DEMO POUCH",
		"desc": "Carry one extra demolition charge.",
		"max_level": 2,
		"costs": [60, 150],
	},
}

# --- Derived helpers -------------------------------------------------------
func drill_power(level: int) -> float:
	return 1.0 + 0.55 * level

func drill_tier(level: int) -> int:
	return 1 if level >= 1 else 0

func player_max_hp(level: int) -> int:
	return PLAYER_BASE_HP + 25 * level

func heat_capacity(level: int) -> float:
	return 1.0 + 0.22 * level

func carry_capacity(level: int) -> int:
	return BASE_CARRY + 6 * level

func charge_capacity(level: int) -> int:
	return CHARGE_MAX + level
