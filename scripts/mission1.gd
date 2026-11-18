extends Node
## МИССИЯ 1 — «Хулиган».
## Cutscene: shooting in the city, officer Petrov calls the player -> meet him at his
## police car -> he hands over a rifle ("Удачи, жду хулигана") -> find the hooligan ->
## chase / knock down and arrest him -> escort him (he keeps yelling it wasn't him) ->
## officer thanks the player -> reward $250.

const NpcScript := preload("res://scripts/npc.gd")

enum St { INTRO, TO_OFFICER, BRIEF, FIND, CHASE, ARREST, ESCORT, FINALE, DONE }

var world: Node
var stage := St.INTRO
var objective := ""
var cinematic := false
var sub_name := ""
var sub_text := ""

var officer: CharacterBody3D
var hooligan: CharacterBody3D
var police_car: Node3D
var pistol: Node3D
var _cam: Camera3D
var _marker: Node3D
var _marker_target: Node3D
var _arrest_requested := false
var _yell_t := 4.0
var _shoot_t := 3.0
var _flee_t := 0.0
var _beacon_t := 0.0
var _beacons: Array[OmniLight3D] = []
var _rng := RandomNumberGenerator.new()

const YELLS := ["Это не я!", "Отпусти меня!", "Я ничего не делал!", "Ты не того взял!", "Отпусти, говорю!", "Это был не я, клянусь!"]


func _ready() -> void:
	_rng.randomize()
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.far = 650.0
	_cam.near = 0.1
	world.add_child(_cam)
	_marker = _make_marker()
	world.add_child(_marker)
	_marker.visible = false
	_run()


# ------------------------------------------------------------------ helpers
func _wait(t: float) -> void:
	await get_tree().create_timer(t, false).timeout


func _frame() -> void:
	await get_tree().physics_frame


func _say(name: String, text: String, t: float) -> void:
	sub_name = name
	sub_text = text
	await _wait(t)
	if sub_text == text:
		sub_text = ""
		sub_name = ""


func _begin_cs() -> void:
	cinematic = true
	var p: Node = world.player
	p.input_locked = true
	p.fire_held = false
	p.move_input = Vector2.ZERO
	_cam.make_current()


func _end_cs() -> void:
	cinematic = false
	sub_text = ""
	sub_name = ""
	world.player.input_locked = false
	world.player.camera.make_current()


## Places the cutscene camera at `pos` looking at `look`, pulled in if a wall is in the way.
func _shot(pos: Vector3, look: Vector3) -> void:
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(look, pos, 1))
	if not hit.is_empty():
		pos = look + (hit.position - look) * 0.85
	_cam.look_at_from_position(pos, look)


func _dolly(a: Vector3, b: Vector3, look: Vector3, t: float) -> void:
	var tw := create_tween()
	tw.tween_method(func(k: float): _shot(a.lerp(b, k), look), 0.0, 1.0, t).set_trans(Tween.TRANS_SINE)


func _flat_dist(a: Node3D, b: Node3D) -> float:
	var d := a.global_position - b.global_position
	d.y = 0.0
	return d.length()


func _make_marker() -> Node3D:
	var n := Node3D.new()
	var beam := MeshInstance3D.new()
	beam.mesh = Props.cyl(0.6, 0.6, 40.0, 16)
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = Color(1.0, 0.85, 0.2, 0.18)
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = bm
	beam.position.y = 20.0
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(beam)
	var arrow := MeshInstance3D.new()
	arrow.name = "Arrow"
	arrow.mesh = Props.cyl(0.0, 0.45, 0.8, 4)
	var am := StandardMaterial3D.new()
	am.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	am.albedo_color = Color(1.0, 0.85, 0.2)
	arrow.material_override = am
	arrow.rotation.x = PI
	arrow.position.y = 3.0
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(arrow)
	return n


func _point_marker(target: Node3D) -> void:
	_marker_target = target
	_marker.visible = target != null


func get_blips() -> Array:
	var out := []
	if is_instance_valid(officer) and stage in [St.TO_OFFICER, St.ESCORT, St.FIND, St.CHASE]:
		out.append([officer.global_position, Color(0.3, 0.55, 1.0)])
	if is_instance_valid(hooligan) and stage in [St.FIND, St.CHASE, St.ESCORT]:
		out.append([hooligan.global_position, Color(1.0, 0.25, 0.2)])
	if _marker.visible and is_instance_valid(_marker_target):
		out.append([_marker_target.global_position, Color(1.0, 0.85, 0.2)])
	return out


func can_arrest() -> bool:
	if stage != St.CHASE or not is_instance_valid(hooligan):
		return false
	var p: Node3D = world.player
	return p.get("vehicle") == null and _flat_dist(p, hooligan) < (3.2 if hooligan.is_down() else 2.3)


func on_action() -> bool:
	if can_arrest():
		_arrest_requested = true
		return true
	return false


func blocks_vehicle() -> bool:
	return stage == St.ESCORT


# ------------------------------------------------------------------ actors
const POLICE_MODEL := "res://assets/characters/police_src.glb"
const THUG_MODEL := "res://assets/characters/thug.glb"


func _spawn_npc(pos: Vector3, clothes: Color, label: String, skin := Color(0, 0, 0, 0), model := "") -> CharacterBody3D:
	var n := CharacterBody3D.new()
	n.set_script(NpcScript)
	n.set("world", world)
	n.set("persistent", true)
	n.set("scripted", true)
	n.set("no_react", true)
	n.set("preset_clothes", clothes)
	n.set("preset_skin", skin)
	n.set("model_override", model)
	n.set("label", label)
	world.add_child(n)
	n.global_position = pos + Vector3.UP * 0.05
	return n


func _setup_actors() -> void:
	var p: Node3D = world.player
	var base := p.global_position
	# police car on a road ~45 m away, the officer on the sidewalk next to it
	var car_pos = null
	for i in 6:
		var a := _rng.randf() * TAU
		var c: Vector3 = base + Vector3(cos(a), 0, sin(a)) * 45.0
		car_pos = world.find_spot(c, 18.0, true, Vector3(1.2, 1.0, 2.6))
		if car_pos != null:
			break
	if car_pos == null:
		car_pos = base + Vector3(30, 0, 0)
	var car_yaw := _rng.randf() * TAU
	police_car = world.spawn_car("Car_0", car_pos, car_yaw)
	for i in 2:
		var l := OmniLight3D.new()
		l.light_color = Color(1, 0.1, 0.1) if i == 0 else Color(0.15, 0.3, 1.0)
		l.omni_range = 9.0
		l.light_energy = 0.0
		l.position = Vector3(0.5 if i == 0 else -0.5, 2.4, 0.2)
		police_car.add_child(l)
		_beacons.append(l)
	var off_pos = world.find_spot(car_pos, 7.0, false)
	if off_pos == null:
		off_pos = car_pos + Vector3(2.5, 0, 0)
	officer = _spawn_npc(off_pos, Color.WHITE, "Петров", Color.WHITE, POLICE_MODEL)
	# hooligan ~110 m away on a sidewalk, roughly opposite side from the police
	var away: Vector3 = (base - car_pos)
	away.y = 0.0
	away = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
	var h_pos = null
	for i in 8:
		var c: Vector3 = base + away.rotated(Vector3.UP, _rng.randf_range(-0.8, 0.8)) * 100.0
		h_pos = world.find_spot(c, 25.0, false)
		if h_pos != null:
			break
	if h_pos == null:
		h_pos = world.find_spot(base, 90.0, false)
	if h_pos == null:
		h_pos = base + away * 60.0
	hooligan = _spawn_npc(h_pos, Color.WHITE, "Хулиган", Color.WHITE, THUG_MODEL)
	hooligan.add_to_group("aim_priority")
	hooligan.set("no_react", true)
	await _frame()
	pistol = Weapons.pistol()
	hooligan.body.el_r.add_child(pistol)
	pistol.position = Vector3(0, -0.33, 0.03)
	pistol.rotation = Vector3(PI / 2, 0, 0)
	officer.script_face = p.global_position


func _hooligan_fire(at: Vector3, can_hit: bool) -> void:
	if not is_instance_valid(hooligan) or hooligan.is_down():
		return
	var from: Vector3 = hooligan.global_position + Vector3.UP * 1.45
	var muzzle: Vector3 = pistol.get_node("Muzzle").global_position if is_instance_valid(pistol) else from
	var dir := (at - from).normalized()
	dir = (dir + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.5, 1), _rng.randf_range(-1, 1)) * 0.06).normalized()
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dir * 80.0, 1 | 2 | 4 | 32, [hooligan.get_rid()]))
	var to := from + dir * 80.0
	if not hit.is_empty():
		to = hit.position
		if can_hit and hit.collider == world.player and _rng.randf() < 0.45:
			world.player.take_hit(dir, 5.0)
	Weapons.shot_fx(world, muzzle, to, not hit.is_empty(), false)
	var d: float = world.player.global_position.distance_to(from)
	world.bang(clampf(1.2 - d / 120.0, 0.15, 1.0))


# ------------------------------------------------------------------ per-frame
func _process(dt: float) -> void:
	# police beacons
	_beacon_t += dt
	var ph := fmod(_beacon_t * 2.5, 1.0)
	for i in _beacons.size():
		if is_instance_valid(_beacons[i]):
			_beacons[i].light_energy = 3.0 if (ph < 0.5) == (i == 0) else 0.0
	# marker follows its target, arrow bobs
	if _marker.visible and is_instance_valid(_marker_target):
		_marker.global_position = _marker_target.global_position + Vector3.UP * 1.0
		var arrow := _marker.get_node("Arrow") as Node3D
		arrow.position.y = 2.6 + sin(_beacon_t * 3.0) * 0.25
		arrow.rotation.y += dt * 2.0
	# officer keeps an eye on the player
	if is_instance_valid(officer) and stage != St.FINALE:
		officer.script_face = world.player.global_position + Vector3.UP * 1.5


func _physics_process(dt: float) -> void:
	var p: Node3D = world.player
	if not is_instance_valid(hooligan):
		return
	match stage:
		St.TO_OFFICER, St.BRIEF, St.FIND:
			# shoots in the air now and then, scaring people around
			_shoot_t -= dt
			if _shoot_t <= 0.0 and not hooligan.is_down():
				_shoot_t = _rng.randf_range(2.5, 5.0)
				hooligan.body.pose_mode = "shoot_air"
				for i in _rng.randi_range(2, 4):
					_hooligan_fire(hooligan.global_position + Vector3(_rng.randf_range(-3, 3), 30, _rng.randf_range(-3, 3)), false)
					await _wait(0.18)
				world.alarm(hooligan.global_position, 30.0, false)
				await _wait(0.6)
				if stage in [St.TO_OFFICER, St.BRIEF, St.FIND] and is_instance_valid(hooligan):
					hooligan.body.pose_mode = ""
		St.CHASE:
			if hooligan.is_down():
				return
			_flee_t -= dt
			var d := _flat_dist(p, hooligan)
			if _flee_t <= 0.0:
				_flee_t = 1.2
				var away := hooligan.global_position - p.global_position
				away.y = 0.0
				away = away.normalized().rotated(Vector3.UP, _rng.randf_range(-0.6, 0.6))
				hooligan.script_target = hooligan.global_position + away * 12.0
			# a bit slower than the player's sprint, tired when far ahead
			hooligan.script_speed = 5.0 if d < 40.0 else 3.2
			_shoot_t -= dt
			if _shoot_t <= 0.0 and d < 24.0 and d > 3.0:
				_shoot_t = _rng.randf_range(1.8, 3.2)
				hooligan.script_target = null
				hooligan.script_face = p.global_position
				hooligan.body.pose_mode = "aim_pistol"
				await _wait(0.35)
				for i in 2:
					if stage == St.CHASE:
						_hooligan_fire(p.global_position + Vector3.UP * 1.2, true)
					await _wait(0.2)
				if is_instance_valid(hooligan):
					hooligan.body.pose_mode = ""
					hooligan.script_face = null
				_flee_t = 0.0
		St.ESCORT:
			# walks behind the player in cuffs, yelling
			var behind := p.global_position - Vector3(sin(p.body.rotation.y), 0, cos(p.body.rotation.y)) * 1.6
			hooligan.script_target = behind
			var d := _flat_dist(p, hooligan)
			hooligan.script_speed = 1.6 if d < 3.0 else (4.0 if d < 10.0 else 6.5)
			hooligan.script_face = p.global_position
			if d > 35.0:
				hooligan.global_position = behind + Vector3.UP * 0.3
			_yell_t -= dt
			if _yell_t <= 0.0:
				_yell_t = _rng.randf_range(4.0, 7.0)
				_say("Хулиган", YELLS[_rng.randi() % YELLS.size()], 2.2)


# ------------------------------------------------------------------ story
func _run() -> void:
	await _wait(1.0)
	await _setup_actors()
	var p: Node = world.player
	await _wait(1.5)
	world.ui.show_message("МИССИЯ 1: Хулиган", 3.0)
	await _wait(2.0)

	# --- cutscene 1: shooting in the city, the call ---
	_begin_cs()
	var hp: Vector3 = hooligan.global_position
	hooligan.script_face = hp + Vector3(0, 0, 5)
	hooligan.body.pose_mode = "shoot_air"
	_shot(hp + Vector3(4.5, 1.6, 5.0), hp + Vector3.UP * 1.5)
	sub_name = ""
	sub_text = "В центре города началась стрельба..."
	for i in 6:
		_hooligan_fire(hp + Vector3(_rng.randf_range(-2, 2), 30, _rng.randf_range(-2, 2)), false)
		await _wait(0.32)
	world.alarm(hp, 45.0, false)
	_dolly(hp + Vector3(-6, 9, 10), hp + Vector3(8, 12, 14), hp, 3.0)
	await _wait(3.0)
	hooligan.body.pose_mode = ""
	sub_text = ""
	var pp: Vector3 = p.global_position
	var pf := Vector3(sin(p.body.rotation.y), 0, cos(p.body.rotation.y))
	p.body.pose_mode = "phone"
	_shot(pp + pf * 2.2 + Vector3.UP * 1.7 + pf.cross(Vector3.UP) * 0.8, pp + Vector3.UP * 1.55)
	await _say("", "*звонит телефон*", 1.6)
	await _say("Офицер Петров", "Алло! Это офицер Петров. В городе стрельба!", 3.0)
	await _say("Офицер Петров", "Мне нужна твоя помощь. Приезжай ко мне — я у полицейской машины.", 3.6)
	await _say("Ты", "Понял. Уже еду.", 2.0)
	p.body.pose_mode = ""
	_end_cs()

	# --- go to the officer ---
	stage = St.TO_OFFICER
	objective = "Встреться с офицером Петровым"
	_point_marker(officer)
	while true:
		await _frame()
		var near := _flat_dist(p, officer) < 5.0
		var veh = p.get("vehicle")
		if veh != null and _flat_dist(veh, officer) < 9.0 and veh.linear_velocity.length() < 3.0:
			p._exit_vehicle()
			near = true
		if near and p.get("vehicle") == null and not p.body.is_ragdoll():
			break

	# --- cutscene 2: the rifle ---
	stage = St.BRIEF
	_point_marker(null)
	objective = ""
	_begin_cs()
	var op: Vector3 = officer.global_position
	var to_p: Vector3 = p.global_position - op
	to_p.y = 0.0
	if to_p.length() > 2.2 or to_p.length() < 1.0:
		p.global_position = op + to_p.normalized() * 1.7
	officer.script_face = p.global_position + Vector3.UP * 1.5
	p.body.rotation.y = atan2(-to_p.x, -to_p.z)
	var mid: Vector3 = (op + p.global_position) * 0.5
	var side: Vector3 = to_p.normalized().cross(Vector3.UP)
	_shot(mid + side * 3.6 + Vector3.UP * 1.8, mid + Vector3.UP * 1.4)
	officer.body.pose_mode = "talk"
	await _say("Офицер Петров", "Хорошо, что ты здесь. Какой-то хулиган палит в воздух и пугает людей.", 3.6)
	await _say("Офицер Петров", "Держи автомат.", 1.8)
	p.give_rifle()
	officer.body.pose_mode = ""
	_shot(p.global_position + side * 1.6 + Vector3.UP * 1.6 - to_p.normalized() * 1.2, p.global_position + Vector3.UP * 1.3)
	world.ui.show_message("Получен автомат", 2.0)
	await _wait(1.6)
	_shot(mid + side * 3.6 + Vector3.UP * 1.8, mid + Vector3.UP * 1.4)
	officer.body.pose_mode = "talk"
	await _say("Офицер Петров", "Найди его и задержи. Только живым!", 2.8)
	await _say("Офицер Петров", "Удачи. Жду хулигана.", 2.4)
	officer.body.pose_mode = ""
	_end_cs()
	world.ui.show_message("ОГОНЬ — стрелять", 2.5)

	# --- find the hooligan ---
	stage = St.FIND
	objective = "Найди хулигана"
	_point_marker(hooligan)
	while _flat_dist(p, hooligan) > 26.0:
		await _frame()

	# --- chase and arrest ---
	stage = St.CHASE
	objective = "Задержи хулигана! Догони его или сбей с ног"
	hooligan.body.pose_mode = ""
	_say("Хулиган", "Чёрт, легавый!", 1.8)
	_flee_t = 0.0
	_shoot_t = 2.0
	while not _arrest_requested:
		await _frame()

	# --- arrest ---
	stage = St.ARREST
	_point_marker(null)
	objective = ""
	var t := 0.0
	while hooligan.is_down() and t < 6.0:
		await _frame()
		t += get_physics_process_delta_time()
	if hooligan.body.is_ragdoll():
		hooligan.body.stop_ragdoll()
	hooligan.script_target = null
	hooligan.body.knocked = 0.0
	if is_instance_valid(pistol):
		pistol.queue_free()
	hooligan.body.pose_mode = "cuffed"
	_begin_cs()
	var hpos: Vector3 = hooligan.global_position
	var hp2: Vector3 = p.global_position - hpos
	hp2.y = 0.0
	hooligan.script_face = p.global_position + Vector3.UP * 1.5
	_shot(hpos + hp2.normalized().cross(Vector3.UP) * 2.4 + Vector3.UP * 1.7 + hp2.normalized() * 0.6, hpos + Vector3.UP * 1.4)
	await _say("Хулиган", "Эй! Это не я! Отпусти меня!", 2.4)
	await _say("Ты", "Расскажешь это в участке.", 2.0)
	_end_cs()

	# --- escort ---
	stage = St.ESCORT
	objective = "Отведи хулигана к офицеру Петрову"
	_point_marker(officer)
	_yell_t = 3.0
	while _flat_dist(hooligan, officer) > 5.0 or _flat_dist(p, officer) > 7.0:
		await _frame()

	# --- finale ---
	stage = St.FINALE
	_point_marker(null)
	objective = ""
	_begin_cs()
	hooligan.script_target = null
	officer.script_face = hooligan.global_position + Vector3.UP * 1.5
	# two-shot of officer and hooligan from the side away from the player
	var fm: Vector3 = (officer.global_position + hooligan.global_position) * 0.5
	var oh: Vector3 = hooligan.global_position - officer.global_position
	oh.y = 0.0
	var perp: Vector3 = oh.normalized().cross(Vector3.UP) if oh.length() > 0.1 else Vector3.RIGHT
	if (p.global_position - fm).dot(perp) > 0.0:
		perp = -perp
	_shot(fm + perp * 4.2 + Vector3.UP * 1.9, fm + Vector3.UP * 1.35)
	officer.body.pose_mode = "talk"
	await _say("Офицер Петров", "Отличная работа! Спасибо!", 2.6)
	await _say("Хулиган", "Это не я!!! Отпустите меня!", 2.4)
	await _say("Офицер Петров", "В участке разберёмся. А это тебе — заслужил.", 3.2)
	officer.body.pose_mode = ""
	hooligan.script_target = police_car.global_position
	hooligan.script_speed = 1.5
	await _wait(2.5)
	_end_cs()
	world.add_money(250)
	world.ui.show_message("МИССИЯ ПРОЙДЕНА    +$250", 4.5)
	stage = St.DONE
	world.missions_done["m1"] = true
	world.save_game()
	await _wait(3.0)
	if is_instance_valid(hooligan):
		hooligan.queue_free()
	officer.set("scripted", false)
	officer.set("persistent", false)
	_marker.queue_free()
	_cam.queue_free()
	world.mission = null
	queue_free()
