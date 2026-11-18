extends Node3D
## World bootstrap: city, sky / day-night / weather, water, clouds, birds, ambient audio,
## streamed "Part" props around the player, pedestrians, street-light pool, HUD.

const PlayerScript := preload("res://scripts/player.gd")
const NpcScript := preload("res://scripts/npc.gd")
const TouchUI := preload("res://scripts/touch_ui.gd")

# minimap covers this square of the world (must match tools/render_minimap.gd)
const MAP_X0 := -495.0
const MAP_Z0 := -1861.0
const MAP_SIZE := 2450.0

const DAY_LENGTH := 840.0     # seconds for 24h
const CHUNK := 40.0
const CHUNK_RADIUS := 2
const NPC_COUNT := 12
const LIGHT_POOL := 6

const SPAWN_HINT := Vector3(532, 0, -901)

var time_of_day := 17.2
var weather_name := "Ясно"

var player: CharacterBody3D
var ui: Control
var env: Environment
var sky_mat: ProceduralSkyMaterial
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var rain: CPUParticles3D
var dust: CPUParticles3D
var clouds: MeshInstance3D
var cloud_mat: ShaderMaterial
var city_mats: Array[BaseMaterial3D] = []
var lights: Array[OmniLight3D] = []
var birds: Array[Node3D] = []

var _chunks := {}            # Vector2i -> Node3D
var _chunk_queue: Array[Vector2i] = []
var _last_chunk := Vector2i(999999, 999999)
var _npcs: Array[Node] = []
var _light_timer := 0.0
var _traffic_timer := 0.0
var _traffic_phase := 0
var _weather := 0.0          # 0 clear .. 1 storm (smoothed)
var _weather_target := 0.0
var _fog_extra := 0.0
var _fog_target := 0.0
var _weather_timer := 90.0
var _rng := RandomNumberGenerator.new()
var _audio_pb: AudioStreamGeneratorPlayback
var _brown := 0.0
var _brown2 := 0.0
var _ready_done := false

const PROP_WEIGHTS := {
	"lamp": 10, "tree": 7, "bench": 5, "hydrant": 5, "booth": 2, "dumpster": 3, "busstop": 2,
	"mailbox": 3, "traffic": 2, "cone": 8, "crate": 6, "barrel": 5, "trash": 7, "barrier": 4, "pallets": 3, "ball": 1,
}


func _ready() -> void:
	_rng.randomize()
	_setup_environment()
	var city: Node3D = load("res://assets/city/city.glb").instantiate()
	add_child(city)
	for mi in city.find_children("*", "MeshInstance3D", true, false):
		var mt = (mi as MeshInstance3D).mesh.surface_get_material(0)
		if mt is BaseMaterial3D and not city_mats.has(mt):
			city_mats.append(mt)
	_setup_water()
	_setup_clouds()
	_setup_particles()
	_setup_birds()
	_setup_audio()
	for i in LIGHT_POOL:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.78, 0.5)
		l.omni_range = 16.0
		l.light_energy = 0.0
		l.omni_attenuation = 1.2
		add_child(l)
		lights.append(l)

	player = CharacterBody3D.new()
	player.set_script(PlayerScript)
	add_child(player)
	player.global_position = SPAWN_HINT + Vector3(0, 30, 0)  # temporary until physics is ready

	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_script(TouchUI)
	layer.add_child(ui)
	ui.player = player
	ui.world = self
	player.respawned.connect(func(): ui.show_message("Возрождение", 2.0))


func world_to_map_uv(p: Vector3) -> Vector2:
	return Vector2((p.x - MAP_X0) / MAP_SIZE, (p.z - MAP_Z0) / MAP_SIZE)


# ------------------------------------------------------------------ setup
func _setup_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 20.0
	sky_mat.sun_curve = 0.1
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.8
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_density = 0.004
	env.fog_sky_affect = 0.35
	env.fog_aerial_perspective = 0.4
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_blur = 1.5
	sun.light_angular_distance = 0.5
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.light_energy = 0.0
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(moon)


func _setup_water() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(4200, 4200)
	pm.subdivide_width = 0
	pm.subdivide_depth = 0
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.name = "Water"
	var sm := ShaderMaterial.new()
	sm.shader = load("res://scripts/water.gdshader")
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(730, -2.2, -636)
	add_child(mi)


func _setup_clouds() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(3000, 3000)
	clouds = MeshInstance3D.new()
	clouds.mesh = pm
	cloud_mat = ShaderMaterial.new()
	cloud_mat.shader = load("res://scripts/clouds.gdshader")
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_PERLIN
	fn.frequency = 0.012
	fn.fractal_octaves = 5
	nt.noise = fn
	cloud_mat.set_shader_parameter("noise", nt)
	clouds.material_override = cloud_mat
	clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	clouds.extra_cull_margin = 4000
	add_child(clouds)


func _setup_particles() -> void:
	rain = CPUParticles3D.new()
	rain.amount = 1400
	rain.lifetime = 1.0
	rain.emitting = false
	rain.local_coords = false
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(22, 1, 22)
	rain.direction = Vector3(0.08, -1, 0)
	rain.spread = 2.0
	rain.initial_velocity_min = 22.0
	rain.initial_velocity_max = 26.0
	rain.gravity = Vector3(0, -9, 0)
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.6)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(0.75, 0.8, 0.9, 0.35)
	rm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	q.material = rm
	rain.mesh = q
	rain.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	add_child(rain)

	dust = CPUParticles3D.new()
	dust.amount = 60
	dust.lifetime = 7.0
	dust.local_coords = false
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(14, 3, 14)
	dust.direction = Vector3(1, 0.1, 0.3)
	dust.spread = 40.0
	dust.initial_velocity_min = 0.4
	dust.initial_velocity_max = 1.6
	dust.gravity = Vector3(0, -0.15, 0)
	dust.angular_velocity_min = -180
	dust.angular_velocity_max = 180
	var dq := QuadMesh.new()
	dq.size = Vector2(0.12, 0.09)
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.85, 0.82, 0.7)
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	dq.material = dm
	dust.mesh = dq
	add_child(dust)


func _setup_birds() -> void:
	var wing := BoxMesh.new()
	wing.size = Vector3(0.5, 0.02, 0.18)
	var bodym := BoxMesh.new()
	bodym.size = Vector3(0.12, 0.1, 0.35)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.12, 0.12, 0.13)
	for f in 3:
		var flock := Node3D.new()
		flock.set_meta("r", _rng.randf_range(25, 60))
		flock.set_meta("h", _rng.randf_range(28, 55))
		flock.set_meta("speed", _rng.randf_range(0.12, 0.25) * (1 if _rng.randf() < 0.5 else -1))
		flock.set_meta("a", _rng.randf() * TAU)
		add_child(flock)
		for i in 7:
			var b := Node3D.new()
			b.position = Vector3(_rng.randf_range(-5, 5), _rng.randf_range(-2, 2), _rng.randf_range(-5, 5))
			var bodyi := MeshInstance3D.new()
			bodyi.mesh = bodym
			bodyi.material_override = bm
			b.add_child(bodyi)
			for s in [-1.0, 1.0]:
				var w := MeshInstance3D.new()
				w.mesh = wing
				w.material_override = bm
				w.position = Vector3(0.25 * s, 0, 0)
				w.set_meta("side", s)
				b.add_child(w)
			b.set_meta("ph", _rng.randf() * TAU)
			flock.add_child(b)
		birds.append(flock)


func _setup_audio() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.25
	var ap := AudioStreamPlayer.new()
	ap.stream = gen
	ap.volume_db = -6.0
	add_child(ap)
	ap.play()
	_audio_pb = ap.get_stream_playback()


# ------------------------------------------------------------------ main loop
func _physics_process(_dt: float) -> void:
	if not _ready_done:
		_ready_done = true
		var p := _find_ground_near(SPAWN_HINT, 40.0, 60)
		player.global_position = p + Vector3(0, 0.2, 0)
		player.set("_last_safe", player.global_position)
		ui.show_message("Добро пожаловать в город", 3.0)
	_stream_chunks()
	_manage_npcs()


func _process(dt: float) -> void:
	time_of_day = fmod(time_of_day + dt * 24.0 / DAY_LENGTH, 24.0)
	_update_weather(dt)
	_update_sky()
	var cam_pos: Vector3 = player.camera.global_position if player and player.camera else Vector3.ZERO
	rain.global_position = cam_pos + Vector3(0, 14, 0)
	dust.global_position = cam_pos
	clouds.global_position = Vector3(cam_pos.x, 320, cam_pos.z)
	_update_birds(dt, cam_pos)
	_update_lights(dt)
	_update_traffic(dt)
	_fill_audio()


func _night_factor() -> float:
	var h := (time_of_day - 6.0) / 12.0 * PI
	var sun_y := sin(h)
	return clampf(1.0 - (sun_y + 0.08) / 0.25, 0.0, 1.0)


func _update_sky() -> void:
	var h := (time_of_day - 6.0) / 12.0 * PI
	var sun_dir := Vector3(cos(h), sin(h) * 0.9, 0.35).normalized()
	var sun_y := sun_dir.y
	if sun_y > -0.2:
		sun.look_at_from_position(Vector3.ZERO, -sun_dir, Vector3.UP if absf(sun_dir.y) < 0.99 else Vector3.FORWARD)
	var day := clampf((sun_y + 0.05) / 0.35, 0.0, 1.0)
	var golden := clampf(1.0 - absf(sun_y - 0.08) / 0.22, 0.0, 1.0)
	var night := _night_factor()
	var storm := _weather

	sun.light_energy = day * (1.25 - storm * 0.75)
	sun.light_color = Color(1.0, 0.97, 0.9).lerp(Color(1.0, 0.6, 0.32), golden)
	sun.shadow_enabled = day > 0.05
	var moon_dir := -sun_dir
	if moon_dir.y > 0.0:
		moon.look_at_from_position(Vector3.ZERO, -moon_dir, Vector3.UP)
	moon.light_energy = night * 0.22 * (1.0 - storm * 0.5)

	var top_day := Color(0.22, 0.45, 0.82)
	var hor_day := Color(0.66, 0.78, 0.9)
	var top_set := Color(0.25, 0.3, 0.55)
	var hor_set := Color(1.0, 0.55, 0.3)
	var top_night := Color(0.01, 0.015, 0.05)
	var hor_night := Color(0.05, 0.07, 0.14)
	var storm_top := Color(0.3, 0.32, 0.36)
	var storm_hor := Color(0.45, 0.47, 0.5)
	var top := top_day.lerp(top_set, golden).lerp(top_night, night)
	var hor := hor_day.lerp(hor_set, golden).lerp(hor_night, night)
	top = top.lerp(storm_top * (1.0 - night * 0.85), storm * 0.85)
	hor = hor.lerp(storm_hor * (1.0 - night * 0.85), storm * 0.85)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = hor
	sky_mat.ground_horizon_color = hor
	sky_mat.ground_bottom_color = hor.darkened(0.5)
	sky_mat.sun_angle_max = lerpf(20.0, 40.0, golden)
	env.ambient_light_energy = lerpf(1.0, 0.35, night) * (1.0 - storm * 0.2)
	env.fog_light_color = hor.lerp(top, 0.25)
	env.fog_density = 0.0028 + storm * 0.006 + _fog_extra * 0.018 + night * 0.002
	env.tonemap_exposure = lerpf(1.0, 1.25, night)
	cloud_mat.set_shader_parameter("coverage", lerpf(0.42, 0.85, storm))
	cloud_mat.set_shader_parameter("tint", Color(1, 1, 1).lerp(Color(1.0, 0.7, 0.5), golden).lerp(Color(0.12, 0.13, 0.18), night).lerp(Color(0.5, 0.52, 0.55), storm * 0.7))
	Props.bulb_mat().emission_energy_multiplier = night * 4.0
	Props.bulb_mat().emission = Color(1.0, 0.85, 0.55) if night > 0.05 else Color.BLACK


func _update_weather(dt: float) -> void:
	_weather_timer -= dt
	if _weather_timer <= 0.0:
		_weather_timer = _rng.randf_range(100.0, 220.0)
		var r := _rng.randf()
		if r < 0.45:
			_weather_target = 0.0; _fog_target = 0.0; weather_name = "Ясно"
		elif r < 0.65:
			_weather_target = 0.45; _fog_target = 0.0; weather_name = "Облачно"
		elif r < 0.88:
			_weather_target = 1.0; _fog_target = 0.1; weather_name = "Дождь"
		else:
			_weather_target = 0.35; _fog_target = 1.0; weather_name = "Туман"
	_weather = move_toward(_weather, _weather_target, dt * 0.03)
	_fog_extra = move_toward(_fog_extra, _fog_target, dt * 0.03)
	var raining := _weather > 0.75
	rain.emitting = raining
	# wet streets: lower roughness while it rains
	var wet := clampf((_weather - 0.6) / 0.4, 0.0, 1.0)
	for m in city_mats:
		m.roughness = lerpf(0.92, 0.35, wet)
	dust.emitting = _weather < 0.5


func _update_birds(dt: float, cam: Vector3) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for f in birds:
		var a: float = f.get_meta("a") + dt * f.get_meta("speed")
		f.set_meta("a", a)
		var r: float = f.get_meta("r")
		var center := Vector3(cam.x, 0, cam.z)
		var pos := center + Vector3(cos(a) * r, f.get_meta("h"), sin(a) * r)
		var nxt := center + Vector3(cos(a + 0.05 * signf(f.get_meta("speed"))) * r, f.get_meta("h"), sin(a + 0.05 * signf(f.get_meta("speed"))) * r)
		f.global_position = f.global_position.lerp(pos, 1.0 - exp(-0.5 * dt)) if f.global_position.length() > 1 else pos
		if f.global_position.distance_to(nxt) > 0.1:
			f.look_at(nxt, Vector3.UP)
		f.visible = _night_factor() < 0.6
		for b in f.get_children():
			var ph: float = b.get_meta("ph")
			for w in b.get_children():
				if w.has_meta("side"):
					var s: float = w.get_meta("side")
					w.rotation.z = sin(t * 9.0 + ph) * 0.6 * s
					w.position.y = sin(t * 9.0 + ph) * 0.05


func _update_lights(dt: float) -> void:
	_light_timer -= dt
	var night := _night_factor()
	if _light_timer > 0.0:
		for l in lights:
			l.light_energy = lerpf(l.light_energy, l.get_meta("target", 0.0) * night * 2.2, 1.0 - exp(-4.0 * dt))
		return
	_light_timer = 0.4
	var pp := player.global_position
	var anchors := get_tree().get_nodes_in_group("lamp_light")
	anchors.sort_custom(func(a, b): return a.global_position.distance_squared_to(pp) < b.global_position.distance_squared_to(pp))
	for i in lights.size():
		var l := lights[i]
		if i < anchors.size() and anchors[i].global_position.distance_to(pp) < 70.0:
			if l.global_position.distance_to(anchors[i].global_position) > 0.5:
				l.light_energy = 0.0
			l.global_position = anchors[i].global_position
			l.set_meta("target", 1.0)
		else:
			l.set_meta("target", 0.0)


func _update_traffic(dt: float) -> void:
	_traffic_timer -= dt
	if _traffic_timer > 0.0:
		return
	_traffic_phase = (_traffic_phase + 1) % 3
	_traffic_timer = [6.0, 2.0, 6.0][_traffic_phase]
	var active: int = [0, 1, 2][_traffic_phase]
	var cols := [Color(1, 0.15, 0.1), Color(1, 0.75, 0.1), Color(0.1, 1, 0.35)]
	for n in get_tree().get_nodes_in_group("traffic_lamp"):
		var i: int = n.get_meta("tl_index")
		n.material_override = Props.m(cols[i], 0.3, 0.0, 3.0) if i == active else Props.m(cols[i] * 0.3)


func _fill_audio() -> void:
	if _audio_pb == null:
		return
	var n := _audio_pb.get_frames_available()
	var rain_amt := clampf((_weather - 0.6) / 0.4, 0.0, 1.0)
	var wind := 0.04 + _weather * 0.05
	for i in n:
		var w := randf() * 2.0 - 1.0
		_brown = clampf(_brown + w * 0.02, -1.0, 1.0) * 0.998   # deep city/wind rumble
		_brown2 = lerpf(_brown2, w, 0.35)                        # brighter hiss for rain
		var v := _brown * wind * 3.0 + _brown2 * rain_amt * 0.12
		_audio_pb.push_frame(Vector2(v, v))


# ------------------------------------------------------------------ streaming
func _find_ground_near(center: Vector3, radius: float, tries: int) -> Vector3:
	var space := get_world_3d().direct_space_state
	for i in tries:
		var off := Vector3.ZERO if i == 0 else Vector3(_rng.randf_range(-radius, radius), 0, _rng.randf_range(-radius, radius))
		var p := center + off
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 6.0, p.z), Vector3(p.x, -3.0, p.z), 1)
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and hit.normal.y > 0.95 and _clear(hit.position, Vector3(0.4, 0.9, 0.4)):
			return hit.position
	return center + Vector3(0, 2, 0)


func _clear(ground: Vector3, half: Vector3, yaw := 0.0) -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var b := BoxShape3D.new()
	b.size = half * 2.0
	q.shape = b
	q.transform = Transform3D(Basis(Vector3.UP, yaw), ground + Vector3(0, half.y + 0.2, 0))
	q.collision_mask = 1 | 2
	return space.intersect_shape(q, 1).is_empty()


func _stream_chunks() -> void:
	var pp := player.global_position
	var c := Vector2i(floori(pp.x / CHUNK), floori(pp.z / CHUNK))
	if c != _last_chunk:
		_last_chunk = c
		for dx in range(-CHUNK_RADIUS, CHUNK_RADIUS + 1):
			for dz in range(-CHUNK_RADIUS, CHUNK_RADIUS + 1):
				var k := Vector2i(c.x + dx, c.y + dz)
				if not _chunks.has(k) and not _chunk_queue.has(k):
					_chunk_queue.append(k)
		for k in _chunks.keys():
			if absi(k.x - c.x) > CHUNK_RADIUS + 1 or absi(k.y - c.y) > CHUNK_RADIUS + 1:
				_chunks[k].queue_free()
				_chunks.erase(k)
		_chunk_queue.sort_custom(func(a, b): return (a - c).length_squared() < (b - c).length_squared())
	if not _chunk_queue.is_empty():
		_build_chunk(_chunk_queue.pop_front())


func _build_chunk(k: Vector2i) -> void:
	var root := Node3D.new()
	root.name = "Chunk_%d_%d" % [k.x, k.y]
	add_child(root)
	_chunks[k] = root
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(k)
	var space := get_world_3d().direct_space_state
	_place_parked_cars(root, rng, k, space)
	var total_w := 0
	for v in PROP_WEIGHTS.values():
		total_w += v
	var placed := 0
	for attempt in 22:
		if placed >= 11:
			break
		var p := Vector3(k.x * CHUNK + rng.randf() * CHUNK, 0, k.y * CHUNK + rng.randf() * CHUNK)
		var pick := rng.randi() % total_w
		var kind := ""
		for kk in PROP_WEIGHTS:
			pick -= PROP_WEIGHTS[kk]
			if pick < 0:
				kind = kk
				break
		var yaw := rng.randf() * TAU
		if p.distance_to(Vector3(player.global_position.x, 0, player.global_position.z)) < 3.0:
			continue
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 7.0, p.z), Vector3(p.x, -3.0, p.z), 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or hit.normal.y < 0.97:
			continue
		var fp: Array = Props.KINDS[kind]
		var tall := 1.6 if kind != "car" else 1.2
		if not _clear(hit.position, Vector3(fp[0], tall, fp[1]), yaw):
			continue
		var node := Props.make(kind, rng)
		root.add_child(node)
		node.global_position = hit.position + Vector3(0, 0.01, 0)
		node.rotation.y = yaw
		placed += 1


func _manage_npcs() -> void:
	var pp := player.global_position
	for n in _npcs.duplicate():
		if not is_instance_valid(n):
			_npcs.erase(n)
		elif n.global_position.distance_to(pp) > 95.0 or n.global_position.y < -8.0:
			n.queue_free()
			_npcs.erase(n)
	if _npcs.size() < NPC_COUNT and Engine.get_physics_frames() % 10 == 0:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(18.0, 55.0)
		var c := pp + Vector3(cos(a) * d, 0, sin(a) * d)
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(Vector3(c.x, pp.y + 6.0, c.z), Vector3(c.x, pp.y - 6.0, c.z), 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or hit.normal.y < 0.9 or not _clear(hit.position, Vector3(0.35, 0.9, 0.35)):
			return
		var npc := CharacterBody3D.new()
		npc.set_script(NpcScript)
		add_child(npc)
		npc.global_position = hit.position + Vector3(0, 0.1, 0)
		_npcs.append(npc)


# ------------------------------------------------------------------ parked cars
const CAR_ROW_CHANCE := 0.8

func _ground_h(space: PhysicsDirectSpaceState3D, p: Vector3, y0: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, y0 + 2.2, p.z), Vector3(p.x, y0 - 1.5, p.z), 1)
	var h := space.intersect_ray(q)
	if h.is_empty():
		return NAN
	return h.position.y


## Walks from p along dir until the ground changes. Returns [distance, kind]:
## kind 2 = curb (ground steps up), 1 = wall, -1 = drop / hole, 0 = nothing within maxd.
func _edge_dist(space: PhysicsDirectSpaceState3D, p: Vector3, dir: Vector3, y0: float, maxd: float) -> Array:
	var from := Vector3(p.x, y0 + 0.7, p.z)
	var wq := PhysicsRayQueryParameters3D.create(from, from + dir * maxd, 1)
	var wall := space.intersect_ray(wq)
	var wd := maxd + 1.0
	if not wall.is_empty():
		wd = Vector2(wall.position.x - p.x, wall.position.z - p.z).length()
	var d := 0.3
	while d < minf(wd, maxd):
		var h := _ground_h(space, p + dir * d, y0)
		if is_nan(h) or h < y0 - 0.12:
			return [d, -1]
		if h > y0 + 0.06:
			return [d, 2]
		d += 0.3
	if wd <= maxd:
		return [wd, 1]
	return [maxd + 1.0, 0]


func _place_parked_cars(root: Node3D, rng: RandomNumberGenerator, k: Vector2i, space: PhysicsDirectSpaceState3D) -> void:
	if rng.randf() > CAR_ROW_CHANCE:
		return
	for attempt in 5:
		var p := Vector3(k.x * CHUNK + rng.randf() * CHUNK, 0, k.y * CHUNK + rng.randf() * CHUNK)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, 7.0, p.z), Vector3(p.x, -3.0, p.z), 1))
		if hit.is_empty() or hit.normal.y < 0.97:
			continue
		var start: Vector3 = hit.position
		var y0 := start.y
		# nearest curb around the point
		var best_d := 99.0
		var best_dir := Vector3.ZERO
		for i in 16:
			var a := i * TAU / 16.0
			var dir := Vector3(cos(a), 0, sin(a))
			var r := _edge_dist(space, start, dir, y0, 5.0)
			if r[1] == 2 and r[0] < best_d:
				best_d = r[0]
				best_dir = dir
		if best_d > 5.0:
			continue
		# refine the curb line from two samples along it
		var axis := Vector3(-best_dir.z, 0, best_dir.x)
		var e1 := _edge_dist(space, start + axis * 2.5, best_dir, y0, 7.0)
		var e2 := _edge_dist(space, start - axis * 2.5, best_dir, y0, 7.0)
		if e1[1] != 2 or e2[1] != 2 or absf(e1[0] - e2[0]) > 1.2:
			continue
		var c1: Vector3 = start + axis * 2.5 + best_dir * float(e1[0])
		var c2: Vector3 = start - axis * 2.5 + best_dir * float(e2[0])
		axis = (c1 - c2)
		axis.y = 0.0
		axis = axis.normalized()
		var n := Vector3(axis.z, 0, -axis.x)
		if n.dot(best_dir) < 0.0:
			n = -n
		var curb := _edge_dist(space, start, n, y0, 7.0)
		if curb[1] != 2:
			continue
		var curb_d: float = curb[0]
		var facing := 0.0 if rng.randf() < 0.5 else PI
		var count := rng.randi_range(1, 4)
		var offset := 0.0
		var placed := 0
		for c in count * 2:
			if placed >= count:
				break
			var tmpl := Props.random_car(rng)
			var size: Vector3 = tmpl.get_meta("size")
			var center_off := offset + size.z * 0.5
			offset += size.z + rng.randf_range(0.8, 2.0)
			var pos := start + n * (curb_d - size.x * 0.5 - 0.3) + axis * center_off
			if _try_put_car(space, root, tmpl, size, pos, axis, facing, y0):
				placed += 1
		if placed > 0:
			return


func _try_put_car(space: PhysicsDirectSpaceState3D, root: Node3D, tmpl: Node3D, size: Vector3, pos: Vector3, axis: Vector3, facing: float, y0: float) -> bool:
	if Vector2(pos.x - player.global_position.x, pos.z - player.global_position.z).length() < 4.0:
		return false
	var yaw := atan2(axis.x, axis.z) + facing
	var cb := Basis(Vector3.UP, yaw)
	# all four corners and the middle must be on flat road
	for cx in [-0.5, 0.5]:
		for cz in [-0.5, 0.0, 0.5]:
			var cp := pos + cb * Vector3(cx * size.x, 0, cz * size.z)
			var h := _ground_h(space, cp, y0)
			if is_nan(h) or absf(h - y0) > 0.08:
				return false
	if not _clear(Vector3(pos.x, y0, pos.z), Vector3(size.x * 0.5, size.y * 0.5 - 0.15, size.z * 0.5), yaw):
		return false
	var car := Props.car_from(tmpl, size)
	root.add_child(car)
	car.global_position = Vector3(pos.x, y0 + 0.01, pos.z)
	car.rotation.y = yaw
	return true
