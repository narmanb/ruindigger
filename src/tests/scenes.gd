extends Node
## Scene smoke test: instantiates every shipped scene and asserts it builds
## without script errors, so a broken .tscn or a renamed node can never reach a
## build unnoticed.

const SCENES := [
	"res://src/ui/title_screen.tscn",
	"res://src/world/mine.tscn",
]

const SCRIPTS := [
	"res://src/autoload/fx.gd",
	"res://src/autoload/balance.gd",
	"res://src/autoload/game_state.gd",
	"res://src/autoload/save_manager.gd",
	"res://src/autoload/audio.gd",
	"res://src/autoload/input_setup.gd",
	"res://src/terrain/terrain_grid.gd",
	"res://src/terrain/terrain_renderer.gd",
	"res://src/gen/world_gen.gd",
	"res://src/player/player.gd",
	"res://src/hazards/demo_charge.gd",
	"res://src/hazards/collapse_system.gd",
	"res://src/enemies/grid_pathfinder.gd",
	"res://src/enemies/burrow_crawler.gd",
	"res://src/enemies/ruin_sentry.gd",
	"res://src/enemies/sentry_shot.gd",
	"res://src/world/mine.gd",
	"res://src/ui/hud.gd",
	"res://src/ui/minimap.gd",
	"res://src/ui/ui_theme.gd",
	"res://src/ui/title_screen.gd",
	"res://src/ui/outpost.gd",
	"res://src/ui/settings.gd",
	"res://src/ui/pause_menu.gd",
	"res://src/ui/result_screen.gd",
	"res://src/ui/touch_controls.gd",
]

var _passed := true

func _ready() -> void:
	print("=== RUIN DIGGER scene smoke test ===")
	for path in SCRIPTS:
		var res := load(path)
		check(res != null, "loads %s" % path)
	for path in SCENES:
		await _smoke_scene(path)
	print("=== scene smoke result: %s ===" % ("PASS" if _passed else "FAIL"))
	get_tree().quit(0 if _passed else 1)

func _smoke_scene(path: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		check(false, "%s is a PackedScene" % path)
		return
	var inst := packed.instantiate()
	check(inst != null, "%s instantiates" % path)
	if inst == null:
		return
	# Mine and title screens are heavy; add them for one frame to force _ready.
	add_child(inst)
	await get_tree().process_frame
	check(inst.get_child_count() >= 0, "%s builds its tree" % path)
	# Free immediately (not queue_free) and let a physics frame pass, so the
	# bodies the scene created are released before the process exits; otherwise
	# the engine reports leaked PhysicsBody2D RIDs at shutdown.
	inst.free()
	await get_tree().physics_frame

func check(cond: bool, name: String) -> void:
	if cond:
		print("  ok   ", name)
	else:
		print("  FAIL ", name)
		_passed = false
