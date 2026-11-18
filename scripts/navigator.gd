extends Node
## GPS navigator: A* over a baked 4 m grid of the city (assets/ui/navgrid.png:
## 0 = blocked, 128 = walkable, 255 = road). Roads are cheaper than sidewalks, so routes
## follow the streets. Targets whatever the active mission returns from nav_target().

const X0 := -10.0
const Z0 := -1840.0
const CELL := 4.0

var world: Node
var astar: AStarGrid2D
var path: PackedVector3Array = PackedVector3Array()
var target: Node3D = null
var target_name := ""
var distance := 0.0

var _grid: Image
var _w := 0
var _h := 0
var _timer := 0.0
var _last_target_pos := Vector3(1e9, 0, 0)
var _ready_grid := false


func _ready() -> void:
	call_deferred("_build")


func _build() -> void:
	var tex: Texture2D = load("res://assets/ui/navgrid.png")
	_grid = tex.get_image()
	if _grid.is_compressed():
		_grid.decompress()
	_w = _grid.get_width()
	_h = _grid.get_height()
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, _w, _h)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	# run-length fill: few calls instead of one per cell
	for y in _h:
		var x := 0
		while x < _w:
			var v := _cell(x, y)
			var x1 := x
			while x1 + 1 < _w and _cell(x1 + 1, y) == v:
				x1 += 1
			var r := Rect2i(x, y, x1 - x + 1, 1)
			if v == 0:
				astar.fill_solid_region(r, true)
			elif v == 1:
				astar.fill_weight_scale_region(r, 2.5)
			x = x1 + 1
	_ready_grid = true


## 0 blocked, 1 walkable, 2 road
func _cell(x: int, y: int) -> int:
	var l := _grid.get_pixel(x, y).r
	return 0 if l < 0.25 else (2 if l > 0.75 else 1)


func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(clampi(floori((p.x - X0) / CELL), 0, _w - 1), clampi(floori((p.z - Z0) / CELL), 0, _h - 1))


func cell_to_world(c: Vector2i, y: float) -> Vector3:
	return Vector3(X0 + (c.x + 0.5) * CELL, y, Z0 + (c.y + 0.5) * CELL)


func _nearest_open(c: Vector2i) -> Vector2i:
	if not astar.is_point_solid(c):
		return c
	for r in range(1, 14):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var q := c + Vector2i(dx, dy)
				if astar.is_in_boundsv(q) and not astar.is_point_solid(q):
					return q
	return Vector2i(-1, -1)


func _pick_target() -> void:
	target = null
	target_name = ""
	var m: Node = world.get("mission")
	if m != null and m.has_method("nav_target"):
		var t = m.nav_target()
		if t != null and is_instance_valid(t[0]):
			target = t[0]
			target_name = t[1]
			return


func _process(dt: float) -> void:
	if not _ready_grid or world.player == null:
		return
	_pick_target()
	if target == null:
		path = PackedVector3Array()
		return
	var pp: Vector3 = world.player.global_position
	_timer -= dt
	var moved := target.global_position.distance_to(_last_target_pos) > 6.0
	var off := path.size() > 0 and _dist_to_path(pp) > 10.0
	if _timer <= 0.0 or moved or off:
		_timer = 1.5
		_last_target_pos = target.global_position
		_compute(pp, target.global_position)
	# trim points already passed
	while path.size() > 1 and Vector2(path[0].x - pp.x, path[0].z - pp.z).length() < 6.0:
		path.remove_at(0)
	distance = 0.0
	var prev := pp
	for p in path:
		distance += Vector2(p.x - prev.x, p.z - prev.z).length()
		prev = p


func _dist_to_path(p: Vector3) -> float:
	var best := 1e9
	for i in range(0, mini(path.size(), 8)):
		best = minf(best, Vector2(path[i].x - p.x, path[i].z - p.z).length())
	return best


func _compute(from: Vector3, to: Vector3) -> void:
	var a := _nearest_open(world_to_cell(from))
	var b := _nearest_open(world_to_cell(to))
	path = PackedVector3Array()
	if a.x < 0 or b.x < 0:
		path.append(to)
		return
	# in a car the road preference is stronger
	var ids := astar.get_id_path(a, b, true)
	if ids.is_empty():
		path.append(to)
		return
	# simplify: keep points where the direction changes
	var prev_dir := Vector2i.ZERO
	for i in ids.size():
		var c: Vector2i = ids[i]
		if i > 0 and i < ids.size() - 1:
			var d: Vector2i = ids[i + 1] - c
			if d == prev_dir and i % 6 != 0:
				continue
			prev_dir = d
		path.append(cell_to_world(c, from.y))
	path.append(to)


## Point ~15 m ahead along the route, for the HUD arrow.
func guide_point(from: Vector3) -> Vector3:
	var acc := 0.0
	var prev := from
	for p in path:
		acc += Vector2(p.x - prev.x, p.z - prev.z).length()
		if acc > 15.0:
			return p
		prev = p
	return path[path.size() - 1] if path.size() > 0 else from
