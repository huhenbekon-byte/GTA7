extends SceneTree
func _init():
	var out = OS.get_cmdline_user_args()[0]
	var e = WorldEnvironment.new(); e.environment = Environment.new(); e.environment.background_mode = Environment.BG_COLOR; e.environment.background_color = Color(0.6,0.7,0.8)
	e.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.environment.ambient_light_color = Color(0.6,0.6,0.6); root.add_child(e)
	var l = DirectionalLight3D.new(); root.add_child(l); l.rotation_degrees = Vector3(-30, 20, 0)
	var x = -1.2
	for p in ["res://assets/characters/thug.glb", "res://assets/characters/police_src.glb"]:
		var s = load(p).instantiate(); root.add_child(s)
		await process_frame
		var tot = AABB(); var first = true
		for m in s.find_children("*", "MeshInstance3D", true, false):
			var a = m.global_transform * m.get_aabb()
			if first: tot = a; first = false
			else: tot = tot.merge(a)
		print(p, " aabb ", tot)
		var sc = 1.8 / tot.size.y
		s.scale = Vector3.ONE * sc
		s.position = Vector3(x, -tot.position.y * sc, 0)
		x += 2.4
		for sk in s.find_children("*", "Skeleton3D", true, false):
			print(" skel global ", sk.global_transform.basis.get_scale(), " bone hip ", sk.get_bone_global_rest(sk.find_bone("hip_01")).origin if sk.find_bone("hip_01") >= 0 else "")
			for b in ["L_arm_015", "L_wrist_017", "L_leg_02", "head_062", "top_065"]:
				var i = sk.find_bone(b)
				if i >= 0: print("  ", b, " ", (sk.global_transform * sk.get_bone_global_rest(i)).origin)
	var c = Camera3D.new(); root.add_child(c); c.fov = 40
	await process_frame
	c.look_at_from_position(Vector3(0, 1.3, 6.5), Vector3(0, 0.95, 0)); c.current = true
	for i in 5: await process_frame
	root.get_texture().get_image().save_png(out)
	quit()
