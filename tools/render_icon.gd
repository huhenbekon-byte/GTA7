extends SceneTree
func _init():
	var vp := SubViewport.new(); vp.size = Vector2i(512, 512); vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)
	var e = WorldEnvironment.new(); var env = Environment.new()
	env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.95, 0.55, 0.15)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color(0.6, 0.55, 0.6)
	e.environment = env; vp.add_child(e)
	var l = DirectionalLight3D.new(); vp.add_child(l); l.rotation_degrees = Vector3(-30, 40, 0); l.light_energy = 1.3
	var h = Humanoid.new(); h.has_cap = true; h.cap_color = Color(0.85, 0.15, 0.12); h.shirt_color = Color(0.93, 0.93, 0.9); h.pants_color = Color(0.18, 0.24, 0.42); h.shoe_color = Color(0.1,0.1,0.1)
	vp.add_child(h); h.rotation.y = 0.45
	var c = Camera3D.new(); vp.add_child(c); c.fov = 30
	await process_frame
	c.look_at_from_position(Vector3(0, 1.6, 2.6), Vector3(0, 1.45, 0)); c.current = true
	for i in 6: await process_frame
	var img = vp.get_texture().get_image(); img.convert(Image.FORMAT_RGBA8)
	img.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	img.save_png("res://icon.png")
	quit()
