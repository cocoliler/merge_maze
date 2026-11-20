extends Node3D
class_name MudPit
## 震地雷（炮塔变异）命中后在地面留下的泥潭。
##
## 作用：持续 MUD_TIME 秒，踩进范围内的敌人被减速 MUD_SLOW；走出泥潭后
## 减速还会残留一小段（施加时给的是短时长），不会一出圈就瞬间恢复。
## 注意这层减速是**额外乘区**（Enemy.apply_extra_slow）：和冰塔的减速乘算，
## 冰塔 -22% + 泥潭 -16% = 0.78 × 0.84，不会互相覆盖。
## 视觉：textures/fx_mud_0…6 的 7 帧在 life 秒内正好走完一遍（不循环），
## 末尾淡出；没放图就退回一个半透明泥盘。

const FRAMES := 7
const FADE_TIME := 0.3          # 干涸前的淡出时间
const SCAN_INTERVAL := 0.1      # 扫描敌人的间隔（别每帧遍历全场）
const SLOW_TIME := 0.3          # 每次施加的减速时长：离开泥潭这么久后恢复

var radius: float = 1.7
var life: float = 1.5
var slow: float = 0.16

var _age := 0.0
var _scan := 0.0
var _mat: StandardMaterial3D
var _frames: Array[Texture2D] = []
var _fading := false


## 由子弹在命中点调用。pos 是泥潭的**地面**坐标（不是敌人身体中心）。
func setup(pos: Vector3) -> void:
	radius = float(TowerData.MUD_RADIUS)
	life = float(TowerData.MUD_TIME)
	slow = float(TowerData.MUD_SLOW)
	global_position = pos
	_build()
	# 落地那一下立刻生效，别让刚被命中的敌人白走出泥潭
	_scan_enemies()


func _build() -> void:
	for i in FRAMES:
		var tex := TextureLib.get_texture("fx_mud_%d" % i)
		if tex != null:
			_frames.append(tex)

	var mi := MeshInstance3D.new()
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.emission_enabled = true
	_mat.emission = Color(0.85, 0.55, 0.25)
	_mat.emission_energy_multiplier = 0.22

	if not _frames.is_empty():
		var tex := _frames[0]
		var aspect := float(tex.get_height()) / maxf(float(tex.get_width()), 1.0)
		var quad := QuadMesh.new()
		quad.size = Vector2(radius * 2.0, radius * 2.0 * aspect)
		mi.mesh = quad
		_mat.albedo_texture = tex
		# 平铺地面：QuadMesh 默认站在 XY 平面、法线朝 +Z，绕 X 轴转 -90° 后朝上
		mi.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	else:
		var cyl := CylinderMesh.new()
		cyl.top_radius = radius
		cyl.bottom_radius = radius
		cyl.height = 0.04
		cyl.radial_segments = 24
		mi.mesh = cyl
		_mat.albedo_color = Color(0.34, 0.23, 0.12, 0.65)

	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _process(delta: float) -> void:
	if not GameState.running:
		return

	_age += delta

	# 7 帧正好铺满整个存在时间（不循环）：最后一帧停在原地淡出，像泥潭慢慢干涸
	if _frames.size() > 1:
		var step := life / float(_frames.size())
		var idx := mini(int(_age / step), _frames.size() - 1)
		if _mat.albedo_texture != _frames[idx]:
			_mat.albedo_texture = _frames[idx]

	_scan += delta
	if _scan >= SCAN_INTERVAL:
		_scan = 0.0
		_scan_enemies()

	if not _fading and _age >= life - FADE_TIME:
		_fading = true
		var tw := create_tween()
		tw.tween_property(_mat, "albedo_color:a", 0.0, FADE_TIME)
		tw.tween_callback(queue_free)

	if _age >= life + 0.2:
		queue_free()


## 给范围内的敌人挂减速（只算水平距离，敌人和泥潭都在地面上）
func _scan_enemies() -> void:
	if slow <= 0.0:
		return
	var r2 := radius * radius
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e):
			continue
		var dx: float = e.global_position.x - global_position.x
		var dz: float = e.global_position.z - global_position.z
		if dx * dx + dz * dz > r2:
			continue
		# 走「额外减速乘区」：和冰塔之类的减速**乘算**，不是取更强
		if e.has_method("apply_extra_slow"):
			e.apply_extra_slow(slow, SLOW_TIME)
		elif e.has_method("apply_slow"):
			e.apply_slow(slow, SLOW_TIME)
