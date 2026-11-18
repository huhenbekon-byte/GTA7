extends SceneTree
var out := ""
var main
func _init():
	out = OS.get_cmdline_user_args()[0]
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.time_of_day = 13.0
	for i in 120: await physics_frame
	var p = main.player
	var npcs = main.get_tree().get_nodes_in_group("npc")
	print("npcs ", npcs.size(), " states ", npcs.map(func(n): return n.state))
	await _shot("p01_npcs_near")
	# bring an npc in front of the player and punch
	var f = Vector3(sin(p.body.rotation.y), 0, cos(p.body.rotation.y))
	var n = npcs[0]
	n.global_position = p.global_position + f * 1.0
	n.state = 1
	for k in 6:
		p.attack_pressed = true
		for i in 22: await physics_frame
	print("npc after punches state=", n.state, " health=", n.health, " ragdoll=", n.body.is_ragdoll())
	await _shot("p02_punched")
	# grab a crate and throw at another npc
	var crate = Props.crate(RandomNumberGenerator.new())
	main.add_child(crate)
	crate.global_position = p.global_position + f * 0.9 + Vector3.UP * 0.1
	for i in 10: await physics_frame
	p.grab_pressed = true
	for i in 20: await physics_frame
	print("holding ", p.held != null)
	await _shot("p03_carry")
	var n2 = npcs[1]
	n2.global_position = p.global_position + f * 5.0
	n2.state = 1
	p.cam_yaw = p.body.rotation.y + PI
	p.grab_pressed = true
	for i in 30: await physics_frame
	print("npc2 after throw state=", n2.state, " ragdoll=", n2.body.is_ragdoll())
	await _shot("p04_thrown")
	# explosion amidst pedestrians
	var b = Props.barrel(RandomNumberGenerator.new())
	main.add_child(b)
	var bp = p.global_position + f * 6.0 + Vector3(2, 0, 0)
	b.global_position = bp
	for k in range(2, 6):
		npcs[k].global_position = bp + Vector3(randf_range(-2.5, 2.5), 0.2, randf_range(-2.5, 2.5))
	for i in 5: await physics_frame
	main.explode(bp + Vector3.UP * 0.5)
	b.queue_free()
	for i in 6: await physics_frame
	await _shot("p05_explosion")
	for i in 20: await physics_frame
	await _shot("p06_after")
	print("after explosion: ", npcs.slice(2, 6).map(func(x): return [x.state, x.body.is_ragdoll()]), " player ragdoll ", p.body.is_ragdoll(), " hp ", p.health)
	for i in 400: await physics_frame
	print("later: ", npcs.slice(0, 6).map(func(x): return x.state if is_instance_valid(x) else -1), " player ragdoll ", p.body.is_ragdoll())
	await _shot("p07_later")
	quit()

func _shot(nm):
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out + "/" + nm + ".png")
