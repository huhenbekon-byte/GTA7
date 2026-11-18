extends SceneTree
func _init():
	for f in DirAccess.get_files_at("res://scripts"):
		if f.ends_with(".gd"):
			var s = load("res://scripts/" + f)
			print(f, " ok=", s != null and s.can_instantiate())
	quit()
