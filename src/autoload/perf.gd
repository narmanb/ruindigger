extends Node
## Performance recorder (Settings > Record performance). While a mine is
## running it samples every frame and keeps a compact log: one row per
## interval, plus every slow frame with what was going on. It only watches;
## it never changes how the game plays. When the run ends the report is kept
## in memory (COPY PERFORMANCE REPORT puts it on the clipboard) and written
## to a text file, so it can be sent from any phone and compared.

const INTERVAL := 2.0            # seconds per row
const MAX_ROWS := 600            # ~20 minutes; after that rows are merged in pairs
const SPIKE_MS := 34.0           # a frame slower than this (under 30 fps) is logged
const MAX_SPIKES := 120

var active := false
var mine: Node
var last_report := ""            # the newest finished report
var last_path := ""              # where it was saved
var seconds := 0.0
var frames := 0
var rows: Array = []             # [t, zone, fps, avg_ms, worst_ms, phys_ms, water_ms, sand_ms, lava_ms, drops, wcells, sand, enemies, rocks, draws]
var spikes: Array = []           # [t, ms, zone, drops, sand, enemies, rocks]
var frame_ms: PackedFloat32Array = PackedFloat32Array()
var _acc := 0.0
var _n := 0
var _worst := 0.0
var _phys := 0.0
var _sys := {"water": 0.0, "sand": 0.0, "lava": 0.0}     # usec in this interval
var _sys_n := 0
var _sys_total := {"water": 0.0, "sand": 0.0, "lava": 0.0}
var _sys_worst := {"water": 0.0, "sand": 0.0, "lava": 0.0}
var _row_span := INTERVAL
var _start := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func wanted() -> bool:
	return bool(Settings.get_value("perf_record"))


## Start recording a mine. Does nothing unless the setting is on.
func begin(m: Node) -> void:
	if active:
		finish()
	if not wanted():
		return
	mine = m
	active = true
	seconds = 0.0
	frames = 0
	rows.clear()
	spikes.clear()
	frame_ms = PackedFloat32Array()
	_acc = 0.0
	_n = 0
	_worst = 0.0
	_phys = 0.0
	_sys_n = 0
	_row_span = INTERVAL
	for k in _sys:
		_sys[k] = 0.0
		_sys_total[k] = 0.0
		_sys_worst[k] = 0.0
	_start = {
		"time": Time.get_datetime_string_from_system(),
		"seed": int(Game.run.get("seed", 0)),
		"stage": String(Game.run.get("stage", "mine")),
		"mission": String(Game.run.get("mission", "")),
	}


## Time one system's update (Mine calls this around water, sand and lava).
func add_time(system: String, usec: int) -> void:
	if not active:
		return
	_sys[system] = float(_sys[system]) + usec
	_sys_total[system] = float(_sys_total[system]) + usec
	_sys_worst[system] = maxf(float(_sys_worst[system]), float(usec))


func physics_tick() -> void:
	if active:
		_sys_n += 1


func _process(delta: float) -> void:
	if not active or not is_instance_valid(mine) or get_tree().paused:
		return
	var ms := delta * 1000.0
	seconds += delta
	frames += 1
	_acc += delta
	_n += 1
	_worst = maxf(_worst, ms)
	_phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	if frame_ms.size() < 200000:
		frame_ms.append(ms)
	if ms >= SPIKE_MS and frames > 30 and spikes.size() < MAX_SPIKES:
		var c := _counts()
		spikes.append([seconds, ms, _zone(), c[0], c[2], c[3], c[4]])
	if _acc >= _row_span:
		_flush_row()


func _zone() -> String:
	var z: int = int(mine.get("presented_zone")) if mine.get("presented_zone") != null else 0
	return String(Balance.STRATUM_NAMES[clampi(z, 0, Balance.STRATUM_NAMES.size() - 1)]).substr(0, 4)


## [droplets, active water cells, moving sand cells, enemies, falling rocks]
func _counts() -> Array:
	var w = mine.get("water")
	var s = mine.get("sand")
	var col = mine.get("collapse")
	var en: Array = mine.get("enemies") if mine.get("enemies") != null else []
	return [
		w.drop_count() if w else 0,
		w.active.size() if w else 0,
		s.active.size() if s else 0,
		en.size(),
		(col.falling.size() + col.boulders.size()) if col else 0,
	]


func _flush_row() -> void:
	var c := _counts()
	var n := maxi(1, _n)
	var pn := maxi(1, _sys_n)
	rows.append([
		seconds, _zone(), float(n) / maxf(0.001, _acc), _acc * 1000.0 / n, _worst, _phys / n,
		float(_sys["water"]) / pn / 1000.0, float(_sys["sand"]) / pn / 1000.0, float(_sys["lava"]) / pn / 1000.0,
		c[0], c[1], c[2], c[3], c[4], int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
	])
	_acc = 0.0
	_n = 0
	_worst = 0.0
	_phys = 0.0
	_sys_n = 0
	for k in _sys:
		_sys[k] = 0.0
	if rows.size() > MAX_ROWS:
		_merge_rows()


## Keep long sessions bounded: fold neighbouring rows together and double the
## interval from here on.
func _merge_rows() -> void:
	var out: Array = []
	for i in range(0, rows.size() - 1, 2):
		var a: Array = rows[i]
		var b: Array = rows[i + 1]
		var m: Array = b.duplicate()
		for k in [2, 3, 5, 6, 7, 8]:
			m[k] = (float(a[k]) + float(b[k])) * 0.5
		m[4] = maxf(float(a[4]), float(b[4]))
		for k in [9, 10, 11, 12, 13, 14]:
			m[k] = maxi(int(a[k]), int(b[k]))
		out.append(m)
	rows = out
	_row_span *= 2.0


## Stop recording, build the report and save it. Returns the report text.
func finish() -> String:
	if not active:
		return last_report
	if _n > 0 and is_instance_valid(mine):
		_flush_row()
	active = false
	if frames < 60:
		return last_report       # too short to mean anything
	last_report = build_report()
	last_path = _save(last_report)
	mine = null
	return last_report


func _pct(sorted: PackedFloat32Array, p: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[clampi(int(float(sorted.size() - 1) * p), 0, sorted.size() - 1)]


func build_report() -> String:
	var sorted := frame_ms.duplicate()
	sorted.sort()
	var total := 0.0
	var slow30 := 0
	var slow20 := 0
	for v in frame_ms:
		total += v
		if v > 33.4:
			slow30 += 1
		if v > 50.0:
			slow20 += 1
	var nf := maxi(1, frame_ms.size())
	var avg := total / nf
	var lines: Array = []
	lines.append("RUIN DIGGER PERFORMANCE REPORT")
	lines.append("version %s   recorded %s" % [str(ProjectSettings.get_setting("application/config/version")), _start.get("time", "")])
	lines.append("device: %s | %s %s | %s x%d | %s" % [OS.get_model_name(), OS.get_name(), OS.get_version(), OS.get_processor_name(), OS.get_processor_count(), RenderingServer.get_video_adapter_name()])
	var win := DisplayServer.window_get_size()
	lines.append("screen: %dx%d   refresh %.0f Hz   renderer %s" % [win.x, win.y, DisplayServer.screen_get_refresh_rate(), str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"))])
	lines.append("settings: sand_physics=%d low_effects=%s fps_30=%s camera_zoom=%.2f touch=%s" % [int(Settings.get_value("sand_physics")), str(Settings.get_value("low_effects")), str(Settings.get_value("fps_30")), float(Settings.get_value("camera_zoom")), InputSetup.last_device])
	lines.append("run: stage=%s%s seed=%d   length %.0f s   %d frames" % [_start.get("stage", ""), (" mission=" + String(_start["mission"])) if String(_start.get("mission", "")) != "" else "", int(_start.get("seed", 0)), seconds, frames])
	lines.append("")
	lines.append("SUMMARY")
	lines.append("fps: average %.1f | typical (median) %.1f | 1%% low %.1f | worst frame %.0f ms" % [1000.0 / maxf(0.01, avg), 1000.0 / maxf(0.01, _pct(sorted, 0.5)), 1000.0 / maxf(0.01, _pct(sorted, 0.99)), _pct(sorted, 1.0)])
	lines.append("frames under 30 fps: %.2f%% (%d)   under 20 fps: %.2f%% (%d)" % [100.0 * slow30 / nf, slow30, 100.0 * slow20 / nf, slow20])
	var ticks := maxf(1.0, seconds * float(Engine.physics_ticks_per_second))
	lines.append("per physics tick, average / worst (ms): water %.2f / %.1f | sand %.2f / %.1f | lava %.2f / %.1f" % [
		float(_sys_total["water"]) / ticks / 1000.0, float(_sys_worst["water"]) / 1000.0,
		float(_sys_total["sand"]) / ticks / 1000.0, float(_sys_worst["sand"]) / 1000.0,
		float(_sys_total["lava"]) / ticks / 1000.0, float(_sys_worst["lava"]) / 1000.0])
	lines.append("memory: %.0f MB static   objects %d   nodes %d" % [Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, int(Performance.get_monitor(Performance.OBJECT_COUNT)), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	lines.append("")
	lines.append("SLOW FRAMES (over %.0f ms): %d%s" % [SPIKE_MS, spikes.size(), " (list full)" if spikes.size() >= MAX_SPIKES else ""])
	lines.append("t_s,ms,zone,droplets,sand_moving,enemies,falling_rock")
	for s: Array in spikes:
		lines.append("%.1f,%.0f,%s,%d,%d,%d,%d" % [s[0], s[1], s[2], s[3], s[4], s[5], s[6]])
	lines.append("")
	lines.append("TIMELINE (one row per %.0f s)" % _row_span)
	lines.append("t_s,zone,fps,frame_ms,worst_ms,physics_ms,water_ms,sand_ms,lava_ms,droplets,water_cells,sand_moving,enemies,falling_rock,draw_calls")
	for r: Array in rows:
		lines.append("%.0f,%s,%.0f,%.1f,%.0f,%.1f,%.2f,%.2f,%.2f,%d,%d,%d,%d,%d,%d" % [r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], r[10], r[11], r[12], r[13], r[14]])
	lines.append("END OF REPORT")
	return "\n".join(lines)


## Save under user://perf, and also in the app's own Documents folder on
## the device's shared storage where the platform gives us one.
func _save(text: String) -> String:
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var name := "perf_%s_%s.txt" % [str(ProjectSettings.get_setting("application/config/version")), stamp]
	var saved := ""
	var dirs: Array = ["user://perf"]
	var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS, false)
	if docs != "":
		dirs.append(docs.path_join("RuinDigger"))
	for d: String in dirs:
		if DirAccess.make_dir_recursive_absolute(d) != OK and not DirAccess.dir_exists_absolute(d):
			continue
		var f := FileAccess.open(d.path_join(name), FileAccess.WRITE)
		if f:
			f.store_string(text)
			f.close()
			saved = ProjectSettings.globalize_path(d.path_join(name))
	return saved


## Put the newest report on the clipboard. Returns false if there is none.
func copy_report() -> bool:
	var text := build_report() if active and frames >= 60 else last_report
	if text == "":
		return false
	DisplayServer.clipboard_set(text)
	return true


func has_report() -> bool:
	return last_report != "" or (active and frames >= 60)
