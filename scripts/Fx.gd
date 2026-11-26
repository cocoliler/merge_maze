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


## 两点之间的一道发光「曳光」（箭塔离弦时的箭轨 / 箭矢飞行拖尾）。
##
## 为什么不用 Line3D：Godot 没有内置的「世界空间线段」渲染，线宽靠手搓两个三角形最省。
## 这里把线段朝**镜头方向**张开成一条 ribbon —— 好处是从俯视角看永远有宽度，
## 不会像细圆柱那样在某个角度缩成一根看不见的针。
##
## glow：在内芯外面再套一层更宽的柔光。白天场景很亮，一道细线会被背景吃掉，
##       外圈柔光才让曳光「看得见」；传 0 表示不要外圈。
## alpha：整体不透明度。飞行拖尾要更淡（0.3~0.5），枪口曳光要更亮（0.9 以上）。
static func tracer(parent: Node, from: Vector3, to: Vector3, color: Color,
		width: float = 0.08, duration: float = 0.14, glow: float = 0.0,
		alpha: float = 0.95) -> bool:
	if parent == null:
		return false
	if not _ribbon(parent, from, to, color, width, duration, alpha, 1.6):
		return false
	if glow > 0.0:
		# 外圈：更宽、更淡、稍短命 —— 中心那道亮线才是主体，外圈只负责「在亮背景里也看得见」
		_ribbon(parent, from, to, color, glow, duration * 0.95, alpha * 0.34, 0.9)
	return true


## tracer 的底层实现：手搓一条正对镜头的发光带子。
static func _ribbon(parent: Node, from: Vector3, to: Vector3, color: Color,
		width: float, duration: float, alpha: float, energy: float) -> bool:
	var dir := to - from
	if dir.length_squared() < 0.000001:
		return false
	var view := _cam_pos(parent) - (from + to) * 0.5
	var side := dir.cross(view)
	if side.length_squared() < 0.0000001:
		side = dir.cross(Vector3(0.0, 1.0, 0.0))
	if side.length_squared() < 0.0000001:
		return false
	side = side.normalized() * maxf(width, 0.005) * 0.5

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.add_vertex(from - side)
	st.add_vertex(to - side)
	st.add_vertex(to + side)
	st.add_vertex(from - side)
	st.add_vertex(to + side)
	st.add_vertex(from + side)
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return false

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(color.r, color.g, color.b, clampf(alpha, 0.0, 1.0))
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# 加法混合：普通 alpha 混白会被明亮的草地/土路背景吃掉，加法才「自己会亮」
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 只写深度判断、不写深度：光线横穿敌人时不会被「切」成两截
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration)
	tw.chain().tween_callback(mi.queue_free)
	return true


## 火星：从 pos 朝 dir 喷出一把小球，各自飞散、缩小、淡出。
static func sparks(parent: Node, pos: Vector3, dir: Vector3, color: Color,
		count: int = 5, spread: float = 0.55, speed: float = 4.0,
		size: float = 0.18, life: float = 0.16) -> void:
	if parent == null or count <= 0:
		return
	var d := dir.normalized() if dir.length_squared() > 0.000001 else Vector3.UP
	for i in count:
		var s := size * randf_range(0.55, 1.25)
		var sm := SphereMesh.new()
		sm.radius = s
		sm.height = s * 2.0
		sm.radial_segments = 6
		sm.rings = 3
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(color.r, color.g, color.b, 0.95)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.5
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		mi.global_position = pos
		# 把发射方向绕一根随机轴转一个随机角度，就得到一个锥形的散开
		var axis := d.cross(Vector3(randf() * 2.0 - 1.0, randf() * 2.0 - 1.0, randf() * 2.0 - 1.0))
		if axis.length_squared() < 0.000001:
			axis = Vector3.UP
		var v := d.rotated(axis.normalized(), randf_range(-spread, spread))
		var l := life * randf_range(0.7, 1.2)
		var tw := mi.create_tween()
		tw.set_parallel(true)
		tw.tween_property(mi, "global_position", pos + v * speed * l, l).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "scale", Vector3(0.25, 0.25, 0.25), l)
		tw.tween_property(mat, "albedo_color:a", 0.0, l)
		tw.chain().tween_callback(mi.queue_free)


static func _cam_pos(parent: Node) -> Vector3:
	var vp := parent.get_viewport()
	if vp == null:
		return Vector3.ZERO
	var cam := vp.get_camera_3d()
	if cam == null:
		return Vector3.ZERO
	return cam.global_position


## 冰雾拖尾：踩进霜环冰雾的敌人，脚下会不断留下这样一摊霜迹。
##
## 和 burst / flash 的区别：**不 billboard**。拖尾是贴在地面上的痕迹，竖起来会像插了面旗子，
## 所以这里用「QuadMesh 绕 X 轴 -90° 躺平 + 只改节点缩放」，不碰 billboard 那套。
## pos 传敌人的世界坐标即可，高度在这里统一抬到地面上方（高于路面与桥顶）。
## 两张帧随机取一张，连续铺十几摊时不会看出是同一张图在重复。
static func frost_puff(parent: Node, pos: Vector3, size: float = 1.4,
		duration: float = 0.55) -> bool:
	if parent == null:
		return false
	var tex := TextureLib.get_texture("fx_frost_trail_%d" % (randi() % 2))
	if tex == null:
		tex = TextureLib.get_texture("fx_frost_trail_0")
	if tex == null:
		return false
	var aspect := float(tex.get_height()) / maxf(float(tex.get_width()), 1.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size * aspect)

	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.rotation_degrees = Vector3(-90.0, randf() * 360.0, 0.0)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 贴地覆盖层不写深度：免得和路面 / 冰雾抢 Z
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.albedo_texture = tex
	mat.albedo_color = Color(0.74, 0.93, 1.0, 0.90)
	mat.emission_enabled = true
	mat.emission = Color(0.60, 0.88, 1.0)
	mat.emission_energy_multiplier = 0.18
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	# 雾铺在 1.00，这里再高一点，免得和雾、路面抢深度
	mi.global_position = Vector3(pos.x, pos.y + 0.22, pos.z)

	# 一边慢慢摊开一边淡出：静止不动的霜迹看着像贴纸
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(1.18, 1.18, 1.18), duration)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration)
	tw.chain().tween_callback(mi.queue_free)
	return true


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
