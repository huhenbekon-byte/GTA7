extends RefCounted
class_name Props
## Library of 3D props built from primitives, with procedural (noise) textures and real
## collision. Every prop's visual parts are baked into one mesh per material and cached
## per variant, so even detailed props cost only 1-3 draw calls.
##
## Sidewalk (breakable street furniture, frozen until hit): lamp, traffic, bench, hydrant,
##   booth, mailbox, trash, planter, bike_rack, meter, sign, bollards, kiosk; static: tree, busstop.
## Yard (against walls): crate, barrel, pallets, cone, barrier, dumpster, ball, container,
##   tires, spool, sandbags, fence, pipes, scaffold, trashbags, generator.
## Wall details (no collision): ac, drainpipe, awning, shop_sign, balcony, fire_escape, wall_lamp.
## Roof details: water_tower, roof_ac, antenna, dish, vents.

const L_WORLD := 1
const L_PROPS := 2

static var _mats := {}
static var _meshes := {}
static var _noise := {}
static var _bulb: StandardMaterial3D
static var _car_templates: Array[Node3D] = []
static var _bake_cache := {}
static var neon_mats: Array[StandardMaterial3D] = []


# ================================================================ cars
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


static var _all_cars := {}

## A specific car template by node name (e.g. "Car_0", the police jeep).
static func car_template(name: String) -> Node3D:
	if _all_cars.is_empty():
		var lib: Node = (load("res://assets/cars/cars.glb") as PackedScene).instantiate()
		for c in lib.get_children():
			lib.remove_child(c)
			_all_cars[str(c.name)] = c
		lib.free()
	return _all_cars.get(name)


static func car_from(tmpl: Node3D, size: Vector3) -> Node3D:
	var b := _breakable(1200.0)
	b.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	b.center_of_mass = Vector3(0, size.y * 0.3, 0)
	b.set_meta("tmpl", tmpl)
	b.set_meta("size", size)
	var vis := tmpl.duplicate()
	b.add_to_group("parked_car")
	b.add_child(vis)
	cull_by_size(vis)
	col_box(b, Vector3(size.x * 0.96, size.y * 0.55, size.z * 0.98), Vector3(0, size.y * 0.3, 0))
	col_box(b, Vector3(size.x * 0.85, size.y * 0.45, size.z * 0.7), Vector3(0, size.y * 0.75, 0))
	return b


# ================================================================ materials
## Shared street-lamp bulb material; main.gd drives its emission with the day/night cycle.
static func bulb_mat() -> StandardMaterial3D:
	if _bulb == null:
		_bulb = StandardMaterial3D.new()
		_bulb.albedo_color = Color(1.0, 0.9, 0.7)
		_bulb.emission_enabled = true
		_bulb.emission = Color(1.0, 0.85, 0.55)
		_bulb.emission_energy_multiplier = 0.0
	return _bulb


## Plain colour material.
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


static func _ntex(kind: String, normal: bool) -> NoiseTexture2D:
	var key := kind + ("_n" if normal else "")
	if _noise.has(key):
		return _noise[key]
	var fn := FastNoiseLite.new()
	fn.seed = absi(hash(kind)) % 1000
	match kind:
		"concrete":
			fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			fn.frequency = 0.07
			fn.fractal_octaves = 5
		"metal":
			fn.noise_type = FastNoiseLite.TYPE_SIMPLEX
			fn.frequency = 0.035
			fn.fractal_octaves = 4
		"rust":
			fn.noise_type = FastNoiseLite.TYPE_CELLULAR
			fn.frequency = 0.05
			fn.fractal_octaves = 3
		"wood":
			fn.noise_type = FastNoiseLite.TYPE_PERLIN
			fn.frequency = 0.03
			fn.fractal_octaves = 4
		"leaf":
			fn.noise_type = FastNoiseLite.TYPE_CELLULAR
			fn.frequency = 0.12
			fn.fractal_octaves = 2
		_:
			fn.frequency = 0.05
	var t := NoiseTexture2D.new()
	t.width = 128
	t.height = 128
	t.seamless = true
	t.noise = fn
	if normal:
		t.as_normal_map = true
		t.bump_strength = 4.0
	else:
		var g := Gradient.new()
		var lo := 0.5 if kind in ["rust", "leaf"] else 0.7
		g.set_color(0, Color(lo, lo, lo))
		g.set_color(1, Color(1, 1, 1))
		t.color_ramp = g
	_noise[key] = t
	return t


## Textured material (triplanar noise albedo + bump) for concrete / metal / rust / wood / leaf.
static func tm(c: Color, kind := "concrete", rough := 0.85, metal := 0.0, scale := 1.5) -> StandardMaterial3D:
	var key := "t%s|%s|%s|%s|%s" % [c.to_html(), kind, rough, metal, scale]
	if _mats.has(key):
		return _mats[key]
	var mt := StandardMaterial3D.new()
	mt.albedo_color = c
	mt.albedo_texture = _ntex(kind, false)
	mt.normal_enabled = true
	mt.normal_texture = _ntex(kind, true)
	mt.normal_scale = 0.5
	mt.uv1_triplanar = true
	mt.uv1_scale = Vector3(scale * 0.35, scale * 3.0, scale * 0.35) if kind == "wood" else Vector3.ONE * scale
	mt.roughness = rough
	mt.metallic = metal
	mt.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_mats[key] = mt
	return mt


## Shop-sign neon colours; main.gd scales their glow at night.
static func neon(c: Color) -> StandardMaterial3D:
	var key := "neon|" + c.to_html()
	if _mats.has(key):
		return _mats[key]
	var mt := StandardMaterial3D.new()
	mt.albedo_color = c
	mt.emission_enabled = true
	mt.emission = c
	mt.emission_energy_multiplier = 0.4
	mt.roughness = 0.3
	_mats[key] = mt
	neon_mats.append(mt)
	return mt


# ================================================================ mesh helpers
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


static func torus(inner: float, outer: float, seg := 16) -> TorusMesh:
	var key := "t%s|%s|%s" % [inner, outer, seg]
	if not _meshes.has(key):
		var t := TorusMesh.new()
		t.inner_radius = inner
		t.outer_radius = outer
		t.rings = seg
		t.ring_segments = 8
		_meshes[key] = t
	return _meshes[key]


static func vis(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, shadow := true, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## A cylinder "rod" between two points (pipes, rails, braces, frames).
static func rod(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: Material, shadow := true, seg := 6) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return
	var y := d / l
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	var mi := MeshInstance3D.new()
	mi.mesh = cyl(r, r, l, seg)
	mi.material_override = mat
	mi.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func col_box(body: CollisionObject3D, size: Vector3, pos: Vector3, rot := Vector3.ZERO) -> void:
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	cs.shape = s
	cs.position = pos
	cs.rotation = rot
	body.add_child(cs)


static func col_cyl(body: CollisionObject3D, r: float, h: float, pos: Vector3, rot := Vector3.ZERO) -> void:
	var cs := CollisionShape3D.new()
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = h
	cs.shape = s
	cs.position = pos
	cs.rotation = rot
	body.add_child(cs)


## Merges all plain MeshInstance3D children of `root` into one mesh per (material, shadow)
## and caches the result under `key`, so later props of the same variant reuse it.
static func bake(root: Node3D, key: String) -> void:
	var mis: Array[MeshInstance3D] = []
	for c in root.get_children():
		if c is MeshInstance3D and (c as Node).get_groups().is_empty() and not (c as Node).has_meta("tl_index"):
			mis.append(c)
	if mis.size() <= 1:
		return
	var out: Array
	if _bake_cache.has(key):
		out = _bake_cache[key]
	else:
		var groups := {}
		var order := []
		for mi in mis:
			var gk := "%d|%d" % [mi.material_override.get_instance_id() if mi.material_override else 0, mi.cast_shadow]
			if not groups.has(gk):
				var st := SurfaceTool.new()
				groups[gk] = [st, mi.material_override, mi.cast_shadow]
				order.append(gk)
			(groups[gk][0] as SurfaceTool).append_from(mi.mesh, 0, mi.transform)
		out = []
		for gk in order:
			var am: ArrayMesh = (groups[gk][0] as SurfaceTool).commit()
			if groups[gk][1]:
				am.surface_set_material(0, groups[gk][1])
			out.append([am, groups[gk][2]])
		_bake_cache[key] = out
	for mi in mis:
		root.remove_child(mi)
		mi.free()
	for e in out:
		var n := MeshInstance3D.new()
		n.mesh = e[0]
		n.cast_shadow = e[1]
		n.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		root.add_child(n)
	cull_by_size(root)


## Distance culling for mobile: small things vanish sooner than big ones (fog hides it).
static func cull_by_size(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		var sz := g.get_aabb().size.length()
		g.visibility_range_end = 60.0 if sz < 1.6 else (110.0 if sz < 5.0 else 180.0)
		g.visibility_range_end_margin = 5.0
		g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		if sz < 1.0:
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ================================================================ bodies
static func _static() -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = L_PROPS
	b.collision_mask = 0
	return b


## Street furniture: stays put (frozen) until a car or an explosion knocks it loose.
static func _breakable(mass: float) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.collision_layer = L_PROPS
	b.collision_mask = L_WORLD | L_PROPS | 16 | 32
	b.mass = mass
	b.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	b.freeze = true
	b.add_to_group("breakable")
	var pm := PhysicsMaterial.new()
	pm.friction = 0.7
	pm.bounce = 0.05
	b.physics_material_override = pm
	return b


static func _rigid(mass: float) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.collision_layer = L_PROPS
	b.collision_mask = L_WORLD | L_PROPS | 4 | 8 | 16
	b.mass = mass
	b.can_sleep = true
	b.sleeping = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.8
	pm.bounce = 0.1
	b.physics_material_override = pm
	return b


# common materials
static func _iron() -> StandardMaterial3D: return tm(Color(0.17, 0.2, 0.19), "metal", 0.45, 0.65, 2.0)
static func _steel() -> StandardMaterial3D: return tm(Color(0.62, 0.64, 0.66), "metal", 0.35, 0.8, 2.0)
static func _concrete() -> StandardMaterial3D: return tm(Color(0.66, 0.65, 0.62), "concrete", 0.95, 0.0, 1.2)
static func _wood() -> StandardMaterial3D: return tm(Color(0.6, 0.42, 0.25), "wood", 0.8, 0.0, 1.5)
static func _dark() -> StandardMaterial3D: return m(Color(0.06, 0.06, 0.07), 0.6)
static func _glass() -> StandardMaterial3D: return m(Color(0.42, 0.55, 0.62), 0.08, 0.4)


# ================================================================ sidewalk furniture
static func lamp() -> Node3D:
	var b := _breakable(140.0)
	var pole := _iron()
	vis(b, cyl(0.24, 0.26, 0.08, 14), pole, Vector3(0, 0.04, 0))
	vis(b, cyl(0.13, 0.17, 0.7, 12), pole, Vector3(0, 0.43, 0))
	vis(b, cyl(0.15, 0.15, 0.06, 12), pole, Vector3(0, 0.8, 0))
	vis(b, box(0.12, 0.3, 0.02), m(Color(0.1, 0.12, 0.12), 0.5, 0.5), Vector3(0, 0.45, 0.16), Vector3.ZERO, false)   # service door
	vis(b, cyl(0.06, 0.095, 5.6, 10), pole, Vector3(0, 3.6, 0))
	vis(b, cyl(0.09, 0.09, 0.08, 10), pole, Vector3(0, 2.6, 0))
	vis(b, sph(0.08, 8), pole, Vector3(0, 6.42, 0))
	rod(b, Vector3(0, 6.3, 0), Vector3(0, 6.42, 1.75), 0.04, pole, false)
	rod(b, Vector3(0, 5.75, 0.05), Vector3(0, 6.32, 0.8), 0.025, pole, false)
	vis(b, box(0.36, 0.12, 0.66), pole, Vector3(0, 6.42, 1.85), Vector3.ZERO, false)
	vis(b, cyl(0.16, 0.2, 0.1, 10), pole, Vector3(0, 6.5, 1.85), Vector3.ZERO, false)
	var bulb := vis(b, box(0.3, 0.04, 0.54), bulb_mat(), Vector3(0, 6.35, 1.85), Vector3.ZERO, false)
	bulb.add_to_group("lamp_bulb")
	var anchor := Marker3D.new()
	anchor.position = Vector3(0, 6.0, 1.85)
	anchor.add_to_group("lamp_light")
	b.add_child(anchor)
	col_cyl(b, 0.16, 6.4, Vector3(0, 3.2, 0))
	bake(b, "lamp")
	return b


static func traffic_light() -> Node3D:
	var b := _breakable(180.0)
	var pole := tm(Color(0.3, 0.31, 0.28), "metal", 0.5, 0.5, 2.0)
	var housing := m(Color(0.12, 0.12, 0.1), 0.5, 0.3)
	vis(b, cyl(0.2, 0.22, 0.1, 12), pole, Vector3(0, 0.05, 0))
	vis(b, cyl(0.08, 0.1, 5.6, 10), pole, Vector3(0, 2.8, 0))
	rod(b, Vector3(0, 5.3, 0), Vector3(0, 5.3, 3.6), 0.055, pole)
	rod(b, Vector3(0, 4.6, 0), Vector3(0, 5.25, 1.6), 0.03, pole, false)
	# pedestrian button and walk signal
	vis(b, box(0.12, 0.18, 0.1), m(Color(0.85, 0.75, 0.1), 0.5), Vector3(0, 1.1, 0.12), Vector3.ZERO, false)
	vis(b, box(0.3, 0.3, 0.2), housing, Vector3(0, 2.7, 0.18), Vector3.ZERO, false)
	vis(b, box(0.22, 0.22, 0.02), m(Color(1, 1, 1), 0.3, 0, 1.2), Vector3(0, 2.7, 0.29), Vector3.ZERO, false)
	# two signal heads: on the pole and hanging over the road, each lit on both sides
	var cols := [Color(1, 0.15, 0.1), Color(1, 0.75, 0.1), Color(0.1, 1, 0.35)]
	for head in [Vector3(0, 3.6, 0.2), Vector3(0, 4.75, 3.4)]:
		vis(b, box(0.36, 1.0, 0.34), housing, head)
		vis(b, box(0.5, 1.12, 0.04), housing, head + Vector3(0, 0, -0.19), Vector3.ZERO, false)  # back plate
		for side in [-1.0, 1.0]:
			for i in 3:
				var lp: Vector3 = head + Vector3(0.19 * side, 0.3 - i * 0.3, 0)
				var lm := vis(b, cyl(0.1, 0.1, 0.04, 12), m(cols[i] * 0.3), lp, Vector3(0, 0, PI / 2), false)
				lm.set_meta("tl_index", i)
				lm.add_to_group("traffic_lamp")
				vis(b, box(0.14, 0.03, 0.24), housing, lp + Vector3(0.06 * side, 0.12, 0), Vector3.ZERO, false)  # visor
	col_cyl(b, 0.12, 5.6, Vector3(0, 2.8, 0))
	bake(b, "traffic")
	return b


static func tree(rng: RandomNumberGenerator) -> Node3D:
	var b := _static()
	var variant := rng.randi() % 4
	var r := RandomNumberGenerator.new()
	r.seed = variant * 7919 + 13
	var h := r.randf_range(3.6, 5.6)
	var bark := tm(Color(0.36, 0.26, 0.18), "wood", 0.95, 0.0, 3.0)
	var leaf_a := tm(Color(0.22, 0.42 + r.randf() * 0.1, 0.16), "leaf", 0.95, 0.0, 2.0)
	var leaf_b := tm(Color(0.3, 0.5, 0.2), "leaf", 0.95, 0.0, 2.0)
	# tree pit with grate and low stone ring
	vis(b, box(1.5, 0.12, 1.5), _concrete(), Vector3(0, 0.06, 0))
	vis(b, box(1.25, 0.04, 1.25), m(Color(0.22, 0.16, 0.1), 0.95), Vector3(0, 0.12, 0), Vector3.ZERO, false)
	for i in 4:
		vis(b, box(1.25, 0.02, 0.04), m(Color(0.15, 0.15, 0.15), 0.5, 0.6), Vector3(0, 0.145, -0.45 + i * 0.3), Vector3.ZERO, false)
	# trunk with flare and branches
	vis(b, cyl(0.14, 0.24, 0.5, 10), bark, Vector3(0, 0.38, 0))
	vis(b, cyl(0.1, 0.14, h, 10), bark, Vector3(0, 0.6 + h * 0.5, 0))
	var crowns := []
	for i in 3:
		var a := r.randf() * TAU
		var from := Vector3(0, h * r.randf_range(0.55, 0.8), 0)
		var to := from + Vector3(cos(a) * 1.0, r.randf_range(0.6, 1.1), sin(a) * 1.0)
		rod(b, from, to, 0.06, bark, true, 6)
		crowns.append(to)
	crowns.append(Vector3(0, h + 0.6, 0))
	for c in crowns:
		for j in 3:
			var s := r.randf_range(0.8, 1.25)
			var p: Vector3 = c + Vector3(r.randf_range(-0.6, 0.6), r.randf_range(-0.2, 0.5), r.randf_range(-0.6, 0.6))
			vis(b, sph(1.0, 8), leaf_a if j % 2 == 0 else leaf_b, p, Vector3(r.randf(), r.randf(), r.randf()), true, Vector3(s, s * 0.8, s))
	col_cyl(b, 0.22, h, Vector3(0, h * 0.5, 0))
	col_box(b, Vector3(1.5, 0.15, 1.5), Vector3(0, 0.075, 0))
	bake(b, "tree%d" % variant)
	return b


static func bench() -> Node3D:
	var b := _breakable(70.0)
	var wood := _wood()
	var iron := _iron()
	for i in 4:
		vis(b, box(1.9, 0.045, 0.1), wood, Vector3(0, 0.46, -0.2 + i * 0.12))
	for i in 3:
		vis(b, box(1.9, 0.09, 0.035), wood, Vector3(0, 0.62 + i * 0.13, -0.3 - i * 0.03), Vector3(-0.22, 0, 0))
	for x in [-0.85, 0.85]:
		vis(b, box(0.06, 0.06, 0.55), iron, Vector3(x, 0.42, -0.08))           # seat bearer
		rod(b, Vector3(x, 0.0, 0.15), Vector3(x, 0.42, 0.12), 0.03, iron)       # front leg
		rod(b, Vector3(x, 0.0, -0.3), Vector3(x, 0.95, -0.4), 0.03, iron)       # back leg + back support
		rod(b, Vector3(x, 0.62, 0.12), Vector3(x, 0.62, -0.32), 0.025, iron)    # armrest
		rod(b, Vector3(x, 0.42, 0.12), Vector3(x, 0.62, 0.12), 0.02, iron)
		vis(b, box(0.12, 0.02, 0.12), iron, Vector3(x, 0.01, 0.15), Vector3.ZERO, false)
		vis(b, box(0.12, 0.02, 0.12), iron, Vector3(x, 0.01, -0.3), Vector3.ZERO, false)
	col_box(b, Vector3(1.9, 0.48, 0.55), Vector3(0, 0.24, -0.05))
	col_box(b, Vector3(1.9, 0.45, 0.12), Vector3(0, 0.75, -0.36))
	bake(b, "bench")
	return b


static func hydrant() -> Node3D:
	var b := _breakable(90.0)
	var red := tm(Color(0.72, 0.1, 0.08), "metal", 0.45, 0.25, 4.0)
	var brass := m(Color(0.75, 0.6, 0.25), 0.3, 0.8)
	vis(b, cyl(0.21, 0.21, 0.06, 12), red, Vector3(0, 0.03, 0))
	for i in 6:
		var a := i * TAU / 6.0
		vis(b, sph(0.025, 6), brass, Vector3(cos(a) * 0.17, 0.065, sin(a) * 0.17), Vector3.ZERO, false)
	vis(b, cyl(0.13, 0.15, 0.55, 14), red, Vector3(0, 0.33, 0))
	vis(b, cyl(0.16, 0.16, 0.05, 14), red, Vector3(0, 0.6, 0))
	vis(b, sph(0.135, 12), red, Vector3(0, 0.63, 0))
	vis(b, cyl(0.03, 0.045, 0.08, 6), brass, Vector3(0, 0.79, 0))
	vis(b, cyl(0.055, 0.055, 0.42, 10), red, Vector3(0, 0.43, 0), Vector3(0, 0, PI / 2))
	for sx in [-0.23, 0.23]:
		vis(b, cyl(0.065, 0.065, 0.04, 10), brass, Vector3(sx, 0.43, 0), Vector3(0, 0, PI / 2), false)
	vis(b, cyl(0.08, 0.08, 0.14, 12), red, Vector3(0, 0.38, 0.14), Vector3(PI / 2, 0, 0))
	vis(b, cyl(0.09, 0.09, 0.04, 12), brass, Vector3(0, 0.38, 0.22), Vector3(PI / 2, 0, 0), false)
	col_cyl(b, 0.17, 0.82, Vector3(0, 0.41, 0))
	bake(b, "hydrant")
	return b


static func phone_booth() -> Node3D:
	var b := _breakable(240.0)
	var frame := tm(Color(0.14, 0.28, 0.55), "metal", 0.4, 0.4, 2.0)
	var glass := _glass()
	vis(b, box(1.06, 0.08, 1.06), _concrete(), Vector3(0, 0.04, 0))
	vis(b, box(1.04, 0.16, 1.04), frame, Vector3(0, 2.36, 0))
	vis(b, box(1.0, 0.2, 1.0), m(Color(0.95, 0.95, 0.95), 0.3, 0, 0.6), Vector3(0, 2.2, 0), Vector3.ZERO, false)
	vis(b, box(1.1, 0.05, 1.1), frame, Vector3(0, 2.46, 0))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			vis(b, box(0.07, 2.3, 0.07), frame, Vector3(0.48 * sx, 1.18, 0.48 * sz))
	vis(b, box(0.92, 0.04, 0.92), frame, Vector3(0, 0.3, 0), Vector3.ZERO, false)
	vis(b, box(0.9, 1.7, 0.02), glass, Vector3(0, 1.25, -0.48))
	vis(b, box(0.02, 1.7, 0.9), glass, Vector3(-0.48, 1.25, 0))
	vis(b, box(0.02, 1.7, 0.9), glass, Vector3(0.48, 1.25, 0))
	vis(b, box(0.32, 0.5, 0.14), m(Color(0.25, 0.25, 0.27), 0.4, 0.6), Vector3(0, 1.35, -0.4))
	vis(b, box(0.06, 0.2, 0.06), _dark(), Vector3(0.12, 1.45, -0.32), Vector3.ZERO, false)
	vis(b, box(0.4, 0.04, 0.3), m(Color(0.3, 0.3, 0.32), 0.5, 0.5), Vector3(0, 1.0, -0.35), Vector3.ZERO, false)
	col_box(b, Vector3(1.06, 2.5, 0.1), Vector3(0, 1.25, -0.48))
	col_box(b, Vector3(0.1, 2.5, 1.06), Vector3(-0.48, 1.25, 0))
	col_box(b, Vector3(0.1, 2.5, 1.06), Vector3(0.48, 1.25, 0))
	bake(b, "booth")
	return b


static func mailbox() -> Node3D:
	var b := _breakable(80.0)
	var blue := tm(Color(0.1, 0.22, 0.55), "metal", 0.45, 0.3, 3.0)
	vis(b, box(0.56, 0.85, 0.5), blue, Vector3(0, 0.78, 0))
	vis(b, cyl(0.25, 0.25, 0.56, 14), blue, Vector3(0, 1.2, 0), Vector3(0, 0, PI / 2))
	vis(b, box(0.4, 0.05, 0.02), _dark(), Vector3(0, 1.05, 0.26), Vector3.ZERO, false)
	vis(b, box(0.36, 0.22, 0.02), m(Color(0.9, 0.9, 0.9), 0.5), Vector3(0, 0.7, 0.255), Vector3.ZERO, false)
	for sx in [-0.22, 0.22]:
		for sz in [-0.2, 0.2]:
			vis(b, box(0.06, 0.36, 0.06), blue, Vector3(sx, 0.18, sz))
	col_box(b, Vector3(0.56, 1.45, 0.5), Vector3(0, 0.72, 0))
	bake(b, "mailbox")
	return b


static func trash_can() -> Node3D:
	var b := _rigid(9.0)
	var body := tm(Color(0.2, 0.32, 0.22), "metal", 0.5, 0.5, 3.0)
	vis(b, cyl(0.27, 0.23, 0.85, 14), body, Vector3(0, 0.43, 0))
	for y in [0.2, 0.5, 0.8]:
		vis(b, cyl(0.275, 0.275, 0.03, 14), m(Color(0.12, 0.18, 0.13), 0.5, 0.5), Vector3(0, y, 0), Vector3.ZERO, false)
	vis(b, cyl(0.24, 0.29, 0.1, 14), body, Vector3(0, 0.9, 0))
	vis(b, cyl(0.15, 0.15, 0.04, 12), _dark(), Vector3(0, 0.955, 0), Vector3.ZERO, false)
	vis(b, box(0.18, 0.03, 0.05), _steel(), Vector3(0, 0.98, 0), Vector3.ZERO, false)
	col_cyl(b, 0.27, 0.95, Vector3(0, 0.47, 0))
	bake(b, "trash")
	return b


static func planter(rng: RandomNumberGenerator) -> Node3D:
	var b := _breakable(400.0)
	var v := rng.randi() % 3
	var r := RandomNumberGenerator.new()
	r.seed = v * 31 + 5
	vis(b, box(1.7, 0.55, 0.85), _concrete(), Vector3(0, 0.275, 0))
	vis(b, box(1.8, 0.06, 0.95), _concrete(), Vector3(0, 0.57, 0))
	vis(b, box(1.55, 0.05, 0.7), m(Color(0.2, 0.14, 0.09), 0.95), Vector3(0, 0.56, 0), Vector3.ZERO, false)
	var leaf := tm(Color(0.2, 0.42, 0.18), "leaf", 0.95, 0.0, 3.0)
	for i in 4:
		var s := r.randf_range(0.28, 0.42)
		vis(b, sph(1.0, 8), leaf, Vector3(-0.6 + i * 0.4, 0.65 + s * 0.5, r.randf_range(-0.12, 0.12)), Vector3.ZERO, true, Vector3(s, s * 0.9, s))
	var fc: Color = [Color(0.9, 0.2, 0.3), Color(0.95, 0.85, 0.2), Color(0.7, 0.3, 0.9)][v]
	for i in 9:
		vis(b, sph(0.05, 6), m(fc, 0.7), Vector3(r.randf_range(-0.7, 0.7), r.randf_range(0.75, 1.0), r.randf_range(-0.25, 0.25)), Vector3.ZERO, false)
	col_box(b, Vector3(1.8, 0.6, 0.95), Vector3(0, 0.3, 0))
	bake(b, "planter%d" % v)
	return b


static func bike_rack(rng: RandomNumberGenerator) -> Node3D:
	var b := _breakable(60.0)
	var steel := _steel()
	for i in 3:
		var x := -0.8 + i * 0.8
		rod(b, Vector3(x, 0, -0.3), Vector3(x, 0.75, -0.3), 0.03, steel)
		rod(b, Vector3(x, 0, 0.3), Vector3(x, 0.75, 0.3), 0.03, steel)
		rod(b, Vector3(x, 0.75, -0.3), Vector3(x, 0.75, 0.3), 0.03, steel)
	var n := 1 + rng.randi() % 2
	for k in n:
		var x := -0.4 + k * 0.8
		var col: Color = [Color(0.8, 0.1, 0.1), Color(0.1, 0.3, 0.8), Color(0.1, 0.1, 0.1), Color(0.9, 0.7, 0.1)][(rng.randi() + k) % 4]
		_bicycle(b, Vector3(x, 0, 0), col)
	col_box(b, Vector3(1.8, 0.8, 0.7), Vector3(0, 0.4, 0))
	bake(b, "bike%d%s" % [n, str(rng.randi() % 3)])
	return b


static func _bicycle(b: Node3D, at: Vector3, col: Color) -> void:
	var frame := m(col, 0.4, 0.4)
	var tire := _dark()
	for z in [-0.52, 0.52]:
		vis(b, torus(0.29, 0.34, 18), tire, at + Vector3(0, 0.34, z), Vector3(0, 0, PI / 2))
		vis(b, cyl(0.04, 0.04, 0.08, 8), _steel(), at + Vector3(0, 0.34, z), Vector3(0, 0, PI / 2), false)
	var rear := at + Vector3(0, 0.34, -0.52)
	var front := at + Vector3(0, 0.34, 0.52)
	var crank := at + Vector3(0, 0.3, -0.05)
	var seat := at + Vector3(0, 0.82, -0.2)
	var head := at + Vector3(0, 0.85, 0.38)
	for pair in [[rear, crank], [crank, seat], [seat, rear], [crank, head], [seat, head], [head, front]]:
		rod(b, pair[0], pair[1], 0.018, frame, false)
	vis(b, box(0.08, 0.04, 0.22), _dark(), seat + Vector3(0, 0.04, 0), Vector3.ZERO, false)
	rod(b, head, head + Vector3(0, 0.12, -0.05), 0.016, frame, false)
	rod(b, head + Vector3(-0.25, 0.12, -0.05), head + Vector3(0.25, 0.12, -0.05), 0.014, _dark(), false)


static func parking_meter() -> Node3D:
	var b := _breakable(35.0)
	var pole := _iron()
	vis(b, cyl(0.04, 0.05, 1.1, 8), pole, Vector3(0, 0.55, 0))
	vis(b, box(0.2, 0.3, 0.15), tm(Color(0.5, 0.52, 0.5), "metal", 0.4, 0.6, 4.0), Vector3(0, 1.25, 0))
	vis(b, sph(0.1, 10), _glass(), Vector3(0, 1.38, 0.03), Vector3.ZERO, false, Vector3(0.9, 0.6, 0.7))
	vis(b, box(0.12, 0.07, 0.02), m(Color(0.2, 0.8, 0.3), 0.3, 0, 0.8), Vector3(0, 1.2, 0.08), Vector3.ZERO, false)
	col_cyl(b, 0.12, 1.45, Vector3(0, 0.72, 0))
	bake(b, "meter")
	return b


static func street_sign(rng: RandomNumberGenerator) -> Node3D:
	var b := _breakable(30.0)
	var v := rng.randi() % 4
	var pole := _steel()
	vis(b, cyl(0.035, 0.035, 2.6, 8), pole, Vector3(0, 1.3, 0))
	match v:
		0:  # stop
			vis(b, cyl(0.36, 0.36, 0.03, 8), m(Color(0.8, 0.08, 0.06), 0.4), Vector3(0, 2.3, 0.05), Vector3(PI / 2, 0, PI / 8))
			vis(b, box(0.42, 0.1, 0.01), m(Color(1, 1, 1), 0.4), Vector3(0, 2.3, 0.07), Vector3.ZERO, false)
		1:  # speed limit
			vis(b, box(0.5, 0.62, 0.03), m(Color(0.95, 0.95, 0.95), 0.4), Vector3(0, 2.25, 0.05))
			vis(b, torus(0.17, 0.22, 20), m(Color(0.8, 0.1, 0.08), 0.4), Vector3(0, 2.25, 0.07), Vector3(PI / 2, 0, 0), false)
			vis(b, box(0.16, 0.12, 0.01), _dark(), Vector3(0, 2.25, 0.075), Vector3.ZERO, false)
		2:  # one way
			vis(b, box(0.8, 0.28, 0.03), m(Color(0.1, 0.25, 0.6), 0.4), Vector3(0, 2.35, 0.05))
			vis(b, box(0.5, 0.07, 0.01), m(Color(1, 1, 1), 0.4), Vector3(-0.05, 2.35, 0.07), Vector3.ZERO, false)
			vis(b, cyl(0.0, 0.11, 0.18, 3), m(Color(1, 1, 1), 0.4), Vector3(0.27, 2.35, 0.07), Vector3(0, 0, -PI / 2), false)
		3:  # street name blade
			vis(b, box(0.9, 0.2, 0.03), m(Color(0.1, 0.42, 0.2), 0.4), Vector3(0, 2.5, 0), Vector3(0, PI / 2, 0))
			vis(b, box(0.9, 0.2, 0.03), m(Color(0.1, 0.42, 0.2), 0.4), Vector3(0, 2.28, 0))
	col_cyl(b, 0.08, 2.6, Vector3(0, 1.3, 0))
	bake(b, "sign%d" % v)
	return b


static func bollards() -> Node3D:
	var b := _breakable(120.0)
	var post := tm(Color(0.85, 0.7, 0.1), "metal", 0.5, 0.2, 4.0)
	for i in 3:
		var x := -1.0 + i * 1.0
		vis(b, cyl(0.09, 0.1, 0.9, 12), post, Vector3(x, 0.45, 0))
		vis(b, sph(0.09, 10), post, Vector3(x, 0.9, 0))
		vis(b, cyl(0.102, 0.102, 0.08, 12), _dark(), Vector3(x, 0.7, 0), Vector3.ZERO, false)
		col_cyl(b, 0.1, 0.95, Vector3(x, 0.47, 0))
	bake(b, "bollards")
	return b


static func kiosk(rng: RandomNumberGenerator) -> Node3D:
	var b := _breakable(900.0)
	var v := rng.randi() % 3
	var body := tm([Color(0.15, 0.35, 0.25), Color(0.5, 0.15, 0.12), Color(0.2, 0.25, 0.45)][v], "metal", 0.5, 0.3, 2.0)
	vis(b, box(2.4, 2.3, 1.6), body, Vector3(0, 1.15, -0.1))
	vis(b, box(2.6, 0.12, 2.1), body, Vector3(0, 2.36, 0.05))
	vis(b, box(2.6, 0.06, 1.0), m(Color(0.9, 0.85, 0.75), 0.6), Vector3(0, 2.2, 1.05), Vector3(0.35, 0, 0))   # awning
	vis(b, box(2.0, 0.9, 0.03), _glass(), Vector3(0, 1.45, 0.71))
	vis(b, box(2.0, 0.08, 0.35), body, Vector3(0, 0.95, 0.85))           # counter
	for i in 10:
		var c := Color.from_hsv(float(i) / 10.0, 0.6, 0.9)
		vis(b, box(0.17, 0.24, 0.02), m(c, 0.6), Vector3(-0.9 + i * 0.2, 1.62, 0.74), Vector3(-0.15, 0, 0), false)
	vis(b, box(1.6, 0.35, 0.05), neon(Color(1.0, 0.85, 0.3)), Vector3(0, 2.6, 0.7), Vector3.ZERO, false)
	col_box(b, Vector3(2.5, 2.4, 1.8), Vector3(0, 1.2, 0))
	bake(b, "kiosk%d" % v)
	return b


static func bus_stop() -> Node3D:
	var b := _static()
	var frame := tm(Color(0.3, 0.32, 0.34), "metal", 0.4, 0.6, 2.0)
	var glass := _glass()
	vis(b, box(3.6, 0.1, 1.6), frame, Vector3(0, 2.55, 0))
	vis(b, box(3.6, 0.22, 0.06), frame, Vector3(0, 2.45, 0.78))
	vis(b, box(3.4, 0.05, 1.4), m(Color(0.9, 0.9, 0.85), 0.3, 0, 0.3), Vector3(0, 2.48, 0), Vector3.ZERO, false)
	for x in [-1.7, 0.0, 1.7]:
		vis(b, box(0.08, 2.5, 0.08), frame, Vector3(x, 1.25, -0.7))
	for x in [-1.7, 1.7]:
		vis(b, box(0.08, 2.5, 0.08), frame, Vector3(x, 1.25, 0.7))
	vis(b, box(3.3, 1.8, 0.03), glass, Vector3(0, 1.35, -0.7))
	vis(b, box(0.03, 1.8, 1.3), glass, Vector3(-1.7, 1.35, 0))
	vis(b, box(0.12, 1.9, 1.35), frame, Vector3(1.7, 1.3, 0))
	vis(b, box(0.03, 1.6, 1.15), m(Color(0.95, 0.9, 0.7), 0.3, 0, 0.6), Vector3(1.64, 1.35, 0), Vector3.ZERO, false)   # lit ad
	vis(b, box(2.4, 0.06, 0.4), _wood(), Vector3(-0.2, 0.5, -0.45))
	for x in [-1.2, 0.8]:
		vis(b, box(0.06, 0.5, 0.06), frame, Vector3(x, 0.25, -0.45))
	# stop sign pole
	vis(b, cyl(0.04, 0.04, 2.9, 8), frame, Vector3(2.2, 1.45, 0.6))
	vis(b, cyl(0.25, 0.25, 0.04, 16), m(Color(0.95, 0.75, 0.1), 0.4), Vector3(2.2, 2.85, 0.6), Vector3(PI / 2, 0, 0))
	vis(b, cyl(0.17, 0.17, 0.045, 16), m(Color(0.1, 0.4, 0.15), 0.4), Vector3(2.2, 2.85, 0.6), Vector3(PI / 2, 0, 0), false)
	col_box(b, Vector3(3.6, 2.5, 0.12), Vector3(0, 1.25, -0.7))
	col_box(b, Vector3(0.15, 2.5, 1.4), Vector3(1.7, 1.25, 0))
	col_box(b, Vector3(2.4, 0.5, 0.4), Vector3(-0.2, 0.25, -0.45))
	col_box(b, Vector3(3.6, 0.12, 1.6), Vector3(0, 2.55, 0))
	bake(b, "busstop")
	return b


# ================================================================ yard / loose props
static func cone() -> Node3D:
	var b := _rigid(3.0)
	var o := m(Color(1.0, 0.4, 0.05), 0.6)
	vis(b, cyl(0.03, 0.17, 0.7, 14), o, Vector3(0, 0.37, 0))
	vis(b, cyl(0.085, 0.12, 0.1, 14), m(Color(0.95, 0.95, 0.95), 0.3), Vector3(0, 0.42, 0), Vector3.ZERO, false)
	vis(b, cyl(0.135, 0.155, 0.07, 14), m(Color(0.95, 0.95, 0.95), 0.3), Vector3(0, 0.22, 0), Vector3.ZERO, false)
	vis(b, box(0.45, 0.04, 0.45), m(Color(0.1, 0.1, 0.1), 0.8), Vector3(0, 0.02, 0))
	col_cyl(b, 0.16, 0.74, Vector3(0, 0.37, 0))
	bake(b, "cone")
	return b


static func crate(rng: RandomNumberGenerator) -> Node3D:
	var v := rng.randi() % 3
	var s: float = [0.6, 0.8, 1.0][v]
	var b := _rigid(12.0 * s)
	var wood := _wood()
	var dark := tm(Color(0.4, 0.27, 0.14), "wood", 0.85, 0.0, 2.0)
	vis(b, box(s - 0.04, s - 0.04, s - 0.04), wood, Vector3(0, s * 0.5, 0))
	# edge battens + diagonal braces on two faces
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			vis(b, box(0.06, s, 0.06), dark, Vector3((s * 0.5 - 0.03) * sx, s * 0.5, (s * 0.5 - 0.03) * sz))
	for sy in [0.03, s - 0.03]:
		for sz in [-1.0, 1.0]:
			vis(b, box(s, 0.06, 0.06), dark, Vector3(0, sy, (s * 0.5 - 0.03) * sz), Vector3.ZERO, false)
	for sz in [-1.0, 1.0]:
		vis(b, box(s * 1.25, 0.07, 0.03), dark, Vector3(0, s * 0.5, (s * 0.5 + 0.01) * sz), Vector3(0, 0, 0.78), false)
	col_box(b, Vector3(s, s, s), Vector3(0, s * 0.5, 0))
	bake(b, "crate%d" % v)
	return b


static func barrel(rng: RandomNumberGenerator) -> Node3D:
	var b := _rigid(25.0)
	var explosive := rng.randf() < 0.4
	var ci := rng.randi() % 3
	var c: Color = Color(0.78, 0.1, 0.06) if explosive else [Color(0.1, 0.3, 0.6), Color(0.2, 0.4, 0.2), Color(0.85, 0.65, 0.1)][ci]
	var mt := tm(c, "rust", 0.55, 0.4, 3.0)
	vis(b, cyl(0.29, 0.29, 0.88, 16), mt, Vector3(0, 0.45, 0))
	for y in [0.02, 0.3, 0.6, 0.88]:
		vis(b, cyl(0.305, 0.305, 0.04, 16), tm(c.darkened(0.3), "rust", 0.5, 0.5, 3.0), Vector3(0, y, 0), Vector3.ZERO, false)
	vis(b, cyl(0.04, 0.04, 0.02, 8), _dark(), Vector3(0.15, 0.9, 0.05), Vector3.ZERO, false)
	if explosive:
		vis(b, cyl(0.295, 0.295, 0.2, 16), m(Color(0.95, 0.8, 0.1), 0.5), Vector3(0, 0.45, 0), Vector3.ZERO, false)
		vis(b, box(0.16, 0.16, 0.02), m(Color(0.05, 0.05, 0.05)), Vector3(0, 0.45, 0.3), Vector3(0, 0, PI / 4), false)
		b.add_to_group("explosive")
		b.contact_monitor = true
		b.max_contacts_reported = 2
		b.body_entered.connect(func(_o: Node):
			if b.linear_velocity.length() > 8.0 and b.is_inside_tree():
				var w := b.get_tree().get_first_node_in_group("world")
				if w and w.has_method("ignite"):
					w.ignite(b, 0.05))
	col_cyl(b, 0.3, 0.9, Vector3(0, 0.45, 0))
	bake(b, "barrel%s%d" % ["x" if explosive else "", ci])
	return b


static func barrier(rng: RandomNumberGenerator) -> Node3D:
	var b := _rigid(60.0)
	var striped := rng.randf() < 0.5
	vis(b, box(2.0, 0.25, 0.6), _concrete(), Vector3(0, 0.125, 0))
	vis(b, cyl(0.12, 0.3, 0.3, 4), _concrete(), Vector3(0, 0.4, 0), Vector3(0, PI / 4, 0), true, Vector3(4.7, 1, 1))
	vis(b, box(2.0, 0.35, 0.22), _concrete(), Vector3(0, 0.72, 0))
	if striped:
		for i in 4:
			vis(b, box(0.25, 0.3, 0.235), m(Color(0.9, 0.15, 0.1) if i % 2 == 0 else Color(0.95, 0.95, 0.95)), Vector3(-0.75 + i * 0.5, 0.72, 0), Vector3.ZERO, false)
	col_box(b, Vector3(2.0, 0.55, 0.6), Vector3(0, 0.275, 0))
	col_box(b, Vector3(2.0, 0.35, 0.24), Vector3(0, 0.72, 0))
	bake(b, "barrier%s" % ("s" if striped else ""))
	return b


static func pallets() -> Node3D:
	var b := _rigid(20.0)
	var wood := tm(Color(0.72, 0.6, 0.42), "wood", 0.85, 0.0, 2.0)
	for i in 3:
		var y := i * 0.15
		for k in 5:
			vis(b, box(1.2, 0.025, 0.14), wood, Vector3(0, y + 0.135, -0.4 + k * 0.2))
		for x in [-0.55, 0.0, 0.55]:
			vis(b, box(0.1, 0.09, 1.0), wood, Vector3(x, y + 0.075, 0))
		for k in 3:
			vis(b, box(1.2, 0.025, 0.12), wood, Vector3(0, y + 0.015, -0.42 + k * 0.42), Vector3.ZERO, false)
	col_box(b, Vector3(1.2, 0.45, 1.0), Vector3(0, 0.225, 0))
	bake(b, "pallets")
	return b


static func ball() -> Node3D:
	var b := _rigid(0.6)
	b.physics_material_override.bounce = 0.6
	vis(b, sph(0.22, 14), m(Color(0.95, 0.5, 0.1), 0.6), Vector3(0, 0.22, 0))
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.22
	cs.shape = s
	cs.position.y = 0.22
	b.add_child(cs)
	return b


static func dumpster(rng: RandomNumberGenerator) -> Node3D:
	var b := _breakable(350.0)
	var ci := rng.randi() % 3
	var c: Color = [Color(0.15, 0.35, 0.2), Color(0.2, 0.25, 0.45), Color(0.45, 0.2, 0.12)][ci]
	var body := tm(c, "rust", 0.6, 0.4, 2.0)
	vis(b, box(2.0, 1.15, 1.25), body, Vector3(0, 0.75, 0))
	for x in [-0.8, -0.4, 0.0, 0.4, 0.8]:
		vis(b, box(0.06, 1.0, 1.29), body, Vector3(x, 0.75, 0), Vector3.ZERO, false)   # ribs
	vis(b, box(2.08, 0.1, 1.33), tm(c.darkened(0.3), "rust", 0.6, 0.4, 2.0), Vector3(0, 1.35, 0))
	vis(b, box(1.0, 0.05, 1.3), m(Color(0.08, 0.08, 0.08), 0.7), Vector3(-0.5, 1.43, -0.05), Vector3(0.08, 0, 0))
	vis(b, box(1.0, 0.05, 1.3), m(Color(0.08, 0.08, 0.08), 0.7), Vector3(0.5, 1.47, -0.1), Vector3(0.22, 0, 0))
	for sx in [-1.0, 1.0]:
		rod(b, Vector3(1.05 * sx, 0.95, -0.4), Vector3(1.05 * sx, 0.95, 0.4), 0.03, _steel(), false)
		for sz in [-0.45, 0.45]:
			vis(b, cyl(0.08, 0.08, 0.06, 10), _dark(), Vector3(0.8 * sx, 0.09, sz), Vector3(0, 0, PI / 2), false)
	col_box(b, Vector3(2.1, 1.45, 1.3), Vector3(0, 0.72, 0))
	bake(b, "dumpster%d" % ci)
	return b


static func container(rng: RandomNumberGenerator) -> Node3D:
	var b := _static()
	var ci := rng.randi() % 5
	var c: Color = [Color(0.55, 0.16, 0.1), Color(0.12, 0.3, 0.55), Color(0.2, 0.42, 0.25), Color(0.55, 0.55, 0.55), Color(0.85, 0.55, 0.12)][ci]
	var body := tm(c, "rust", 0.65, 0.3, 1.0)
	var L := 6.0
	var W := 2.44
	var H := 2.6
	vis(b, box(W, H, L), body, Vector3(0, H * 0.5, 0))
	for i in 24:
		var z := -L * 0.5 + 0.2 + i * 0.245
		for sx in [-1.0, 1.0]:
			vis(b, box(0.05, H - 0.3, 0.1), body, Vector3((W * 0.5 + 0.02) * sx, H * 0.5, z), Vector3.ZERO, false)
	var frame := tm(c.darkened(0.35), "rust", 0.6, 0.4, 1.0)
	for sy in [0.08, H - 0.08]:
		for sx in [-1.0, 1.0]:
			vis(b, box(0.14, 0.16, L), frame, Vector3((W * 0.5) * sx, sy, 0))
	for sz in [-1.0, 1.0]:
		vis(b, box(W + 0.1, H, 0.12), frame, Vector3(0, H * 0.5, (L * 0.5) * sz))
	for i in 4:
		rod(b, Vector3(-0.9 + i * 0.6, 0.2, L * 0.5 + 0.08), Vector3(-0.9 + i * 0.6, H - 0.2, L * 0.5 + 0.08), 0.03, _steel(), false)
	col_box(b, Vector3(W, H, L), Vector3(0, H * 0.5, 0))
	bake(b, "container%d" % ci)
	return b


static func tires() -> Node3D:
	var b := _rigid(35.0)
	var rubber := tm(Color(0.08, 0.08, 0.08), "concrete", 0.9, 0.0, 4.0)
	for i in 4:
		vis(b, torus(0.2, 0.37, 18), rubber, Vector3(0.0 + (i % 2) * 0.03, 0.09 + i * 0.18, 0), Vector3(0, i * 0.4, 0))
	col_cyl(b, 0.37, 0.72, Vector3(0, 0.36, 0))
	bake(b, "tires")
	return b


static func spool() -> Node3D:
	var b := _rigid(70.0)
	var wood := _wood()
	for x in [-0.4, 0.4]:
		vis(b, cyl(0.6, 0.6, 0.06, 18), wood, Vector3(x, 0.6, 0), Vector3(0, 0, PI / 2))
	vis(b, cyl(0.3, 0.3, 0.74, 14), m(Color(0.1, 0.1, 0.1), 0.7), Vector3(0, 0.6, 0), Vector3(0, 0, PI / 2))
	vis(b, cyl(0.38, 0.38, 0.7, 16), m(Color(0.75, 0.3, 0.1), 0.6), Vector3(0, 0.6, 0), Vector3(0, 0, PI / 2), false)
	col_cyl(b, 0.6, 0.86, Vector3(0, 0.6, 0), Vector3(0, 0, PI / 2))
	bake(b, "spool")
	return b


static func sandbags() -> Node3D:
	var b := _static()
	var bag := tm(Color(0.62, 0.55, 0.38), "concrete", 0.95, 0.0, 4.0)
	for row in 3:
		for i in 4 - row:
			var x := -0.75 + i * 0.5 + row * 0.25
			vis(b, sph(1.0, 8), bag, Vector3(x, 0.12 + row * 0.2, 0), Vector3(0, 0.1 * i, 0), true, Vector3(0.27, 0.12, 0.2))
	col_box(b, Vector3(2.0, 0.6, 0.45), Vector3(0, 0.3, 0))
	bake(b, "sandbags")
	return b


static func fence() -> Node3D:
	var b := _breakable(90.0)
	var wood := tm(Color(0.5, 0.38, 0.25), "wood", 0.9, 0.0, 2.0)
	for x in [-1.45, 0.0, 1.45]:
		vis(b, box(0.1, 1.9, 0.1), wood, Vector3(x, 0.95, 0))
	for y in [0.4, 1.5]:
		vis(b, box(3.0, 0.08, 0.05), wood, Vector3(0, y, 0.07), Vector3.ZERO, false)
	for i in 14:
		vis(b, box(0.18, 1.7 + (i % 3) * 0.04, 0.025), wood, Vector3(-1.4 + i * 0.215, 0.92, 0.11))
	col_box(b, Vector3(3.0, 1.9, 0.2), Vector3(0, 0.95, 0.05))
	bake(b, "fence")
	return b


static func pipes() -> Node3D:
	var b := _rigid(450.0)
	var c := _concrete()
	vis(b, cyl(0.6, 0.6, 2.0, 18), c, Vector3(0, 0.6, 0), Vector3(PI / 2, 0, 0))
	for z in [-1.005, 1.005]:
		vis(b, cyl(0.46, 0.46, 0.02, 16), m(Color(0.05, 0.05, 0.05), 0.9), Vector3(0, 0.6, z), Vector3(PI / 2, 0, 0), false)
	col_cyl(b, 0.6, 2.0, Vector3(0, 0.6, 0), Vector3(PI / 2, 0, 0))
	bake(b, "pipes")
	return b


static func scaffold() -> Node3D:
	var b := _static()
	var steel := tm(Color(0.6, 0.6, 0.58), "metal", 0.4, 0.7, 3.0)
	var plank := tm(Color(0.65, 0.5, 0.3), "wood", 0.85, 0.0, 2.0)
	for x in [-1.2, 1.2]:
		for z in [-0.4, 0.4]:
			rod(b, Vector3(x, 0, z), Vector3(x, 4.2, z), 0.03, steel, true, 6)
	for y in [0.1, 2.0, 4.0]:
		for z in [-0.4, 0.4]:
			rod(b, Vector3(-1.2, y, z), Vector3(1.2, y, z), 0.025, steel, false)
		rod(b, Vector3(-1.2, y, -0.4), Vector3(-1.2, y, 0.4), 0.025, steel, false)
		rod(b, Vector3(1.2, y, -0.4), Vector3(1.2, y, 0.4), 0.025, steel, false)
	rod(b, Vector3(-1.2, 0.1, 0.4), Vector3(1.2, 2.0, 0.4), 0.02, steel, false)
	rod(b, Vector3(1.2, 2.0, 0.4), Vector3(-1.2, 4.0, 0.4), 0.02, steel, false)
	for y in [2.04, 4.04]:
		for i in 3:
			vis(b, box(2.5, 0.05, 0.24), plank, Vector3(0, y, -0.28 + i * 0.28))
	col_box(b, Vector3(2.5, 0.1, 0.85), Vector3(0, 2.04, 0))
	col_box(b, Vector3(2.5, 0.1, 0.85), Vector3(0, 4.04, 0))
	for x in [-1.2, 1.2]:
		col_box(b, Vector3(0.08, 4.2, 0.9), Vector3(x, 2.1, 0))
	bake(b, "scaffold")
	return b


static func trashbags() -> Node3D:
	var b := _rigid(12.0)
	var bag := m(Color(0.05, 0.05, 0.06), 0.25, 0.1)
	vis(b, sph(1.0, 10), bag, Vector3(-0.25, 0.25, 0), Vector3(0.2, 0, 0.1), true, Vector3(0.42, 0.36, 0.38))
	vis(b, sph(1.0, 10), bag, Vector3(0.22, 0.24, 0.1), Vector3(0, 0.5, -0.1), true, Vector3(0.4, 0.34, 0.42))
	vis(b, sph(1.0, 10), m(Color(0.25, 0.3, 0.45), 0.3, 0.1), Vector3(0.0, 0.5, -0.05), Vector3(0.3, 0.2, 0), true, Vector3(0.34, 0.28, 0.3))
	col_box(b, Vector3(1.0, 0.65, 0.6), Vector3(0, 0.32, 0))
	bake(b, "trashbags")
	return b


static func generator() -> Node3D:
	var b := _rigid(140.0)
	var body := tm(Color(0.85, 0.65, 0.1), "metal", 0.5, 0.3, 3.0)
	vis(b, box(1.3, 0.75, 0.75), body, Vector3(0, 0.58, 0))
	vis(b, box(1.0, 0.05, 0.6), _dark(), Vector3(0, 0.96, 0), Vector3.ZERO, false)
	vis(b, cyl(0.05, 0.05, 0.4, 8), _steel(), Vector3(0.5, 1.15, -0.2))
	for x in [-0.55, 0.55]:
		vis(b, cyl(0.17, 0.17, 0.1, 12), _dark(), Vector3(x, 0.17, 0.42), Vector3(PI / 2, 0, 0), false)
		vis(b, box(0.06, 0.2, 0.06), _steel(), Vector3(x, 0.1, -0.3))
	for i in 5:
		vis(b, box(0.03, 0.4, 0.02), _dark(), Vector3(-0.4 + i * 0.12, 0.6, 0.38), Vector3.ZERO, false)
	col_box(b, Vector3(1.3, 1.0, 0.85), Vector3(0, 0.5, 0))
	bake(b, "generator")
	return b


# ================================================================ wall details (no collision)
## Local +Z points away from the wall, origin on the wall surface.
static func wall_detail(kind: String, rng: RandomNumberGenerator, height := 6.0) -> Node3D:
	var n := Node3D.new()
	var key := kind
	match kind:
		"ac":
			var body := tm(Color(0.82, 0.82, 0.8), "metal", 0.5, 0.3, 4.0)
			vis(n, box(0.85, 0.58, 0.55), body, Vector3(0, 0, 0.33))
			vis(n, cyl(0.22, 0.22, 0.02, 16), _dark(), Vector3(0.12, 0, 0.61), Vector3(PI / 2, 0, 0), false)
			for i in 5:
				vis(n, box(0.5, 0.015, 0.02), body, Vector3(0.12, -0.2 + i * 0.1, 0.625), Vector3.ZERO, false)
			for sx in [-0.35, 0.35]:
				rod(n, Vector3(sx, -0.3, 0.0), Vector3(sx, -0.3, 0.58), 0.02, _steel(), false)
				rod(n, Vector3(sx, -0.3, 0.58), Vector3(sx, -0.7, 0.02), 0.015, _steel(), false)
			rod(n, Vector3(-0.42, -0.2, 0.15), Vector3(-0.42, -1.6, 0.08), 0.012, m(Color(0.9, 0.9, 0.9), 0.5), false)
		"drainpipe":
			var pipe := tm(Color(0.45, 0.47, 0.48), "metal", 0.4, 0.6, 3.0)
			var hq := snappedf(height, 1.0)
			key = "drain%d" % int(hq)
			vis(n, cyl(0.06, 0.06, hq, 8), pipe, Vector3(0, hq * 0.5, 0.12))
			vis(n, cyl(0.12, 0.07, 0.25, 8), pipe, Vector3(0, hq + 0.05, 0.12))
			vis(n, cyl(0.06, 0.06, 0.3, 8), pipe, Vector3(0, 0.05, 0.25), Vector3(PI / 3, 0, 0), false)
			var y := 0.8
			while y < hq:
				vis(n, box(0.16, 0.04, 0.14), pipe, Vector3(0, y, 0.06), Vector3.ZERO, false)
				y += 1.6
		"awning":
			var v := rng.randi() % 4
			key = "awning%d" % v
			var ca: Color = [Color(0.75, 0.12, 0.1), Color(0.1, 0.4, 0.2), Color(0.15, 0.25, 0.55), Color(0.85, 0.6, 0.1)][v]
			for i in 8:
				var c := ca if i % 2 == 0 else Color(0.95, 0.93, 0.88)
				vis(n, box(0.35, 0.04, 1.3), m(c, 0.9), Vector3(-1.225 + i * 0.35, -0.3, 0.6), Vector3(0.45, 0, 0))
			for i in 8:
				vis(n, box(0.35, 0.22, 0.02), m(ca if i % 2 == 0 else Color(0.95, 0.93, 0.88), 0.9), Vector3(-1.225 + i * 0.35, -0.68, 1.18), Vector3.ZERO, false)
			for sx in [-1.4, 1.4]:
				rod(n, Vector3(sx, 0, 0.02), Vector3(sx, -0.58, 1.18), 0.02, _iron(), false)
			# shop door + window beneath
			vis(n, box(1.0, 2.1, 0.06), m(Color(0.12, 0.1, 0.08), 0.6), Vector3(-0.6, -1.65, 0.03), Vector3.ZERO, false)
			vis(n, box(1.3, 1.2, 0.05), _glass(), Vector3(0.75, -1.3, 0.03), Vector3.ZERO, false)
		"shop_sign":
			var v := rng.randi() % 5
			key = "shopsign%d" % v
			var c: Color = [Color(1.0, 0.25, 0.3), Color(0.2, 0.8, 1.0), Color(1.0, 0.8, 0.2), Color(0.4, 1.0, 0.4), Color(0.9, 0.4, 1.0)][v]
			vis(n, box(2.4, 0.7, 0.14), m(Color(0.1, 0.1, 0.12), 0.5, 0.3), Vector3(0, 0, 0.08))
			vis(n, box(2.2, 0.5, 0.02), neon(c), Vector3(0, 0, 0.16), Vector3.ZERO, false)
			for i in 5:
				vis(n, box(0.22, 0.3, 0.02), m(Color(0.08, 0.08, 0.1), 0.5), Vector3(-0.8 + i * 0.4, 0, 0.175), Vector3.ZERO, false)
		"balcony":
			var conc := _concrete()
			var rail := _iron()
			vis(n, box(2.6, 0.14, 1.1), conc, Vector3(0, 0, 0.55))
			for i in 9:
				vis(n, box(0.035, 0.95, 0.035), rail, Vector3(-1.25 + i * 0.3125, 0.55, 1.07), Vector3.ZERO, false)
			rod(n, Vector3(-1.28, 1.02, 1.07), Vector3(1.28, 1.02, 1.07), 0.03, rail, false)
			for sx in [-1.28, 1.28]:
				rod(n, Vector3(sx, 1.02, 0.02), Vector3(sx, 1.02, 1.07), 0.03, rail, false)
				for i in 3:
					vis(n, box(0.035, 0.95, 0.035), rail, Vector3(sx, 0.55, 0.2 + i * 0.3), Vector3.ZERO, false)
			vis(n, box(0.95, 2.1, 0.05), m(Color(0.25, 0.18, 0.12), 0.6), Vector3(0, 1.1, 0.03), Vector3.ZERO, false)
			vis(n, box(0.6, 0.9, 0.04), _glass(), Vector3(0, 1.4, 0.06), Vector3.ZERO, false)
			if rng.randf() < 0.5:
				vis(n, box(0.5, 0.25, 0.3), tm(Color(0.6, 0.35, 0.25), "concrete", 0.9), Vector3(0.8, 0.2, 0.85), Vector3.ZERO, false)
				vis(n, sph(0.22, 8), tm(Color(0.2, 0.45, 0.2), "leaf", 0.9), Vector3(0.8, 0.45, 0.85), Vector3.ZERO, false)
				key = "balcony_p"
		"fire_escape":
			var iron := _iron()
			var levels := clampi(int(height / 3.0), 2, 4)
			key = "fire%d" % levels
			for l in levels:
				var y := 2.6 + l * 3.0
				vis(n, box(2.8, 0.06, 1.1), iron, Vector3(0, y, 0.6))
				rod(n, Vector3(-1.4, y + 0.95, 1.15), Vector3(1.4, y + 0.95, 1.15), 0.025, iron, false)
				for i in 8:
					rod(n, Vector3(-1.4 + i * 0.4, y, 1.15), Vector3(-1.4 + i * 0.4, y + 0.95, 1.15), 0.012, iron, false)
				for sx in [-1.4, 1.4]:
					rod(n, Vector3(sx, y, 0.02), Vector3(sx, y - 0.9, 0.02), 0.03, iron, false)
					rod(n, Vector3(sx, y - 0.9, 0.02), Vector3(sx, y, 1.1), 0.025, iron, false)
				if l < levels - 1:
					# stairs to the next platform
					rod(n, Vector3(-1.0, y, 0.35), Vector3(0.9, y + 3.0, 0.35), 0.03, iron, false)
					rod(n, Vector3(-1.0, y, 0.85), Vector3(0.9, y + 3.0, 0.85), 0.03, iron, false)
					for s in 7:
						var t := float(s + 1) / 8.0
						vis(n, box(0.15, 0.03, 0.5), iron, Vector3(lerpf(-1.0, 0.9, t), y + 3.0 * t, 0.6), Vector3.ZERO, false)
				vis(n, box(1.0, 2.0, 0.05), m(Color(0.2, 0.2, 0.22), 0.6), Vector3(0, y + 1.0, 0.03), Vector3.ZERO, false)
			# drop ladder
			rod(n, Vector3(1.0, 0.9, 1.1), Vector3(1.0, 2.6, 1.1), 0.02, iron, false)
			rod(n, Vector3(1.35, 0.9, 1.1), Vector3(1.35, 2.6, 1.1), 0.02, iron, false)
			for i in 6:
				rod(n, Vector3(1.0, 1.0 + i * 0.28, 1.1), Vector3(1.35, 1.0 + i * 0.28, 1.1), 0.012, iron, false)
		"wall_lamp":
			vis(n, box(0.16, 0.24, 0.06), _iron(), Vector3(0, 0, 0.03))
			rod(n, Vector3(0, 0.05, 0.05), Vector3(0, 0.15, 0.4), 0.018, _iron(), false)
			vis(n, cyl(0.06, 0.16, 0.14, 12), _iron(), Vector3(0, 0.12, 0.45), Vector3.ZERO, false)
			var bl := vis(n, sph(0.07, 8), bulb_mat(), Vector3(0, 0.04, 0.45), Vector3.ZERO, false)
			bl.add_to_group("lamp_bulb")
	bake(n, "w_" + key)
	return n


# ================================================================ roof details (no collision)
static func roof_detail(kind: String, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	match kind:
		"water_tower":
			var wood := tm(Color(0.45, 0.33, 0.22), "wood", 0.9, 0.0, 1.5)
			var iron := _iron()
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					rod(n, Vector3(1.1 * sx, 0, 1.1 * sz), Vector3(0.95 * sx, 3.0, 0.95 * sz), 0.08, iron)
			rod(n, Vector3(-1.05, 1.5, -1.05), Vector3(1.05, 1.5, 1.05), 0.04, iron, false)
			rod(n, Vector3(1.05, 1.5, -1.05), Vector3(-1.05, 1.5, 1.05), 0.04, iron, false)
			vis(n, cyl(1.5, 1.5, 0.15, 18), iron, Vector3(0, 3.05, 0))
			vis(n, cyl(1.4, 1.45, 2.8, 20), wood, Vector3(0, 4.5, 0))
			for y in [3.5, 4.4, 5.3]:
				vis(n, cyl(1.46, 1.46, 0.06, 20), iron, Vector3(0, y, 0), Vector3.ZERO, false)
			vis(n, cyl(0.05, 1.55, 0.9, 20), wood, Vector3(0, 6.35, 0))
			vis(n, sph(0.1, 8), iron, Vector3(0, 6.82, 0), Vector3.ZERO, false)
			rod(n, Vector3(1.45, 3.1, 0), Vector3(1.45, 6.0, 0), 0.03, iron, false)
		"roof_ac":
			var body := tm(Color(0.75, 0.76, 0.75), "metal", 0.5, 0.4, 2.0)
			vis(n, box(2.2, 1.1, 1.4), body, Vector3(0, 0.6, 0))
			vis(n, box(2.3, 0.1, 1.5), m(Color(0.3, 0.3, 0.3), 0.6), Vector3(0, 0.05, 0))
			for x in [-0.55, 0.55]:
				vis(n, cyl(0.42, 0.42, 0.06, 18), _dark(), Vector3(x, 1.16, 0), Vector3.ZERO, false)
				vis(n, box(0.85, 0.02, 0.06), body, Vector3(x, 1.2, 0), Vector3.ZERO, false)
			for i in 6:
				vis(n, box(0.02, 0.7, 1.42), body, Vector3(-1.0 + i * 0.4, 0.6, 0), Vector3.ZERO, false)
		"antenna":
			var steel := _steel()
			rod(n, Vector3(0, 0, 0), Vector3(0, 5.5, 0), 0.05, steel)
			for i in 4:
				var y := 3.0 + i * 0.6
				var w := 1.2 - i * 0.2
				rod(n, Vector3(-w, y, 0), Vector3(w, y, 0), 0.015, steel, false)
			for a in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
				rod(n, Vector3(0, 3.5, 0), Vector3(cos(a) * 2.0, 0, sin(a) * 2.0), 0.008, _dark(), false)
			vis(n, sph(0.06, 6), m(Color(1, 0.1, 0.1), 0.3, 0, 2.0), Vector3(0, 5.55, 0), Vector3.ZERO, false)
		"dish":
			var white := m(Color(0.88, 0.88, 0.86), 0.5, 0.2)
			rod(n, Vector3.ZERO, Vector3(0, 1.0, 0), 0.05, _steel())
			var d := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.6
			sm.height = 0.35
			sm.is_hemisphere = true
			sm.radial_segments = 16
			sm.rings = 4
			d.mesh = sm
			d.material_override = white
			d.transform = Transform3D(Basis(Vector3.RIGHT, -2.2), Vector3(0, 1.15, 0))
			n.add_child(d)
			rod(n, Vector3(0, 1.15, 0), Vector3(0, 1.55, 0.45), 0.015, _steel(), false)
		"vents":
			var metal := _steel()
			for i in 3:
				var x := -0.8 + i * 0.8
				vis(n, cyl(0.15, 0.15, 0.9 + i * 0.2, 10), metal, Vector3(x, 0.45 + i * 0.1, 0))
				vis(n, cyl(0.0, 0.28, 0.18, 10), metal, Vector3(x, 1.0 + i * 0.2, 0), Vector3.ZERO, false)
	bake(n, "r_" + kind)
	return n


# ================================================================ catalogue
## Footprint half extents (x, z) used by the spawner for clearance checks.
const KINDS := {
	"lamp": [0.3, 0.3], "tree": [0.8, 0.8], "bench": [1.0, 0.45], "hydrant": [0.25, 0.25],
	"booth": [0.6, 0.6], "dumpster": [1.1, 0.7], "busstop": [1.9, 0.85], "mailbox": [0.35, 0.35],
	"traffic": [0.3, 0.3], "cone": [0.25, 0.25], "crate": [0.55, 0.55], "barrel": [0.35, 0.35],
	"trash": [0.3, 0.3], "barrier": [1.1, 0.4], "pallets": [0.7, 0.6], "ball": [0.3, 0.3],
	"planter": [0.95, 0.5], "bike_rack": [1.0, 0.6], "meter": [0.15, 0.15], "sign": [0.2, 0.2],
	"bollards": [1.15, 0.15], "kiosk": [1.3, 1.1], "container": [1.3, 3.1], "tires": [0.4, 0.4],
	"spool": [0.45, 0.65], "sandbags": [1.0, 0.3], "fence": [1.5, 0.15], "pipes": [0.65, 1.05],
	"scaffold": [1.3, 0.5], "trashbags": [0.55, 0.35], "generator": [0.7, 0.5],
}


static func make(kind: String, rng: RandomNumberGenerator) -> Node3D:
	match kind:
		"lamp": return lamp()
		"tree": return tree(rng)
		"bench": return bench()
		"hydrant": return hydrant()
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
		"planter": return planter(rng)
		"bike_rack": return bike_rack(rng)
		"meter": return parking_meter()
		"sign": return street_sign(rng)
		"bollards": return bollards()
		"kiosk": return kiosk(rng)
		"container": return container(rng)
		"tires": return tires()
		"spool": return spool()
		"sandbags": return sandbags()
		"fence": return fence()
		"pipes": return pipes()
		"scaffold": return scaffold()
		"trashbags": return trashbags()
		"generator": return generator()
	return Node3D.new()
