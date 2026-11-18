extends SceneTree
func _init():
	var s = load("res://assets/city/city.glb").instantiate()
	var mat
	var arr
	for mi in s.find_children("*", "MeshInstance3D", true, false):
		var m = mi.mesh.surface_get_material(0)
		if m and m.resource_name == "material_104_93_34":
			mat = m; arr = mi.mesh.surface_get_arrays(0); break
	var cols = arr[Mesh.ARRAY_COLOR]
	print("has colors ", cols != null and cols.size() > 0)
	if cols: 
		var mn = 9.0; var mx = -9.0
		for c in cols: mn = min(mn, c.a); mx = max(mx, c.a)
		print("vc alpha ", mn, " ", mx, " sample ", cols[0])
	var uvs = arr[Mesh.ARRAY_TEX_UV]
	print("uv sample ", uvs[0], uvs[1], uvs[2])
	var q = MeshInstance3D.new(); var qm = QuadMesh.new(); qm.size = Vector2(4,4); q.mesh = qm
	var m2 = mat.duplicate(); m2.vertex_color_use_as_albedo = false
	q.material_override = mat; root.add_child(q)
	var q2 = MeshInstance3D.new(); q2.mesh = qm; q2.material_override = m2; q2.position.x = 4.5; root.add_child(q2)
	var c = Camera3D.new(); root.add_child(c); c.position = Vector3(2.2,0,6); c.current = true
	var e = WorldEnvironment.new(); e.environment = Environment.new(); e.environment.background_mode = Environment.BG_COLOR; e.environment.background_color = Color(1,0,1); root.add_child(e)
	var l = DirectionalLight3D.new(); root.add_child(l)
	for i in 5: await process_frame
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	quit()
