extends SceneTree
func _init():
	var w = Node3D.new(); root.add_child(w)
	var city = load("res://assets/city/city.glb").instantiate(); w.add_child(city)
	for i in 3: await physics_frame
	var space = w.get_world_3d().direct_space_state
	var N = 700
	var img = Image.create(N, N, false, Image.FORMAT_RGB8); img.fill(Color(0.1, 0.15, 0.3))
	var cols = {"material_104_93_1": Color(1, 0, 0), "material_104_93_19": Color(0, 1, 0), "material_104_93_18": Color(0, 0, 1), "material_104_93_68": Color(1, 1, 0), "material_104_93_58": Color(1, 0, 1), "material_104_93_42": Color(0, 1, 1)}
	var road = ["material_104_93_39","material_104_93_38","material_104_93_37","material_104_93_45","material_104_93_40","material_104_93_70","material_104_93_36","material_104_93_43"]
	# zoom on central district
	var x0 = 300.0; var z0 = -1150.0; var size = 600.0
	for py in N:
		for px in N:
			var x = x0 + px * size / N; var z = z0 + py * size / N
			var h = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 6, z), Vector3(x, -4, z), 1))
			if h.is_empty(): continue
			var m = h.collider.get_meta("shape_mats")[h.shape]
			var c = cols.get(m, Color(0.5, 0.5, 0.5))
			if m in road: c = Color(1, 1, 1)
			if h.normal.y < 0.95: c = c.darkened(0.6)
			img.set_pixel(px, py, c)
	img.save_png(OS.get_cmdline_user_args()[0])
	quit()
