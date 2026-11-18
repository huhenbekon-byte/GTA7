extends SceneTree
func _init():
	var w = Node3D.new(); root.add_child(w); current_scene = w
	var floor = StaticBody3D.new(); var cs = CollisionShape3D.new(); var bs = BoxShape3D.new(); bs.size = Vector3(40,1,40); cs.shape = bs; floor.add_child(cs); floor.position.y = -0.5; w.add_child(floor)
	var h = Humanoid.new(); h.model_path = "res://assets/character/character.glb"; w.add_child(h)
	for i in 5: await physics_frame
	h.start_ragdoll(Vector3.ZERO, Vector3(0, 20, -60))
	var r = h.ragdoll
	await physics_frame
	for k in r.order: print("v ", k, " ", r.parts[k].body.linear_velocity.snapped(Vector3.ONE*0.01), " m ", r.parts[k].body.mass)
	for k in r.order: print(k, " ", r.parts[k].body.global_position.snapped(Vector3.ONE*0.01))
	for i in 60:
		await physics_frame
		if i % 10 == 0:
			var s = ""
			for k in ["hips","chest","head","shin_l"]: s += k + str(r.parts[k].body.global_position.snapped(Vector3.ONE*0.01)) + " "
			print(i, " ", s)
	quit()
