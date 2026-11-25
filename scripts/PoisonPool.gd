extends Node3D
class_name PoisonPool
## 毒瓶塔砸出来的毒液池。
##
## 作用：落地后停留 POISON_POOL_TIME 秒，期间每 POISON_TICK 秒给圈内敌人续一次中毒
## （Enemy.apply_poison：每 0.5 秒结算一跳、**无视护甲**，所以对重甲 / 冰甲单位特别有效）。
## 每次只续 POISON_REFRESH 秒，走出去毒也就慢慢退了，不会隔着半张地图一直掉血。
##
## 视觉：默认是程序化的「一滩绿」——深色底 + 亮芯 + 一圈大小不一的液滴 + 会鼓泡的亮斑；
## 如果放了贴图 textures/fx_poison_0…n，就改用序列帧（按存在时间走完一遍，不循环）。
## 这一套和 MudPit 保持一致，两者的素材接口可以互换。

const MAX_FRAMES := 8
const FADE_TIME := 0.45

var radius: float = 1.5
var dps: float = 15.0
var life: float = 4.2

var _age := 0.0
var _scan := 0.0
var _fading := false
var _frames: Array[Texture2D] = []
var _mat: StandardMaterial3D
var _blobs: Array[MeshInstance3D] = []
var _bubble_t := 0.0


## pos 是毒池的**地面**坐标（不是敌人身体中心），由子弹算好 SURFACE_Y 之上的高度传进来。
func setup(pos: Vector3, r: float, dps_per_sec: float, time: float = -1.0) -> void:
	radius = maxf(r, 0.5)
	dps = maxf(dps_per_sec, 0.0)
	life = float(TowerData.POISON_POOL_TIME) if time <= 0.0 else time
	global_position = pos
	_build()
	# 落地那一下立刻生效：刚被砸中的敌人不能白站在池子里
	_scan_enemies()


func _build() -> void:
	for i in MAX_FRAMES:
		var tex := TextureLib.get_texture("fx_poison_%d" % i)
		if tex != null:
			_frames.append(tex)

	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.emission_enabled = true
	_mat.emission = Color(0.42, 0.95, 0.25)
	_mat.emission_energy_multiplier = 0.35

	if not _frames.is_empty():
		var aspect := float(_frames[0].get_height()) / maxf(float(_frames[0].get_width()), 1.0)
		var quad := QuadMesh.new()
		quad.size = Vector2(radius * 2.0, radius * 2.0 * aspect)
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		_mat.albedo_texture = _frames[0]
		_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.92)
		mi.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	else:
		_build_procedural()
		_mat.albedo_color = Color(0.30, 0.86, 0.22, 0.80)


## 没有素材时的程序化毒滩：底盘 + 亮芯 + 一圈液滴 + 会鼓的泡。
## 形状故意做成不规则 —— 正圆看起来像「范围指示圈」，不像地上的一滩东西。
func _build_procedural() -> void:
	_mat.albedo_color = Color(0.30, 0.86, 0.22, 0.80)
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 0.02
	cm.radial_segments = 22
	disc.mesh = cm
	disc.material_override = _mat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)

	# 亮芯：一小块更亮的绿，让整滩毒有「正在冒泡」的中心
	var core := MeshInstance3D.new()
	var cm2 := CylinderMesh.new()
	cm2.top_radius = radius * 0.58
	cm2.bottom_radius = radius * 0.58
	cm2.height = 0.022
	cm2.radial_segments = 18
	core.mesh = cm2
	var cmat := StandardMaterial3D.new()
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cmat.albedo_color = Color(0.58, 1.0, 0.32, 0.72)
	cmat.emission_enabled = true
	cmat.emission = Color(0.60, 1.0, 0.35)
	cmat.emission_energy_multiplier = 0.55
	cmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	core.material_override = cmat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.position.y = 0.004
	add_child(core)
	_blobs.append(core)

	# 边缘液滴：位置/大小都用固定种子算，重开一局也能得到同样的一滩
	var rng := RandomNumberGenerator.new()
	for i in 9:
		rng.seed = hash(global_position) + i * 7919
		var a := TAU * float(i) / 9.0 + rng.randf_range(-0.25, 0.25)
		var rr := radius * rng.randf_range(0.72, 1.06)
		var blob := MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = radius * rng.randf_range(0.16, 0.30)
		bm.height = bm.radius * 0.55
		bm.radial_segments = 10
		bm.rings = 5
		blob.mesh = bm
		blob.material_override = _mat
		blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		blob.position = Vector3(cos(a) * rr, 0.012, sin(a) * rr)
		add_child(blob)
		_blobs.append(blob)


func _process(delta: float) -> void:
	if not GameState.running:
		return

	_age += delta
	_bubble_t += delta

	# 序列帧正好铺满整个存在时间（不循环）：最后一帧停在原地淡出，像毒液慢慢渗进地里
	if _frames.size() > 1:
		var step := life / float(_frames.size())
		var idx := mini(int(_age / step), _frames.size() - 1)
		if _mat.albedo_texture != _frames[idx]:
			_mat.albedo_texture = _frames[idx]

	# 鼓泡：整体轻微一张一缩，静止的绿盘子看起来太「假」
	if not _frames.is_empty():
		pass
	else:
		var k := 1.0 + sin(_bubble_t * 3.2) * 0.04
		for i in range(1, _blobs.size()):
			var b: MeshInstance3D = _blobs[i]
			var ph := sin(_bubble_t * (2.4 + 0.3 * i) + i) * 0.14
			b.scale = Vector3(1.0 + ph, 1.0, 1.0 + ph)
		if _blobs.size() > 0:
			_blobs[0].scale = Vector3(k, 1.0, k)

	_scan += delta
	if _scan >= float(TowerData.POISON_TICK):
		_scan = 0.0
		_scan_enemies()

	if not _fading and _age >= life - FADE_TIME:
		_fading = true
		var tw := create_tween()
		tw.tween_property(_mat, "albedo_color:a", 0.0, FADE_TIME)
		tw.tween_callback(queue_free)

	if _age >= life + 0.2:
		queue_free()


## 给范围内的敌人续中毒（只算水平距离：敌人和毒池都在地面上）。
## 用 apply_poison 而不是直接扣血 —— 中毒是「无视护甲」的独立乘区，
## 这样毒瓶塔对重甲 / 带冰甲的怪才有明确优势，也不会和别的塔的直伤口径混在一起。
func _scan_enemies() -> void:
	if dps <= 0.0:
		return
	var r2 := radius * radius
	var refresh := float(TowerData.POISON_REFRESH)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e):
			continue
		var dx: float = e.global_position.x - global_position.x
		var dz: float = e.global_position.z - global_position.z
		if dx * dx + dz * dz > r2:
			continue
		if e.has_method("apply_poison"):
			e.apply_poison(dps, refresh)
