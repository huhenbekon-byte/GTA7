@tool
extends EditorScenePostImport
## Post-import for the city model:
## - scales Sketchfab export (cm) to meters
## - merges ~2400 small meshes into per-material chunks (far fewer draw calls on phones)
## - builds trimesh collision per chunk (everything except bushes / ivy / road decals)
## - fixes alpha materials to alpha-scissor (cheap + no sorting artifacts)

const CELL := 240.0
const SCALE := 100.0
# Materials that should NOT block the player: bush, ivy, road-marking decals.
const NO_COLLIDE := ["material_104_93_8", "material_104_93_9", "material_104_93_34"]


func _post_import(scene: Node) -> Object:
	var tools := {}   # key -> {mat, st, cell}
	_walk(scene, Transform3D(Basis.from_scale(Vector3.ONE * SCALE), Vector3.ZERO), tools)

	var city := Node3D.new()
	city.name = "City"
	var meshes_node := Node3D.new()
	meshes_node.name = "Meshes"
	city.add_child(meshes_node)
	meshes_node.owner = city
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	city.add_child(body)
	body.owner = city

	var faces_by_cell := {}
	var fixed_mats := {}
	for key in tools:
		var entry: Dictionary = tools[key]
		var st: SurfaceTool = entry.st
		var mesh: ArrayMesh = st.commit()
		var mat: Material = entry.mat
		if mat and not fixed_mats.has(mat):
			_fix_material(mat)
			fixed_mats[mat] = true
		if mat:
			mesh.surface_set_material(0, mat)
		var mi := MeshInstance3D.new()
		mi.name = "M_%d" % meshes_node.get_child_count()
		mi.mesh = mesh
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		meshes_node.add_child(mi)
		mi.owner = city
		var mname: String = mat.resource_name if mat else ""
		if mname in NO_COLLIDE:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			continue
		var cell: Vector2i = entry.cell
		if not faces_by_cell.has(cell):
			faces_by_cell[cell] = PackedVector3Array()
		faces_by_cell[cell].append_array(mesh.get_faces())

	for cell in faces_by_cell:
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces_by_cell[cell])
		var cs := CollisionShape3D.new()
		cs.name = "C_%d_%d" % [cell.x, cell.y]
		cs.shape = shape
		body.add_child(cs)
		cs.owner = city

	scene.free()
	return city


func _walk(n: Node, parent_xf: Transform3D, tools: Dictionary) -> void:
	var xf := parent_xf
	if n is Node3D:
		xf = parent_xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mesh: Mesh = (n as MeshInstance3D).mesh
		var aabb: AABB = xf * mesh.get_aabb()
		var c := aabb.get_center()
		var cell := Vector2i(floori(c.x / CELL), floori(c.z / CELL))
		for i in mesh.get_surface_count():
			var mat: Material = (n as MeshInstance3D).get_surface_override_material(i)
			if mat == null:
				mat = mesh.surface_get_material(i)
			var key := "%s|%d|%d" % [str(mat.get_instance_id()) if mat else "none", cell.x, cell.y]
			if not tools.has(key):
				var st := SurfaceTool.new()
				tools[key] = {"st": st, "mat": mat, "cell": cell}
			(tools[key].st as SurfaceTool).append_from(mesh, i, xf)
	for ch in n.get_children():
		_walk(ch, xf, tools)


func _fix_material(mat: Material) -> void:
	if not (mat is BaseMaterial3D):
		return
	var m := mat as BaseMaterial3D
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.roughness = 0.92
	m.metallic = 0.0
	m.metallic_specular = 0.3
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Grayscale(+alpha) PNGs lose alpha / get tinted in the Compatibility renderer: convert to RGBA.
	var tex := m.albedo_texture
	if tex:
		var img := tex.get_image()
		if img and img.get_format() in [Image.FORMAT_L8, Image.FORMAT_LA8]:
			img = img.duplicate()
			img.convert(Image.FORMAT_RGBA8)
			img.generate_mipmaps()
			m.albedo_texture = ImageTexture.create_from_image(img)
	if m.resource_name == "material_104_93_34":
		# road markings: soft semi-transparent decal -> real blending, drawn after the road
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.render_priority = 1
	elif m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.45
