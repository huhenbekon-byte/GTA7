extends CharacterBody3D
## Third-person player controller: camera-relative movement, walk/jog/sprint, jump,
## curb/step climbing, pushing physics props, melee, fall damage, respawn from water.

signal health_changed(value: float)
signal respawned

const WALK := 2.0
const JOG := 4.6
const SPRINT := 7.6
const ACCEL := 9.0
const AIR_ACCEL := 2.5
const GRAVITY := 22.0
const JUMP_V := 7.2
const STEP_H := 0.5
const TURN_SPEED := 11.0

var move_input := Vector2.ZERO      # x = right, y = forward (from touch joystick or keys)
var sprint_held := false
var jump_pressed := false
var attack_pressed := false

var cam_yaw := 0.0
var cam_pitch := -0.25
var cam_input_timer := 0.0
var health := 100.0

var body: Humanoid
var cam_pivot: Node3D
var spring: SpringArm3D
var camera: Camera3D

var _was_on_floor := true
var _fall_peak_v := 0.0
var _last_safe := Vector3.ZERO
var _safe_timer := 0.0
var _shake := 0.0
var _hit_done := false
var _footstep_phase := 0.0


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 8
	floor_max_angle = deg_to_rad(50)
	floor_snap_length = 0.45
	floor_constant_speed = true
	var shape := CapsuleShape3D.new()
	shape.radius = 0.33
	shape.height = 1.8
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.9
	add_child(cs)

	body = Humanoid.new()
	body.model_path = "res://assets/character/character.glb"
	body.has_cap = true
	body.cap_color = Color(0.85, 0.15, 0.12)
	body.shirt_color = Color(0.93, 0.93, 0.9)
	body.pants_color = Color(0.18, 0.24, 0.42)
	body.shoe_color = Color(0.1, 0.1, 0.1)
	add_child(body)

	cam_pivot = Node3D.new()
	cam_pivot.top_level = true
	add_child(cam_pivot)
	spring = SpringArm3D.new()
	spring.spring_length = 4.3
	spring.margin = 0.25
	spring.collision_mask = 1
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	spring.shape = probe
	spring.add_excluded_object(get_rid())
	cam_pivot.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 70
	camera.far = 650
	camera.near = 0.25
	spring.add_child(camera)
	camera.current = true
	cam_yaw = rotation.y + PI
	_last_safe = global_position
	cam_pivot.global_position = global_position + Vector3(0, 1.55, 0)


func add_camera_input(delta: Vector2) -> void:
	cam_yaw -= delta.x * 0.006
	cam_pitch = clampf(cam_pitch - delta.y * 0.005, -1.25, 0.6)
	cam_input_timer = 1.6


func _physics_process(dt: float) -> void:
	# --- input (keyboard fallback for desktop) ---
	var kb := Vector2(
		Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left"),
		Input.get_action_strength("ui_up") - Input.get_action_strength("ui_down"))
	if Input.is_physical_key_pressed(KEY_D): kb.x += 1
	if Input.is_physical_key_pressed(KEY_A): kb.x -= 1
	if Input.is_physical_key_pressed(KEY_W): kb.y += 1
	if Input.is_physical_key_pressed(KEY_S): kb.y -= 1
	var inp := move_input
	if kb.length() > 0.01:
		inp = kb.limit_length(1.0)
	var sprint := sprint_held or Input.is_physical_key_pressed(KEY_SHIFT)
	if Input.is_physical_key_pressed(KEY_SPACE):
		jump_pressed = true

	var knocked := body.knocked > 0.0
	if knocked:
		body.knocked -= dt
		inp = Vector2.ZERO

	# --- desired velocity, camera relative ---
	var fwd := Vector3(sin(cam_yaw), 0, cos(cam_yaw)) * -1.0
	var right := Vector3(-fwd.z, 0, fwd.x)
	var dir := right * inp.x + fwd * inp.y
	var mag := clampf(inp.length(), 0.0, 1.0)
	var target_speed := 0.0
	if mag > 0.05:
		target_speed = lerpf(WALK, JOG, clampf((mag - 0.3) / 0.6, 0.0, 1.0))
		if sprint and mag > 0.5:
			target_speed = SPRINT
		dir = dir.normalized()
	if body.is_attacking() and is_on_floor():
		target_speed *= 0.25

	var hv := Vector3(velocity.x, 0, velocity.z)
	var accel := ACCEL if is_on_floor() else AIR_ACCEL
	hv = hv.lerp(dir * target_speed, 1.0 - exp(-accel * dt))

	# --- facing ---
	var prev_yaw := body.rotation.y
	if hv.length() > 0.3 and not knocked:
		var want := atan2(hv.x, hv.z)
		body.rotation.y = lerp_angle(body.rotation.y, want, 1.0 - exp(-TURN_SPEED * dt))
	elif body.is_attacking():
		body.rotation.y = lerp_angle(body.rotation.y, atan2(fwd.x, fwd.z), 1.0 - exp(-12.0 * dt))
	var turn := wrapf(body.rotation.y - prev_yaw, -PI, PI) / maxf(dt, 0.0001)

	# --- vertical ---
	velocity.x = hv.x
	velocity.z = hv.z
	if is_on_floor():
		if jump_pressed and not knocked:
			velocity.y = JUMP_V
			floor_snap_length = 0.0
	else:
		velocity.y -= GRAVITY * dt
		_fall_peak_v = minf(_fall_peak_v, velocity.y)
	jump_pressed = false

	# --- attack ---
	if attack_pressed or Input.is_physical_key_pressed(KEY_F):
		if not knocked and body.play_attack() >= 0:
			_hit_done = false
	attack_pressed = false
	if body.is_attacking() and body.attack_hit_moment() and not _hit_done:
		_hit_done = true
		_do_hit()

	var pre_vel := velocity
	move_and_slide()
	if velocity.y <= 0.0:
		floor_snap_length = 0.45

	# --- step up curbs / stairs ---
	if is_on_floor() and is_on_wall() and Vector2(pre_vel.x, pre_vel.z).length() > 0.5:
		_try_step(Vector3(pre_vel.x, 0, pre_vel.z) * dt)

	# --- push rigid bodies ---
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var rb := c.get_collider() as RigidBody3D
		if rb:
			var push := -c.get_normal()
			push.y = 0.0
			rb.apply_impulse(push.normalized() * (0.6 + hv.length() * 0.35) * minf(rb.mass, 20.0) * 0.12, c.get_position() - rb.global_position)

	# --- landing / fall damage ---
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		var impact := -_fall_peak_v
		body.play_land(clampf((impact - 3.0) / 12.0, 0.15, 1.0))
		if impact > 13.0:
			_damage((impact - 13.0) * 9.0)
			_shake = clampf((impact - 10.0) * 0.04, 0.0, 0.5)
		_fall_peak_v = 0.0
	_was_on_floor = on_floor

	if on_floor:
		_safe_timer += dt
		if _safe_timer > 0.6 and get_floor_normal().y > 0.9:
			_last_safe = global_position
			_safe_timer = 0.0
	if global_position.y < -6.0:
		_respawn()

	# --- feed animation ---
	body.speed = Vector2(velocity.x, velocity.z).length() if on_floor else hv.length()
	body.grounded = on_floor
	body.vertical_speed = velocity.y
	body.turn_rate = turn
	body.sprinting = sprint

	if health < 100.0 and health > 0.0:
		health = minf(100.0, health + dt * 2.0)
		health_changed.emit(health)


func _process(dt: float) -> void:
	# camera follow
	var target := global_position + Vector3(0, 1.55, 0)
	cam_pivot.global_position = cam_pivot.global_position.lerp(target, 1.0 - exp(-16.0 * dt))
	cam_input_timer -= dt
	var spd := Vector2(velocity.x, velocity.z).length()
	if cam_input_timer <= 0.0 and spd > 1.0:
		# GTA-like auto align behind the character when moving
		var behind := body.rotation.y + PI
		cam_yaw = lerp_angle(cam_yaw, behind, 1.0 - exp(-1.2 * dt))
		cam_pitch = lerpf(cam_pitch, -0.2, 1.0 - exp(-1.0 * dt))
	cam_pivot.rotation = Vector3(cam_pitch, cam_yaw, 0)
	var sprinting := spd > 6.0
	camera.fov = lerpf(camera.fov, 80.0 if sprinting else 70.0, 1.0 - exp(-3.0 * dt))
	spring.spring_length = lerpf(spring.spring_length, 4.9 if sprinting else 4.2, 1.0 - exp(-2.0 * dt))
	_shake = maxf(0.0, _shake - dt)
	camera.h_offset = 0.35 + randf_range(-1, 1) * _shake * 0.3
	camera.v_offset = randf_range(-1, 1) * _shake * 0.3
	# subtle run camera bob
	camera.v_offset += sin(Time.get_ticks_msec() * 0.012) * 0.02 * clampf(spd / 7.0, 0, 1)


func _try_step(motion: Vector3) -> void:
	var xf := global_transform
	var up := Vector3.UP * STEP_H
	if test_move(xf, up):
		return
	xf.origin += up
	var horiz := motion.normalized() * maxf(motion.length(), 0.08)
	if test_move(xf, horiz):
		return
	xf.origin += horiz
	var col := KinematicCollision3D.new()
	if test_move(xf, -up * 1.1, col):
		if col.get_normal().y > 0.75:
			xf.origin += col.get_travel()
			global_transform = xf


func _do_hit() -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.6
	q.shape = sph
	var f := Vector3(sin(body.rotation.y), 0, cos(body.rotation.y))
	q.transform = Transform3D(Basis(), global_position + Vector3(0, 1.1, 0) + f * 0.8)
	q.collision_mask = 2 | 8
	q.exclude = [get_rid()]
	for r in space.intersect_shape(q, 8):
		var o: Object = r.collider
		if o is RigidBody3D:
			(o as RigidBody3D).apply_central_impulse((f + Vector3.UP * 0.35) * 6.0 * minf((o as RigidBody3D).mass, 15.0) * 0.35)
		elif o.has_method("get_hit"):
			o.get_hit(f)
	_shake = 0.08


func _damage(amount: float) -> void:
	health -= amount
	health_changed.emit(health)
	if health <= 0.0:
		body.knocked = 3.0
		await get_tree().create_timer(2.5).timeout
		_respawn()


func _respawn() -> void:
	velocity = Vector3.ZERO
	global_position = _last_safe + Vector3(0, 0.5, 0)
	health = 100.0
	body.knocked = 0.0
	health_changed.emit(health)
	respawned.emit()
