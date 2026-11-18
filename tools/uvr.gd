extends SceneTree
func _init():
	for p in ["res://assets/character/character.glb", "res://assets/cars/cars.glb"]:
		var s = load(p).instantiate()
		for mi in s.find_children("*", "MeshInstance3D", true, false).slice(0, 8):
			var a = mi.mesh.surface_get_arrays(0)
			var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
			var mn = Vector2(1e9,1e9); var mx = Vector2(-1e9,-1e9)
			for u in uv: mn = mn.min(u); mx = mx.max(u)
			var m = mi.mesh.surface_get_material(0)
			print(p.get_file(), " ", mi.name, " uv ", mn, " .. ", mx, " tex ", m.albedo_texture.get_size() if m and m.albedo_texture else "-")
	quit()
