class_name LayoutPlanner
extends RefCounted
## High-level mine plan, decided before detailed carving.
##
## Dustworks: the timber shaft is the spine; 3 side chambers (works, sediment
##   halls, slumped terraces, the odd fissure) hang off it at platform landings,
##   and two of them are linked to each other, making a loop through the shaft.
## Spore Veins: 3-5 organic chambers (often one monumental cathedral). The
##   guaranteed route passes through 2-3 of them; the rest are optional side
##   caverns. Consecutive backbone chambers get a second, alternate connection.
## Forgotten Engine: 2-3 alloy ruins in varied arrangements; one or two sit on
##   the route, the others are optional (with sentries and aetherite lures).
## The planner only chooses footprints and roles; ChamberCarver gives shape and
## MineGenerator carves connections and validates the result.

var ARCH: Dictionary = Balance.GEN_ARCH_WEIGHTS

var gen: MineGenerator
var rng: RandomNumberGenerator
var space: GenSpace


func _init(generator: MineGenerator, r: RandomNumberGenerator) -> void:
	gen = generator
	rng = r
	space = generator.space


## Weighted pick; archetypes already used in this stratum are three times less
## likely, so a mine rarely repeats one shape while others go unused.
func _pick(s: int, used: Array = []) -> String:
	var opts: Array = ARCH[s]
	var total := 0
	for o in opts:
		total += int(o[1]) * (1 if _has_arch(used, o[0]) else 3)
	var roll := rng.randi_range(1, total)
	for o in opts:
		roll -= int(o[1]) * (1 if _has_arch(used, o[0]) else 3)
		if roll <= 0:
			return o[0]
	return opts[0][0]


func _has_arch(list: Array, arch: String) -> bool:
	for c in list:
		if c["arch"] == arch:
			return true
	return false


func _size(arch: String, s: int, variant: String) -> Vector2i:
	match arch:
		"works":
			return Vector2i(rng.randi_range(18, 30), 3)
		"hall":
			return Vector2i(rng.randi_range(14, 22), rng.randi_range(5, 7)) if s == 0 else Vector2i(rng.randi_range(16, 24), rng.randi_range(6, 8))
		"terraces":
			return Vector2i(rng.randi_range(18, 24), rng.randi_range(8, 10))
		"fissure":
			return Vector2i(rng.randi_range(4, 6), rng.randi_range(13, 20))
		"cathedral":
			return Vector2i(rng.randi_range(26, 34), rng.randi_range(13, 16))
		"ruin":
			match variant:
				"twin":
					return Vector2i(rng.randi_range(24, 30), rng.randi_range(6, 7))
				"stacked":
					return Vector2i(rng.randi_range(12, 16), rng.randi_range(12, 14))
				_:
					return Vector2i(rng.randi_range(11, 20), rng.randi_range(6, 8))
	return Vector2i(12, 6)


func _try(arch: String, s: int, y_lo: int, y_hi: int, variant: String = "") -> Dictionary:
	for attempt in 6:
		var sz := _size(arch, s, variant)
		var r := space.place(rng, sz.x, sz.y, y_lo, y_hi, 3, 30)
		if r.size.x > 0:
			space.claim(r, "chamber", "%s_%d_%d" % [arch, s, space.claims.size()])
			return {"arch": arch, "variant": variant, "rect": r, "stratum": s, "backbone": false, "basin": []}
	return {}


func plan() -> Array:
	var chambers: Array = []
	# Dustworks side chambers along the shaft
	var s0: Array = []
	var tries := 0
	while s0.size() < 3 and tries < 12:
		tries += 1
		var c := _try(_pick(0, s0), 0, 14, Balance.STRATUM_ROWS[1] - 10)
		if not c.is_empty():
			s0.append(c)
	# Spore Veins: maybe a cathedral first (it needs the most room)
	var s1: Array = []
	if rng.randf() < Balance.GEN_CATHEDRAL_CHANCE:
		var cat := _try("cathedral", 1, Balance.STRATUM_ROWS[1] + 12, Balance.STRATUM_ROWS[2] - 4)
		if not cat.is_empty():
			s1.append(cat)
	tries = 0
	var want1 := rng.randi_range(3, 4) + (1 if s1.is_empty() else 0)
	while s1.size() < want1 and tries < 16:
		tries += 1
		var c1 := _try(_pick(1, s1), 1, Balance.STRATUM_ROWS[1] + 12, Balance.STRATUM_ROWS[2] - 4)
		if not c1.is_empty():
			s1.append(c1)
	# Forgotten Engine ruins, varied arrangements
	var s2: Array = []
	var variants := ["hall", "twin", "stacked"]
	variants = [variants[rng.randi_range(0, 2)], variants[rng.randi_range(0, 2)], "hall"]
	var relic_top: int = (gen.data["relic_room"] as Rect2i).position.y
	tries = 0
	var want2 := rng.randi_range(2, 3)
	while s2.size() < want2 and tries < 14:
		var v: String = variants[mini(s2.size(), 2)] if tries < 8 else "hall"
		tries += 1
		var c2 := _try("ruin", 2, Balance.STRATUM_ROWS[2] + 4, relic_top - 4, v)
		if not c2.is_empty():
			s2.append(c2)
	# roles: backbone chambers in Spore Veins and the Engine, ordered by depth
	s1.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["rect"] as Rect2i).position.y < (b["rect"] as Rect2i).position.y)
	s2.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["rect"] as Rect2i).position.y < (b["rect"] as Rect2i).position.y)
	var n1 := mini(s1.size(), 2 + (1 if s1.size() >= 4 and rng.randf() < 0.5 else 0))
	# spread backbone picks across the band so the route visits varied depths
	var picks: Array = []
	for i in n1:
		picks.append(int(round(float(i) * (s1.size() - 1) / maxf(1.0, float(n1 - 1)))) if n1 > 1 else 0)
	for i in s1.size():
		s1[i]["backbone"] = picks.has(i)
	for i in s2.size():
		s2[i]["backbone"] = i == 0 or (i == 1 and s2.size() == 3 and rng.randf() < 0.5)
	var idx := 0
	for c in s0 + s1 + s2:
		c["id"] = "c%d" % idx
		idx += 1
		chambers.append(c)
	return chambers
