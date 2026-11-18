extends SceneTree
func _init():
	var e = WorldEnvironment.new(); e.environment = Environment.new(); e.environment.background_mode = Environment.BG_COLOR; e.environment.background_color = Color(0.6,0.7,0.8)
	e.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.environment.ambient_light_color = Color(0.5,0.5,0.5); root.add_child(e)
	var l = DirectionalLight3D.new(); root.add_child(l); l.rotation_degrees = Vector3(-40, 30, 0)
	var hs = []
	for i in 3:
		var h = Humanoid.new(); h.model_path = "res://assets/character/character.glb"; root.add_child(h)
		h.position = Vector3((i - 1) * 1.3, 0, 0); h.rotation.y = 1.2; hs.append(h); h.set_process(false)
	var c = Camera3D.new(); root.add_child(c); c.fov = 45
	await process_frame
	c.look_at_from_position(Vector3(0, 1.3, 5.5), Vector3(0, 0.9, 0)); c.current = true
	for i in 3:
		var h = hs[i]
		h._attack_kind = i - 1  # next play_attack -> kind i
		h.play_attack()
		var t = 0.0
		while not h.attack_hit_moment() or t < 0.17:
			h._process(1.0/60.0); t += 1.0/60.0
	for i in 3: await process_frame
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	quit()
