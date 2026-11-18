extends SceneTree
func _init():
	var s = load("res://assets/cars/cars.glb").instantiate()
	root.add_child(s)
	await process_frame
	var r = s.find_child("GLTF_SceneRootNode", true, false)
	print("children ", r.get_child_count())
	for c in r.get_children():
		var tot = AABB(); var first = true; var n = 0; var v = 0
		for m in c.find_children("*", "MeshInstance3D", true, false):
			var a = m.global_transform * m.get_aabb()
			if first: tot = a; first = false
			else: tot = tot.merge(a)
			n += 1
		print(c.name, " meshes ", n, " aabb ", tot.position.snapped(Vector3.ONE*0.01), " size ", tot.size.snapped(Vector3.ONE*0.01))
	quit()
