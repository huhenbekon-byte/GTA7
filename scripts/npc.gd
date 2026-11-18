extends CharacterBody3D
## Pedestrian with a small behaviour state machine:
## WALK (sidewalk-following, whisker steering, separation) / IDLE (phone, talk, look around)
## FLEE (panic run) / COWER / FIGHT (tough guys hit back) / RAGDOLL / GETUP.
## Reacts to fights and explosions around it (main.gd calls alarm()).

enum S { WALK, IDLE, FLEE, COWER, FIGHT, RAGDOLL, GETUP }

const GRAVITY := 22.0
const MODEL := "res://assets/character/character.glb"

var state := S.WALK
var body: Humanoid
var health := 100.0
var personality := 0          # 0 flee, 1 coward (cower), 2 tough (fights back)
var world: Node               # main.gd

# --- scripted / mission control ---
var persistent := false        # never despawned by the crowd manager
var no_react := false          # ignores alarms (police officer, scripted actors)
var scripted := false          # movement driven by a mission script
var script_target = null       # Vector3 to walk to, or null
var script_speed := 1.4
var script_face = null         # Vector3 to face when standing
var preset_clothes := Color(0, 0, 0, 0)
var preset_skin := Color(0, 0, 0, 0)
var label := ""                # shown above the head (mission actors)
var model_override := ""       # use another rigged model instead of the default
var force_personality := -1

var _dir := Vector3.FORWARD
var _speed := 1.3
var _timer := 0.0
var _threat := Vector3.ZERO
var _attack_cd := 0.0
var _hit_done := false
var _rng := RandomNumberGenerator.new()
var _shape: CollisionShape3D
var _stuck := 0.0
var _last_pos := Vector3.ZERO
var _level := 0.0              # ground height the walker sticks to (sidewalk level)

const CLOTHES := [Color(1, 1, 1), Color(1.0, 0.7, 0.68), Color(0.7, 0.8, 1.0), Color(1.0, 0.92, 0.65),
	Color(0.72, 1.0, 0.75), Color(0.85, 0.72, 1.0), Color(0.5, 0.5, 0.55), Color(1.0, 0.82, 0.6), Color(0.65, 0.95, 1.0)]
const SKINS := [Color(1, 1, 1), Color(0.95, 0.9, 0.88), Color(0.8, 0.68, 0.6), Color(0.62, 0.5, 0.43), Color(0.48, 0.38, 0.33)]


func _ready() -> void:
	_rng.randomize()
	add_to_group("npc")
	collision_layer = 8
	collision_mask = 1 | 2 | 4 | 8 | 32
	floor_max_angle = deg_to_rad(50)
	floor_snap_length = 0.4
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.8
	_shape = CollisionShape3D.new()
	_shape.shape = shape
	_shape.position.y = 0.9
	add_child(_shape)

	body = Humanoid.new()
	body.model_path = model_override if model_override != "" else MODEL
	body.tint_clothes = preset_clothes if preset_clothes.a > 0.0 else CLOTHES[_rng.randi() % CLOTHES.size()]
	body.tint_skin = preset_skin if preset_skin.a > 0.0 else SKINS[_rng.randi() % SKINS.size()]
	body.model_height = _rng.randf_range(1.66, 1.92)
	add_child(body)
	var r := _rng.randf()
	personality = 2 if r < 0.22 else (1 if r < 0.45 else 0)
	if force_personality >= 0:
		personality = force_personality
	_level = global_position.y
	_start_walk()


# ------------------------------------------------------------------ reactions
## Something scary happened at `pos` (fight, explosion).
func alarm(pos: Vector3, from_player: bool) -> void:
	if no_react or scripted:
		return
	if state in [S.RAGDOLL, S.GETUP, S.FIGHT]:
		return
	_threat = pos
	if personality == 2 and from_player and _rng.randf() < 0.5:
		_start_fight()
	elif personality == 1 and state != S.FLEE:
		state = S.COWER
		_timer = _rng.randf_range(3.0, 6.0)
	else:
		_start_flee()


## Hit by the player (strength 1 = punch, 2 = kick / thrown object, 3 = heavy).
func get_hit(from_dir: Vector3, strength := 1.0) -> void:
	health -= 22.0 * strength
	_threat = global_position - from_dir
	if state == S.RAGDOLL:
		if body.ragdoll:
			body.ragdoll.push(from_dir * 120.0 * strength + Vector3.UP * 40.0)
		return
	var knock := strength >= 2.0 or health <= 0.0 or _rng.randf() < 0.35
	if knock:
		ragdoll(from_dir * (110.0 + 90.0 * strength) + Vector3.UP * (50.0 + 30.0 * strength))
	else:
		# stagger
		velocity += from_dir.normalized() * 3.5
		body.play_land(0.6)
		if personality == 2:
			_start_fight()
	if world:
		world.alarm(global_position, 14.0, true)


func ragdoll(impulse: Vector3) -> void:
	if state == S.RAGDOLL:
		return
	if body.start_ragdoll(velocity, impulse):
		state = S.RAGDOLL
		_shape.disabled = true
		collision_layer = 0
		velocity = Vector3.ZERO


func is_down() -> bool:
	return state == S.RAGDOLL or state == S.GETUP


# ------------------------------------------------------------------ states
func _start_walk() -> void:
	state = S.WALK
	body.pose_mode = ""
	var a := _rng.randf() * TAU
	_dir = Vector3(sin(a), 0, cos(a))
	_timer = _rng.randf_range(8.0, 20.0)
	_speed = _rng.randf_range(1.05, 1.55)


func _start_idle() -> void:
	state = S.IDLE
	_timer = _rng.randf_range(3.0, 9.0)
	var r := _rng.randf()
	body.pose_mode = "phone" if r < 0.35 else ("talk" if r < 0.6 else "")


func _start_flee() -> void:
	state = S.FLEE
	body.pose_mode = "panic" if _rng.randf() < 0.6 else ""
	_timer = _rng.randf_range(6.0, 10.0)
	var away := global_position - _threat
	away.y = 0.0
	_dir = away.normalized() if away.length() > 0.1 else -_dir


func _start_fight() -> void:
	state = S.FIGHT
	body.pose_mode = "guard"
	_timer = 15.0


func _physics_process(dt: float) -> void:
	if state == S.RAGDOLL:
		_update_ragdoll(dt)
		return
	_timer -= dt
	_attack_cd -= dt
	var player: Node3D = world.player if world else null
	var target_speed := 0.0
	var face_dir := _dir
	body.look_point = null

	if scripted and state in [S.WALK, S.IDLE, S.FLEE, S.COWER, S.FIGHT]:
		state = S.WALK
		body.look_point = script_face
		if script_target != null:
			var to: Vector3 = script_target - global_position
			to.y = 0.0
			if to.length() > 0.7:
				var want := to.normalized()
				# steer around obstacles but keep heading to the target
				_dir = _dir.lerp(want, 1.0 - exp(-6.0 * dt)).normalized()
				_steer(dt, false)
				target_speed = script_speed
				face_dir = _dir
			elif script_face != null:
				var f: Vector3 = script_face - global_position
				f.y = 0.0
				if f.length() > 0.01:
					face_dir = f.normalized()
		elif script_face != null:
			var f: Vector3 = script_face - global_position
			f.y = 0.0
			if f.length() > 0.01:
				face_dir = f.normalized()
	else:
		match state:
			S.WALK:
				target_speed = _speed
				_steer(dt, true)
				if _timer <= 0.0:
					if _rng.randf() < 0.45:
						_start_idle()
					else:
						_start_walk()
				_look_at_player(player, 5.0)
			S.IDLE:
				_look_at_player(player, 7.0)
				if _timer <= 0.0:
					_start_walk()
			S.FLEE:
				target_speed = 5.2
				_steer(dt, false)
				if _timer <= 0.0:
					_start_walk()
			S.COWER:
				body.pose_mode = "cower"
				face_dir = (_threat - global_position).normalized()
				if _timer <= 0.0:
					_start_flee()
			S.FIGHT:
				if player == null or player.global_position.distance_to(global_position) > 25.0 or _timer <= 0.0 or player.get("health") <= 0.0:
					_start_walk()
				else:
					var to := player.global_position - global_position
					to.y = 0.0
					var d := to.length()
					face_dir = to / maxf(d, 0.01)
					_dir = face_dir
					body.look_point = player.global_position + Vector3.UP * 1.6
					if d > 1.2:
						target_speed = 3.6 if d > 4.0 else 1.6
					elif _attack_cd <= 0.0:
						if body.play_attack() >= 0:
							_attack_cd = _rng.randf_range(0.7, 1.3)
							_hit_done = false
					if body.is_attacking() and body.attack_hit_moment() and not _hit_done:
						_hit_done = true
						if d < 1.6 and player.has_method("take_hit"):
							player.take_hit(face_dir, 7.0)
			S.GETUP:
				if body.knocked <= 0.0 and body._down < 0.15:
					if health <= 0.0:
						health = 60.0
					if personality == 2 and _rng.randf() < 0.6:
						_start_fight()
					else:
						_start_flee()
	if body.knocked > 0.0:
		body.knocked -= dt
		target_speed = 0.0

	var hv := Vector3(velocity.x, 0, velocity.z)
	hv = hv.lerp(_dir * target_speed, 1.0 - exp(-(6.0 if is_on_floor() else 0.6) * dt))
	velocity.x = hv.x
	velocity.z = hv.z
	if not is_on_floor():
		velocity.y -= GRAVITY * dt
	var prev := body.rotation.y
	if body.knocked <= 0.0:
		var fd := hv if hv.length() > 0.3 else face_dir
		if fd.length() > 0.01:
			body.rotation.y = lerp_angle(body.rotation.y, atan2(fd.x, fd.z), 1.0 - exp(-7.0 * dt))
	move_and_slide()

	# bumped hard by the sprinting player -> fall over
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_collider() == player and player.velocity.length() > 6.5 and state != S.FIGHT:
			ragdoll(player.velocity * 9.0 + Vector3.UP * 60.0)
			return
		var rb := c.get_collider() as RigidBody3D
		if rb and rb.linear_velocity.length() > 5.0 and rb.mass > 1.0:
			get_hit(rb.linear_velocity.normalized(), 2.0)
			return

	if is_on_floor() and state == S.WALK:
		_level = lerpf(_level, global_position.y, 0.05)
	body.speed = hv.length()
	body.grounded = is_on_floor()
	body.vertical_speed = velocity.y
	body.turn_rate = wrapf(body.rotation.y - prev, -PI, PI) / maxf(dt, 0.0001)

	# unstick
	if target_speed > 0.5 and global_position.distance_to(_last_pos) < target_speed * dt * 0.2:
		_stuck += dt
		if _stuck > 0.8:
			_stuck = 0.0
			var a := atan2(_dir.x, _dir.z) + _rng.randf_range(PI * 0.6, PI * 1.4)
			_dir = Vector3(sin(a), 0, cos(a))
	else:
		_stuck = 0.0
	_last_pos = global_position


func _update_ragdoll(dt: float) -> void:
	var rd := body.ragdoll
	if rd == null:
		state = S.GETUP
		return
	# keep the (disabled) character with the body so culling / despawn work
	global_position = rd.hips_position() - Vector3(0, 0.15, 0)
	if rd.settled() or rd.age > 6.0:
		var res := body.stop_ragdoll()
		var p: Vector3 = res[0]
		var space := get_world_3d().direct_space_state
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP, p + Vector3.DOWN * 3.0, 1 | 2))
		global_position = (hit.position if not hit.is_empty() else p) + Vector3(0, 0.05, 0)
		body.rotation.y = res[1]
		_shape.disabled = false
		collision_layer = 8
		velocity = Vector3.ZERO
		body.knocked = 4.0 if health <= 0.0 else _rng.randf_range(0.6, 1.4)
		state = S.GETUP


func _look_at_player(player: Node3D, dist: float) -> void:
	if player and player.global_position.distance_to(global_position) < dist:
		body.look_point = player.global_position + Vector3.UP * 1.6


## Whisker steering + staying on the current ground level (sidewalks) + separation.
func _steer(dt: float, keep_level: bool) -> void:
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3(0, 0.9, 0)
	var ex := [get_rid()]
	var turn := 0.0
	for side in [-0.5, 0.0, 0.5]:
		var d := _dir.rotated(Vector3.UP, side)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + d * (2.2 if side == 0.0 else 1.6), 1 | 2 | 8, ex))
		if not hit.is_empty():
			turn += (1.0 if side <= 0.0 else -1.0) * (1.6 if side == 0.0 else 1.0)
	# ground ahead: avoid holes, and (when walking) stepping off the sidewalk
	var ahead := global_position + _dir * 1.3 + Vector3(0, 0.8, 0)
	var g := space.intersect_ray(PhysicsRayQueryParameters3D.create(ahead, ahead + Vector3.DOWN * 2.5, 1, ex))
	var bad: bool = g.is_empty() or (g.position.y < global_position.y - 0.6)
	if keep_level and not g.is_empty() and g.position.y < _level - 0.07 and _rng.randf() < 0.97:
		bad = true
	# pedestrians stay off the road (they only rarely cross)
	if keep_level and world and world.is_road_hit(g) and _rng.randf() < 0.985:
		bad = true
	if bad:
		turn += 2.5 if _rng.randf() < 0.5 else -2.5
	# separation from other pedestrians
	for o in get_tree().get_nodes_in_group("npc"):
		if o == self:
			continue
		var off: Vector3 = global_position - (o as Node3D).global_position
		off.y = 0.0
		var l := off.length()
		if l < 1.2 and l > 0.01:
			var side_sign := signf(_dir.cross(off).y)
			turn -= side_sign * (1.2 - l) * 2.0
	if absf(turn) > 0.01:
		_dir = _dir.rotated(Vector3.UP, clampf(turn, -3.0, 3.0) * dt * 2.2).normalized()
