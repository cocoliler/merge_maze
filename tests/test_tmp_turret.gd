extends Node
## 临时诊断：确认重新生成的 GLB 在 Godot 里到底有没有 Turret 节点。


func test_turret_nodes() -> void:
	for p in ["res://models/towers/tower_cannon_l3.glb",
			"res://models/towers/tower_sniper_l3.glb",
			"res://models/towers/tower_bounce_l2.glb",
			"res://models/towers/tower_arrow_l1.glb"]:
		var ps := load(p) as PackedScene
		if ps == null:
			print("TMP ", p, " -> LOAD FAILED")
			continue
		var n := ps.instantiate()
		print("TMP ", p, " root=", n.name, " (", n.get_class(), ") children=[", _names(n), "]")
		print("TMP   find_child(Turret) = ", n.find_child("Turret", true, false))
		n.free()


func _names(n: Node) -> String:
	var out := PackedStringArray()
	for c in n.get_children():
		out.append("%s<%s>" % [c.name, c.get_class()])
		var sub := _names(c)
		if sub != "":
			out.append(sub)
	return ", ".join(out)
