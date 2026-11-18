extends SceneTree
var out := ""
var main
func _init():
	out = OS.get_cmdline_user_args()[0]
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.time_of_day = 14.0
	var p
	var shots = 0
	while main.mission == null: await physics_frame
	var m = main.mission
	p = main.player
	print("mission started")
	while not m.cinematic: await physics_frame
	for i in 40: await physics_frame
	await _shot("m1_cs_shooting")
	while m.sub_name != "Офицер Петров": await physics_frame
	await _shot("m2_cs_phone")
	while m.stage != 1: await physics_frame
	print("stage TO_OFFICER, objective: ", m.objective, " officer dist ", p.global_position.distance_to(m.officer.global_position))
	await _shot("m3_objective")
	p.global_position = m.officer.global_position + Vector3(2.5, 0.3, 0)
	while not m.cinematic: await physics_frame
	for i in 30: await physics_frame
	await _shot("m4_cs_officer")
	while m.stage != 3: await physics_frame
	print("FIND; has rifle ", p.has_rifle)
	# walk near the hooligan
	var hp = m.hooligan.global_position
	p.global_position = hp + (p.global_position - hp).normalized() * 18.0 + Vector3.UP * 0.5
	p.cam_yaw = atan2(-(hp - p.global_position).x, -(hp - p.global_position).z)
	while m.stage != 4: await physics_frame
	print("CHASE")
	for i in 60: await physics_frame
	p.cam_yaw = atan2(-(m.hooligan.global_position - p.global_position).x, -(m.hooligan.global_position - p.global_position).z)
	p.fire_held = true
	for i in 25: await physics_frame
	await _shot("m5_shooting")
	p.fire_held = false
	for i in 60: await physics_frame
	print("hooligan down: ", m.hooligan.is_down(), " hp ", m.hooligan.health)
	# get next to him and arrest
	p.global_position = m.hooligan.global_position + Vector3(1.2, 0.4, 0)
	for i in 5: await physics_frame
	print("can arrest ", m.can_arrest())
	p.grab_pressed = true
	while m.stage != 6: await physics_frame
	print("ESCORT")
	await _shot("m6_escort")
	# walk player to officer gradually (teleport near), hooligan follows/teleports
	p.global_position = m.officer.global_position + Vector3(3.0, 0.3, 1.0)
	for i in 120: await physics_frame
	await _shot("m7_escort_arrive")
	while m.stage != 7 and is_instance_valid(m): await physics_frame
	for i in 60: await physics_frame
	await _shot("m8_finale")
	while is_instance_valid(m) and m.stage != 8: await physics_frame
	print("DONE money=", main.money)
	await _shot("m9_done")
	quit()

func _shot(nm):
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out + "/" + nm + ".png")
