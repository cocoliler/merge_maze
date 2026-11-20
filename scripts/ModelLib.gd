extends RefCounted
class_name ModelLib
## Kenney 3D 模型工具：加载 GLB、算整体高度、给模型换色。
## 模型统一放在 res://models/kenney/，共享一张 colormap.png 调色板贴图。

const DIR := "res://models/kenney/"

## 塔 / 地面瓦片的统一缩放：Kenney 模型是 1×1 单位，我们棋盘每格 2 单位
const SCALE := 2.0

static var _scene_cache: Dictionary = {}
static var _path_cache: Dictionary = {}   # 完整路径 -> PackedScene / null（外挂模型）


## 加载并实例化模型，返回根 Node3D
static func instance(model: String) -> Node3D:
	var p: PackedScene = _scene_cache.get(model)
	if p == null:
		p = load(DIR + model + ".glb")
		if p == null:
			push_error("ModelLib: 找不到模型 " + model)
			return null
		_scene_cache[model] = p
	return p.instantiate()


## 返回实例在 scale=1 下的整体高度（考虑模型内部嵌套子节点的 y 偏移，
## 但忽略根节点自身的 position——那是调用方用来做堆叠偏移的）。
static func height_of(n: Node3D) -> float:
	if n == null:
		return 0.0
	return _height_from(n, 0.0)


## 按「完整 res:// 路径」加载模型（用于 res://models/enemies/ 这类外挂目录）。
## 文件不存在返回 null，调用方自己回退到程序化外观。
## 结果按路径缓存：没放模型时只查一次磁盘，不会每刷一只怪就扫一遍目录。
static func instance_path(path: String) -> Node3D:
	if _path_cache.has(path):
		var cached = _path_cache[path]
		if cached == null:
			return null
		return (cached as PackedScene).instantiate()
	var p = null
	if ResourceLoader.exists(path):
		p = load(path)
	if p is PackedScene:
		_path_cache[path] = p
		return (p as PackedScene).instantiate()
	_path_cache[path] = null
	return null


## 整个模型（含所有子节点变换）在根节点坐标系下的包围盒：
## 用来把「随便找来的模型」自动缩放、居中、贴地。
static func aabb_of(root: Node3D) -> AABB:
	if root == null:
		return AABB()
	var out := AABB()
	var first := true
	for mi in _all_meshes(root):
		var box: AABB = _rel_transform(root, mi) * mi.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out


## 从 root 到 target 的相对变换（root 自身的变换不计入）
static func _rel_transform(root: Node, target: Node) -> Transform3D:
	var t := Transform3D()
	var c: Node = target
	while c != null and c != root:
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t


static func _height_from(n: Node, acc_y: float) -> float:
	var m := acc_y
	if n is MeshInstance3D:
		var aabb := (n as MeshInstance3D).get_aabb()
		m = acc_y + aabb.position.y + aabb.size.y
	for c in n.get_children():
		var cy := acc_y
		if c is Node3D:
			cy = acc_y + (c as Node3D).position.y
		m = maxf(m, _height_from(c, cy))
	return m


## 给模型所有材质叠加一个颜色 tint（用于给冰塔上蓝色等）。
## 用 material_override 实现，只影响当前实例，不污染共享材质。
static func tint(n: Node3D, color: Color) -> void:
	if n == null:
		return
	for mi in _all_meshes(n):
		var mesh: Mesh = mi.mesh
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var mat := mi.material_override
		if mat == null:
			mat = mesh.surface_get_material(0)
		if mat is StandardMaterial3D:
			var m2 := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			m2.albedo_color = color
			mi.material_override = m2


static func _all_meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n as MeshInstance3D)
	for c in n.get_children():
		out.append_array(_all_meshes(c))
	return out
