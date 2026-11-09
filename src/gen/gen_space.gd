class_name GenSpace
extends RefCounted
## Central footprint reservations for generation. Every room, landmark, anchor
## and water feature claims its full footprint (plus clearance) here before it
## carves, so late passes can never silently overwrite earlier structures.

var w: int
var h: int
var claims: Array = []   # [{rect: Rect2i, kind: String, id: String}]


func _init(width: int, height: int) -> void:
	w = width
	h = height


func fits(r: Rect2i, margin: int = 1, ignore_kinds: Array = []) -> bool:
	if r.position.x < 3 or r.position.y < 3 or r.end.x > w - 3 or r.end.y > h - 7:
		return false
	var grown := r.grow(margin)
	for c in claims:
		if ignore_kinds.has(c["kind"]):
			continue
		if (c["rect"] as Rect2i).intersects(grown):
			return false
	return true


func claim(r: Rect2i, kind: String, id: String = "") -> void:
	claims.append({"rect": r, "kind": kind, "id": id if id != "" else "%s%d" % [kind, claims.size()]})


func kind_at(c: Vector2i) -> String:
	for cl in claims:
		if (cl["rect"] as Rect2i).has_point(c):
			return cl["kind"]
	return ""


func rects_of(kind: String) -> Array:
	var out: Array = []
	for c in claims:
		if c["kind"] == kind:
			out.append(c["rect"])
	return out


## True if any two claims overlap (used by tests: there must be none).
func overlaps() -> Array:
	var out: Array = []
	for i in claims.size():
		for j in range(i + 1, claims.size()):
			if claims[i]["kind"] == "anchor" and claims[j]["kind"] == "anchor":
				continue   # the shaft, its landing and the lift room are one structure
			if (claims[i]["rect"] as Rect2i).intersects(claims[j]["rect"]):
				out.append([claims[i]["id"], claims[j]["id"]])
	return out


## Try random placements of a w x h footprint inside a vertical band.
func place(rng: RandomNumberGenerator, rw: int, rh: int, y_lo: int, y_hi: int, margin: int, tries: int = 40, x_lo: int = 3, x_hi: int = -1) -> Rect2i:
	if x_hi < 0:
		x_hi = w - 3
	for t in tries:
		var x := rng.randi_range(x_lo, maxi(x_lo, x_hi - rw))
		var y := rng.randi_range(y_lo, maxi(y_lo, y_hi - rh))
		var r := Rect2i(x, y, rw, rh)
		if fits(r, margin):
			return r
	return Rect2i()
