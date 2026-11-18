@tool
extends EditorScenePostImport
## Automatic rigging for a static T-pose character (the police officer model has no skeleton).
## Builds a Mixamo-named Skeleton3D from body proportions measured on the mesh and skins
## every vertex to the nearest bone segments of its body region (arms / legs / torso),
## so the procedural animation system can drive it like any rigged model.

func _post_import(scene: Node) -> Object:
	# 1. collect all surfaces with vertices in model space (y up, facing +Z)
	var surfs := []
	_collect(scene, Transform3D.IDENTITY, surfs)
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for s in surfs:
		for v in (s.arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			lo = lo.min(v)
			hi = hi.max(v)
	var H := hi.y - lo.y
	var foot_y := lo.y
	var cx := (lo.x + hi.x) * 0.5
	var cz := 0.0
	# 2. measure: arm line height, shoulder width, leg spacing
	var arm_y_sum := 0.0
	var arm_n := 0
	var arm_z_sum := 0.0
	var max_x := 0.0
	var leg_x_sum := 0.0
	var leg_n := 0
	var torso_z_sum := 0.0
	var torso_n := 0
	for s in surfs:
		for v in (s.arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			var x := v.x - cx
			var y := v.y - foot_y
			if absf(x) > (hi.x - cx) * 0.55:
				arm_y_sum += y
				arm_z_sum += v.z
				arm_n += 1
			max_x = maxf(max_x, absf(x))
			if y > H * 0.3 and y < H * 0.42:
				leg_x_sum += absf(x)
				leg_n += 1
			if y > H * 0.55 and y < H * 0.75 and absf(x) < H * 0.1:
				torso_z_sum += v.z
				torso_n += 1
	var arm_y := arm_y_sum / maxf(arm_n, 1) if arm_n > 0 else H * 0.8
	var arm_z := arm_z_sum / maxf(arm_n, 1)
	cz = torso_z_sum / maxf(torso_n, 1)
	var leg_x := clampf(leg_x_sum / maxf(leg_n, 1), H * 0.035, H * 0.08)
	# shoulder joint: where the torso ends at arm height
	var sh_x := H * 0.1
	var widths := []
	for s in surfs:
		for v in (s.arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			var y := v.y - foot_y
			if y > arm_y - H * 0.11 and y < arm_y - H * 0.06:
				widths.append(absf(v.x - cx))
	if widths.size() > 10:
		widths.sort()
		sh_x = float(widths[int(widths.size() * 0.95)]) * 0.9
	var wrist_x := max_x - H * 0.1
	var elbow_x := sh_x + (wrist_x - sh_x) * 0.52

	# 3. skeleton (identity rest rotations, cm units like the source)
	var P := {
		"Hips": Vector3(0, H * 0.53, cz), "Spine": Vector3(0, H * 0.6, cz), "Spine1": Vector3(0, H * 0.67, cz),
		"Spine2": Vector3(0, H * 0.74, cz), "Neck": Vector3(0, H * 0.845, cz), "Head": Vector3(0, H * 0.885, cz),
		"HeadTop_End": Vector3(0, H, cz),
	}
	for side in [["Left", 1.0], ["Right", -1.0]]:
		var sx: float = side[1]
		var n: String = side[0]
		P[n + "Shoulder"] = Vector3(sx * H * 0.04, arm_y - H * 0.01, arm_z)
		P[n + "Arm"] = Vector3(sx * sh_x, arm_y, arm_z)
		P[n + "ForeArm"] = Vector3(sx * elbow_x, arm_y, arm_z)
		P[n + "Hand"] = Vector3(sx * wrist_x, arm_y, arm_z)
		P[n + "HandEnd"] = Vector3(sx * max_x, arm_y, arm_z)
		P[n + "UpLeg"] = Vector3(sx * leg_x, H * 0.5, cz)
		P[n + "Leg"] = Vector3(sx * leg_x, H * 0.28, cz)
		P[n + "Foot"] = Vector3(sx * leg_x, H * 0.05, cz)
		P[n + "ToeBase"] = Vector3(sx * leg_x, H * 0.012, cz + H * 0.08)
	var parents := {
		"Hips": "", "Spine": "Hips", "Spine1": "Spine", "Spine2": "Spine1", "Neck": "Spine2", "Head": "Neck", "HeadTop_End": "Head",
	}
	for n in ["Left", "Right"]:
		parents[n + "Shoulder"] = "Spine2"
		parents[n + "Arm"] = n + "Shoulder"
		parents[n + "ForeArm"] = n + "Arm"
		parents[n + "Hand"] = n + "ForeArm"
		parents[n + "HandEnd"] = n + "Hand"
		parents[n + "UpLeg"] = "Hips"
		parents[n + "Leg"] = n + "UpLeg"
		parents[n + "Foot"] = n + "Leg"
		parents[n + "ToeBase"] = n + "Foot"
	var order := ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "HeadTop_End"]
	for n in ["Left", "Right"]:
		order.append_array([n + "Shoulder", n + "Arm", n + "ForeArm", n + "Hand", n + "HandEnd", n + "UpLeg", n + "Leg", n + "Foot", n + "ToeBase"])
	var root := Node3D.new()
	root.name = "AutoRigged"
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	root.add_child(sk)
	sk.owner = root
	var idx := {}
	for n in order:
		var i := sk.get_bone_count()
		sk.add_bone("mixamorig_" + n)
		idx[n] = i
		var par: String = parents[n]
		var gpos: Vector3 = P[n] + Vector3(cx, foot_y, 0)
		if par != "":
			sk.set_bone_parent(i, idx[par])
			sk.set_bone_rest(i, Transform3D(Basis(), gpos - (P[par] + Vector3(cx, foot_y, 0))))
		else:
			sk.set_bone_rest(i, Transform3D(Basis(), gpos))
	sk.reset_bone_poses()

	# segments for weighting: bone -> [start, end]
	var seg := {}
	for n in order:
		var kids := []
		for c in order:
			if parents[c] == n:
				kids.append(c)
		var a: Vector3 = P[n]
		var b: Vector3 = a + Vector3(0, H * 0.05, 0)
		if n == "Hips":
			b = P["Spine"]
		elif n == "Spine2":
			b = P["Neck"]
		elif n.ends_with("Shoulder"):
			b = P[n.replace("Shoulder", "Arm")]
		elif kids.size() > 0:
			b = P[kids[0]]
		seg[n] = [a, b]
	var torso := ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head"]

	# 4. skin
	var skin := Skin.new()
	for n in order:
		var g: Transform3D = sk.get_bone_global_rest(idx[n])
		skin.add_named_bind("mixamorig_" + n, g.affine_inverse())
	var mesh := ArrayMesh.new()
	for s in surfs:
		var arrays: Array = s.arrays
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		bones.resize(verts.size() * 4)
		weights.resize(verts.size() * 4)
		for vi in verts.size():
			var v: Vector3 = verts[vi] - Vector3(cx, foot_y, 0)
			var cands: Array
			var side := "Left" if v.x > 0.0 else "Right"
			if absf(v.x) > sh_x * 0.85 and v.y > arm_y - H * 0.13:
				cands = [side + "Shoulder", side + "Arm", side + "ForeArm", side + "Hand", "Spine2"]
				if absf(v.x) > sh_x * 1.15:
					cands = [side + "Arm", side + "ForeArm", side + "Hand"]
			elif v.y < H * 0.5:
				cands = [side + "UpLeg", side + "Leg", side + "Foot", side + "ToeBase", "Hips"]
				if v.y < H * 0.4:
					cands = [side + "UpLeg", side + "Leg", side + "Foot", side + "ToeBase"]
			else:
				cands = torso.duplicate()
				cands.append_array([side + "Shoulder", side + "UpLeg"])
			var scored := []
			for c in cands:
				var d := _seg_dist(v, seg[c][0], seg[c][1])
				scored.append([1.0 / pow(d + H * 0.02, 4.0), idx[c]])
			scored.sort_custom(func(a, b): return a[0] > b[0])
			var tot := 0.0
			for k in mini(3, scored.size()):
				tot += scored[k][0]
			for k in 4:
				if k < mini(3, scored.size()):
					bones[vi * 4 + k] = scored[k][1]
					weights[vi * 4 + k] = scored[k][0] / tot
				else:
					bones[vi * 4 + k] = 0
					weights[vi * 4 + k] = 0.0
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, s.mat)
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = mesh
	mi.skin = skin
	sk.add_child(mi)
	mi.owner = root
	mi.skeleton = NodePath("..")
	scene.free()
	return root


func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	var x := xf
	if n is Node3D:
		x = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mesh: Mesh = (n as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(i)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for k in verts.size():
				verts[k] = x * verts[k]
			if norms.size() == verts.size():
				for k in norms.size():
					norms[k] = (x.basis * norms[k]).normalized()
				arrays[Mesh.ARRAY_NORMAL] = norms
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_TANGENT] = null
			var mat: Material = (n as MeshInstance3D).get_surface_override_material(i)
			if mat == null:
				mat = mesh.surface_get_material(i)
			out.append({"arrays": arrays, "mat": mat})
	for c in n.get_children():
		_collect(c, x, out)
