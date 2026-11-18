extends SceneTree
func _init():
	var out = OS.get_cmdline_user_args()[0]
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.time_of_day = 12.0
	for i in 80: await physics_frame
	main.ui.get_parent().visible = false
	var cam = Camera3D.new(); main.add_child(cam); cam.far = 600
	var p = main.player.global_position
	var views = [[Vector3(18, 30, 18), Vector3.ZERO], [Vector3(-25, 22, 30), Vector3(-10, 0, 25)], [Vector3(30, 25, -30), Vector3(10, 0, -30)]]
	for i in views.size():
		cam.look_at_from_position(p + views[i][0], p + views[i][1]); cam.current = true
		for f in 3: await process_frame
		root.get_texture().get_image().save_png(out + "/aerial_%d.png" % i)
	quit()
