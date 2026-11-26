class_name Fx
## 程序化视觉特效：闪光球、爆炸环、冲击波。无需外部贴图。

## 在 parent 下生成一个膨胀并淡出的光球
static func flash(parent: Node, pos: Vector3, color: Color, radius: float = 0.5, duration: float = 0.2) -> void:
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 12
	m.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(color.r, color.g, color.b, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	m.global_position = pos
	var tw := m.create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "scale", Vector3(1.8, 1.8, 1.8), duration)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration)
	tw.chain().tween_callback(m.queue_free)


## 贴图爆炸：一张素材里的「烟 + 火花」方片，始终面向镜头，边放大边淡出。
## 返回 false 表示没放图（res://textures/fx_explosion.png），调用方可以回退到 flash / ring。
##
## 两个坑：
##   1. billboard 在顶点着色器里会把模型矩阵换成正交相机基，**节点 scale 被丢掉**，
##      所以「放大」不能 tween 节点 scale，只能 tween QuadMesh.size（顶点数据）。
##   2. 淡出用 albedo_color.a × 贴图 alpha，所以 transparency 必须是 ALPHA / ALPHA_SCISSOR，
##      不能用 OPAQUE —— 那个模式下 alpha 直接被忽略。
static func burst(parent: Node, pos: Vector3, slot: String = "fx_explosion",
		size: float = 1.5, duration: float = 0.32) -> bool:
	var tex := TextureLib.get_texture(slot)
	if tex == null or parent == null:
		return false
	var aspect := float(tex.get_height()) / maxf(float(tex.get_width()), 1.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(size * 0.55, size * 0.55 * aspect)

	var mi := MeshInstance3D.new()
	mi.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = tex
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.82, 0.50)
	mat.emission_energy_multiplier = 0.45
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos

	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(quad, "size", Vector2(size, size * aspect), duration)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration)
	tw.chain().tween_callback(mi.queue_free)
	return true


## 水平爆炸环（用于溅射/死亡）
## 序列帧爆炸：逐帧播放 fx_<prefix>_0 … fx_<prefix>_<count-1>（billboard 方片，播完淡出）。
## 帧图必须是**同一画布尺寸**的成套素材，尺寸一致切换帧才不会抖动。
## tint 是加在自发光上的颜色：炮塔的爆炸偏暖橙，冰塔的碎冰要偏冷蓝。
## albedo_tint 会**乘到贴图本身**上（默认白 = 保持素材原色）：素材偏白的特效在亮场景里
## 会糊成一片，这时候用更深的 albedo_tint 把它压出颜色来。
## 返回 false 表示一帧都没找到，调用方自己回退到 burst / flash。
static func burst_seq(parent: Node, pos: Vector3, prefix: String, count: int,
		size: float = 2.5, duration: float = 0.55, fade: float = 0.14,
		tint: Color = Color(1.0, 0.82, 0.50),
		albedo_tint: Color = Color.WHITE) -> bool:
	if parent == null or count <= 0:
		return false
	var frames: Array[Texture2D] = []
	for i in count:
		var tex := TextureLib.get_texture("%s_%d" % [prefix, i])
		if tex != null:
			frames.append(tex)
	if frames.is_empty():
		return false

	var aspect := float(frames[0].get_height()) / maxf(float(frames[0].get_width()), 1.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(size * 0.55, size * 0.55 * aspect)

	var mi := MeshInstance3D.new()
	mi.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = frames[0]
	mat.albedo_color = albedo_tint
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 0.35
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos

	# 逐帧切贴图（并行分支 + 延迟），播完再淡出，避免"啪"地消失
	var step := duration / float(frames.size())
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(1.25, 1.25, 1.25), duration)
	for i in frames.size():
		tw.tween_callback(_set_tex.bind(mat, frames[i])).set_delay(step * float(i))
	tw.tween_property(mat, "albedo_color:a", 0.0, fade).set_delay(maxf(duration - fade, 0.0))
	tw.chain().tween_callback(mi.queue_free)
	return true


static func _set_tex(mat: StandardMaterial3D, tex: Texture2D) -> void:
	mat.albedo_texture = tex


## 水平爆炸环（用于溅射/死亡）
static func ring(parent: Node, pos: Vector3, color: Color, radius: float = 0.6, duration: float = 0.28) -> void:
	var m := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 0.5
	tm.outer_radius = radius
	m.mesh = tm
	m.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(color.r, color.g, color.b, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	m.global_position = pos + Vector3(0.0, 0.15, 0.0)
	var tw := m.create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "scale", Vector3(2.2, 2.2, 2.2), duration)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration)
	tw.chain().tween_callback(m.queue_free)


## 让节点快速闪烁一下（用于水晶受击）。node 需有 material_override。
static func blink(node: Node3D, color: Color = Color(1.0, 0.4, 0.4), times: int = 3, duration: float = 0.12) -> void:
	if node == null or not is_instance_valid(node):
		return
	var tw := node.create_tween()
	for i in range(times):
		tw.tween_callback(func():
			for mi in _meshes(node):
				if mi.material_override is StandardMaterial3D:
					(mi.material_override as StandardMaterial3D).emission_energy_multiplier = 2.0
					(mi.material_override as StandardMaterial3D).emission = color
		)
		tw.tween_interval(duration)
		tw.tween_callback(func():
			for mi in _meshes(node):
				if mi.material_override is StandardMaterial3D:
					(mi.material_override as StandardMaterial3D).emission_energy_multiplier = 0.6
		)
		tw.tween_interval(duration)


static func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


## 同屏飘字上限：每个飘字要建 Label3D + Tween + 字体渲染，无节制会很吃 CPU。
## 计数挂在 parent 的 meta 上，**不是静态变量**：
## 旧的静态计数有个隐患 —— tween 一旦被打断（节点被外部释放 / 树暂停后被丢弃），
## 那次回调就不会执行，计数只增不减，之后整局都再也不飘字（长时间运行后「伤害数字消失」）。
## 挂在 parent 上的计数会随场景一起消失，天然不会残留。
const MAX_NUMBERS := 14
const NUM_META := "dmg_num_live"


## 重新开始（场景重载）时调用。计数已经跟着 parent 走了，这里只是保留旧调用点。
static func reset_counters() -> void:
	pass


## 参数故意不标 Node：回调里拿到的可能是「已释放的实例」，标了类型会在传参时报错
static func _num_live(parent) -> int:
	if parent == null or not is_instance_valid(parent):
		return 0
	return int(parent.get_meta(NUM_META, 0))


static func _num_add(parent, d: int) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	parent.set_meta(NUM_META, maxi(_num_live(parent) + d, 0))


## 3D 伤害 / 治疗飘字：用 Label3D 始终面向镜头，向上飘并淡出
static func damage_number(parent: Node, pos: Vector3, text: String, color: Color, crit: bool = false) -> void:
	if parent == null:
		return
	if _num_live(parent) >= MAX_NUMBERS:
		return
	_num_add(parent, 1)
	var l := Label3D.new()
	l.text = text
	l.font_size = 48 if crit else 30
	l.pixel_size = 0.02
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.outline_size = 10
	l.outline_modulate = Color(0.0, 0.0, 0.0, 0.7)
	parent.add_child(l)
	l.global_position = pos + Vector3((randf() - 0.5) * 0.5, 0.0, (randf() - 0.5) * 0.5)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y + 1.2, 0.55)
	tw.tween_property(l, "modulate:a", 0.0, 0.55)
	l.set_meta("dmg_owner", parent)   # 回调里要还计数，防止 parent 已释放时踩空
	tw.chain().tween_callback(func():
		_num_add(l.get_meta("dmg_owner"), -1)
		l.queue_free()
	)
