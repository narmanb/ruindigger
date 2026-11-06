extends Node
## Debug tool: writes a colour-coded PNG of a generated mine.
## godot --headless res://tests/gen_dump.tscn -- seed=123 out=/tmp/map.png

func _ready() -> void:
	var seed_value := 123
	var out := "user://map.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seed="):
			seed_value = int(a.substr(5))
		elif a.begins_with("out="):
			out = a.substr(4)
	var gen := MineGenerator.new()
	gen.no_repair = OS.get_cmdline_user_args().has("norepair")
	var t0 := Time.get_ticks_msec()
	var d := gen.generate(seed_value)
	if OS.get_cmdline_user_args().has("norepair"):
		pass
	print(d.get("diag_0"), d.get("diag_1"))
	print("generated in %d ms, valid=%s repairs=%d" % [Time.get_ticks_msec() - t0, d["valid"], d["repairs"]])
	var g: TerrainGrid = d["grid"]
	var img := Image.create(g.w, g.h, false, Image.FORMAT_RGBA8)
	var cols := {0: Color(0.05, 0.04, 0.07), 1: Color(0.55, 0.38, 0.2), 2: Color(0.45, 0.43, 0.42), 3: Color(0.8, 0.7, 0.45),
		4: Color(0.45, 0.35, 0.7), 5: Color(0.1, 0.1, 0.12), 6: Color(0.7, 0.9, 0.2), 7: Color(0.9, 0.5, 0.3),
		8: Color(0.9, 0.8, 0.2), 9: Color(0.7, 0.5, 0.3)}
	for y in g.h:
		for x in g.w:
			var c: Color = cols[g.get_mat(x, y)]
			if g.get_mat(x, y) in [1, 2] and g.get_stratum(x, y) == 1:
				c = c.lerp(Color(0.1, 0.5, 0.45), 0.5)
			if g.get_mat(x, y) in [1, 2] and g.get_stratum(x, y) == 2:
				c = c.lerp(Color(0.3, 0.2, 0.4), 0.6)
			var o := g.get_ore(x, y)
			if o != 0:
				c = Balance.ore_color(o)
			img.set_pixel(x, y, c)
	for e in d["entities"]:
		var col := Color.WHITE
		match e["type"]:
			"crawler": col = Color.RED
			"sentry": col = Color.MAGENTA
			"lift": col = Color.GREEN
			"relic": col = Color.CYAN
			"cache": col = Color.ORANGE
		img.set_pixelv(e["cell"], col)
	var reach := RouteCheck.reachable(g, d["spawn"], gen.door_open_cells())
	for c in reach.keys():
		img.set_pixelv(c, img.get_pixelv(c).lerp(Color(0.2, 1.0, 0.3), 0.6))
	img.set_pixelv(d["spawn"], Color(0, 1, 0))
	img.set_pixelv(d["door_outside"], Color(1, 1, 1))
	img.resize(g.w * 4, g.h * 4, Image.INTERPOLATE_NEAREST)
	img.save_png(out)
	get_tree().quit(0)
