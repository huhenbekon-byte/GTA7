extends SceneTree
func _init():
	var out = OS.get_cmdline_user_args()[0]
	var s = load("res://assets/city/city.glb").instantiate()
	var seen := {}
	var imgs := []
	for m in s.find_children("*", "MeshInstance3D", true, false):
		for i in m.mesh.get_surface_count():
			var mat = m.mesh.surface_get_material(i)
			if mat and mat.transparency != 0 and not seen.has(mat):
				seen[mat]=1
				var im: Image = mat.albedo_texture.get_image(); im.decompress(); im.convert(Image.FORMAT_RGBA8); im.resize(128,128)
				imgs.append(im); print(mat.resource_name)
	var atlas = Image.create(128*imgs.size(), 128, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(1,0,1))
	for k in imgs.size(): atlas.blend_rect(imgs[k], Rect2i(0,0,128,128), Vector2i(128*k,0))
	atlas.save_png(out)
	quit()
