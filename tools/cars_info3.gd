extends SceneTree
func _init():
	var s = load("res://assets/cars/cars.glb").instantiate()
	var n = 0
	for c in s.get_children():
		var wheels = c.get_children().filter(func(x): return x.name.begins_with("Wheel_"))
		if wheels.size() == 4: n += 1
		print(c.name, " wheels ", wheels.map(func(w): return [w.name, w.position.snapped(Vector3.ONE*0.01), snappedf(w.get_meta("radius"), 0.01)]))
	print("with wheels: ", n, "/", s.get_child_count())
	quit()
