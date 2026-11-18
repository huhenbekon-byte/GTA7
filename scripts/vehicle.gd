extends VehicleBody3D
## Drivable car built from a car-pack template (Car_N node with Wheel_LF/RF/LB/RB children).
## Raycast-suspension physics (VehicleBody3D) tuned for an arcade-but-weighty feel:
## low centre of mass, speed-sensitive steering, downforce, anti-roll help, handbrake
## drifts, nitro, auto-flip recovery. Knocks down pedestrians and street furniture.

signal crashed(strength: float)

const MAX_ENGINE := 5200.0
const MAX_BRAKE := 45.0
const REVERSE_FORCE := 2600.0
const TOP_SPEED := 46.0          # m/s (~165 km/h)

var throttle := 0.0              # -1..1 (from joystick y)
var steer_input := 0.0           # -1..1
var handbrake := false
var nitro := false
var driver: Node = null
var size := Vector3(1.8, 1.5, 4.4)
var rpm := 0.0                   # 0..1 for the engine sound

var _wheels: Array[VehicleWheel3D] = []
var _steer := 0.0
var _flip_timer := 0.0
var _hit_cd := 0.0
var _last_vel := Vector3.ZERO


func setup(tmpl: Node3D, car_size: Vector3) -> void:
	size = car_size
	collision_layer = 32
	collision_mask = 1 | 2 | 16 | 32
	mass = clampf(900.0 + size.x * size.z * size.y * 60.0, 1000.0, 3200.0)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.18, 0.1)
	contact_monitor = true
	max_contacts_reported = 6
	can_sleep = false
	linear_damp = 0.05
	angular_damp = 0.6
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6
	pm.bounce = 0.05
	physics_material_override = pm
	add_to_group("vehicle")
	body_entered.connect(_on_body_entered)

	var vis := tmpl.duplicate() as Node3D
	add_child(vis)
	# collision: lower body + cabin
	_box(Vector3(size.x * 0.96, size.y * 0.42, size.z * 0.98), Vector3(0, size.y * 0.36, 0))
	_box(Vector3(size.x * 0.84, size.y * 0.42, size.z * 0.62), Vector3(0, size.y * 0.76, -size.z * 0.04))

	for key in ["LF", "RF", "LB", "RB"]:
		var wn := vis.get_node_or_null("Wheel_" + key) as Node3D
		var r := 0.33
		var pos := Vector3((size.x * 0.5 - 0.25) * (1.0 if key[0] == "L" else -1.0), 0.33, (size.z * 0.5 - 0.85) * (1.0 if key[1] == "F" else -1.0))
		if wn:
			r = wn.get_meta("radius", 0.33)
			pos = wn.position
		var w := VehicleWheel3D.new()
		w.wheel_radius = r
		w.wheel_rest_length = 0.16
		w.suspension_travel = 0.22
		w.suspension_stiffness = 48.0
		w.suspension_max_force = mass * 9.8
		w.damping_compression = 1.9
		w.damping_relaxation = 2.4
		w.wheel_friction_slip = 2.5 if key[1] == "F" else 2.3
		w.wheel_roll_influence = 0.02
		w.use_as_steering = key[1] == "F"
		w.use_as_traction = true
		w.position = pos + Vector3.UP * 0.1
		add_child(w)
		if wn:
			# move the visible wheel under the physics wheel so it spins and steers
			vis.remove_child(wn)
			w.add_child(wn)
			wn.position = Vector3.ZERO
			wn.rotation = Vector3.ZERO
		_wheels.append(w)


func _box(sz: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = sz
	cs.shape = b
	cs.position = pos
	add_child(cs)


func speed_kmh() -> float:
	return linear_velocity.length() * 3.6


func forward_speed() -> float:
	return linear_velocity.dot(global_transform.basis.z)


func _physics_process(dt: float) -> void:
	var fwd := global_transform.basis.z
	var v := linear_velocity
	var fs := v.dot(fwd)
	var spd := v.length()
	_hit_cd -= dt

	# --- steering: smooth, less lock at speed ---
	var max_steer := lerpf(0.62, 0.16, clampf(spd / 32.0, 0.0, 1.0))
	_steer = move_toward(_steer, steer_input * max_steer, dt * (2.4 if absf(steer_input) > 0.01 else 3.2))
	steering = _steer

	# --- engine / brakes ---
	var eng := 0.0
	var brk := 0.0
	if driver == null:
		brk = 4.0
	elif throttle > 0.05:
		if fs < -1.0:
			brk = MAX_BRAKE * throttle            # braking while rolling back
		else:
			var curve := clampf(1.0 - fs / (TOP_SPEED * (1.25 if nitro else 1.0)), 0.0, 1.0)
			eng = MAX_ENGINE * throttle * (0.35 + 0.65 * curve) * (1.6 if nitro else 1.0)
	elif throttle < -0.05:
		if fs > 1.5:
			brk = MAX_BRAKE * -throttle
		else:
			eng = -REVERSE_FORCE * -throttle * clampf(1.0 - (-fs) / 14.0, 0.0, 1.0)
	else:
		brk = 1.2                                  # engine braking
	engine_force = eng
	brake = brk
	for w in _wheels:
		if not w.use_as_steering:
			w.wheel_friction_slip = 1.0 if handbrake else 2.3
			if handbrake:
				w.brake = MAX_BRAKE * 0.8

	# --- aero: downforce + a little drag so it stays planted ---
	apply_central_force(-global_transform.basis.y * spd * spd * 2.2)
	apply_central_force(-v * spd * 0.35)
	# anti-roll: while wheels touch the ground, pull the body back upright
	var grounded := 0
	for w in _wheels:
		if w.is_in_contact():
			grounded += 1
	if grounded >= 2:
		var up := global_transform.basis.y
		var tilt := up.cross(Vector3.UP)
		apply_torque(tilt * mass * 14.0 - angular_velocity.project(global_transform.basis.z) * mass * 1.2)
	# yaw damping helps recover from slides when not on handbrake
	if not handbrake:
		apply_torque(-global_transform.basis.y * angular_velocity.dot(global_transform.basis.y) * mass * 0.35)

	rpm = clampf(absf(fs) / TOP_SPEED + absf(throttle) * 0.25, 0.0, 1.0)

	# --- flip recovery ---
	if global_transform.basis.y.y < 0.3 and spd < 2.0:
		_flip_timer += dt
		if _flip_timer > 2.0:
			_flip_timer = 0.0
			var yaw := atan2(fwd.x, fwd.z)
			global_transform = Transform3D(Basis(Vector3.UP, yaw), global_position + Vector3.UP * 1.2)
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
	else:
		_flip_timer = 0.0

	# --- run people over ---
	if spd > 3.0:
		_hit_people(v)

	# --- crash detection for camera shake ---
	var dv := (_last_vel - v).length()
	if dv > 7.0:
		crashed.emit(dv)
	_last_vel = v


func _hit_people(v: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(size.x + 0.3, 1.6, size.z + 0.6)
	q.shape = b
	q.transform = Transform3D(global_transform.basis, global_transform * Vector3(0, 0.9, 0))
	q.collision_mask = 4 | 8
	for r in space.intersect_shape(q, 8):
		var o: Object = r.collider
		if o == driver:
			continue
		if o.has_method("ragdoll") and not o.is_down():
			o.health -= v.length() * 6.0
			o.ragdoll(v * 11.0 + Vector3.UP * (80.0 + v.length() * 9.0))
		elif o.has_method("knockdown") and o.get("vehicle") == null:
			o.health -= v.length() * 3.0
			o.knockdown(v * 8.0 + Vector3.UP * 120.0)


func _on_body_entered(o: Node) -> void:
	var spd := linear_velocity.length()
	if o is RigidBody3D and o.is_in_group("breakable") and (o as RigidBody3D).freeze and spd > 4.0:
		var rb := o as RigidBody3D
		rb.freeze = false
		var dir := linear_velocity.normalized()
		rb.apply_central_impulse((dir + Vector3.UP * 0.3) * minf(rb.mass, 600.0) * spd * 0.25)
		rb.apply_torque_impulse(dir.cross(Vector3.UP) * -rb.mass * spd * 0.15)
		linear_velocity *= 0.9 if rb.mass < 300.0 else 0.7
	elif o is RigidBody3D and (o as RigidBody3D).is_in_group("explosive") and spd > 6.0:
		var w := get_tree().get_first_node_in_group("world")
		if w:
			w.ignite(o, 0.05)
