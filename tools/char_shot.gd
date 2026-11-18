extends SceneTree
func _init():
	var s = load("res://assets/character/character.glb").instantiate(); root.add_child(s)
	var e = WorldEnvironment.new(); e.environment = Environment.new(); e.environment.background_mode = Environment.BG_COLOR; e.environment.background_color = Color(0.6,0.7,0.8)
	e.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.environment.ambient_light_color = Color(0.5,0.5,0.5); root.add_child(e)
	var l = DirectionalLight3D.new(); root.add_child(l); l.rotation_degrees = Vector3(-30, 20, 0)
	var c = Camera3D.new(); root.add_child(c); c.fov = 40
	await process_frame
	c.look_at_from_position(Vector3(6, 12, 30), Vector3(0, 9, 0)); c.current = true; c.far = 2000
	for i in 5: await process_frame
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	quit()
