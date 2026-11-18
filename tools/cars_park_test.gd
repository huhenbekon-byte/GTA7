extends SceneTree
func _init():
	var out = OS.get_cmdline_user_args()[0]
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.time_of_day = 12.0
	for i in 80: await physics_frame
	var cars = main.get_tree().get_nodes_in_group("parked_car")
	print("cars ", cars.size())
	var cam = Camera3D.new(); main.add_child(cam); cam.far = 500
	main.ui.get_parent().visible = false
	for i in min(4, cars.size()):
		var c = cars[i * cars.size() / 4]
		cam.look_at_from_position(c.global_position + Vector3(9, 14, 9), c.global_position)
		cam.current = true
		for f in 3: await process_frame
		root.get_texture().get_image().save_png(out + "/park_%d.png" % i)
	quit()
