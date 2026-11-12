extends Node
## Colour-coded PNG of a generated First Civilization map.
##   godot --headless res://tests/deep_dump.tscn -- seed=7 out=/tmp/deep.png [norepair]
## `seed` is the RUN seed (the deep seed is derived from it, as in the game).

func _ready() -> void:
	var run_seed := 7
	var out := "user://deep.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seed="):
			run_seed = int(a.substr(5))
		elif a.begins_with("out="):
			out = a.substr(4)
	var gen := FirstCivGenerator.new()
	gen.no_repair = OS.get_cmdline_user_args().has("norepair")
	var t0 := Time.get_ticks_msec()
	var d := gen.generate(FirstCivGenerator.deep_seed(run_seed))
	print("deep generated in %d ms, valid=%s repairs=%d" % [Time.get_ticks_msec() - t0, d["valid"], d["repairs"]])
	print("dig_to_gate_s=", d.get("dig_to_gate_s"), " traps_sealed=", d.get("traps_sealed", 0), " plan=", d["plan"],
		" water=", d.get("water_total"), " settle=", d.get("settle_steps"), " crawlers=", d.get("crawlers"), " sentries=", d.get("sentries"), " lava=", d.get("lava_total"), " pockets=", d.get("lava_pockets"), " pairs=", d.get("quench_pairs"), " lava_settle=", d.get("lava_settle_steps"))
	var g: TerrainGrid = d["grid"]
	var cols := {0: Color(0.05, 0.04, 0.07), 1: Color(0.22, 0.2, 0.25), 2: Color(0.34, 0.34, 0.4), 3: Color(0.6, 0.4, 0.25),
		4: Color(0.7, 0.58, 0.32), 5: Color(0.02, 0.02, 0.03), 6: Color(0.7, 0.9, 0.2), 7: Color(0.9, 0.5, 0.3),
		8: Color(0.9, 0.8, 0.2), 9: Color(0.7, 0.5, 0.3)}
	var img := Image.create(g.w, g.h, false, Image.FORMAT_RGBA8)
	for y in g.h:
		for x in g.w:
			var c: Color = cols[g.get_mat(x, y)]
			if not Cell.is_solid(g.get_mat(x, y)) and g.get_water(x, y) > 0:
				c = Color(0.2, 0.45, 1.0)
			if not Cell.is_solid(g.get_mat(x, y)) and g.get_lava(x, y) > 0:
				c = Color(1.0, 0.4, 0.08)
			var o := g.get_ore(x, y)
			if o != 0:
				c = Balance.ore_color(o)
			img.set_pixel(x, y, c)
	var reach := RouteCheck.reachable(g, d["spawn"])
	for c2 in reach.keys():
		img.set_pixelv(c2, img.get_pixelv(c2).lerp(Color(0.2, 1.0, 0.3), 0.45))
	for e in d["entities"]:
		var col := Color.WHITE
		match e["type"]:
			"crawler": col = Color.RED
			"sentry": col = Color.MAGENTA
			"transit_gate": col = Color.CYAN
		img.set_pixelv(e["cell"], col)
	img.set_pixelv(d["spawn"], Color(0, 1, 0))
	img.resize(g.w * 4, g.h * 4, Image.INTERPOLATE_NEAREST)
	img.save_png(out)
	get_tree().quit(0)
