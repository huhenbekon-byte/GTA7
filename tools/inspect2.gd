extends SceneTree
func _init():
	var s = load("res://assets/city/city.glb").instantiate()
	print("meshes ", s.get_node("Meshes").get_child_count(), " shapes ", s.get_node("Collision").get_child_count())
	var f=0
	for c in s.get_node("Collision").get_children(): f += c.shape.get_faces().size()/3
	print("tris ", f)
	quit()
