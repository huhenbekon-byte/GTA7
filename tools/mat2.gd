extends SceneTree
func _init():
	var s = load("res://assets/city/city.glb").instantiate()
	var seen = {}
	for mi in s.find_children("*", "MeshInstance3D", true, false):
		var m = mi.mesh.surface_get_material(0)
		if m and m.resource_name in ["material_104_93_34","material_104_93_8","material_104_93_63"] and not seen.has(m):
			seen[m]=1
			var img = m.albedo_texture.get_image()
			print(m.resource_name, " transp=", m.transparency, " fmt=", img.get_format(), " alpha=", img.detect_alpha(), " flags vc=", m.vertex_color_use_as_albedo, " tex=", m.albedo_texture.resource_path)
	quit()
