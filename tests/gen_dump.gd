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
	var ci := 0
	for a2 in OS.get_cmdline_user_args():
		if a2.begins_with("contract="):
			ci = int(a2.substr(9))
	var d := gen.generate(seed_value, Balance.CONTRACTS[ci])
	if OS.get_cmdline_user_args().has("norepair"):
		pass
	print(d.get("diag_0"), d.get("diag_1"))
	print("boulders=", d.get("boulders"), " geodes=", d.get("geodes"), " pockets=", d.get("water_pockets", []).size(), " lake=", d.get("lake"), " settle=", d.get("settle_steps"), " stabilized=", d.get("basalt_stabilized"), " water=", d.get("water_total"))
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
			if not Cell.is_solid(g.get_mat(x, y)) and g.get_water(x, y) > 0:
				c = Color(0.2, 0.45, 1.0)
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
	var reach := RouteCheck.reachable(g, d["door_outside"] if OS.get_cmdline_user_args().has("up") else d["spawn"], gen.door_open_cells())
	for c in reach.keys():
		img.set_pixelv(c, img.get_pixelv(c).lerp(Color(0.2, 1.0, 0.3), 0.6))
	for a4 in OS.get_cmdline_user_args():
		if a4.begins_with("routeband="):
			var yy4 := a4.substr(10).split(",")
			var rr: Array = d["route"]
			var outs := PackedStringArray()
			for i in rr.size():
				var c4: Vector2i = rr[i]
				if c4.y >= int(yy4[0]) and c4.y <= int(yy4[1]):
					outs.append("%d:%d,%d%s" % [i, c4.x, c4.y, "" if g.get_mat(c4.x, c4.y) in [0, 8, 9] else "!m%d" % g.get_mat(c4.x, c4.y)])
			print("route band: ", " ".join(outs))
	if OS.get_cmdline_user_args().has("ascii"):
		var first := Vector2i(-1, -1)
		var order: Array = d["route"].duplicate()
		if OS.get_cmdline_user_args().has("up"):
			order.reverse()
		for rc in order:
			if not reach.has(rc) and RouteCheck.body_ok(g, rc.x, rc.y):
				first = rc
				break
		print("first unreached standing route cell: ", first)
		for a3 in OS.get_cmdline_user_args():
			if a3.begins_with("at="):
				var pp := a3.substr(3).split(",")
				first = Vector2i(int(pp[0]), int(pp[1]))
		var chars := {0: ".", 1: "s", 2: "H", 3: "o", 4: "A", 5: "#", 6: "g", 7: "c", 8: "L", 9: "="}
		for yy in range(first.y - 10, first.y + 6):
			var line := ""
			for xx in range(first.x - 16, first.x + 16):
				var ch: String = chars[g.get_mat(xx, yy)]
				if reach.has(Vector2i(xx, yy)):
					ch = "*" if ch == "." else ch.to_upper()
				if Vector2i(xx, yy) == first:
					ch = "@"
				line += ch
			print("%3d %s" % [yy, line])
	img.set_pixelv(d["spawn"], Color(0, 1, 0))
	img.set_pixelv(d["door_outside"], Color(1, 1, 1))
	img.resize(g.w * 4, g.h * 4, Image.INTERPOLATE_NEAREST)
	if not OS.get_cmdline_user_args().has("plain"):
		var plan: Dictionary = d.get("plan", {})
		for c in plan.get("chambers", []):
			_outline(img, c["rect"], Color(1, 1, 1, 0.9) if c["backbone"] else Color(0.6, 0.6, 0.7, 0.9))
		for l in d.get("landmarks", []):
			_outline(img, l["rect"], Color(1.0, 0.6, 0.1))
		for wf in d.get("water_features", []):
			_outline(img, wf["rect"], Color(0.3, 0.7, 1.0))
		var kinds: Array = []
		for c in plan.get("chambers", []):
			kinds.append("%s%s%s" % [c["arch"], "/" + c["variant"] if c["variant"] != "" else "", "*" if c["backbone"] else ""])
		print("plan: ", " ".join(PackedStringArray(kinds)), " | branches=", plan.get("branches"), " loops=", plan.get("loops"), " fixes=", plan.get("chamber_fixes"), " approach=", plan.get("relic_approach"), " overlaps=", plan.get("overlaps", []).size())
		var lm: Array = []
		for l in d.get("landmarks", []):
			lm.append(l["kind"])
		var wfs: Array = []
		for wf in d.get("water_features", []):
			wfs.append(wf["kind"])
		print("landmarks: ", lm, " water: ", wfs)
		for c in plan.get("chambers", []):
			if c["fixed"]:
				print("FIXED chamber ", c["arch"], " ", c["rect"])
		print("metrics: ", GenMetrics.compute(d))
	img.save_png(out)
	get_tree().quit(0)


func _outline(img: Image, r: Rect2i, col: Color) -> void:
	var x0 := r.position.x * 4
	var y0 := r.position.y * 4
	var x1 := r.end.x * 4 - 1
	var y1 := r.end.y * 4 - 1
	for x in range(x0, x1 + 1):
		if x >= 0 and x < img.get_width():
			if y0 >= 0 and y0 < img.get_height():
				img.set_pixel(x, y0, col)
			if y1 >= 0 and y1 < img.get_height():
				img.set_pixel(x, y1, col)
	for y in range(y0, y1 + 1):
		if y >= 0 and y < img.get_height():
			if x0 >= 0 and x0 < img.get_width():
				img.set_pixel(x0, y, col)
			if x1 >= 0 and x1 < img.get_width():
				img.set_pixel(x1, y, col)
