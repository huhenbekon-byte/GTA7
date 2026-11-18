extends SceneTree
func _init():
	var e = WorldEnvironment.new(); e.environment = Environment.new(); e.environment.background_mode = Environment.BG_COLOR; e.environment.background_color = Color(0.6,0.7,0.8)
	e.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.environment.ambient_light_color = Color(0.7,0.7,0.7); root.add_child(e)
	var l = DirectionalLight3D.new(); root.add_child(l); l.rotation_degrees = Vector3(-30, 60, 0)
	var x = -1.5
	for n in ["rifle", "pistol"]:
		var mi = MeshInstance3D.new(); mi.mesh = load("res://assets/weapons/%s.res" % n); root.add_child(mi); mi.position = Vector3(0, 0, 0) if n == "rifle" else Vector3(0, -1.2, 0)
		var mk = MeshInstance3D.new(); var s = SphereMesh.new(); s.radius = 0.06; s.height = 0.12; mk.mesh = s; root.add_child(mk); mk.position = mi.position + Vector3(0, 0, 1.0)  # marker at +Z
	var c = Camera3D.new(); root.add_child(c)
	await process_frame
	c.look_at_from_position(Vector3(4, -0.3, 0), Vector3(0, -0.4, 0)); c.current = true
	for i in 4: await process_frame
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	quit()
