class_name CodexPanel
extends PanelContainer
## The codex: creatures (open on your first kill), hazards, explosives, relics
## and zones (open the first time you meet them), your records, and the hints
## you have seen. Shared by the title screen and the pause menu.

signal closed

const TABS := ["creature", "hazard", "explosive", "relic", "zone", "records", "hints"]
const TAB_NAMES := {"creature": "CREATURES", "hazard": "HAZARDS", "explosive": "EXPLOSIVES", "relic": "RELICS",
	"zone": "ZONES", "records": "RECORDS", "hints": "HINTS"}

var tab := "creature"
var selected := ""                 # "cat:id" of the page shown
var tab_buttons: Dictionary = {}
var list: VBoxContainer
var list_scroll: ScrollContainer
var page: Label
var page_title: Label
var count_label: Label
var back: Button


func _ready() -> void:
	theme = UIKit.theme()
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	add_child(outer)
	var head := HBoxContainer.new()
	head.add_child(UIKit.header("CODEX"))
	count_label = UIKit.label("", 10, UIKit.MUTED)
	count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(count_label)
	outer.add_child(head)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 2)
	outer.add_child(tabs)
	for t: String in TABS:
		var b := UIKit.button(TAB_NAMES[t], func() -> void: show_tab(t), 0.0)
		b.add_theme_font_size_override("font_size", 9)
		b.toggle_mode = true
		tabs.add_child(b)
		tab_buttons[t] = b
	outer.add_child(UIKit.Scanline.new())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	outer.add_child(body)
	var h := clampf(get_viewport_rect().size.y - 130.0, 120.0, 220.0)
	list_scroll = ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(160, h)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UIKit.touch_scrollbar(list_scroll)
	body.add_child(list_scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	list_scroll.add_child(list)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(330, h)
	body.add_child(right)
	page_title = UIKit.label("", 13, UIKit.AMBER, true)
	right.add_child(page_title)
	var page_scroll := ScrollContainer.new()
	page_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UIKit.touch_scrollbar(page_scroll)
	right.add_child(page_scroll)
	page = UIKit.label("", 10, UIKit.TEXT)
	page.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.custom_minimum_size = Vector2(310, 0)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_scroll.add_child(page)
	back = UIKit.button("BACK", close, 160.0)
	outer.add_child(back)
	show_tab(tab)
	_center()
	get_viewport().size_changed.connect(_center)
	await get_tree().process_frame
	_center()
	if tab_buttons.has(tab):
		tab_buttons[tab].grab_focus()


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()


## Pages found / pages in total, over the five page categories.
static func found_counts() -> Vector2i:
	var have := 0
	var total := 0
	for cat: String in CodexData.CATS:
		for e: Dictionary in CodexData.entries(cat):
			total += 1
			if Progress.has_entry("%s:%s" % [cat, e["id"]]):
				have += 1
	return Vector2i(have, total)


func show_tab(t: String) -> void:
	tab = t
	for k: String in tab_buttons:
		tab_buttons[k].button_pressed = k == t
	for c in list.get_children():
		c.queue_free()
	var fc := found_counts()
	count_label.text = "%d / %d PAGES FOUND" % [fc.x, fc.y]
	list_scroll.visible = t in CodexData.CATS
	if t == "records":
		page_title.text = "RECORDS"
		page.text = records_text()
		return
	if t == "hints":
		page_title.text = "HINTS SEEN"
		page.text = hints_text()
		return
	var first := ""
	for e: Dictionary in CodexData.entries(t):
		var key := "%s:%s" % [t, e["id"]]
		var open := Progress.has_entry(key)
		var b := UIKit.button(String(e["name"]) if open else "???", func() -> void: show_page(key), 150.0)
		b.add_theme_font_size_override("font_size", 10)
		b.disabled = not open
		list.add_child(b)
		if open and first == "":
			first = key
	if first != "":
		show_page(first)
	else:
		page_title.text = String(TAB_NAMES[t])
		page.text = locked_text(t)


func show_page(key: String) -> void:
	selected = key
	var e := CodexData.entry(key)
	page_title.text = String(e.get("name", "")).to_upper()
	page_title.add_theme_color_override("font_color", Color(e["color"]) if e.has("color") else UIKit.AMBER)
	page.text = String(e.get("text", ""))


static func locked_text(cat: String) -> String:
	match cat:
		"creature":
			return "Nothing here yet. A creature's page opens the first time you kill one."
		"relic":
			return "Nothing here yet. Relics are rare finds in the mine."
	return "Nothing here yet. Pages open the first time you run into something."


static func records_text() -> String:
	var st := Progress.stats
	var lines: Array = [
		"Dives: %d" % int(st.get("runs", 0)),
		"Extractions: %d" % int(st.get("extractions", 0)),
		"Deaths: %d" % int(st.get("deaths", 0)),
		"Best depth: %d m" % int(st.get("best_depth", 0)),
		"Best haul: %d CR" % int(st.get("best_haul", 0)),
		"Credits earned: %d CR" % int(st.get("lifetime_credits", 0)),
		"Contract relics recovered: %d" % int(st.get("relics", 0)),
		"",
		"Kills: %d" % int(st.get("kills", 0)),
		"Terrain kills: %d" % int(st.get("terrain_kills", 0)),
		"Most kills in one dive: %d" % int(st.get("most_kills", 0)),
		"Ore broken: %d" % int(st.get("ore_mined", 0)),
		"Ladders built: %d" % int(st.get("ladders_built", 0)),
		"Explosives used: %d" % int(st.get("explosives_used", 0)),
		"Longest dive: %s" % clock(int(st.get("longest_run", 0))),
	]
	var missions: Array = []
	for m: Dictionary in Balance.MISSIONS:
		var id := String(m["id"])
		if Progress.mission_done(id):
			var best := "fastest %s" % clock(int(Progress.mission_best[id])) if Progress.mission_best.has(id) else "done"
			missions.append("%s: %s" % [String(m["name"]).capitalize(), best])
	if not missions.is_empty():
		lines.append("")
		lines.append("Missions (%d / %d):" % [missions.size(), Balance.MISSIONS.size()])
		lines.append_array(missions)
	var fc := found_counts()
	lines.append("")
	lines.append("Codex pages found: %d / %d" % [fc.x, fc.y])
	return "\n".join(lines)


static func hints_text() -> String:
	if Progress.hints_seen.is_empty():
		return "No hints seen yet." if bool(Settings.get_value("hints")) else "Hints are turned off in Settings."
	var lines: Array = []
	for id: String in CodexData.HINTS:
		if Progress.seen_hint(id):
			lines.append("- " + String(CodexData.HINTS[id]))
	return "\n".join(lines)


static func clock(s: int) -> String:
	return "%d:%02d" % [s / 60, s % 60]


func _center() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport_rect().size
	var ms := get_combined_minimum_size()
	ms.x = minf(ms.x, vp.x - 12.0)
	ms.y = minf(ms.y, vp.y - 12.0)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -ms.x * 0.5
	offset_right = ms.x * 0.5
	offset_top = -ms.y * 0.5
	offset_bottom = ms.y * 0.5
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
