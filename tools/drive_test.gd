extends SceneTree
var out := ""
func _init():
	out = OS.get_cmdline_user_args()[0]
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.time_of_day = 12.5
	for i in 100: await physics_frame
	var p = main.player
	await _shot("d00_street")
	var cars = main.get_tree().get_nodes_in_group("parked_car")
	print("parked ", cars.size(), " breakables ", main.get_tree().get_nodes_in_group("breakable").size())
	cars.sort_custom(func(a, b): return a.global_position.distance_to(p.global_position) < b.global_position.distance_to(p.global_position))
	var car = cars[0]
	p.global_position = car.global_transform * Vector3(car.get_meta("size").x * 0.5 + 0.8, 0.2, 0)
	for i in 5: await physics_frame
	print("near car: ", main.nearest_car(p.global_position) != null)
	p.grab_pressed = true
	for i in 5: await physics_frame
	print("in vehicle: ", p.vehicle != null)
	var v = p.vehicle
	for i in 40: await physics_frame
	print("settled y ", v.global_position.y, " up ", v.global_transform.basis.y.y)
	await _shot("d01_in_car")
	p.move_input = Vector2(0, 1)
	for i in 180:
		await physics_frame
	print("speed after 3s: ", v.speed_kmh(), " km/h")
	await _shot("d02_driving")
	p.move_input = Vector2(1, 0.8)
	for i in 70: await physics_frame
	print("turning speed ", v.speed_kmh(), " up ", v.global_transform.basis.y.y)
	await _shot("d03_turn")
	p.move_input = Vector2(0, -1)
	p.jump_held = true
	for i in 90: await physics_frame
	p.jump_held = false
	p.move_input = Vector2.ZERO
	print("after brake ", v.speed_kmh())
	p.grab_pressed = true
	for i in 10: await physics_frame
	print("exited: ", p.vehicle == null)
	await _shot("d04_exit")
	quit()

func _shot(nm):
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out + "/" + nm + ".png")
