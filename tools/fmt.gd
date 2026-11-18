extends SceneTree
func _init():
	for p in ["res://assets/character/character.glb", "res://assets/cars/cars.glb", "res://assets/city/city.glb"]:
		var s = load(p).instantiate()
		var mi = s.find_children("*", "MeshInstance3D", true, false)[0]
		var f = mi.mesh.surface_get_format(0)
		print(p, " compressed=", (f & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) != 0, " fmt=", f)
	quit()
