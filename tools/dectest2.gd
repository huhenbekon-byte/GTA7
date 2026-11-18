extends SceneTree
func _init():
	var tex = load("res://assets/city/city_34.png")
	var img = tex.get_image()
	print("img fmt ", img.get_format(), " compressed ", img.is_compressed(), " px ", img.get_pixel(5, 250), " tex class ", tex.get_class())
	var mats = []
	for t in [1, 2]:
		var m = StandardMaterial3D.new(); m.albedo_texture = tex; m.transparency = t; mats.append(m)
	var m3 = StandardMaterial3D.new(); var it = ImageTexture.create_from_image(img); m3.albedo_texture = it; m3.transparency = 2; mats.append(m3)
	var qm = QuadMesh.new(); qm.size = Vector2(3,3)
	for i in mats.size():
		var q = MeshInstance3D.new(); q.mesh = qm; q.material_override = mats[i]; q.position.x = i * 3.3; root.add_child(q)
	var c = Camera3D.new(); root.add_child(c); c.position = Vector3(3.3,0,6); c.current = true
	var e = WorldEnvironment.new(); e.environment = Environment.new(); e.environment.background_mode = Environment.BG_COLOR; e.environment.background_color = Color(1,0,1); root.add_child(e)
	var l = DirectionalLight3D.new(); root.add_child(l)
	for i in 5: await process_frame
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	quit()
