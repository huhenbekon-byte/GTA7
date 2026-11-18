extends SceneTree
func _init():
	var s = load("res://assets/character/character.glb").instantiate()
	root.add_child(s)
	await process_frame
	var sk: Skeleton3D = s.find_children("*", "Skeleton3D", true, false)[0]
	for i in sk.get_bone_count():
		var n = sk.get_bone_name(i)
		if "Hand" in n and not n.ends_with("Hand_010") and not n.ends_with("Hand_034"): continue
		var g = sk.get_bone_global_rest(i)
		print(i, " ", n, " parent ", sk.get_bone_parent(i), " pos ", g.origin.snapped(Vector3.ONE*0.1), " rest_rot ", sk.get_bone_rest(i).basis.get_euler().snapped(Vector3.ONE*0.01))
	quit()
