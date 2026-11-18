extends SceneTree
func _init():
	var s = load("res://assets/cars/cars.glb").instantiate()
	print("cars ", s.get_child_count())
	for c in s.get_children(): print(c.name, " ", c.get_meta("size"), " surfaces ", c.get_child_count())
	quit()
