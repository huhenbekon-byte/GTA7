extends CharacterBody3D
## Simple pedestrian: wanders, avoids walls and ledges, idles, reacts to being hit
## (falls, gets up, runs away).

const GRAVITY := 22.0

var body: Humanoid
var _dir := Vector3.FORWARD
var _speed := 1.3
var _state_t := 0.0
var _idle := false
var _flee := 0.0
var _rng := RandomNumberGenerator.new()

const SHIRTS := [Color(0.7, 0.15, 0.15), Color(0.15, 0.3, 0.7), Color(0.85, 0.75, 0.2), Color(0.2, 0.2, 0.22),
	Color(0.9, 0.9, 0.9), Color(0.4, 0.6, 0.3), Color(0.55, 0.3, 0.6), Color(0.95, 0.5, 0.2), Color(0.3, 0.55, 0.6)]
const PANTS := [Color(0.15, 0.2, 0.35), Color(0.1, 0.1, 0.1), Color(0.45, 0.38, 0.28), Color(0.3, 0.3, 0.32), Color(0.25, 0.3, 0.2)]
const SKINS := [Color(0.95, 0.78, 0.65), Color(0.8, 0.6, 0.45), Color(0.55, 0.38, 0.27), Color(0.35, 0.24, 0.17), Color(0.9, 0.7, 0.55)]
const HAIR := [Color(0.06, 0.05, 0.05), Color(0.35, 0.22, 0.1), Color(0.75, 0.6, 0.3), Color(0.5, 0.5, 0.5)]


func _ready() -> void:
	_rng.randomize()
	collision_layer = 8
	collision_mask = 1 | 2 | 4 | 8
	floor_max_angle = deg_to_rad(50)
	floor_snap_length = 0.4
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.8
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.9
	add_child(cs)
	body = Humanoid.new()
	body.shirt_color = SHIRTS[_rng.randi() % SHIRTS.size()]
	body.pants_color = PANTS[_rng.randi() % PANTS.size()]
	body.skin_color = SKINS[_rng.randi() % SKINS.size()]
	body.hair_color = HAIR[_rng.randi() % HAIR.size()]
	body.has_cap = _rng.randf() < 0.25
	body.cap_color = SHIRTS[_rng.randi() % SHIRTS.size()].darkened(0.3)
	var s := _rng.randf_range(0.92, 1.06)
	body.scale = Vector3(s, s, s)
	add_child(body)
	_pick_dir()


func _pick_dir() -> void:
	var a := _rng.randf() * TAU
	_dir = Vector3(sin(a), 0, cos(a))
	_state_t = _rng.randf_range(4.0, 10.0)
	_idle = _rng.randf() < 0.2
	_speed = _rng.randf_range(1.1, 1.6)


func get_hit(from_dir: Vector3) -> void:
	if body.knocked > 0.0:
		return
	body.knocked = 2.4
	velocity = from_dir * 5.0 + Vector3.UP * 3.5
	_dir = from_dir.normalized()
	_flee = 0.0


func _physics_process(dt: float) -> void:
	var space := get_world_3d().direct_space_state
	_state_t -= dt
	var target_speed := 0.0

	if body.knocked > 0.0:
		body.knocked -= dt
		if body.knocked <= 0.0:
			_flee = 6.0
	else:
		if _flee > 0.0:
			_flee -= dt
			target_speed = 5.0
		elif not _idle:
			target_speed = _speed
		if _state_t <= 0.0:
			_pick_dir()
		# obstacle / ledge check every frame (cheap rays)
		if target_speed > 0.0:
			var origin := global_position + Vector3(0, 1.0, 0)
			var q := PhysicsRayQueryParameters3D.create(origin, origin + _dir * 1.4, 1 | 2 | 4 | 8, [get_rid()])
			var blocked := not space.intersect_ray(q).is_empty()
			var ahead := global_position + _dir * 1.2 + Vector3(0, 0.6, 0)
			var q2 := PhysicsRayQueryParameters3D.create(ahead, ahead + Vector3(0, -1.8, 0), 1 | 2, [get_rid()])
			var ground := space.intersect_ray(q2)
			if blocked or ground.is_empty():
				var a := atan2(_dir.x, _dir.z) + _rng.randf_range(PI * 0.5, PI * 1.5)
				_dir = Vector3(sin(a), 0, cos(a))

	var hv := Vector3(velocity.x, 0, velocity.z)
	var k := 6.0 if is_on_floor() else 0.5
	if body.knocked <= 0.0 or is_on_floor():
		hv = hv.lerp(_dir * target_speed, 1.0 - exp(-k * dt))
	velocity.x = hv.x
	velocity.z = hv.z
	if not is_on_floor():
		velocity.y -= GRAVITY * dt
	var prev := body.rotation.y
	if hv.length() > 0.2 and body.knocked <= 0.0:
		body.rotation.y = lerp_angle(body.rotation.y, atan2(hv.x, hv.z), 1.0 - exp(-6.0 * dt))
	move_and_slide()
	body.speed = hv.length() if body.knocked <= 0.0 else 0.0
	body.grounded = is_on_floor()
	body.vertical_speed = velocity.y
	body.turn_rate = wrapf(body.rotation.y - prev, -PI, PI) / maxf(dt, 0.0001)
