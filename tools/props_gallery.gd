extends SceneTree
func _init():
	var out = OS.get_cmdline_user_args()[0]
	var w = Node3D.new(); root.add_child(w)
	var e = WorldEnvironment.new(); var env = Environment.new(); env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.62,0.72,0.82)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color(0.55,0.55,0.6); env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.environment = env; w.add_child(e)
	var l = DirectionalLight3D.new(); w.add_child(l); l.rotation_degrees = Vector3(-45, 35, 0); l.shadow_enabled = true; l.light_energy = 1.2
	var fl = MeshInstance3D.new(); var pm = PlaneMesh.new(); pm.size = Vector2(80, 80); fl.mesh = pm; fl.material_override = Props.tm(Color(0.5,0.5,0.48), "concrete", 0.95, 0.0, 0.5); w.add_child(fl)
	var rng = RandomNumberGenerator.new(); rng.seed = 3
	var sets = [
		["lamp","traffic","tree","bench","hydrant","booth","mailbox","trash","planter","bike_rack","meter","sign"],
		["bollards","kiosk","busstop","cone","crate","barrel","barrier","pallets","dumpster","tires","spool","sandbags"],
		["fence","pipes","scaffold","trashbags","generator","container"],
	]
	var cam = Camera3D.new(); w.add_child(cam); cam.fov = 45
	for si in sets.size():
		for c in w.get_children():
			if c.has_meta("g"): c.queue_free()
		await process_frame
		var list = sets[si]
		for i in list.size():
			var n = Props.make(list[i], rng)
			n.set_meta("g", true)
			w.add_child(n)
			n.position = Vector3((i % 6) * 3.4 - 8.5, 0, -(i / 6) * 5.0)
			n.rotation.y = 0.5
		await process_frame
		cam.look_at_from_position(Vector3(0, 7, 12), Vector3(0, 1.2, -3)); cam.current = true
		for f in 4: await process_frame
		root.get_texture().get_image().save_png(out + "/props_%d.png" % si)
	# wall + roof details on a wall
	for c in w.get_children():
		if c.has_meta("g"): c.queue_free()
	var wall = MeshInstance3D.new(); var bm = BoxMesh.new(); bm.size = Vector3(26, 11, 0.4); wall.mesh = bm; wall.material_override = Props.tm(Color(0.62,0.5,0.42), "concrete", 0.9, 0.0, 0.4); wall.position = Vector3(0, 5.5, -6.2); w.add_child(wall)
	var dets = [["awning", 2.85, -10], ["shop_sign", 3.6, -10], ["ac", 5.0, -6], ["drainpipe", 0.0, -4.5], ["balcony", 5.2, -1.5], ["fire_escape", 0.0, 3.5], ["wall_lamp", 2.6, 8], ["ac", 7.5, 9.5], ["shop_sign", 3.6, 8.5]]
	for d in dets:
		var n = Props.wall_detail(d[0], rng, 10.0)
		w.add_child(n); n.position = Vector3(d[2], d[1], -6.0)
	var roofs = ["water_tower", "roof_ac", "antenna", "dish", "vents"]
	for i in roofs.size():
		var n = Props.roof_detail(roofs[i], rng)
		w.add_child(n); n.position = Vector3(-9 + i * 4.5, 0, 3)
	cam.look_at_from_position(Vector3(0, 6, 16), Vector3(0, 3.5, -3)); cam.fov = 60
	for f in 4: await process_frame
	root.get_texture().get_image().save_png(out + "/props_3.png")
	quit()
