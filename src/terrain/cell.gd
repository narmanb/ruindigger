class_name Cell
extends RefCounted
## Material ids and static per-material facts. Tuning numbers live in Balance.

const AIR := 0
const SOFT := 1      # sediment
const HARD := 2      # basalt
const LOOSE := 3     # rubble / gravel, falls when unsupported
const ALLOY := 4     # ruin alloy (Mk.IV drill only, immune to blasts)
const BEDROCK := 5   # map boundary, indestructible
const GAS := 6       # gas sac embedded in rock
const CRACKED := 7   # weak wall that hides secrets
const LADDER := 8    # non-solid, climbable
const PLATFORM := 9  # one-way, solid from above only

# flags
const F_EXPLORED := 1
const F_PROTECTED := 2   # never damaged by anything (lift, relic chamber shell)
const F_DUG := 4         # was solid at generation time; shows back wall
const F_CLAIMED := 8     # ore already paid out
const F_WATER_SAFE := 32 # erosion immunity for guaranteed route bodies/supports
const F_PLAYER_BUILT := 64 # ladder cell materialised by the player
const F_NO_RUBBLE := 16  # rubble shatters instead of landing here

# ore ids (see Balance.ORE)
const ORE_NONE := 0
const ORE_COPPER := 1
const ORE_COBALT := 2
const ORE_AETHER := 3
const ORE_FOSSIL := 4

# visual atlas block group per material
const VIS_SOFT := "soft"
const VIS_HARD := "hard"
const VIS_LOOSE := "loose"


static func is_solid(m: int) -> bool:
	return m != AIR and m != LADDER and m != PLATFORM


static func is_open(m: int) -> bool:
	return not is_solid(m)


static func blocks_walk(m: int) -> bool:
	return is_solid(m)


static func supports(m: int) -> bool:
	## can a body stand on top of this cell?
	return is_solid(m) or m == PLATFORM


static func is_destructible(m: int) -> bool:
	return m != AIR and m != BEDROCK and m != LADDER


static func blast_proof(m: int) -> bool:
	return m == ALLOY or m == BEDROCK


static func max_hp(m: int) -> float:
	if Balance.MATERIAL.has(m):
		return float(Balance.MATERIAL[m]["hp"])
	return 1.0


static func tier(m: int) -> int:
	if Balance.MATERIAL.has(m):
		return int(Balance.MATERIAL[m]["tier"])
	return 0


static func sound_class(m: int) -> String:
	match m:
		HARD, CRACKED:
			return "hard"
		ALLOY, BEDROCK:
			return "metal"
		_:
			return "soft"


static func debris_color(m: int, stratum: int) -> Color:
	match m:
		SOFT, CRACKED:
			return [Color("a46a33"), Color("2f7566"), Color("54485f"), Color("3a5f80"), Color("6e3a72"), Color("2a2730")][stratum]
		HARD:
			return [Color("756e70"), Color("4f6a83"), Color("4b3a5c"), Color("6c8ba6"), Color("a56cc0"), Color("3c3c4a")][stratum]
		LOOSE:
			return [Color("c4a070"), Color("5e9a80"), Color("73617a"), Color("7fa2bd"), Color("c79ae0"), Color("7c4a30")][stratum]
		GAS:
			return Color("a6c51f")
		ALLOY:
			return Color("7c6ca6")
		_:
			return Color("6a6a6a")
