extends Control
## Multi-touch HUD: floating left joystick, right-side camera drag, action buttons,
## health bar, clock and rotating minimap.

var player: Node
var world: Node  # main.gd (for clock)

var _joy_index := -1
var _joy_origin := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _cam_index := -1
var _cam_last := Vector2.ZERO
var _btn_touch := {}   # touch index -> button name
var _mouse_look := false

var _buttons := {}     # name -> {pos, r, label}
var _health := 100.0
var _msg := ""
var _msg_t := 0.0

var minimap: TextureRect
var _font: Font

const JOY_R := 95.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	minimap = TextureRect.new()
	minimap.size = Vector2(230, 230)
	minimap.texture = load("res://assets/ui/minimap.png")
	minimap.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	minimap.stretch_mode = TextureRect.STRETCH_SCALE
	var sm := ShaderMaterial.new()
	sm.shader = load("res://scripts/minimap.gdshader")
	minimap.material = sm
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(minimap)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var s := get_viewport_rect().size
	var u := clampf(s.y / 720.0, 0.7, 2.0)
	_buttons = {
		"jump": {"pos": Vector2(s.x - 110 * u, s.y - 120 * u), "r": 58.0 * u, "label": "ПРЫЖОК"},
		"punch": {"pos": Vector2(s.x - 240 * u, s.y - 85 * u), "r": 52.0 * u, "label": "УДАР"},
		"sprint": {"pos": Vector2(s.x - 115 * u, s.y - 260 * u), "r": 50.0 * u, "label": "БЕГ"},
		"grab": {"pos": Vector2(s.x - 250 * u, s.y - 215 * u), "r": 46.0 * u, "label": "ВЗЯТЬ"},
	}
	minimap.size = Vector2(210, 210) * u
	minimap.position = Vector2(24 * u, 24 * u)


func show_message(t: String, dur := 2.5) -> void:
	_msg = t
	_msg_t = dur


func set_health(v: float) -> void:
	_health = v


func _button_at(p: Vector2) -> String:
	for n in _buttons:
		if p.distance_to(_buttons[n].pos) <= _buttons[n].r * 1.15:
			return n
	return ""


func _press(btn: String, down: bool) -> void:
	if player == null:
		return
	match btn:
		"jump":
			if down: player.jump_pressed = true
		"punch":
			if down: player.attack_pressed = true
		"sprint":
			player.sprint_held = down
		"grab":
			if down: player.grab_pressed = true


func _input(e: InputEvent) -> void:
	if player == null:
		return
	var half := get_viewport_rect().size.x * 0.42
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		if t.pressed:
			var b := _button_at(t.position)
			if b != "":
				_btn_touch[t.index] = b
				_press(b, true)
			elif t.position.x < half and _joy_index == -1:
				_joy_index = t.index
				_joy_origin = t.position
				_joy_pos = t.position
			elif _cam_index == -1:
				_cam_index = t.index
				_cam_last = t.position
		else:
			if _btn_touch.has(t.index):
				_press(_btn_touch[t.index], false)
				_btn_touch.erase(t.index)
			if t.index == _joy_index:
				_joy_index = -1
				player.move_input = Vector2.ZERO
			if t.index == _cam_index:
				_cam_index = -1
		queue_redraw()
	elif e is InputEventScreenDrag:
		var d := e as InputEventScreenDrag
		if d.index == _joy_index:
			_joy_pos = d.position
			var v := (_joy_pos - _joy_origin) / JOY_R
			if v.length() > 1.0:
				_joy_origin = _joy_pos - v.normalized() * JOY_R  # drag the base along
				v = v.normalized()
			player.move_input = Vector2(v.x, -v.y)
			queue_redraw()
		elif d.index == _cam_index:
			player.add_camera_input((d.position - _cam_last) * (1280.0 / get_viewport_rect().size.x) * 1.4)
			_cam_last = d.position
	elif e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		player.add_camera_input((e as InputEventMouseMotion).relative)
	elif e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if e.pressed else Input.MOUSE_MODE_VISIBLE


func _process(dt: float) -> void:
	_msg_t -= dt
	if player:
		_health = player.health
		var mm := minimap.material as ShaderMaterial
		var w: Node = world
		var pos: Vector3 = player.global_position
		mm.set_shader_parameter("center_uv", w.world_to_map_uv(pos))
		mm.set_shader_parameter("angle", player.cam_yaw)
		mm.set_shader_parameter("zoom", 0.07)
	queue_redraw()


func _draw() -> void:
	var s := get_viewport_rect().size
	var u := clampf(s.y / 720.0, 0.7, 2.0)
	# joystick
	if _joy_index != -1:
		draw_circle(_joy_origin, JOY_R, Color(0, 0, 0, 0.25))
		draw_arc(_joy_origin, JOY_R, 0, TAU, 48, Color(1, 1, 1, 0.5), 3.0)
		draw_circle(_joy_pos, 38, Color(1, 1, 1, 0.55))
	else:
		var hint := Vector2(170 * u, s.y - 170 * u)
		draw_arc(hint, JOY_R * 0.8, 0, TAU, 48, Color(1, 1, 1, 0.18), 2.0)
		draw_circle(hint, 30, Color(1, 1, 1, 0.15))
	# buttons
	if player and _buttons.has("grab"):
		_buttons.grab.label = "БРОСИТЬ" if player.held else "ВЗЯТЬ"
	for n in _buttons:
		var b: Dictionary = _buttons[n]
		var pressed: bool = n in _btn_touch.values()
		draw_circle(b.pos, b.r, Color(0.05, 0.05, 0.05, 0.55 if not pressed else 0.8))
		draw_arc(b.pos, b.r, 0, TAU, 40, Color(1, 1, 1, 0.75) if not pressed else Color(1, 0.8, 0.2), 3.0)
		var fs := int(15 * u)
		var tw := _font.get_string_size(b.label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string(_font, b.pos + Vector2(-tw * 0.5, fs * 0.35), b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	# minimap frame + player arrow
	var mc := minimap.position + minimap.size * 0.5
	var mr := minimap.size.x * 0.5
	draw_arc(mc, mr, 0, TAU, 64, Color(0, 0, 0, 0.8), 6.0)
	if player:
		var rel: float = player.body.rotation.y - player.cam_yaw
		var fwd := Vector2(sin(rel), cos(rel))  # screen space: up = camera forward
		var side := Vector2(-fwd.y, fwd.x)
		var tip := mc + fwd * 12 * u
		var pts := PackedVector2Array([tip, mc - fwd * 8 * u + side * 8 * u, mc - fwd * 4 * u, mc - fwd * 8 * u - side * 8 * u])
		draw_colored_polygon(pts, Color(1, 1, 1))
		draw_polyline(pts + PackedVector2Array([tip]), Color(0, 0, 0), 1.5)
	# health bar under minimap
	var hb := Rect2(minimap.position + Vector2(0, minimap.size.y + 10 * u), Vector2(minimap.size.x, 12 * u))
	draw_rect(hb, Color(0, 0, 0, 0.6))
	draw_rect(Rect2(hb.position + Vector2(2, 2), Vector2((hb.size.x - 4) * clampf(_health / 100.0, 0, 1), hb.size.y - 4)), Color(0.3, 0.85, 0.35))
	# clock
	if world:
		var t: float = world.time_of_day
		var txt := "%02d:%02d" % [int(t), int(fmod(t, 1.0) * 60.0)]
		var fs := int(34 * u)
		var tw := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string_outline(_font, Vector2(s.x - tw - 30 * u, 54 * u), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color.BLACK)
		draw_string(_font, Vector2(s.x - tw - 30 * u, 54 * u), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1))
		var w: String = world.weather_name
		var fs2 := int(18 * u)
		var tw2 := _font.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
		draw_string_outline(_font, Vector2(s.x - tw2 - 30 * u, 82 * u), w, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, 4, Color.BLACK)
		draw_string(_font, Vector2(s.x - tw2 - 30 * u, 82 * u), w, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(0.9, 0.9, 0.9))
	# message
	if _msg_t > 0.0:
		var fs := int(40 * u)
		var tw := _font.get_string_size(_msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var a := clampf(_msg_t, 0, 1)
		draw_string_outline(_font, Vector2((s.x - tw) * 0.5, s.y * 0.3), _msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color(0, 0, 0, a))
		draw_string(_font, Vector2((s.x - tw) * 0.5, s.y * 0.3), _msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.85, 0.3, a))
