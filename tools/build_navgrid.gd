extends SceneTree
# Bakes assets/ui/navgrid.png: one pixel per 4x4 m cell. 0 = blocked, 128 = walkable, 255 = road.
const X0 := -10.0
const Z0 := -1840.0
const CELL := 4.0
func _init():
	var w = Node3D.new(); root.add_child(w)
	var city = load("res://assets/city/city.glb").instantiate(); w.add_child(city)
	var main_script = load("res://scripts/main.gd")
	var road_mats = main_script.ROAD_MATS
	for i in 3: await physics_frame
	var space = w.get_world_3d().direct_space_state
	var W := int(1480.0 / CELL)
	var H := int(2410.0 / CELL)
	var img := Image.create(W, H, false, Image.FORMAT_L8)
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new(); sph.radius = 1.2
	q.shape = sph; q.collision_mask = 1
	var counts = [0, 0, 0]
	for gz in H:
		for gx in W:
			var x := X0 + (gx + 0.5) * CELL
			var z := Z0 + (gz + 0.5) * CELL
			var h = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 3.5, z), Vector3(x, -4.0, z), 1))
			var v := 0
			if not h.is_empty() and h.normal.y > 0.85:
				q.transform = Transform3D(Basis(), h.position + Vector3.UP * 1.6)
				if space.intersect_shape(q, 1).is_empty():
					var mats: PackedStringArray = h.collider.get_meta("shape_mats")
					v = 255 if road_mats.has(mats[h.shape]) else 128
			img.set_pixel(gx, gz, Color8(v, v, v))
			counts[0 if v == 0 else (2 if v == 255 else 1)] += 1
	img.save_png("res://assets/ui/navgrid.png")
	print("navgrid ", W, "x", H, " blocked/walk/road ", counts)
	quit()
