extends SceneTree
func _init():
	var out = OS.get_cmdline_user_args()[0]
	var e = WorldEnvironment.new(); e.environment = Environment.new(); e.environment.background_mode = Environment.BG_COLOR; e.environment.background_color = Color(0.6,0.7,0.8)
	e.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.environment.ambient_light_color = Color(0.5,0.5,0.5)
	root.add_child(e)
	var l = DirectionalLight3D.new(); root.add_child(l); l.rotation_degrees = Vector3(-40, 30, 0)
	var states = [["idle",0.0,true,0.0,""],["walk",1.8,true,0.0,""],["jog",4.6,true,0.0,""],["sprint",7.6,true,0.0,""],["jump",3.0,false,4.0,""],["fall",3.0,false,-8.0,"fall"],["jab",0.0,true,0.0,"a1"],["kick",0.0,true,0.0,"a3"],["knock",0.0,true,0.0,"down"]]
	var hs = []
	for i in states.size():
		var h = Humanoid.new(); h.model_path = OS.get_cmdline_user_args()[1] if OS.get_cmdline_user_args().size() > 1 else "res://assets/character/character.glb"; root.add_child(h)
		h.position = Vector3((i - 4) * 1.15, 0, 0)
		h.rotation.y = 0.9
		hs.append(h)
	var c = Camera3D.new(); root.add_child(c); c.fov = 50
	await process_frame
	c.look_at_from_position(Vector3(0, 1.4, 8.5), Vector3(0, 0.9, 0))
	c.current = true
	for i in states.size():
		var s = states[i]; var h = hs[i]
		h.speed = s[1]; h.grounded = s[2]; h.vertical_speed = s[3]
		if s[4] == "a1": h.play_attack(); h.play_attack()  # kind 1->? ensure jab variant
		if s[4] == "a3": h.play_attack(); h._attack = 0; h.play_attack(); h._attack = 0; h.play_attack()
		if s[4] == "down": h.knocked = 5.0
	for f in 40:
		for i in states.size():
			var s = states[i]; var h = hs[i]
			if s[4] == "fall": h._air_time = 2.0
			if s[4].begins_with("a") and f == 25:
				pass
		await process_frame
		if f == 14:
			# freeze attacks near strike moment
			for i in states.size():
				if states[i][4].begins_with("a"): hs[i].set_process(false)
	root.get_texture().get_image().save_png(out)
	quit()
