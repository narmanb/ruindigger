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
const PLATFORM_DROP_TIME := 0.35
const PLATFORM_DROP_SPEED := 60.0
const PLATFORM_DEPTH := 6.0
const TOUCH_LADDER_AXIS_RATIO := 0.8
const TOUCH_STICK_VERTICAL_MIN := 0.55
const TOUCH_STICK_VERTICAL_RATIO := 0.8
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
const CARGO_SCROLL_SPEED := 240.0
const KEEPSAKES := [
	{"name": "Miner's Token", "value": 35, "color": "ffb347", "desc": "A brass shift token from the first Dustworks crews."},
	{"name": "Glowspore Sample", "value": 50, "color": "6ff3d0", "desc": "A sealed vial of living spores, still glowing in the dark."},
	{"name": "Engine Cog", "value": 90, "color": "bc8cff", "desc": "A tiny alloy gear that turns without a visible axle."},
	{"name": "Aqueduct Seal", "value": 70, "color": "5fc0ff", "desc": "A stamped valve seal from the old drowned waterworks."},
	{"name": "Crystal Bloom", "value": 80, "color": "ef9aff", "desc": "A rare cluster of crystals shaped like an unfolding flower."},
]

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
	"scaffold": {"name": "SCAFFOLD HOPPER", "costs": [90, 210, 430],
		"desc": ["40 ladder energy", "70 ladder energy", "110 ladder energy", "160 ladder energy"]},
}
# --- Rubble Ladder (scaffold) ---
# Broken rock packs into scaffold energy; spending it materialises a ladder
# from the player's feet up to the first solid cell.
const SCAFFOLD_CAPACITY := [40, 70, 110, 160]
const SCAFFOLD_GAIN := {1: 1, 2: 2, 3: 1, 7: 1}   # per broken cell by material (soft, hard, loose, cracked)
const SCAFFOLD_ORE_BONUS := 1
const SCAFFOLD_ACTIVATE_COST := 2
const SCAFFOLD_CELL_COST := 1
const SCAFFOLD_MAX_LEN := 120
const SCAFFOLD_BUILD_RATE := 60.0   # cells per second
const CAMERA_LOOK_AHEAD := 0.11     # fraction of the visible width
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
const WATER_EMIT_PER_TICK := 24     # max units a free-falling cell sheds per tick
const WATER_MAX_DROPS := 900        # beyond this, falling water moves cell-to-cell
const WATER_DROP_GRAVITY := 820.0
const WATER_DROP_MAX_FALL := 420.0

# --- Moving water: shared momentum and bounded head approximation ---
const WATER_FLOW_MEMORY := 0.16
const WATER_FLOW_CELL_CAP := 4096
const WATER_FLOW_MAX := 300.0
const WATER_PRESSURE_BUDGET := 512
const WATER_PRESSURE_REGION := 256
const WATER_PRESSURE_MIN_FILL := 48
const WATER_PRESSURE_FREE_HEAD := 1.25  # shallow spills have no pressure jet
const WATER_JET_HEAD_SPEED := 88.0
const WATER_JET_MAX_SPEED := 360.0
const WATER_JET_DISCHARGE := 28
const WATER_DEPOSIT_BUDGET := 24
const WATER_DROP_SWEEP := 4.0          # max travel per collision sample (px)

const WATER_PLAYER_DRIFT_GAIN := 0.65
const WATER_PLAYER_DRIFT_MAX := 120.0
const WATER_PLAYER_SMOOTH := 7.0
const WATER_GROUND_RESISTANCE := 0.45
const WATER_GRIP_RESISTANCE := 0.2
const WATER_CRAWLER_THRESHOLD := 80.0
const WATER_CRAWLER_DRAG := 0.4

# --- Bounded drilling debris and meaningful physics props ---
const DEBRIS_FRAGMENT_CAP := 96
const DEBRIS_PROP_CAP := 24
const DEBRIS_GENERATED_CAP := 12
const DEBRIS_LIFETIME := 90.0
const DEBRIS_FADE := 5.0
const DEBRIS_CHANCE := {1: 0.28, 2: 0.46, 3: 0.55, 4: 0.18, 7: 0.38}
const DEBRIS_LARGE_CHANCE := 0.12
const DEBRIS_SCATTER := 48.0
const DEBRIS_HOP := 65.0
const DEBRIS_LIGHT_DRAG := 240.0
const DEBRIS_STONE_DRAG := 80.0
const DEBRIS_WET_GRAVITY := 0.14
const DEBRIS_BOUNCE := 0.2
const DEBRIS_FRICTION := 160.0
const PROP_AIR_DAMP := 0.25
const PROP_SPIN_DAMP := 2.0
const PROP_FRICTION := 0.65
const PROP_BOUNCE := 0.12
const PROP_MAX_SPEED := 380.0
const PROP_MAX_SPIN := 8.0
const PROP_WAKE_ACCEL := 12.0
const PROP_HIT_SPEED := 100.0
const PROP_MAX_DAMAGE := 12.0
const PROP_DAMAGE_SCALE := 0.025
const PROP_HIT_GRACE := 0.65
const PROP_BLAST_IMPULSE := 240.0
const WATER_PROPS := {
	"crate": {"mass": 0.7, "buoyancy": 1.65, "drag": 4.0, "hp": 2.0, "half": Vector2(6, 6)},
	"canister": {"mass": 0.9, "buoyancy": 1.35, "drag": 3.0, "hp": 3.0, "half": Vector2(4, 6)},
	"stone": {"mass": 4.0, "buoyancy": 0.18, "drag": 0.9, "hp": 4.0, "half": Vector2(5, 4)},
	"scrap": {"mass": 3.0, "buoyancy": 0.08, "drag": 0.7, "hp": 3.0, "half": Vector2(5, 3)},
}

# --- Sustained exposed-face erosion ---
const EROSION_TICK := 0.12
const EROSION_SCAN_BUDGET := 384
const EROSION_FACE_CAP := 512
const EROSION_EDIT_BUDGET := 4
const EROSION_FLOW_THRESHOLD := 32.0
const EROSION_FLOW_SCALE := 100.0
const EROSION_MAX_STRENGTH := 2.0
const EROSION_WARMUP := 1.8
const EROSION_RECOVERY := 0.25
const EROSION_DPS := 0.3
const EROSION_MATERIAL := {1: 1.0, 3: 1.7, 7: 0.55}
const WATER_FX_TICK := 0.18
const WATER_FX_MIN_FLOW := 60.0
const WATER_FX_RADIUS := 360.0
const WATER_FX_BUDGET := 3

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
const CRAWLER_CAP := 20

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
# World shape (0.5): the Dustworks and Spore Veins sit in a central column.
# Under them a bedrock shelf is open only at its far ends; each end drops into
# a wing with its own biome, and both wings meet in the Forgotten Engine vault.
#
#            +---- core: 0 Dustworks ----+
#            |         1 Spore Veins     |
#   +--------+==== bedrock shelf ========+--------+
#   | 3 Drowned Aqueducts  ||  4 Crystal Hollows  |
#   +----------- 2 Forgotten Engine (vault) ------+
const MAP_W := 128
const MAP_H := 236
const CORE_X0 := 28                 # central column spans CORE_X0 .. CORE_X1-1
const CORE_X1 := 100
const STRATUM_ROWS := [2, 72, 142]  # Dustworks top, Spore Veins top, shelf top
const SHELF_Y1 := 150               # shelf rows STRATUM_ROWS[2] .. SHELF_Y1-1
const VAULT_Y0 := 206               # wings span SHELF_Y1 .. VAULT_Y0-1
const DIVIDER_X0 := 62              # bedrock wall between the wings
const DIVIDER_X1 := 66
# zone id == stratum id stored in the grid (tiles, light, music, generation)
const Z_DUST := 0
const Z_SPORE := 1
const Z_ENGINE := 2
const Z_AQUEDUCT := 3
const Z_CRYSTAL := 4
const ZONE_COUNT := 5
const STRATUM_NAMES := ["DUSTWORKS", "SPORE VEINS", "FORGOTTEN ENGINE", "DROWNED AQUEDUCTS", "CRYSTAL HOLLOWS", "THE FIRST CIVILIZATION"]
const ZONE_COLORS := [Color("e0a060"), Color("6ff3d0"), Color("b48cff"), Color("5fb4ff"), Color("ff7ad9"), Color("ffb070")]
# Biome identities (tiles, light, music, backdrop). ZONE_COUNT is the number of
# zones in the main mine; the sixth identity belongs to the separate deep stage.
const BIOME_COUNT := 6
const Z_FIRST := 5

# --- The First Civilization (separate one-way stage under the Engine) --------
# Its own generated map; nothing here resizes or touches the five-zone mine.
const DEEP_W := 200
const DEEP_H := 120
const DEEP_BAND_PLANT := 40          # row where the thermal plant region begins
const DEEP_BAND_TRANSIT := 82        # row where the lower transit region begins
const DEEP_REGION_NAMES := ["ARRIVAL STRUCTURES", "THERMAL PLANT", "LOWER TRANSIT"]
const DEEP_VAULTS := [6, 8]          # great chambers per map
const DEEP_VAULT_W := [26, 44]
const DEEP_VAULT_H := [10, 17]
const DEEP_MONOLITHS := [7, 11]      # buried blocks of ancient composite
const DEEP_CAVE_THRESH := 0.46
const DEEP_HARD_THRESH := 0.05
const DEEP_ORE_VEINS := 46
const DEEP_CRAWLERS := 9
const DEEP_SENTRIES := 3
const DEEP_WATER_POCKETS := [3, 5]
const DEEP_PLUG_CHANCE := 0.55       # share of link tunnels left as cracked rock
const DEEP_DIG_BUDGET := 260.0       # DigCheck seconds, arrival -> Transit Gate
const DEEP_EXIT_BONUS := 450         # credits for leaving through the Transit Gate
const DEEP_DESCENT_SECONDS := 2.4    # length of the descent sequence
# --- Lava, steam and the water/lava reaction (deep stage) ---------------------
# Lava is a second, much more viscous fluid stored beside water. Where the two
# touch they are both consumed: the lava crusts into drillable rock and the
# water flashes to steam. Nothing is created: totals only ever go down.
const LAVA_MAX := 64                 # units per cell (same scale as water)
const LAVA_TICK := 0.24              # seconds per lava step (water: 0.06)
const LAVA_REACT_TICK := 0.06        # contact reactions run as often as water moves
const LAVA_BUDGET := 700             # active cells processed per step
const LAVA_FALL := 16                # units a cell can drop per step
const LAVA_SIDE := 5                 # units a cell can push sideways per step
const LAVA_SPREAD_MIN := 10          # level difference needed before it creeps sideways
const LAVA_REACT_UNITS := 16         # water boiled per contact per step
const LAVA_SOLIDIFY_AT := 48         # cooling a lava cell absorbs before it crusts over (3 contacts)
const LAVA_ROCK_MIN := 12           # a thinner film just hardens away as steam and slag
const LAVA_BURN_MIN := 6             # lava level that burns
const LAVA_BURN_DAMAGE := 9.0
const LAVA_BURN_INTERVAL := 0.45     # seconds between burns (never instant death)
const LAVA_ENEMY_DAMAGE := 30.0
const LAVA_SLOW := 0.55              # horizontal speed kept while wading in lava
const LAVA_WARN_CELLS := 3           # heat warning distance
const STEAM_TICK := 0.1
const STEAM_PER_UNIT := 0.11         # steam density made per unit of water boiled
const STEAM_DECAY := 0.006           # flat density lost per step
const STEAM_KEEP := 0.975            # share of density kept per step (proportional decay)
const STEAM_MIN := 0.04
const STEAM_MAX_CELLS := 480         # hard cap on live steam cells
const STEAM_MAX_DENSITY := 3.0
const STEAM_VENT_SCAN := 16          # cells steam looks along a ceiling for a way up
const STEAM_SCALD := 1.1             # density that starts to hurt
const STEAM_DAMAGE := 3.0
const STEAM_INTERVAL := 0.7
const STEAM_LIFT := 55.0             # upward shove from dense steam (px/s)
const DEEP_LAVA_POCKETS := [5, 8]
const DEEP_LAVA_PITS := 0.6          # chance a lower vault has a lava pit in its floor
const DEEP_QUENCH_PAIRS := [2, 3]    # water pocket sealed above a lava pocket
# --- Thermal plant: the power that wakes the Transit Gate ---------------------
const PLANT_W := 36                  # hall interior (see FirstCivGenerator._thermal_plant)
const PLANT_H := 12
const PLANT_HEAT_NEED := 384         # lava units in the heat basin (6 cells)
const PLANT_COOL_NEED := 384         # water units in the coolant basin (6 cells)
const PLANT_CHECK := 0.25            # seconds between engine state checks
const PLANT_SPINUP := 2.0            # seconds both inputs must hold before power flows
const DESCENT_ROOM := Vector2i(11, 7)   # Ancient Descent Platform room in the Engine vault
const DESCENT_ROOM_SMALL := Vector2i(9, 6)   # used when the vault is crowded
const DESCENT_APPROACH := 14            # cells of approach corridor carved from its door
const DESCENT_TRIES := 2500             # placement attempts per room size (cheap rejection sampling)
const ZONE_RECTS := [
	Rect2i(28, 2, 72, 70),      # Dustworks
	Rect2i(28, 72, 72, 70),     # Spore Veins
	Rect2i(2, 206, 124, 24),    # Forgotten Engine vault
	Rect2i(2, 150, 60, 56),     # Drowned Aqueducts (left wing)
	Rect2i(66, 150, 60, 56),    # Crystal Hollows (right wing)
]
const METERS_PER_CELL := 2.0

# --- generation v2 -----------------------------------------------------------
# chamber archetype weights per stratum (LayoutPlanner); used archetypes are
# down-weighted x3 so a mine rarely repeats one shape
const GEN_LADDER_MIN_RUN := 3
const GEN_LANDING_MAX_RUN := 3
const GEN_LANDING_WIDTH := 2
const GEN_ARCH_WEIGHTS := {
	0: [["works", 3], ["hall", 3], ["terraces", 2], ["fissure", 1]],
	1: [["terraces", 3], ["hall", 2], ["fissure", 2]],
	2: [["ruin", 1]],
	3: [["terraces", 3], ["hall", 4]],                    # aqueducts: wide, wet, level
	4: [["fissure", 3], ["hall", 2], ["terraces", 1]],   # crystal: tall cracks and vaults
}
# per-zone generation budgets, indexed by zone id
#                       dust spore engine aqueduct crystal
const GEN_CHAMBERS :=     [3,   4,    3,     3,       3]
const GEN_CAVE_THRESH :=  [0.4, 0.36, 0.56,  0.5,     0.44]
const GEN_HARD_THRESH :=  [0.28, 0.12, -0.02, 0.2,    0.0]
const GEN_LOOSE :=        [14,  10,   5,     5,       26]
const GEN_BOULDERS :=     [5,   4,    2,     1,       5]
const GEN_POCKETS :=      [[1, 2], [2, 3], [0, 1], [3, 5], [0, 1]]
const GEN_ORE_VEINS :=    [24,  21,   10,    13,      16]
const GEN_GAS :=          [2,   7,    2,     1,       3]
const GEN_CRAWLERS :=     [3,   5,    2,     3,       3]
const GEN_GEODES :=       [0,   [1, 2], [0, 1], [0, 1], [3, 5]]
const GEN_AQUEDUCT_CHANNELS := [2, 3]
# primary ore per zone for fault veins (Cell.ORE_* ids: 1 copper, 2 cobalt, 3 aetherite, 4 fossil)
const GEN_ZONE_ORE :=     [1,   2,    3,     2,       3]
const GEN_CATHEDRAL_CHANCE := 0.55
# base odds of each optional landmark (contracts adjust them in MineGenerator)
const GEN_LANDMARK_ODDS := {"survey_post": 0.6, "hanging_gallery": 0.7, "flooded_machinery": 0.65, "cistern": 0.45, "vent_cluster": 0.3, "floodgate": 0.55}
const GEN_MIN_LANDMARKS := 2
# a basin's flood may reach this many cells beyond the body before it counts as leaking
const GEN_BASIN_LEAK_SLACK := 12
# --- dig-first routes (below the Dustworks the player cuts their own way) ---
# how a vertical route section is built, by stratum: [ladder, ledges, open, plug]
#   ladder - old 2-wide shaft with a full ladder (authored, tutorial zone)
#   ledges - open shaft with plank scaffolds one jump apart
#   open   - bare drop: jump down, come back with a Rubble Ladder or by digging
#   plug   - cracked rock left in place: drill down, ladder back up your own bore
const GEN_SHAFT_STYLE := {
	0: [1.0, 0.0, 0.0, 0.0],
	1: [0.05, 0.2, 0.25, 0.5],
	2: [0.0, 0.15, 0.25, 0.6],
	3: [0.0, 0.2, 0.2, 0.6],
	4: [0.0, 0.1, 0.35, 0.55],
}
const GEN_CORRIDOR_PLUG_CHANCE := 0.9   # per plug opportunity below the Dustworks
const GEN_CORRIDOR_PLUG_LEN := [3, 7]
const GEN_CORRIDOR_PLUG_SPACING := 9   # corridor cells per plug opportunity
# fairness budget (DigCheck seconds with the Mk.I drill, no ladder energy)
const FAIR_DIG_BUDGET_DOWN := 150.0
const FAIR_DIG_BUDGET_UP := 200.0     # way out, using Rubble Ladders

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


func scaffold_capacity(level: int) -> int:
	return SCAFFOLD_CAPACITY[clampi(level, 0, SCAFFOLD_CAPACITY.size() - 1)]


func cargo_capacity(level: int) -> int:
	return CARGO_CAPACITY[clampi(level, 0, CARGO_CAPACITY.size() - 1)]


func hull(level: int) -> float:
	return HULL[clampi(level, 0, HULL.size() - 1)]


func ore_color(id: int) -> Color:
	if ORE.has(id):
		return Color(ORE[id]["color"])
	return Color.WHITE


## Zone at a cell, or -1 for the solid bedrock outside every zone.
func zone_of(x: int, y: int) -> int:
	for z in ZONE_COUNT:
		if (ZONE_RECTS[z] as Rect2i).has_point(Vector2i(x, y)):
			return z
	return -1


## Legacy helper (rows only): prefer TerrainGrid.get_stratum / zone_of.
func stratum_of_row(row: int) -> int:
	if row >= VAULT_Y0:
		return Z_ENGINE
	if row >= STRATUM_ROWS[1]:
		return Z_SPORE
	return Z_DUST
