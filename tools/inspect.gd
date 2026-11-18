extends SceneTree
func _init():
	var s = load("res://assets/city/city.glb").instantiate()
	root.add_child(s)
	await process_frame
	var total := AABB(); var first := true
	var cats := {}
	var big := []
	for m in s.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = m.global_transform * m.get_aabb()
		if first: total = a; first = false
		else: total = total.merge(a)
		var n: String = m.get_parent().name
		var key = n.split("_mdl")[0]
		cats[key] = cats.get(key, 0) + 1
		big.append([a.size.length(), n, a])
	print("TOTAL ", total)
	big.sort_custom(func(x,y): return x[0] > y[0])
	for i in 25: print(big[i])
	var ks = cats.keys(); ks.sort()
	print(ks.size(), " groups")
	var line = ""
	for k in ks: line += "%s:%d " % [k, cats[k]]
	print(line.substr(0, 3000))
	quit()
