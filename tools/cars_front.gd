extends SceneTree
func _init():
	var s = load("res://assets/cars/cars.glb").instantiate()
	var cars = s.get_children()
	for i in cars.size():
		var c = cars[i]; s.remove_child(c); root.add_child(c)
		c.position = Vector3((i % 11) * 3.0 - 15, 0, -(i / 11) * 9.0)
		var lb = Label3D.new(); lb.text = str(i); lb.font_size = 160; lb.position = Vector3(0, 2.6, 2.5); lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED; c.add_child(lb)
	var e = WorldEnvironment.new(); e.environment = Environment.new(); e.environment.background_mode = Environment.BG_COLOR; e.environment.background_color = Color(0.6,0.7,0.8)
	e.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.environment.ambient_light_color = Color(0.7,0.7,0.7); root.add_child(e)
	var l = DirectionalLight3D.new(); root.add_child(l); l.rotation_degrees = Vector3(-30, 10, 0)
	var cam = Camera3D.new(); root.add_child(cam); cam.fov = 55
	await process_frame
	cam.look_at_from_position(Vector3(0, 9, 16), Vector3(0, 0, -8)); cam.current = true
	for i in 5: await process_frame
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	quit()
