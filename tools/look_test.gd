extends SceneTree
func _init():
	var out = OS.get_cmdline_user_args()[0]
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.time_of_day = float(OS.get_cmdline_user_args()[1])
	for i in 90: await physics_frame
	var p = main.player
	var t0 = Time.get_ticks_msec()
	print("nodes ", main.get_tree().get_node_count(), " wall slots ", main._wall_slots.size(), " furniture ", main._furniture_slots.size())
	print("draw objects approx: ", main.get_tree().root.find_children("*", "MeshInstance3D", true, false).size())
	var views = [[0.0, -0.25], [PI * 0.5, -0.2], [PI, -0.2], [PI * 1.5, -0.35]]
	for i in views.size():
		p.cam_yaw = views[i][0]; p.cam_pitch = views[i][1]; p.cam_input_timer = 5.0
		for f in 4: await process_frame
		root.get_texture().get_image().save_png(out + "/v%d.png" % i)
	quit()
