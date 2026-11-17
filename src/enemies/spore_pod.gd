class_name SporePod
extends Flier
## Spore pod (Spore Veins): a slow, drifting puffball. It floats toward you
## and, beside you, swells for SPORE_SWELL seconds and bursts into a gas
## cloud. It does not bite. Killing it bursts it too. If a blast or a
## fireball kills it, its gas goes up at once as a fireball: good when a
## crawler is next to it, bad when you are.

var swell_t := -1.0
var blasted := false              # the hit that killed it was a blast
var burst := ""                   # how it ended: "gas" or "fire"
static var _told := false


func _ready() -> void:
	super._ready()
	hp = Balance.SPORE_HP
	max_hp = hp
	speed_patrol = Balance.SPORE_SPEED_PATROL
	speed_chase = Balance.SPORE_SPEED_CHASE
	sight = Balance.SPORE_SIGHT
	bite = 0.0
	bite_name = "spore pod"
	spr.texture = load("res://assets/gen/spore.png")
	spr.hframes = 4
	spr.vframes = 3
	spr.offset = Vector2(0, 3)
	eye_glow.scale = Vector2(0.4, 0.4)


func hit_rect() -> Rect2:
	return Rect2(global_position - Vector2(8, 8), Vector2(16, 16))


func _physics_process(delta: float) -> void:
	if state == S.DEAD:
		return
	super._physics_process(delta)
	if state == S.DEAD:
		return
	windup = 0.0                  # it never bites
	attack_cd = 1.0
	var pl: Player = mine.player
	if swell_t < 0.0:
		if pl and not pl.dead and state == S.CHASE and pl.global_position.distance_to(global_position) <= Balance.SPORE_REACH:
			swell_t = Balance.SPORE_SWELL
			Audio.play_at("gas_warn", global_position, -4.0, 0.0, 0.0)
	else:
		swell_t -= delta
		path.clear()              # it stops and swells where it is
		if swell_t <= 0.0:
			die()


func hit(dmg: float, from: Vector2, knock: bool = true) -> void:
	blasted = knock and last_hit in ["charge", "gas"]
	super.hit(dmg, from, knock)


func die() -> void:
	var pos := global_position
	var fire := blasted
	super.die()
	burst = "fire" if fire else "gas"
	if fire:
		mine.gas.call_deferred("_fireball", pos, 1.0 + Balance.SPORE_GAS * 0.15)
	else:
		mine.gas.vents.append({"pos": pos, "t": Balance.GAS_TELEGRAPH, "size": Balance.SPORE_GAS})
		Audio.play_at("gas_warn", pos, 0.0)
		if not _told:
			_told = true
			mine.toast("A SPORE POD BURST - gas! A blast would have set it alight")


func _visual() -> void:
	_bob += get_physics_process_delta_time() * 3.0
	var anims: Dictionary = SpriteDB.meta().get("spore", {}).get("anims", {})
	var anim := "float"
	if state == S.STUNNED:
		anim = "stun"
	elif swell_t >= 0.0:
		anim = "swell"
	if flash > 0.5:
		anim = "hurt"
	var a: Array = anims.get(anim, [0, 4])
	if anim == "swell":
		spr.frame = int(a[0]) + (1 if swell_t < Balance.SPORE_SWELL * 0.5 else 0)
	else:
		spr.frame = int(a[0]) + int(anim_t * 5.0) % int(a[1])
	spr.rotation = 0.0
	spr.flip_h = false
	spr.position = Vector2(0, sin(_bob) * 2.5).round() + (Vector2(randf_range(-1, 1), 0).round() if swell_t >= 0.0 else Vector2.ZERO)
	mat.set_shader_parameter("flash", clampf(flash, 0.0, 0.6 if Settings.reduced_flashing() else 1.0))
	eye_glow.global_position = global_position + spr.position
	var k := 1.0 if swell_t >= 0.0 else 0.55 + 0.2 * sin(_bob * 2.0)
	eye_glow.modulate = Color(0.7, 1.0, 0.25, k * (0.0 if state == S.STUNNED else 1.0))
