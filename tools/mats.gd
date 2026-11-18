extends SceneTree
func _init():
	var s = load("res://assets/city/city.glb").instantiate()
	var seen := {}
	for m in s.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = m.mesh
		for i in mesh.get_surface_count():
			var mat = mesh.surface_get_material(i)
			if mat == null or seen.has(mat): continue
			seen[mat] = 1
			var t = mat.albedo_texture
			var img = t.get_image() if t else null
			print(mat.resource_name, " transp=", mat.transparency, " cull=", mat.cull_mode, " tex=", (str(img.get_size()) + (" A" if img.detect_alpha() else "")) if img else "none", " col=", mat.albedo_color, " normal=", mat.normal_enabled)
	quit()
