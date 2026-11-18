extends SceneTree
# usage: godot -s tools/shot.gd -- out.png ortho|persp px py pz tx ty tz [size]
func _init():
	var a = OS.get_cmdline_user_args()
	var s = load("res://assets/city/city.glb").instantiate()
	pass
	root.add_child(s)
	var env = WorldEnvironment.new(); var e = Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.5,0.7,0.9)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(0.6,0.6,0.6)
	env.environment = e; root.add_child(env)
	var l = DirectionalLight3D.new(); l.rotation_degrees = Vector3(-50, 30, 0); root.add_child(l)
	var c = Camera3D.new(); root.add_child(c)
	c.far = 5000
	if a[1] == "ortho":
		c.projection = Camera3D.PROJECTION_ORTHOGONAL; c.size = float(a[8])
	await process_frame
	c.look_at_from_position(Vector3(float(a[2]), float(a[3]), float(a[4])), Vector3(float(a[5]), float(a[6]), float(a[7])), Vector3(0,0,-1) if a[1]=="ortho" else Vector3.UP)
	c.current = true
	for i in 8: await process_frame
	root.get_texture().get_image().save_png(a[0])
	quit()
