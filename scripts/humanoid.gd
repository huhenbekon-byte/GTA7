extends Node3D
class_name Humanoid
## Procedural "Part" humanoid (built from primitives) with a procedural animation system:
## idle (breathing, weight shift, look-around), walk / jog / sprint cycles, turn leaning,
## jump / fall (arm flail), landing squash, punch combo, kick, knock-down and getting up.
## Faces +Z.

# --- look -------------------------------------------------------------------
@export var skin_color := Color(0.55, 0.38, 0.27)
@export var shirt_color := Color(0.12, 0.35, 0.18)
@export var pants_color := Color(0.16, 0.2, 0.32)
@export var shoe_color := Color(0.9, 0.9, 0.88)
@export var hair_color := Color(0.06, 0.05, 0.05)
@export var has_cap := false
@export var cap_color := Color(0.1, 0.1, 0.1)
## Optional rigged model (Mixamo skeleton). When set, the procedural rig drives its bones
## instead of drawing the primitive "Part" body.
@export var model_path := ""
@export var model_height := 1.8

# --- animation inputs (set by controller every frame) -------------------------
var speed := 0.0            # horizontal speed m/s
var grounded := true
var vertical_speed := 0.0
var turn_rate := 0.0        # rad/s, for leaning
var sprinting := false
var knocked := 0.0          # >0 = lying on the ground (seconds left)

# --- internal ---------------------------------------------------------------
var _phase := 0.0
var _t := 0.0
var _land := 0.0            # landing squash amount (decays)
var _air_time := 0.0
var _attack := 0.0          # attack timer (counts down)
var _attack_kind := 0       # 0 left jab, 1 right cross, 2 kick
var _look_yaw := 0.0
var _look_target := 0.0
var _look_timer := 2.0
var _shift := 0.0
var _down := 0.0            # 0 standing ... 1 lying
var _rng := RandomNumberGenerator.new()

var hips: Node3D
var spine: Node3D
var chest: Node3D
var neck: Node3D
var head: Node3D
var sh_l: Node3D
var sh_r: Node3D
var el_l: Node3D
var el_r: Node3D
var hip_l: Node3D
var hip_r: Node3D
var kn_l: Node3D
var kn_r: Node3D
var an_l: Node3D
var an_r: Node3D

const HIP_H := 0.94

static var _mat_cache := {}

var _skel: Skeleton3D
var _bone_map := []   # [bone_idx, pivot, pre: Quaternion, post: Quaternion, rest_rot, gq, gq_inv]
var _hips_bone := -1
var _hips_rest_pos := Vector3.ZERO
var _model_scale := 1.0
var _fist := 0.0


func _ready() -> void:
	_rng.randomize()
	_phase = _rng.randf() * TAU
	_build()


static func mat(c: Color, rough := 0.85) -> StandardMaterial3D:
	var key := "%s|%s" % [c.to_html(), rough]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	_mat_cache[key] = m
	return m


func _part(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	if model_path != "":
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color)
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.position = pos
	parent.add_child(p)
	return p


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 10
	c.rings = 4
	return c


func _box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b


func _sphere(r: float, hemi := false) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * (1.0 if hemi else 2.0)
	s.is_hemisphere = hemi
	s.radial_segments = 14
	s.rings = 7
	return s


func _build() -> void:
	hips = _pivot(self, Vector3(0, HIP_H, 0))
	# pelvis / belt
	_part(hips, _box(0.34, 0.16, 0.21), pants_color, Vector3(0, 0.0, 0))
	_part(hips, _box(0.35, 0.04, 0.22), Color(0.08, 0.06, 0.05), Vector3(0, 0.08, 0))

	spine = _pivot(hips, Vector3(0, 0.08, 0))
	# belly + chest (tapered via two boxes)
	_part(spine, _box(0.33, 0.24, 0.2), shirt_color, Vector3(0, 0.12, 0))
	chest = _pivot(spine, Vector3(0, 0.24, 0))
	_part(chest, _box(0.4, 0.26, 0.23), shirt_color, Vector3(0, 0.1, 0))
	_part(chest, _capsule(0.1, 0.44), shirt_color, Vector3(0, 0.2, 0), Vector3(0, 0, PI / 2))  # shoulders rounding

	neck = _pivot(chest, Vector3(0, 0.27, 0))
	_part(neck, _capsule(0.055, 0.14), skin_color, Vector3(0, 0.04, 0))
	head = _pivot(neck, Vector3(0, 0.1, 0))
	_part(head, _sphere(0.115), skin_color, Vector3(0, 0.1, 0), Vector3.ZERO, Vector3(0.92, 1.08, 1.0))
	# jaw
	_part(head, _box(0.15, 0.08, 0.14), skin_color, Vector3(0, 0.03, 0.025))
	# hair / cap
	if has_cap:
		_part(head, _sphere(0.122, true), cap_color, Vector3(0, 0.12, -0.005), Vector3.ZERO, Vector3(1, 0.9, 1.04))
		_part(head, _box(0.2, 0.02, 0.12), cap_color, Vector3(0, 0.13, 0.12))
	else:
		_part(head, _sphere(0.12, true), hair_color, Vector3(0, 0.125, -0.012), Vector3(-0.15, 0, 0), Vector3(0.96, 0.75, 1.02))
	# eyes, brows, nose, ears
	for sx in [-1.0, 1.0]:
		_part(head, _box(0.032, 0.02, 0.01), Color(0.95, 0.95, 0.95), Vector3(0.042 * sx, 0.115, 0.104))
		_part(head, _box(0.014, 0.016, 0.01), Color(0.05, 0.03, 0.02), Vector3(0.042 * sx, 0.115, 0.109))
		_part(head, _box(0.04, 0.01, 0.015), hair_color, Vector3(0.043 * sx, 0.138, 0.104))
		_part(head, _sphere(0.025), skin_color, Vector3(0.11 * sx, 0.1, 0.0), Vector3.ZERO, Vector3(0.5, 1, 0.8))
	_part(head, _box(0.03, 0.05, 0.03), skin_color.darkened(0.08), Vector3(0, 0.085, 0.115))
	_part(head, _box(0.05, 0.01, 0.01), Color(0.35, 0.15, 0.12), Vector3(0, 0.045, 0.1))

	# arms
	sh_l = _pivot(chest, Vector3(0.235, 0.2, 0))
	sh_r = _pivot(chest, Vector3(-0.235, 0.2, 0))
	for data in [[sh_l, 1.0], [sh_r, -1.0]]:
		var sh: Node3D = data[0]
		_part(sh, _sphere(0.075), shirt_color, Vector3.ZERO)
		_part(sh, _capsule(0.07, 0.24), shirt_color, Vector3(0, -0.09, 0))  # sleeve
		_part(sh, _capsule(0.055, 0.2), skin_color, Vector3(0, -0.2, 0))
		var el := _pivot(sh, Vector3(0, -0.29, 0))
		_part(el, _capsule(0.05, 0.28), skin_color, Vector3(0, -0.12, 0))
		_part(el, _box(0.07, 0.1, 0.045), skin_color, Vector3(0, -0.3, 0.01))  # hand
		_part(el, _box(0.025, 0.06, 0.03), skin_color, Vector3(0.035 * data[1], -0.27, 0.035))  # thumb
		if sh == sh_l:
			el_l = el
		else:
			el_r = el

	# legs
	hip_l = _pivot(hips, Vector3(0.1, -0.06, 0))
	hip_r = _pivot(hips, Vector3(-0.1, -0.06, 0))
	for hp in [hip_l, hip_r]:
		_part(hp, _capsule(0.088, 0.5), pants_color, Vector3(0, -0.2, 0))
		var kn := _pivot(hp, Vector3(0, -0.42, 0))
		_part(kn, _capsule(0.072, 0.46), pants_color, Vector3(0, -0.2, 0))
		var an := _pivot(kn, Vector3(0, -0.42, 0))
		_part(an, _box(0.11, 0.09, 0.26), shoe_color, Vector3(0, -0.035, 0.055))
		_part(an, _box(0.115, 0.025, 0.27), Color(0.2, 0.2, 0.2), Vector3(0, -0.075, 0.055))
		if hp == hip_l:
			kn_l = kn
			an_l = an
		else:
			kn_r = kn
			an_r = an

	if model_path != "":
		_setup_model()
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).gi_mode = GeometryInstance3D.GI_MODE_DISABLED


# --- rigged model support ----------------------------------------------------------
func _bone(names: Array) -> int:
	for i in _skel.get_bone_count():
		var bn := _skel.get_bone_name(i)
		for n in names:
			if bn.begins_with("mixamorig_" + n + "_") or bn == "mixamorig_" + n or bn == "mixamorig:" + n or bn == n:
				return i
	return -1


func _setup_model() -> void:
	var model: Node3D = (load(model_path) as PackedScene).instantiate()
	add_child(model)
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		push_warning("model has no skeleton")
		return
	_skel = sks[0]
	var head_top := _bone(["HeadTop_End"])
	var top_y := (_skel.get_bone_global_rest(head_top).origin.y if head_top >= 0 else 17.0)
	_model_scale = model_height / (top_y * 1.03)
	model.scale = Vector3.ONE * _model_scale
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).extra_cull_margin = 2.0 / _model_scale

	# arms are authored in T-pose: correction that brings them down along the body
	var c_l := _arm_correction(_bone(["LeftArm"]), _bone(["LeftHand"]), Vector3(0.12, -1, 0))
	var c_r := _arm_correction(_bone(["RightArm"]), _bone(["RightHand"]), Vector3(-0.12, -1, 0))
	var I := Quaternion.IDENTITY
	var spec := [
		[["Hips"], hips, I, I], [["Spine"], spine, I, I], [["Spine2"], chest, I, I],
		[["Neck"], neck, I, I], [["Head"], head, I, I],
		[["LeftArm"], sh_l, I, c_l], [["LeftForeArm"], el_l, c_l.inverse(), c_l],
		[["RightArm"], sh_r, I, c_r], [["RightForeArm"], el_r, c_r.inverse(), c_r],
		[["LeftUpLeg"], hip_l, I, I], [["LeftLeg"], kn_l, I, I], [["LeftFoot"], an_l, I, I],
		[["RightUpLeg"], hip_r, I, I], [["RightLeg"], kn_r, I, I], [["RightFoot"], an_r, I, I],
	]
	for sp in spec:
		var b := _bone(sp[0])
		if b < 0:
			continue
		var gq := _skel.get_bone_global_rest(b).basis.get_rotation_quaternion()
		_bone_map.append([b, sp[1], sp[2], sp[3], _skel.get_bone_rest(b).basis.get_rotation_quaternion(), gq, gq.inverse()])
	# fingers: curled procedurally (relaxed hand / fist)
	for side in [["Left", c_l, -1.0], ["Right", c_r, 1.0]]:
		for f in ["Index", "Middle", "Ring", "Pinky"]:
			for j in [1, 2, 3]:
				var fb := _bone([side[0] + "Hand" + f + str(j)])
				if fb < 0:
					continue
				var fq := _skel.get_bone_global_rest(fb).basis.get_rotation_quaternion()
				var cq: Quaternion = side[1]
				_bone_map.append([fb, null, cq.inverse(), cq, _skel.get_bone_rest(fb).basis.get_rotation_quaternion(), fq, fq.inverse(), side[2]])
	_hips_bone = _bone(["Hips"])
	_hips_rest_pos = _skel.get_bone_rest(_hips_bone).origin


func _arm_correction(arm: int, hand: int, want: Vector3) -> Quaternion:
	if arm < 0 or hand < 0:
		return Quaternion.IDENTITY
	var d := _skel.get_bone_global_rest(hand).origin - _skel.get_bone_global_rest(arm).origin
	return Quaternion(d.normalized(), want.normalized())


func _apply_skeleton() -> void:
	var fist := 1.0 if (_attack > 0.0 or speed > 5.0 or knocked > 0.0) else 0.0
	_fist = _damp(_fist, fist, 12.0, get_process_delta_time())
	var curl := lerpf(0.3, 1.25, _fist)
	for m in _bone_map:
		var pivot: Node3D = m[1]
		var local_q: Quaternion = pivot.quaternion if pivot else Quaternion(Vector3(0, 0, 1), curl * m[7])
		var r: Quaternion = m[2] * local_q * m[3]
		var pose: Quaternion = m[4] * (m[6] * r * m[5])
		_skel.set_bone_pose_rotation(m[0], pose.normalized())
	if _hips_bone >= 0:
		var off := (hips.position - Vector3(0, HIP_H, 0)) / _model_scale
		var parent := _skel.get_bone_parent(_hips_bone)
		if parent >= 0:
			off = _skel.get_bone_global_rest(parent).basis.inverse() * off
		_skel.set_bone_pose_position(_hips_bone, _hips_rest_pos + off)


# --- public triggers -----------------------------------------------------------
func play_land(impact: float) -> void:
	_land = clampf(impact, 0.0, 1.0)


func play_attack() -> int:
	if _attack > 0.12:
		return -1
	_attack_kind = (_attack_kind + 1) % 3
	_attack = 0.42 if _attack_kind < 2 else 0.55
	return _attack_kind


func is_attacking() -> bool:
	return _attack > 0.0


func attack_hit_moment() -> bool:
	# true around the moment the strike is fully extended
	var dur := 0.42 if _attack_kind < 2 else 0.55
	var p := 1.0 - _attack / dur
	return p > 0.35 and p < 0.6


# --- animation -----------------------------------------------------------------
static func _damp(cur: float, target: float, k: float, dt: float) -> float:
	return lerpf(cur, target, 1.0 - exp(-k * dt))


func _set_rot(n: Node3D, target: Vector3, k: float, dt: float) -> void:
	n.rotation = Vector3(
		_damp(n.rotation.x, target.x, k, dt),
		_damp(n.rotation.y, target.y, k, dt),
		_damp(n.rotation.z, target.z, k, dt))


func _process(dt: float) -> void:
	if hips == null:
		return
	_t += dt
	_land = maxf(0.0, _land - dt * 3.2)
	_attack = maxf(0.0, _attack - dt)
	_air_time = 0.0 if grounded else _air_time + dt

	# knock-down blend
	var down_target := 1.0 if knocked > 0.0 else 0.0
	_down = _damp(_down, down_target, 6.0 if down_target > 0.5 else 3.0, dt)

	# gait parameters
	var s := speed
	var stride := lerpf(0.9, 1.7, clampf((s - 1.5) / 6.0, 0.0, 1.0))
	if grounded:
		_phase = fmod(_phase + dt * (s / stride) * PI, TAU * 4.0)
	var move := clampf(s / 1.6, 0.0, 1.0)            # 0 idle -> 1 walking
	var run := clampf((s - 2.4) / 2.4, 0.0, 1.0)      # 0 walk -> 1 jog
	var spr := clampf((s - 5.2) / 2.0, 0.0, 1.0)      # jog -> sprint
	var sw := sin(_phase)
	var cw := cos(_phase)

	# idle look-around & weight shift
	_look_timer -= dt
	if _look_timer <= 0.0:
		_look_timer = _rng.randf_range(2.0, 5.0)
		_look_target = _rng.randf_range(-0.7, 0.7) if _rng.randf() < 0.6 else 0.0
	_look_yaw = _damp(_look_yaw, _look_target * (1.0 - move), 3.0, dt)
	_shift = sin(_t * 0.6) * (1.0 - move)
	var breath := sin(_t * 2.1) * (1.0 - move * 0.5)

	var k := 14.0
	var leg_amp := lerpf(0.5, 0.95, run) + spr * 0.15
	var knee_amp := lerpf(0.65, 1.45, run) + spr * 0.2
	var arm_amp := lerpf(0.45, 0.9, run) + spr * 0.35
	var lean := run * 0.14 + spr * 0.16
	var bob := (absf(sw) * lerpf(0.035, 0.07, run)) * move

	var hip_y := HIP_H - 0.02 + bob - _land * 0.32 - run * 0.03
	var lf := Vector3.ZERO  # left thigh
	var rf := Vector3.ZERO
	var lk := 0.0
	var rk := 0.0
	var la := Vector3.ZERO  # left upper arm
	var ra := Vector3.ZERO
	var le := 0.0
	var re := 0.0
	var spine_r := Vector3.ZERO
	var chest_r := Vector3.ZERO
	var head_r := Vector3.ZERO

	if grounded or _air_time < 0.12:
		# --- locomotion / idle ---
		lf.x = -sw * leg_amp * move
		rf.x = sw * leg_amp * move
		lk = maxf(0.0, cw) * knee_amp * move + 0.05
		rk = maxf(0.0, -cw) * knee_amp * move + 0.05
		# idle stance: slight leg spread and weight shift
		lf.z = 0.04 + _shift * 0.04 * (1.0 - move)
		rf.z = -0.04 + _shift * 0.04 * (1.0 - move)
		la.x = sw * arm_amp * move
		ra.x = -sw * arm_amp * move
		la.z = -0.12 - run * 0.1
		ra.z = 0.12 + run * 0.1
		le = -(0.15 + run * 1.0 + spr * 0.3 + maxf(0.0, sw) * 0.3 * move)
		re = -(0.15 + run * 1.0 + spr * 0.3 + maxf(0.0, -sw) * 0.3 * move)
		spine_r.x = lean + breath * 0.015
		spine_r.y = sw * 0.12 * move
		chest_r.y = -sw * 0.18 * move
		chest_r.x = breath * 0.02
		spine_r.z = -turn_rate * 0.05 * clampf(s / 6.0, 0.0, 1.0) + _shift * 0.03
		head_r.y = _look_yaw - chest_r.y * 0.8 - spine_r.y
		head_r.x = -lean * 0.6
		# landing squash bends knees and hips
		lf.x -= _land * 0.9
		rf.x -= _land * 0.9
		lk += _land * 1.7
		rk += _land * 1.7
		spine_r.x += _land * 0.5
	else:
		# --- airborne ---
		var rising := vertical_speed > 0.0
		var fall_long := clampf((_air_time - 0.7) / 0.5, 0.0, 1.0)
		if rising:
			lf.x = -0.9
			lk = 1.4
			rf.x = 0.25
			rk = 0.5
			la.x = -0.6
			ra.x = 0.5
			la.z = -0.5
			ra.z = 0.5
			le = -0.6
			re = -0.4
			spine_r.x = 0.1
		else:
			lf.x = -0.4
			lk = 0.7
			rf.x = -0.1
			rk = 0.4
			la.z = -1.1 - sin(_t * 9.0) * 0.4 * fall_long
			ra.z = 1.1 + sin(_t * 9.0 + 1.0) * 0.4 * fall_long
			la.x = -0.3 + cos(_t * 9.0) * 0.8 * fall_long
			ra.x = -0.3 - cos(_t * 9.0) * 0.8 * fall_long
			le = -0.5
			re = -0.5
			spine_r.x = -0.05
			head_r.x = 0.2 * fall_long
		hip_y = HIP_H

	# --- attacks override upper body (and leg for kick) ---
	if _attack > 0.0:
		var dur := 0.42 if _attack_kind < 2 else 0.55
		var p := 1.0 - _attack / dur
		var strike := sin(clampf(p / 0.45, 0.0, 1.0) * PI * 0.5) * (1.0 - clampf((p - 0.55) / 0.45, 0.0, 1.0))
		if _attack_kind == 0:     # left jab
			la = Vector3(-1.45 * strike - 0.3, 0.0, -0.2)
			le = -1.6 * (1.0 - strike) - 0.05
			ra = Vector3(-0.8, 0.0, 0.25)
			re = -2.0
			chest_r.y = 0.45 * strike
			spine_r.x = 0.08
		elif _attack_kind == 1:   # right cross
			ra = Vector3(-1.5 * strike - 0.3, 0.0, 0.15)
			re = -1.6 * (1.0 - strike) - 0.05
			la = Vector3(-0.8, 0.0, -0.25)
			le = -2.0
			chest_r.y = -0.6 * strike
			spine_r.y = -0.2 * strike
			spine_r.x = 0.12
		else:                     # right front kick
			rf.x = -1.5 * strike
			rk = 1.6 * (1.0 - strike) + 0.1
			lf.x = 0.15 * strike
			lk = 0.25
			spine_r.x = -0.25 * strike
			la = Vector3(-0.6, 0, -0.5)
			ra = Vector3(0.3, 0, 0.6)
			le = -1.2
			re = -0.6
		k = 26.0

	# --- knock-down pose blend ---
	if _down > 0.01:
		var d := _down
		lf.x = lerpf(lf.x, -0.2, d)
		rf.x = lerpf(rf.x, 0.1, d)
		lk = lerpf(lk, 0.6, d)
		rk = lerpf(rk, 0.2, d)
		la = la.lerp(Vector3(-0.3, 0, -1.3), d)
		ra = ra.lerp(Vector3(0.2, 0, 1.0), d)
		le = lerpf(le, -0.4, d)
		re = lerpf(re, -0.2, d)
		spine_r.x = lerpf(spine_r.x, 0.0, d)
		hip_y = lerpf(hip_y, 0.16, d)

	hips.position.y = _damp(hips.position.y, hip_y, 18.0, dt)
	hips.position.x = _damp(hips.position.x, _shift * 0.025, 8.0, dt)
	# lying on the back: rotate whole hips
	hips.rotation.x = _damp(hips.rotation.x, -PI * 0.5 * _down, 10.0, dt)
	_set_rot(spine, spine_r, k, dt)
	_set_rot(chest, chest_r, k, dt)
	_set_rot(head, head_r, 8.0, dt)
	_set_rot(hip_l, lf, k, dt)
	_set_rot(hip_r, rf, k, dt)
	kn_l.rotation.x = _damp(kn_l.rotation.x, lk, k, dt)
	kn_r.rotation.x = _damp(kn_r.rotation.x, rk, k, dt)
	# keep feet roughly flat
	an_l.rotation.x = _damp(an_l.rotation.x, -(lf.x + lk) * 0.6 if grounded else 0.3, k, dt)
	an_r.rotation.x = _damp(an_r.rotation.x, -(rf.x + rk) * 0.6 if grounded else 0.3, k, dt)
	# arms were authored with 'negative z = outward' for the left side; flip to match pivots
	_set_rot(sh_l, Vector3(la.x, la.y, -la.z), k, dt)
	_set_rot(sh_r, Vector3(ra.x, ra.y, -ra.z), k, dt)
	el_l.rotation.x = _damp(el_l.rotation.x, le, k, dt)
	el_r.rotation.x = _damp(el_r.rotation.x, re, k, dt)
	if _skel:
		_apply_skeleton()
