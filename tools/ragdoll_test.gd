extends SceneTree
func _init():
	var out = OS.get_cmdline_user_args()[0]
	var w = Node3D.new(); root.add_child(w); current_scene = w
	var floor = StaticBody3D.new(); var cs = CollisionShape3D.new(); var bs = BoxShape3D.new(); bs.size = Vector3(40,1,40); cs.shape = bs; floor.add_child(cs); floor.position.y = -0.5; w.add_child(floor)
	var fm = MeshInstance3D.new(); var pm = PlaneMesh.new(); pm.size = Vector2(40,40); fm.mesh = pm; w.add_child(fm)
	var e = WorldEnvironment.new(); e.environment = Environment.new(); e.environment.background_mode = Environment.BG_COLOR; e.environment.background_color = Color(0.6,0.7,0.8)
	e.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.environment.ambient_light_color = Color(0.6,0.6,0.6); w.add_child(e)
	var l = DirectionalLight3D.new(); w.add_child(l); l.rotation_degrees = Vector3(-50, 30, 0)
	var hs = []
	for i in 3:
		var h = Humanoid.new(); h.model_path = "res://assets/character/character.glb"; w.add_child(h)
		h.position = Vector3((i - 1) * 2.0, 0, 0); hs.append(h)
	var c = Camera3D.new(); w.add_child(c); c.fov = 50
	await process_frame
	c.look_at_from_position(Vector3(5, 5, 9), Vector3(0, 0.4, 0)); c.current = true
	for i in 10: await physics_frame
	hs[0].speed = 7.0
	hs[0].start_ragdoll(Vector3(0,0,7), Vector3(0, 150, 450))
	hs[1].start_ragdoll(Vector3.ZERO, Vector3(0, 150, -450))
	hs[2].start_ragdoll(Vector3.ZERO, Vector3(450, 200, 0))
	for i in 25:
		await physics_frame
		for h in hs: h.global_position = h.ragdoll.hips_position() * Vector3(1,0,1)
	root.get_texture().get_image().save_png(out + "/rag_a.png")
	for i in 150:
		await physics_frame
		for h in hs: h.global_position = h.ragdoll.hips_position() * Vector3(1,0,1)
	print("settled ", hs.map(func(h): return h.ragdoll.settled()))
	root.get_texture().get_image().save_png(out + "/rag_b.png")
	for h in hs:
		var r = h.stop_ragdoll()
		h.global_position = Vector3(r[0].x, 0, r[0].z); h.rotation.y = r[1]
	for i in 10: await process_frame
	root.get_texture().get_image().save_png(out + "/rag_c.png")
	for i in 90: await process_frame
	root.get_texture().get_image().save_png(out + "/rag_d.png")
	quit()
