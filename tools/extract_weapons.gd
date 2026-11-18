extends SceneTree
# Extracts single weapons from the big gun pack into small self-contained meshes
# (textures embedded, max 256 px): assets/weapons/<name>.res. Prints bounds.
func _init():
	var pack = load("res://assets/weapons/src/gunpack.glb").instantiate()
	root.add_child(pack)
	await process_frame
	var want = {"AK-556_28": "rifle", "G-17_128": "pistol"}
	var tex_cache = {}
	for node_name in want:
		var gun: Node3D = pack.find_child(node_name, true, false)
		var inv = gun.global_transform.affine_inverse()
		var tools = {}
		var lo = Vector3(1e9,1e9,1e9); var hi = -lo
		for mi in gun.find_children("*", "MeshInstance3D", true, false):
			var xf = inv * mi.global_transform
			for si in mi.mesh.get_surface_count():
				var mat = mi.get_active_material(si)
				var key = mat.get_instance_id() if mat else 0
				if not tools.has(key): tools[key] = [SurfaceTool.new(), mat]
				tools[key][0].append_from(mi.mesh, si, xf)
			var a = xf * mi.get_aabb()
			lo = lo.min(a.position); hi = hi.max(a.end)
		var am = ArrayMesh.new()
		for k in tools:
			var m = tools[k][0].commit()
			var arr = m.surface_get_arrays(0)
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var mat = tools[k][1]
			if mat:
				mat = mat.duplicate()
				if mat is BaseMaterial3D and mat.albedo_texture:
					var t = mat.albedo_texture
					if not tex_cache.has(t):
						var img: Image = t.get_image()
						if img.is_compressed(): img.decompress()
						if img.get_width() > 256: img.resize(256, 256 * img.get_height() / img.get_width())
						img.generate_mipmaps()
						tex_cache[t] = ImageTexture.create_from_image(img)
					mat.albedo_texture = tex_cache[t]
				if mat is BaseMaterial3D:
					mat.normal_texture = null; mat.normal_enabled = false
					mat.metallic_texture = null; mat.roughness_texture = null
					mat.emission_texture = null; mat.ao_texture = null
				am.surface_set_material(am.get_surface_count() - 1, mat)
		ResourceSaver.save(am, "res://assets/weapons/%s.res" % want[node_name])
		print(want[node_name], " bounds ", lo, " .. ", hi, " surfaces ", am.get_surface_count())
	quit()
