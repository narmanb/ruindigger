class_name SpriteDB
extends RefCounted
## Reads the metadata the asset generator writes next to the sprite sheets.

static var _meta: Dictionary = {}


static func meta() -> Dictionary:
	if _meta.is_empty():
		var f := FileAccess.open("res://assets/gen/sprites_meta.json", FileAccess.READ)
		if f:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if typeof(d) == TYPE_DICTIONARY:
				_meta = d
	return _meta


static func props() -> Dictionary:
	return meta().get("props", {})


static func prop_texture(n: String) -> AtlasTexture:
	var r: Array = props().get(n, [0, 0, 1, 1])
	var a := AtlasTexture.new()
	a.atlas = load("res://assets/gen/props.png")
	a.region = Rect2(r[0], r[1], r[2], r[3])
	return a


static func frames(sheet: String, fw: int, fh: int, cols: int, start: int, count: int) -> Array[AtlasTexture]:
	var tex: Texture2D = load(sheet)
	var out: Array[AtlasTexture] = []
	for i in count:
		var k := start + i
		var a := AtlasTexture.new()
		a.atlas = tex
		a.region = Rect2((k % cols) * fw, (k / cols) * fh, fw, fh)
		out.append(a)
	return out
