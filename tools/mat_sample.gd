extends SceneTree
# Samples ground hits across the city and counts materials of flat street-level surfaces.
func _init():
	var w = Node3D.new(); root.add_child(w)
	var city = load("res://assets/city/city.glb").instantiate(); w.add_child(city)
	for i in 3: await physics_frame
	var space = w.get_world_3d().direct_space_state
	var counts := {}
	var rng = RandomNumberGenerator.new(); rng.seed = 7
	for i in 30000:
		var x = rng.randf_range(0, 1460); var z = rng.randf_range(-1830, 560)
		var h = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 6, z), Vector3(x, -4, z), 1))
		if h.is_empty() or h.normal.y < 0.95: continue
		var mats = h.collider.get_meta("shape_mats")
		var m = mats[h.shape]
		counts[m] = counts.get(m, 0) + 1
	var arr = counts.keys(); arr.sort_custom(func(a, b): return counts[a] > counts[b])
	var line = ""
	for k in arr.slice(0, 30): line += "%s:%d " % [k, counts[k]]
	print(line)
	# dump textures of top materials
	var by_name := {}
	for mi in city.find_children("*", "MeshInstance3D", true, false):
		var m = mi.mesh.surface_get_material(0)
		if m: by_name[m.resource_name] = m
	var top = arr.slice(0, 24)
	var atlas = Image.create(128 * 8, 150 * 3, false, Image.FORMAT_RGBA8); atlas.fill(Color(0.2, 0.2, 0.2))
	for i in top.size():
		var m = by_name.get(top[i])
		if m == null or m.albedo_texture == null: continue
		var im: Image = m.albedo_texture.get_image(); im.decompress(); im.convert(Image.FORMAT_RGBA8); im.resize(128, 128)
		atlas.blit_rect(im, Rect2i(0, 0, 128, 128), Vector2i((i % 8) * 128, (i / 8) * 150))
	atlas.save_png(OS.get_cmdline_user_args()[0])
	print("order: ", top)
	quit()
