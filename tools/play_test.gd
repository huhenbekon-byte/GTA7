extends SceneTree
# Headless-ish gameplay test: runs main scene, drives the player, saves screenshots.
# usage: godot -s tools/play_test.gd -- <outdir> [time_of_day] [weather]
var out := ""
func _init():
	var a = OS.get_cmdline_user_args()
	out = a[0]
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	if a.size() > 1: main.time_of_day = float(a[1])
	if a.size() > 2:
		main._weather = float(a[2]); main._weather_target = float(a[2]); main._weather_timer = 9999
	for i in 30: await physics_frame
	var p = main.player
	print("spawn ", p.global_position)
	await _shot("01_spawn")
	p.move_input = Vector2(0, 1)
	for i in 90: await physics_frame
	print("walk ", p.global_position, " speed ", p.body.speed)
	await _shot("02_jog")
	p.sprint_held = true
	for i in 60: await physics_frame
	print("sprint ", p.global_position, " speed ", p.body.speed)
	await _shot("03_sprint")
	p.jump_pressed = true
	for i in 12: await physics_frame
	await _shot("04_jump")
	p.sprint_held = false
	p.move_input = Vector2.ZERO
	for i in 60: await physics_frame
	p.add_camera_input(Vector2(400, 0))
	p.attack_pressed = true
	for i in 9: await physics_frame
	await _shot("05_punch")
	p.add_camera_input(Vector2(-900, 60))
	for i in 30: await physics_frame
	await _shot("06_front")
	print("npcs ", main._npcs.size(), " chunks ", main._chunks.size(), " props ", main.get_tree().get_nodes_in_group("lamp_light").size(), " lamps")
	print("fps ", Engine.get_frames_per_second())
	quit()

func _shot(n: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out + "/" + n + ".png")
