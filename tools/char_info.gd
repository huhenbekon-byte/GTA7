extends SceneTree
func _init():
	var s = load("res://assets/character/character.glb").instantiate()
	root.add_child(s)
	await process_frame
	var sk: Skeleton3D = s.find_children("*", "Skeleton3D", true, false)[0]
	print("skel path ", s.get_path_to(sk), " skel global ", sk.global_transform)
	for n in ["mixamorig:Hips_00","mixamorig:Head_05","mixamorig:HeadTop_End_06","mixamorig:LeftArm_08","mixamorig:LeftForeArm_09","mixamorig:LeftHand_010","mixamorig:LeftUpLeg_055","mixamorig:LeftFoot_057","mixamorig:LeftToeBase_058","mixamorig:RightArm_032"]:
		var i = sk.find_bone(n)
		var g = sk.global_transform * sk.get_bone_global_rest(i)
		print(n, " idx ", i, " pos ", g.origin)
	for m in s.find_children("*", "MeshInstance3D", true, false):
		print("mesh ", m.name, " aabb ", m.global_transform * m.get_aabb(), " skin ", m.skin != null)
	quit()
