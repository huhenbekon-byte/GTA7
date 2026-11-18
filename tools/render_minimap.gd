extends SceneTree
# Renders a top-down map of the city into assets/ui/minimap.png (square, matches main.gd MAP_* consts)
func _init():
	var vp := SubViewport.new()
	vp.size = Vector2i(1024, 1024)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var city = load("res://assets/city/city.glb").instantiate()
	vp.add_child(city)
	var we = WorldEnvironment.new(); var e = Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.13, 0.22, 0.32)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(1,1,1); e.ambient_light_energy = 0.9
	we.environment = e; vp.add_child(we)
	var l = DirectionalLight3D.new(); vp.add_child(l); l.rotation_degrees = Vector3(-70, 20, 0); l.light_energy = 0.5
	var c = Camera3D.new(); vp.add_child(c)
	c.projection = Camera3D.PROJECTION_ORTHOGONAL; c.size = 2450.0; c.far = 3000
	await process_frame
	c.look_at_from_position(Vector3(730, 1000, -636), Vector3(730, 0, -636), Vector3(0, 0, -1))
	c.current = true
	for i in 10: await process_frame
	var img: Image = vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.adjust_bcs(1.05, 1.25, 1.1)
	img.save_png("res://assets/ui/minimap.png")
	quit()
