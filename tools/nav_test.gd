extends SceneTree
var out := ""
func _init():
	out = OS.get_cmdline_user_args()[0]
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.time_of_day = 13.0
	while main.mission == null: await physics_frame
	var m = main.mission
	while m.stage != 1: await physics_frame
	for i in 30: await physics_frame
	var nav = main.navigator
	print("target ", nav.target_name, " dist ", nav.distance, " path pts ", nav.path.size())
	await _shot("n1")
	# move far away and check the route
	var p = main.player
	p.global_position = main.find_spot(p.global_position + Vector3(0, 0, 120), 30, false)
	for i in 90: await physics_frame
	print("after move dist ", nav.distance, " path pts ", nav.path.size())
	await _shot("n2")
	quit()
func _shot(nm):
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out + "/" + nm + ".png")
