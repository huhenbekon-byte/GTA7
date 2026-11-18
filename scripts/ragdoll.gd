extends Node3D
class_name Ragdoll
## Physics ragdoll for a Mixamo-rigged Humanoid. Builds capsule rigid bodies for the main
## bones at their current pose, links them with joints, and every frame writes the bodies'
## transforms back into the skeleton. Lives in world space (top_level).

const SPEC := [
	# key, bone, end bone, radius, mass, parent key, joint, swing deg, twist deg
	["hips", "Hips", "Spine1", 0.14, 12.0, "", "", 0, 0],
	["chest", "Spine2", "Neck", 0.15, 14.0, "hips", "cone", 25, 20],
	["head", "Head", "HeadTop_End", 0.1, 5.0, "chest", "cone", 40, 40],
	["uarm_l", "LeftArm", "LeftForeArm", 0.055, 2.5, "chest", "cone", 75, 40],
	["farm_l", "LeftForeArm", "LeftHand", 0.045, 1.8, "uarm_l", "cone", 70, 15],
	["uarm_r", "RightArm", "RightForeArm", 0.055, 2.5, "chest", "cone", 75, 40],
	["farm_r", "RightForeArm", "RightHand", 0.045, 1.8, "uarm_r", "cone", 70, 15],
	["thigh_l", "LeftUpLeg", "LeftLeg", 0.08, 8.0, "hips", "cone", 55, 15],
	["shin_l", "LeftLeg", "LeftFoot", 0.06, 4.0, "thigh_l", "hinge", 0, 0],
	["thigh_r", "RightUpLeg", "RightLeg", 0.08, 8.0, "hips", "cone", 55, 15],
	["shin_r", "RightLeg", "RightFoot", 0.06, 4.0, "thigh_r", "hinge", 0, 0],
]

const LAYER := 16

var skel: Skeleton3D
var parts := {}
var order: Array[String] = []
var age := 0.0
var _calm := 0.0
var _front_local := Vector3.FORWARD


func setup(sk: Skeleton3D, find_bone: Callable, forward: Vector3, velocity: Vector3) -> void:
	skel = sk
	top_level = true
	global_transform = Transform3D.IDENTITY
	var skx := skel.global_transform
	for s in SPEC:
		var b: int = find_bone.call([s[1]])
		var e: int = find_bone.call([s[2]])
		if b < 0 or e < 0:
			continue
		var bw := skx * skel.get_bone_global_pose(b)
		var ew := skx * skel.get_bone_global_pose(e)
		var p := bw.origin
		var q := ew.origin
		var len := p.distance_to(q)
		var dir := (q - p) / maxf(len, 0.001)
		var bb := bw.basis.orthonormalized()
		var x := bb.x - dir * bb.x.dot(dir)
		if x.length() < 0.01:
			x = dir.cross(Vector3.FORWARD)
		x = x.normalized()
		var z := x.cross(dir).normalized()
		var body_xf := Transform3D(Basis(x, dir, z), (p + q) * 0.5)
		var off := body_xf.affine_inverse() * Transform3D(bb, p)

		var rb := RigidBody3D.new()
		rb.mass = s[4]
		rb.collision_layer = LAYER
		rb.collision_mask = 1 | 2
		rb.linear_damp = 0.05
		rb.angular_damp = 2.0
		var pm := PhysicsMaterial.new()
		pm.friction = 0.9
		pm.bounce = 0.05
		rb.physics_material_override = pm
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = s[3]
		cap.height = maxf(len + s[3] * 0.5, s[3] * 2.0 + 0.01)
		cs.shape = cap
		rb.add_child(cs)
		add_child(rb)
		rb.global_transform = body_xf
		rb.linear_velocity = velocity
		parts[s[0]] = {"body": rb, "bone": b, "off": off}
		order.append(s[0])
		if s[0] == "chest":
			_front_local = body_xf.basis.inverse() * forward
		if s[5] != "" and parts.has(s[5]):
			_joint(parts[s[5]].body, rb, p, dir, forward, s[6], s[7], s[8])


func _joint(a: RigidBody3D, b: RigidBody3D, at: Vector3, dir: Vector3, fwd: Vector3, kind: String, swing: float, twist: float) -> void:
	# Generic 6DOF: position locked, angular limits per axis. Joint X = bone direction (twist),
	# Z = side axis (knee/elbow bend), Y = the remaining swing axis.
	var side := fwd.cross(dir)
	if side.length() < 0.01:
		side = dir.cross(Vector3.UP)
		if side.length() < 0.01:
			side = Vector3.RIGHT
	side = side.normalized()
	var yv := side.cross(dir).normalized()
	var jb := Basis(dir, yv, side)
	var j := Generic6DOFJoint3D.new()
	var lo_z := -deg_to_rad(swing)
	var hi_z := deg_to_rad(swing)
	var sw_y := deg_to_rad(swing)
	var tw := deg_to_rad(twist)
	if kind == "hinge":
		lo_z = -deg_to_rad(135)
		hi_z = deg_to_rad(3)
		sw_y = deg_to_rad(4)
		tw = deg_to_rad(4)
	j.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	j.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	j.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -tw)
	j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, tw)
	j.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -sw_y)
	j.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, sw_y)
	j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, lo_z)
	j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, hi_z)
	for ax in ["x", "y", "z"]:
		j.call("set_param_" + ax, Generic6DOFJoint3D.PARAM_ANGULAR_LIMIT_SOFTNESS, 0.6)
		j.call("set_param_" + ax, Generic6DOFJoint3D.PARAM_ANGULAR_DAMPING, 1.0)
		j.call("set_param_" + ax, Generic6DOFJoint3D.PARAM_ANGULAR_RESTITUTION, 0.0)
	j.exclude_nodes_from_collision = true
	add_child(j)
	j.global_transform = Transform3D(jb, at)
	j.node_a = j.get_path_to(a)
	j.node_b = j.get_path_to(b)


## Applies `impulse` (N*s) mostly spread over the whole body (stable for the joint solver),
## with a bit extra on `part` so the hit spot leads.
func push(impulse: Vector3, part := "chest") -> void:
	var total := 0.0
	for k in parts:
		total += (parts[k].body as RigidBody3D).mass
	if total <= 0.0:
		return
	for k in parts:
		var rb: RigidBody3D = parts[k].body
		var share := rb.mass / total * 0.8 + (0.2 if k == part else 0.0)
		# set velocity directly: impulses on a body that hasn't stepped yet use mass 1
		rb.linear_velocity += impulse * share / rb.mass


func push_all(impulse_per_kg: Vector3) -> void:
	for k in parts:
		var rb: RigidBody3D = parts[k].body
		rb.linear_velocity += impulse_per_kg


func apply_to_skeleton() -> void:
	var inv := skel.global_transform.affine_inverse()
	for key in order:
		var p: Dictionary = parts[key]
		var w: Transform3D = (p.body as RigidBody3D).global_transform * (p.off as Transform3D)
		var st := inv * w
		var b: int = p.bone
		var par := skel.get_bone_parent(b)
		var pg := skel.get_bone_global_pose(par) if par >= 0 else Transform3D.IDENTITY
		var gq := st.basis.get_rotation_quaternion()
		skel.set_bone_pose_rotation(b, (pg.basis.get_rotation_quaternion().inverse() * gq).normalized())
		if key == "hips":
			skel.set_bone_pose_position(b, pg.affine_inverse() * st.origin)


func _physics_process(dt: float) -> void:
	age += dt
	var v := 0.0
	for k in parts:
		v += (parts[k].body as RigidBody3D).linear_velocity.length()
	v /= maxf(1.0, parts.size())
	_calm = _calm + dt if v < 0.35 else 0.0


## True once the body has come to rest for a moment.
func settled() -> bool:
	return (age > 1.4 and _calm > 0.5) or age > 4.5


func hips_position() -> Vector3:
	return (parts.hips.body as RigidBody3D).global_position if parts.has("hips") else global_position


func head_position() -> Vector3:
	return (parts.head.body as RigidBody3D).global_position if parts.has("head") else hips_position() + Vector3.UP


func face_up() -> bool:
	if not parts.has("chest"):
		return true
	var f := (parts.chest.body as RigidBody3D).global_transform.basis * _front_local
	return f.y >= 0.0


func average_velocity() -> Vector3:
	var v := Vector3.ZERO
	for k in parts:
		v += (parts[k].body as RigidBody3D).linear_velocity
	return v / maxf(1.0, parts.size())
