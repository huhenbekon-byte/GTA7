extends RefCounted
class_name Props
## Factory of "Part" props built from primitives, each with real collision.
## Static: lamp, tree, bench, hydrant, parked car, phone booth, dumpster, bus stop, traffic light, mailbox.
## Physics (pushable/kickable): cone, crate, barrel, trash can, barrier, pallet stack, ball.

const L_WORLD := 1
const L_PROPS := 2

static var _mats := {}
static var _meshes := {}
static var _bulb: StandardMaterial3D
static var _car_templates: Array[Node3D] = []


## Car models from assets/cars/cars.glb (split into Car_N nodes by cars_import.gd).
static func random_car(rng: RandomNumberGenerator) -> Node3D:
	if _car_templates.is_empty():
		var lib: Node = (load("res://assets/cars/cars.glb") as PackedScene).instantiate()
		for c in lib.get_children():
			var sz: Vector3 = c.get_meta("size", Vector3.ZERO)
			# keep normal-sized vehicles for street parking; big trucks are rarer
			if sz.z <= 5.6 or rng.randf() < 0.3:
				lib.remove_child(c)
				_car_templates.append(c)
		lib.free()
	return _car_templates[rng.randi() % _car_templates.size()]


static func car_from(tmpl: Node3D, size: Vector3) -> Node3D:
	var b := _static()
	var vis := tmpl.duplicate()
	b.add_to_group("parked_car")
	b.add_child(vis)
	col_box(b, Vector3(size.x * 0.96, size.y * 0.55, size.z * 0.98), Vector3(0, size.y * 0.3, 0))
	col_box(b, Vector3(size.x * 0.85, size.y * 0.45, size.z * 0.7), Vector3(0, size.y * 0.75, 0))
	return b


## Shared street-lamp bulb material; main.gd drives its emission with the day/night cycle.
static func bulb_mat() -> StandardMaterial3D:
	if _bulb == null:
		_bulb = StandardMaterial3D.new()
		_bulb.albedo_color = Color(1.0, 0.9, 0.7)
		_bulb.emission_enabled = true
		_bulb.emission = Color(1.0, 0.85, 0.55)
		_bulb.emission_energy_multiplier = 0.0
	return _bulb


static func m(c: Color, rough := 0.8, metal := 0.0, emissive := 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [c.to_html(), rough, metal, emissive]
	if _mats.has(key):
		return _mats[key]
	var mt := StandardMaterial3D.new()
	mt.albedo_color = c
	mt.roughness = rough
	mt.metallic = metal
	if emissive > 0.0:
		mt.emission_enabled = true
		mt.emission = c
		mt.emission_energy_multiplier = emissive
	_mats[key] = mt
	return mt


static func box(x: float, y: float, z: float) -> BoxMesh:
	var key := "b%s|%s|%s" % [x, y, z]
	if not _meshes.has(key):
		var b := BoxMesh.new()
		b.size = Vector3(x, y, z)
		_meshes[key] = b
	return _meshes[key]


static func cyl(rt: float, rb: float, h: float, seg := 12) -> CylinderMesh:
	var key := "c%s|%s|%s|%s" % [rt, rb, h, seg]
	if not _meshes.has(key):
		var c := CylinderMesh.new()
		c.top_radius = rt
		c.bottom_radius = rb
		c.height = h
		c.radial_segments = seg
		c.rings = 1
		_meshes[key] = c
	return _meshes[key]


static func sph(r: float, seg := 10) -> SphereMesh:
	var key := "s%s|%s" % [r, seg]
	if not _meshes.has(key):
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2
		s.radial_segments = seg
		s.rings = seg / 2
		_meshes[key] = s
	return _meshes[key]


static func vis(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func col_box(body: CollisionObject3D, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	cs.shape = s
	cs.position = pos
	body.add_child(cs)


static func col_cyl(body: CollisionObject3D, r: float, h: float, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = h
	cs.shape = s
	cs.position = pos
	body.add_child(cs)


static func _static() -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = L_PROPS
	b.collision_mask = 0
	return b


static func _rigid(mass: float) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.collision_layer = L_PROPS
	b.collision_mask = L_WORLD | L_PROPS | 4 | 8
	b.mass = mass
	b.can_sleep = true
	b.sleeping = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.8
	pm.bounce = 0.1
	b.physics_material_override = pm
	return b


# ---------------------------------------------------------------- static props
static func lamp() -> Node3D:
	var b := _static()
	var pole := m(Color(0.18, 0.2, 0.2), 0.5, 0.6)
	vis(b, cyl(0.07, 0.1, 6.0, 8), pole, Vector3(0, 3.0, 0))
	vis(b, cyl(0.18, 0.2, 0.4, 8), pole, Vector3(0, 0.2, 0))
	vis(b, box(0.08, 0.08, 1.6), pole, Vector3(0, 5.95, 0.75), Vector3.ZERO, false)
	vis(b, box(0.32, 0.14, 0.55), pole, Vector3(0, 5.88, 1.5), Vector3.ZERO, false)
	var bulb := vis(b, box(0.26, 0.04, 0.46), bulb_mat(), Vector3(0, 5.8, 1.5), Vector3.ZERO, false)
	bulb.add_to_group("lamp_bulb")
	var anchor := Marker3D.new()
	anchor.position = Vector3(0, 5.5, 1.5)
	anchor.add_to_group("lamp_light")
	b.add_child(anchor)
	col_cyl(b, 0.15, 6.0, Vector3(0, 3.0, 0))
	return b


static func traffic_light() -> Node3D:
	var b := _static()
	var pole := m(Color(0.25, 0.25, 0.22), 0.5, 0.5)
	vis(b, cyl(0.08, 0.1, 4.2, 8), pole, Vector3(0, 2.1, 0))
	vis(b, box(0.32, 0.95, 0.3), m(Color(0.12, 0.12, 0.1)), Vector3(0, 3.7, 0.2))
	var cols := [Color(1, 0.15, 0.1), Color(1, 0.75, 0.1), Color(0.1, 1, 0.35)]
	for i in 3:
		var lm := vis(b, cyl(0.09, 0.09, 0.06, 10), m(cols[i] * 0.35), Vector3(0, 4.0 - i * 0.3, 0.37), Vector3(PI / 2, 0, 0), false)
		lm.set_meta("tl_index", i)
		lm.add_to_group("traffic_lamp")
	col_cyl(b, 0.12, 4.2, Vector3(0, 2.1, 0))
	return b


static func tree(rng: RandomNumberGenerator) -> Node3D:
	var b := _static()
	var h := rng.randf_range(3.5, 6.0)
	vis(b, cyl(0.12, 0.2, h, 8), m(Color(0.32, 0.22, 0.14)), Vector3(0, h * 0.5, 0))
	var leaf := m(Color(0.2 + rng.randf() * 0.1, 0.38 + rng.randf() * 0.12, 0.14), 0.9)
	for i in 4:
		var r := rng.randf_range(1.0, 1.6)
		var p := Vector3(rng.randf_range(-0.7, 0.7), h + rng.randf_range(-0.6, 0.8), rng.randf_range(-0.7, 0.7))
		var mi := vis(b, sph(1.0, 8), leaf, p)
		mi.scale = Vector3(r, r * 0.85, r)
	# planter
	vis(b, box(1.4, 0.3, 1.4), m(Color(0.5, 0.48, 0.45)), Vector3(0, 0.15, 0))
	vis(b, box(1.2, 0.05, 1.2), m(Color(0.25, 0.18, 0.12)), Vector3(0, 0.3, 0), Vector3.ZERO, false)
	col_cyl(b, 0.25, h, Vector3(0, h * 0.5, 0))
	col_box(b, Vector3(1.4, 0.3, 1.4), Vector3(0, 0.15, 0))
	return b


static func bench() -> Node3D:
	var b := _static()
	var wood := m(Color(0.55, 0.36, 0.2))
	var iron := m(Color(0.1, 0.1, 0.1), 0.5, 0.7)
	for i in 3:
		vis(b, box(1.8, 0.05, 0.12), wood, Vector3(0, 0.45, -0.15 + i * 0.15))
	for i in 2:
		vis(b, box(1.8, 0.1, 0.04), wood, Vector3(0, 0.65 + i * 0.15, -0.26), Vector3(-0.15, 0, 0))
	for x in [-0.8, 0.8]:
		vis(b, box(0.06, 0.45, 0.45), iron, Vector3(x, 0.22, -0.05))
		vis(b, box(0.06, 0.45, 0.05), iron, Vector3(x, 0.7, -0.28))
	col_box(b, Vector3(1.8, 0.47, 0.5), Vector3(0, 0.235, -0.05))
	col_box(b, Vector3(1.8, 0.45, 0.08), Vector3(0, 0.7, -0.27))
	return b


static func hydrant() -> Node3D:
	var b := _static()
	var red := m(Color(0.75, 0.1, 0.08), 0.5, 0.2)
	vis(b, cyl(0.13, 0.15, 0.6, 10), red, Vector3(0, 0.3, 0))
	vis(b, sph(0.13, 10), red, Vector3(0, 0.6, 0))
	vis(b, cyl(0.05, 0.05, 0.42, 8), red, Vector3(0, 0.42, 0), Vector3(0, 0, PI / 2))
	vis(b, cyl(0.2, 0.2, 0.06, 10), red, Vector3(0, 0.03, 0))
	col_cyl(b, 0.16, 0.75, Vector3(0, 0.37, 0))
	return b


static func car(rng: RandomNumberGenerator) -> Node3D:
	var b := _static()
	var colors := [Color(0.7, 0.08, 0.08), Color(0.08, 0.2, 0.55), Color(0.9, 0.9, 0.88), Color(0.08, 0.08, 0.09),
		Color(0.55, 0.57, 0.6), Color(0.95, 0.75, 0.1), Color(0.1, 0.4, 0.25), Color(0.4, 0.1, 0.35)]
	var paint := m(colors[rng.randi() % colors.size()], 0.25, 0.4)
	var glass := m(Color(0.08, 0.1, 0.13), 0.05, 0.6)
	var tire := m(Color(0.05, 0.05, 0.05), 0.9)
	var rim := m(Color(0.7, 0.7, 0.72), 0.3, 0.8)
	var is_van := rng.randf() < 0.2
	var L := 4.4 if not is_van else 4.9
	vis(b, box(1.8, 0.55, L), paint, Vector3(0, 0.62, 0))
	vis(b, box(1.82, 0.12, L - 0.1), m(Color(0.1, 0.1, 0.1)), Vector3(0, 0.38, 0))
	if is_van:
		vis(b, box(1.76, 0.95, L * 0.72), paint, Vector3(0, 1.35, -0.4))
		vis(b, box(1.78, 0.5, 0.05), glass, Vector3(0, 1.5, L * 0.36 - 0.38), Vector3(-0.2, 0, 0))
	else:
		vis(b, box(1.6, 0.5, L * 0.5), paint, Vector3(0, 1.13, -0.2))
		vis(b, box(1.62, 0.36, L * 0.5 - 0.15), glass, Vector3(0, 1.13, -0.2))
		vis(b, box(1.5, 0.05, 0.6), glass, Vector3(0, 1.06, L * 0.25 + 0.05), Vector3(-0.85, 0, 0))
		vis(b, box(1.5, 0.05, 0.5), glass, Vector3(0, 1.06, -L * 0.25 - 0.4), Vector3(0.95, 0, 0))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := Vector3(0.82 * sx, 0.34, (L * 0.5 - 0.8) * sz)
			vis(b, cyl(0.34, 0.34, 0.24, 14), tire, p, Vector3(0, 0, PI / 2))
			vis(b, cyl(0.2, 0.2, 0.26, 10), rim, p, Vector3(0, 0, PI / 2), false)
		vis(b, box(0.32, 0.14, 0.04), m(Color(1, 1, 0.9), 0.2, 0, 0.6), Vector3(0.6 * sx, 0.72, L * 0.5 + 0.01), Vector3.ZERO, false)
		vis(b, box(0.3, 0.12, 0.04), m(Color(0.8, 0.05, 0.05), 0.3, 0, 0.5), Vector3(0.6 * sx, 0.75, -L * 0.5 - 0.01), Vector3.ZERO, false)
		vis(b, box(0.08, 0.1, 0.18), paint, Vector3(0.95 * sx, 1.0, L * 0.12), Vector3.ZERO, false)  # mirrors
	vis(b, box(0.5, 0.12, 0.03), m(Color(0.9, 0.9, 0.9)), Vector3(0, 0.55, L * 0.5 + 0.02), Vector3.ZERO, false)  # plate
	col_box(b, Vector3(1.85, 0.9, L), Vector3(0, 0.6, 0))
	col_box(b, Vector3(1.65, 0.55 if not is_van else 1.0, L * (0.5 if not is_van else 0.72)), Vector3(0, 1.3 if not is_van else 1.55, -0.2 if not is_van else -0.4))
	return b


static func phone_booth() -> Node3D:
	var b := _static()
	var frame := m(Color(0.15, 0.3, 0.55), 0.4, 0.3)
	var glass := m(Color(0.5, 0.65, 0.75), 0.1, 0.2)
	vis(b, box(1.0, 0.15, 1.0), frame, Vector3(0, 2.3, 0))
	vis(b, box(0.98, 0.18, 0.98), m(Color(0.95, 0.95, 0.95), 0.3, 0, 0.5), Vector3(0, 2.15, 0), Vector3.ZERO, false)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			vis(b, box(0.08, 2.2, 0.08), frame, Vector3(0.46 * sx, 1.1, 0.46 * sz))
	vis(b, box(0.9, 1.6, 0.03), glass, Vector3(0, 1.2, -0.46))
	vis(b, box(0.03, 1.6, 0.9), glass, Vector3(-0.46, 1.2, 0))
	vis(b, box(0.03, 1.6, 0.9), glass, Vector3(0.46, 1.2, 0))
	vis(b, box(0.3, 0.45, 0.15), m(Color(0.2, 0.2, 0.2), 0.4, 0.5), Vector3(0, 1.35, -0.38))
	col_box(b, Vector3(1.0, 2.4, 0.1), Vector3(0, 1.2, -0.46))
	col_box(b, Vector3(0.1, 2.4, 1.0), Vector3(-0.46, 1.2, 0))
	col_box(b, Vector3(0.1, 2.4, 1.0), Vector3(0.46, 1.2, 0))
	return b


static func dumpster(rng: RandomNumberGenerator) -> Node3D:
	var b := _static()
	var c: Color = [Color(0.15, 0.35, 0.2), Color(0.2, 0.25, 0.45), Color(0.45, 0.2, 0.12)][rng.randi() % 3]
	var body := m(c, 0.6, 0.4)
	vis(b, box(2.0, 1.2, 1.2), body, Vector3(0, 0.75, 0))
	vis(b, box(2.05, 0.08, 1.25), m(Color(0.1, 0.1, 0.1), 0.7), Vector3(0, 1.38, -0.05), Vector3(0.12, 0, 0))
	for sx in [-0.8, 0.8]:
		for sz in [-0.45, 0.45]:
			vis(b, cyl(0.08, 0.08, 0.06, 8), m(Color(0.05, 0.05, 0.05)), Vector3(sx, 0.08, sz), Vector3(0, 0, PI / 2), false)
	col_box(b, Vector3(2.0, 1.4, 1.2), Vector3(0, 0.7, 0))
	return b


static func bus_stop() -> Node3D:
	var b := _static()
	var frame := m(Color(0.3, 0.32, 0.34), 0.4, 0.6)
	var glass := m(Color(0.55, 0.7, 0.8), 0.1, 0.2)
	vis(b, box(3.4, 0.08, 1.5), frame, Vector3(0, 2.5, 0))
	for x in [-1.6, 1.6]:
		vis(b, box(0.08, 2.5, 0.08), frame, Vector3(x, 1.25, -0.65))
		vis(b, box(0.08, 2.5, 0.08), frame, Vector3(x, 1.25, 0.65))
	vis(b, box(3.2, 1.8, 0.03), glass, Vector3(0, 1.3, -0.65))
	vis(b, box(0.03, 1.8, 1.2), m(Color(0.95, 0.9, 0.7), 0.3, 0, 0.35), Vector3(1.6, 1.3, 0))  # lit ad panel
	vis(b, box(2.4, 0.06, 0.4), frame, Vector3(0, 0.5, -0.4))
	col_box(b, Vector3(3.4, 2.5, 0.12), Vector3(0, 1.25, -0.65))
	col_box(b, Vector3(0.15, 2.5, 1.4), Vector3(1.6, 1.25, 0))
	col_box(b, Vector3(2.4, 0.5, 0.4), Vector3(0, 0.25, -0.4))
	col_box(b, Vector3(3.4, 0.1, 1.5), Vector3(0, 2.5, 0))
	return b


static func mailbox() -> Node3D:
	var b := _static()
	var blue := m(Color(0.1, 0.22, 0.55), 0.5, 0.3)
	vis(b, box(0.55, 0.9, 0.5), blue, Vector3(0, 0.75, 0))
	vis(b, cyl(0.25, 0.25, 0.55, 12), blue, Vector3(0, 1.2, 0), Vector3(0, 0, PI / 2))
	for sx in [-0.22, 0.22]:
		vis(b, box(0.06, 0.3, 0.06), blue, Vector3(sx, 0.15, 0.2))
		vis(b, box(0.06, 0.3, 0.06), blue, Vector3(sx, 0.15, -0.2))
	col_box(b, Vector3(0.55, 1.45, 0.5), Vector3(0, 0.72, 0))
	return b


# ---------------------------------------------------------------- physics props
static func cone() -> Node3D:
	var b := _rigid(3.0)
	var o := m(Color(1.0, 0.4, 0.05), 0.6)
	vis(b, cyl(0.03, 0.17, 0.7, 10), o, Vector3(0, 0.37, 0))
	vis(b, cyl(0.1, 0.13, 0.12, 10), m(Color(0.95, 0.95, 0.95)), Vector3(0, 0.42, 0), Vector3.ZERO, false)
	vis(b, box(0.45, 0.04, 0.45), o, Vector3(0, 0.02, 0))
	col_cyl(b, 0.16, 0.74, Vector3(0, 0.37, 0))
	return b


static func crate(rng: RandomNumberGenerator) -> Node3D:
	var s := rng.randf_range(0.6, 1.0)
	var b := _rigid(12.0 * s)
	var wood := m(Color(0.62, 0.45, 0.25))
	var dark := m(Color(0.42, 0.28, 0.14))
	vis(b, box(s, s, s), wood, Vector3(0, s * 0.5, 0))
	for sz in [-1.0, 1.0]:
		vis(b, box(s + 0.02, 0.08, 0.02), dark, Vector3(0, s * 0.5, (s * 0.5) * sz), Vector3(0, 0, 0.78), false)
		vis(b, box(s + 0.02, 0.08, 0.02), dark, Vector3(0, s * 0.5, (s * 0.5) * sz), Vector3(0, 0, -0.78), false)
	col_box(b, Vector3(s, s, s), Vector3(0, s * 0.5, 0))
	return b


static func barrel(rng: RandomNumberGenerator) -> Node3D:
	var b := _rigid(25.0)
	var c: Color = [Color(0.1, 0.3, 0.6), Color(0.7, 0.12, 0.08), Color(0.2, 0.4, 0.2), Color(0.85, 0.65, 0.1)][rng.randi() % 4]
	var mt := m(c, 0.5, 0.4)
	vis(b, cyl(0.3, 0.3, 0.9, 14), mt, Vector3(0, 0.45, 0))
	for y in [0.2, 0.7]:
		vis(b, cyl(0.31, 0.31, 0.04, 14), m(c.darkened(0.3), 0.4, 0.5), Vector3(0, y, 0), Vector3.ZERO, false)
	col_cyl(b, 0.3, 0.9, Vector3(0, 0.45, 0))
	return b


static func trash_can() -> Node3D:
	var b := _rigid(8.0)
	var mt := m(Color(0.25, 0.27, 0.28), 0.5, 0.6)
	vis(b, cyl(0.26, 0.22, 0.85, 12), mt, Vector3(0, 0.43, 0))
	vis(b, cyl(0.28, 0.28, 0.06, 12), mt, Vector3(0, 0.88, 0))
	vis(b, box(0.15, 0.05, 0.04), mt, Vector3(0, 0.95, 0), Vector3.ZERO, false)
	col_cyl(b, 0.26, 0.92, Vector3(0, 0.46, 0))
	return b


static func barrier(rng: RandomNumberGenerator) -> Node3D:
	var b := _rigid(60.0)
	var concrete := m(Color(0.68, 0.67, 0.64), 0.95)
	vis(b, box(2.0, 0.25, 0.6), concrete, Vector3(0, 0.125, 0))
	vis(b, box(2.0, 0.6, 0.25), concrete, Vector3(0, 0.55, 0))
	if rng.randf() < 0.5:
		for i in 4:
			vis(b, box(0.25, 0.4, 0.27), m(Color(0.9, 0.15, 0.1) if i % 2 == 0 else Color(0.95, 0.95, 0.95)), Vector3(-0.75 + i * 0.5, 0.6, 0), Vector3.ZERO, false)
	col_box(b, Vector3(2.0, 0.25, 0.6), Vector3(0, 0.125, 0))
	col_box(b, Vector3(2.0, 0.6, 0.27), Vector3(0, 0.55, 0))
	return b


static func pallets() -> Node3D:
	var b := _rigid(20.0)
	var wood := m(Color(0.7, 0.58, 0.4))
	for i in 3:
		vis(b, box(1.2, 0.12, 1.0), wood, Vector3(0, 0.06 + i * 0.14, 0), Vector3(0, randf_range(-0.1, 0.1), 0))
	col_box(b, Vector3(1.2, 0.42, 1.0), Vector3(0, 0.21, 0))
	return b


static func ball() -> Node3D:
	var b := _rigid(0.6)
	b.physics_material_override.bounce = 0.6
	vis(b, sph(0.22, 12), m(Color(0.95, 0.5, 0.1), 0.6), Vector3(0, 0.22, 0))
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.22
	cs.shape = s
	cs.position.y = 0.22
	b.add_child(cs)
	return b


## Footprint (half extents x/z) and kind, used by the spawner for clearance checks.
const KINDS := {
	"lamp": [0.3, 0.3], "tree": [0.8, 0.8], "bench": [1.0, 0.4], "hydrant": [0.25, 0.25], "car": [1.1, 2.6],
	"booth": [0.6, 0.6], "dumpster": [1.1, 0.7], "busstop": [1.8, 0.8], "mailbox": [0.35, 0.35],
	"traffic": [0.3, 0.3], "cone": [0.25, 0.25], "crate": [0.55, 0.55], "barrel": [0.35, 0.35],
	"trash": [0.3, 0.3], "barrier": [1.1, 0.4], "pallets": [0.7, 0.6], "ball": [0.3, 0.3],
}


static func make(kind: String, rng: RandomNumberGenerator) -> Node3D:
	match kind:
		"lamp": return lamp()
		"tree": return tree(rng)
		"bench": return bench()
		"hydrant": return hydrant()
		"car": return car(rng)
		"booth": return phone_booth()
		"dumpster": return dumpster(rng)
		"busstop": return bus_stop()
		"mailbox": return mailbox()
		"traffic": return traffic_light()
		"cone": return cone()
		"crate": return crate(rng)
		"barrel": return barrel(rng)
		"trash": return trash_can()
		"barrier": return barrier(rng)
		"pallets": return pallets()
		"ball": return ball()
	return Node3D.new()
