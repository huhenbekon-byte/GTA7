extends RefCounted
class_name Weapons
## Weapon models (built from primitives, baked) and shot effects: muzzle flash,
## tracer, impact sparks / dust. Generic designs, no real-world brand.

static func rifle() -> Node3D:
	var n := Node3D.new()
	var metal := Props.tm(Color(0.12, 0.12, 0.13), "metal", 0.4, 0.7, 6.0)
	var poly := Props.m(Color(0.16, 0.15, 0.13), 0.7)
	var wood := Props.tm(Color(0.42, 0.26, 0.14), "wood", 0.7, 0.0, 6.0)
	Props.vis(n, Props.box(0.06, 0.09, 0.42), metal, Vector3(0, 0, 0.0), Vector3.ZERO, false)          # receiver
	Props.vis(n, Props.box(0.05, 0.03, 0.3), metal, Vector3(0, 0.055, 0.02), Vector3.ZERO, false)      # top cover
	Props.vis(n, Props.cyl(0.012, 0.012, 0.42, 6), metal, Vector3(0, 0.02, 0.42), Vector3(PI / 2, 0, 0), false)   # barrel
	Props.vis(n, Props.cyl(0.018, 0.018, 0.06, 6), metal, Vector3(0, 0.02, 0.64), Vector3(PI / 2, 0, 0), false)   # muzzle
	Props.vis(n, Props.box(0.065, 0.07, 0.24), wood, Vector3(0, 0.0, 0.33), Vector3.ZERO, false)       # handguard
	Props.vis(n, Props.box(0.01, 0.05, 0.01), metal, Vector3(0, 0.05, 0.6), Vector3.ZERO, false)       # front sight
	Props.vis(n, Props.box(0.045, 0.16, 0.07), poly, Vector3(0, -0.13, 0.08), Vector3(0.25, 0, 0), false)  # magazine
	Props.vis(n, Props.box(0.04, 0.11, 0.05), poly, Vector3(0, -0.09, -0.1), Vector3(-0.3, 0, 0), false)  # grip
	Props.vis(n, Props.box(0.05, 0.08, 0.3), wood, Vector3(0, -0.03, -0.34), Vector3(0.12, 0, 0), false)  # stock
	Props.bake(n, "rifle")
	var muzzle := Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0.02, 0.68)
	n.add_child(muzzle)
	return n


static func pistol() -> Node3D:
	var n := Node3D.new()
	var metal := Props.m(Color(0.1, 0.1, 0.11), 0.4, 0.7)
	Props.vis(n, Props.box(0.03, 0.035, 0.17), metal, Vector3(0, 0.02, 0.04), Vector3.ZERO, false)
	Props.vis(n, Props.box(0.028, 0.1, 0.04), metal, Vector3(0, -0.04, -0.02), Vector3(-0.25, 0, 0), false)
	Props.bake(n, "pistol")
	var muzzle := Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0.02, 0.13)
	n.add_child(muzzle)
	return n


static var _flash_mat: StandardMaterial3D
static var _tracer_mat: StandardMaterial3D


static func _fx_mats() -> void:
	if _flash_mat:
		return
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.albedo_color = Color(1.0, 0.8, 0.35)
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.35, Color(1, 0.9, 0.6, 0.85))
	g.set_color(g.get_point_count() - 1, Color(1, 0.6, 0.2, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	gt.width = 32
	gt.height = 32
	_flash_mat.albedo_texture = gt
	_tracer_mat = StandardMaterial3D.new()
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat.albedo_color = Color(1.0, 0.85, 0.5, 0.8)
	_tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


## Muzzle flash + tracer from `from` to `to` + impact puff. Everything frees itself.
static func shot_fx(world: Node3D, from: Vector3, to: Vector3, hit_something: bool, flesh := false) -> void:
	_fx_mats()
	var flash := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.35, 0.35)
	flash.mesh = q
	flash.material_override = _flash_mat
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(flash)
	flash.global_position = from
	flash.rotation.z = randf() * TAU
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.7, 0.3)
	l.omni_range = 5.0
	l.light_energy = 2.5
	world.add_child(l)
	l.global_position = from
	# tracer
	var d := to - from
	var len := d.length()
	if len > 0.5:
		var t := MeshInstance3D.new()
		t.mesh = Props.box(0.015, 0.015, 1.0)
		t.material_override = _tracer_mat
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(t)
		var z := d / len
		var x := z.cross(Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT).normalized()
		var y := x.cross(z)
		t.global_transform = Transform3D(Basis(x, y, z).scaled(Vector3(1, 1, minf(len, 25.0))), from + z * minf(len, 25.0) * 0.5 + z * randf_range(0.0, maxf(0.0, len - 25.0)))
		world.get_tree().create_timer(0.05).timeout.connect(t.queue_free)
	world.get_tree().create_timer(0.04).timeout.connect(flash.queue_free)
	world.get_tree().create_timer(0.05).timeout.connect(l.queue_free)
	if hit_something:
		var p := CPUParticles3D.new()
		p.one_shot = true
		p.explosiveness = 1.0
		p.amount = 10
		p.lifetime = 0.45
		p.direction = -d.normalized()
		p.spread = 35.0
		p.initial_velocity_min = 1.5
		p.initial_velocity_max = 4.0
		p.gravity = Vector3(0, -9.8, 0)
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.2
		var pm := BoxMesh.new()
		pm.size = Vector3(0.03, 0.03, 0.03)
		var mm := StandardMaterial3D.new()
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mm.albedo_color = Color(0.55, 0.05, 0.05) if flesh else Color(1.0, 0.8, 0.4)
		pm.material = mm
		p.mesh = pm
		world.add_child(p)
		p.global_position = to
		p.emitting = true
		world.get_tree().create_timer(1.0).timeout.connect(p.queue_free)
