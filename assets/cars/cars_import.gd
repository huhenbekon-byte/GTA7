@tool
extends EditorScenePostImport
## Splits the car pack (cars laid out in a grid, body / wheels / glass as separate nodes)
## into individual cars: Car_0, Car_1, ... each centred on (0, 0, 0) with its lowest point
## at y = 0, length along Z, meshes merged per material. Car size is stored in meta "size".

const MIN_LEN := 3.2
const MAX_LEN := 6.6


func _post_import(scene: Node) -> Object:
	var root := scene.find_child("GLTF_SceneRootNode", true, false)
	if root == null:
		root = scene
	# global transform of root (Sketchfab adds axis conversion nodes above it)
	var root_xf := Transform3D.IDENTITY
	var n: Node = root
	var chain := []
	while n != null and n != scene.get_parent():
		if n is Node3D:
			chain.push_front((n as Node3D).transform)
		n = n.get_parent()
	for t in chain:
		root_xf = root_xf * t

	# collect top-level parts: [aabb, [[mesh, surface, xf, material]...]]
	var parts := []
	for child in root.get_children():
		var surfs := []
		var box := AABB()
		var first := true
		_collect(child, root_xf * ((child as Node3D).transform if child is Node3D else Transform3D.IDENTITY), surfs)
		for s in surfs:
			var a: AABB = s[2] * (s[0] as Mesh).get_aabb()
			if first:
				box = a
				first = false
			else:
				box = box.merge(a)
		if not surfs.is_empty():
			parts.append([box, surfs])

	# union-find by (slightly grown) AABB overlap
	var parent := range(parts.size())
	for i in parts.size():
		for j in range(i + 1, parts.size()):
			if (parts[i][0] as AABB).grow(0.06).intersects(parts[j][0]):
				var a := _find(parent, i)
				var b := _find(parent, j)
				if a != b:
					parent[a] = b
	var clusters := {}
	for i in parts.size():
		var r := _find(parent, i)
		if not clusters.has(r):
			clusters[r] = []
		clusters[r].append(i)

	var out := Node3D.new()
	out.name = "Cars"
	var idx := 0
	for key in clusters:
		var ids: Array = clusters[key]
		var box: AABB = parts[ids[0]][0]
		for i in ids:
			box = box.merge(parts[i][0])
		var len := maxf(box.size.x, box.size.z)
		var wid := minf(box.size.x, box.size.z)
		if len < MIN_LEN or len > MAX_LEN or wid < 1.4 or wid > 2.6 or box.size.y < 0.9:
			continue
		var along_x := box.size.x > box.size.z
		var center := box.get_center()
		var to_local := Transform3D(Basis(), -Vector3(center.x, box.position.y, center.z))
		if along_x:
			to_local = Transform3D(Basis(Vector3.UP, PI / 2), Vector3.ZERO) * to_local
		# split wheel-like surfaces (so they can spin / steer) from the body
		var body_surfs := []
		var wheel_corners := {}
		for i in ids:
			for sf in parts[i][1]:
				var xf: Transform3D = to_local * (sf[2] as Transform3D)
				var a: AABB = xf * (sf[0] as Mesh).get_aabb()
				var c := a.get_center()
				var is_wheel := a.size.x < 0.5 and absf(a.size.y - a.size.z) < 0.15 and a.size.y > 0.4 and a.size.y < 1.25 and c.y < 0.75 and absf(c.x) > 0.35
				if is_wheel:
					var wk := ("R" if c.x < 0.0 else "L") + ("F" if c.z > 0.0 else "B")
					if not wheel_corners.has(wk):
						wheel_corners[wk] = []
					wheel_corners[wk].append([sf, xf, a])
				else:
					body_surfs.append([sf, xf])
		if wheel_corners.size() != 4:
			for wk in wheel_corners:
				for w in wheel_corners[wk]:
					body_surfs.append([w[0], w[1]])
			wheel_corners = {}
		var car := Node3D.new()
		car.name = "Car_%d" % idx
		car.set_meta("size", Vector3(wid, box.size.y, len))
		out.add_child(car)
		car.owner = out
		_build_meshes(car, out, body_surfs, Vector3.ZERO)
		for wk in wheel_corners:
			var wa: AABB = wheel_corners[wk][0][2]
			for w in wheel_corners[wk]:
				wa = wa.merge(w[2])
			var wc := wa.get_center()
			var wn := Node3D.new()
			wn.name = "Wheel_" + wk
			wn.position = wc
			wn.set_meta("radius", maxf(wa.size.y, wa.size.z) * 0.5)
			car.add_child(wn)
			wn.owner = out
			var ws := []
			for w in wheel_corners[wk]:
				ws.append([w[0], w[1]])
			_build_meshes(wn, out, ws, wc)
		idx += 1
	scene.free()
	return out


func _build_meshes(parent: Node3D, owner_node: Node, surfs: Array, origin: Vector3) -> void:
	var tools := {}
	for e in surfs:
		var sf: Array = e[0]
		var mat: Material = sf[3]
		var mk := str(mat.get_instance_id()) if mat else "none"
		if not tools.has(mk):
			tools[mk] = [SurfaceTool.new(), mat]
		(tools[mk][0] as SurfaceTool).append_from(sf[0], sf[1], Transform3D(Basis(), -origin) * (e[1] as Transform3D))
	for mk in tools:
		var mesh: ArrayMesh = (tools[mk][0] as SurfaceTool).commit()
		if tools[mk][1]:
			var m: Material = tools[mk][1]
			if m is BaseMaterial3D:
				(m as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh.surface_set_material(0, m)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		parent.add_child(mi)
		mi.owner = owner_node


func _find(p: Array, i: int) -> int:
	while p[i] != i:
		p[i] = p[p[i]]
		i = p[i]
	return i


func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mesh: Mesh = (n as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var mat: Material = (n as MeshInstance3D).get_surface_override_material(i)
			if mat == null:
				mat = mesh.surface_get_material(i)
			out.append([mesh, i, xf, mat])
	for c in n.get_children():
		if c is Node3D:
			_collect(c, xf * (c as Node3D).transform, out)
