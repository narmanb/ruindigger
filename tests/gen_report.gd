extends Node
## Generation sweep report: every seed x contract, validity + GenMetrics.
##   godot --headless res://tests/gen_report.tscn -- seeds=125 out=/tmp/report.csv
## Prints aggregate min/mean/max per metric and lists any invalid seeds.

func _ready() -> void:
	var n := 125
	var out := ""
	var start := 1000
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seeds="):
			n = int(a.substr(6))
		elif a.begins_with("out="):
			out = a.substr(4)
		elif a.begins_with("start="):
			start = int(a.substr(6))
	var rows: Array = []
	var keys: Array = []
	var invalid: Array = []
	var t_all := Time.get_ticks_msec()
	for i in n:
		for ci in Balance.CONTRACTS.size():
			var seed_value := start + i * 7919 + ci * 104729
			var gen := MineGenerator.new()
			var t0 := Time.get_ticks_msec()
			var d := gen.generate(seed_value, Balance.CONTRACTS[ci])
			d["gen_ms"] = Time.get_ticks_msec() - t0
			var m := GenMetrics.compute(d)
			m["seed"] = seed_value
			m["contract"] = Balance.CONTRACTS[ci]["id"]
			m["valid"] = 1 if d["valid"] else 0
			m["repairs"] = d["repairs"]
			if not d["valid"] or int(d["repairs"]) > 0:
				invalid.append("%d/%s valid=%s repairs=%d" % [seed_value, m["contract"], d["valid"], d["repairs"]])
			for k in m.keys():
				if not keys.has(k):
					keys.append(k)
			rows.append(m)
	print("combos: %d  total %.1fs" % [rows.size(), (Time.get_ticks_msec() - t_all) / 1000.0])
	for k in keys:
		if k in ["seed", "contract"]:
			continue
		var lo := INF
		var hi := -INF
		var tot := 0.0
		var cnt := 0
		for r in rows:
			if r.has(k):
				var v := float(r[k])
				lo = minf(lo, v)
				hi = maxf(hi, v)
				tot += v
				cnt += 1
		print("%-18s min %9.2f  mean %9.2f  max %9.2f" % [k, lo, tot / maxi(cnt, 1), hi])
	print("invalid or repaired: %d" % invalid.size())
	for s in invalid:
		print("  ", s)
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_line(",".join(PackedStringArray(keys)))
		for r in rows:
			var vals := PackedStringArray()
			for k in keys:
				vals.append(str(r.get(k, "")))
			f.store_line(",".join(vals))
		f.close()
	get_tree().quit(0 if invalid.is_empty() else 1)
