extends RefCounted
class_name SnowkingModel
## 雪人王的 3D 造型（纯程序化几何）。尺寸以 s（EnemyData 的 size）为基准，底面贴在 y = 0。
##
## 为什么不用 textures/enemy_snowking.png：那张原画就是标准的「三球雪人 + 树枝手 + 胡萝卜鼻子」，
## 立成 billboard 方片在 3D 场景里始终是一张纸片，镜头一转就露馅。这里改成真 3D 造型，
## 并且**刻意做了改造**，不和原画一一对应：
##   冰晶王冠（原画没有）、六棱冰甲肩片、胸口发光冰核、冰蓝发光眼 + 斜眉、
##   冰晶腰带、单手托着一颗蓄力雪球（呼应它的雪球技能）。
## 主雪体材质通过 meta("body_mat") 交给 Enemy，用于减速 / 狂暴染色。

## 雪体别用纯白：霜渊的雪地本身就接近纯白，纯白雪人只剩一团过曝的白斑，
## 压一点亮度、留一点蓝，才靠明度差和冰蓝描边立起来。
const BODY_COLOR := Color(0.85, 0.90, 1.0)
const ICE_COLOR := Color(0.44, 0.79, 1.0)
const DEEP_ICE := Color(0.28, 0.60, 0.96)
const WOOD_COLOR := Color(0.31, 0.22, 0.15)
const NOSE_COLOR := Color(0.96, 0.55, 0.18)


static func build(s: float, body_mat: StandardMaterial3D = null) -> Node3D:
	var root := Node3D.new()
	root.name = "SnowkingBody"
	root.set_meta("body_mat", body_mat if body_mat != null else _make_mat(BODY_COLOR, 0.85, BODY_COLOR, 0.10))

	var snow: Material = root.get_meta("body_mat")
	var ice := _make_mat(ICE_COLOR, 0.28, Color(0.28, 0.70, 1.0), 0.75)
	var deep := _make_mat(DEEP_ICE, 0.20, Color(0.24, 0.62, 1.0), 1.25)
	var wood := _make_mat(WOOD_COLOR, 0.90)
	var nose := _make_mat(NOSE_COLOR, 0.60, Color(0.42, 0.16, 0.04), 0.20)
	# 眼睛要「暗」才在白雪上看得见：自发光只给一点冷光，纯亮青色会和冰蓝装饰糊在一起
	var eye := _make_mat(Color(0.05, 0.09, 0.16), 0.15, Color(0.45, 0.85, 1.0), 0.55)

	# 三层雪球：底大上小，中间一层用扁球，远看是「雪人」但不是三个正球。
	# 头必须比中球**多露出来一截**（中球顶 0.96s、头球底 0.775s）：贴太近会融成一坨，
	# 远看就只剩「白球 + 王冠」，五官也全被埋进球面里。
	_ball(root, snow, Vector3(0.0, 0.35 * s, 0.0), 0.41 * s, 0.92)
	_ball(root, snow, Vector3(0.0, 0.70 * s, 0.0), 0.28 * s, 0.93)
	_ball(root, snow, Vector3(0.0, 1.02 * s, 0.0), 0.25 * s, 1.00)

	# 冰晶腰带（把中段和下段隔开，替代原画的「围巾」）
	var belt := MeshInstance3D.new()
	var bm := TorusMesh.new()
	bm.inner_radius = 0.245 * s
	bm.outer_radius = 0.315 * s
	bm.rings = 24
	bm.ring_segments = 6
	belt.mesh = bm
	belt.material_override = deep
	belt.position.y = 0.60 * s
	belt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(belt)

	# 眼睛 + 斜眉：原画是两颗煤球，这里换成会发光的冰蓝眼，压出一点威严。
	# z 必须落在头球表面**外面**（头半径 0.25s，表面在该高度约 0.23s），
	# 只埋一半就会像「没有眼睛」——第一版就是被球面吞掉了。
	for i in range(2):
		var sx: float = 1.0 if i == 0 else -1.0
		_ball(root, eye, Vector3(0.10 * s * sx, 1.055 * s, 0.235 * s), 0.055 * s, 1.0)
		var brow := MeshInstance3D.new()
		var bmm := BoxMesh.new()
		bmm.size = Vector3(0.15 * s, 0.034 * s, 0.05 * s)
		brow.mesh = bmm
		brow.material_override = deep
		brow.position = Vector3(0.10 * s * sx, 1.13 * s, 0.245 * s)
		brow.rotation.z = -0.38 * sx
		brow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(brow)

	# 胡萝卜鼻子：锥尖朝 +Z（敌人正面），比原画更短更粗；根部埋进头里一点才自然
	var carrot := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.062 * s
	cm.height = 0.23 * s
	cm.radial_segments = 7
	carrot.mesh = cm
	carrot.material_override = nose
	carrot.rotation_degrees.x = 90.0
	carrot.position = Vector3(0.0, 1.015 * s, 0.33 * s)
	root.add_child(carrot)

	# 嘴：三颗小冰粒，浅浅一道弧
	for i in range(3):
		var t := float(i) - 1.0
		_ball(root, deep, Vector3(0.05 * s * t, 0.935 * s - absf(t) * 0.012 * s, 0.235 * s), 0.021 * s, 1.0)

	# 冰晶王冠：一圈冰棱 + 底座环，是「王」的识别点，也是改造点
	var band := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.16 * s
	tm.outer_radius = 0.225 * s
	tm.rings = 24
	tm.ring_segments = 6
	band.mesh = tm
	band.material_override = ice
	band.position.y = 1.20 * s
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(band)
	for i in range(5):
		var ang := TAU * float(i) / 5.0
		var spike := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = 0.0
		sm.bottom_radius = 0.048 * s
		sm.height = 0.22 * s
		sm.radial_segments = 5
		spike.mesh = sm
		spike.material_override = ice
		spike.position = Vector3(cos(ang) * 0.195 * s, 1.285 * s, sin(ang) * 0.195 * s)
		# 冰棱向外倾：把圆锥的 +Y 轴转向前方的径向
		var axis := Vector3(sin(ang), 0.0, -cos(ang))
		spike.basis = Basis(axis, 0.26)
		root.add_child(spike)

	# 六棱冰甲肩片：给雪人加装备感，原画是光膀子。
	# 做成**横躺的小圆盘**扣在肩头：立着的高锥会从正面包住中球，看起来像两只蓝爪子捂脸。
	for i in range(2):
		var sx2: float = 1.0 if i == 0 else -1.0
		var pad := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.06 * s
		pm.bottom_radius = 0.155 * s
		pm.height = 0.075 * s
		pm.radial_segments = 6
		pad.mesh = pm
		pad.material_override = ice
		pad.position = Vector3(0.305 * s * sx2, 0.875 * s, 0.0)
		pad.rotation.z = -1.0 * sx2
		root.add_child(pad)

	# 背部冰刺：玩家看到的多数是背影（敌人背对镜头走向基地），
	# 背影也得有辨识度 —— 三道冰棱顺着脊线长出来。
	for i in range(3):
		var by := (0.66 + 0.11 * float(i)) * s
		var fin := MeshInstance3D.new()
		var fm := CylinderMesh.new()
		fm.top_radius = 0.0
		fm.bottom_radius = 0.045 * s
		fm.height = 0.22 * s
		fm.radial_segments = 4
		fin.mesh = fm
		fin.material_override = deep
		fin.position = Vector3(0.0, by, -0.24 * s)
		fin.rotation_degrees.x = -55.0
		fin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(fin)

	# 胸口冰核：两颗四棱锥对顶，呼吸式的技能光源。
	# z 要顶出中球表面（该高度处球面 z ≈ 0.26s），否则整颗核会埋进雪里看不见。
	var core := Node3D.new()
	core.name = "Core"
	core.position = Vector3(0.0, 0.77 * s, 0.285 * s)
	root.add_child(core)
	for i in range(2):
		var sy: float = 1.0 if i == 0 else -1.0
		var cone := MeshInstance3D.new()
		var cm2 := CylinderMesh.new()
		cm2.top_radius = 0.0
		cm2.bottom_radius = 0.10 * s
		cm2.height = 0.19 * s
		cm2.radial_segments = 4
		cone.mesh = cm2
		cone.material_override = deep
		cone.position.y = 0.095 * sy
		if sy < 0.0:
			cone.rotation.z = PI
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		core.add_child(cone)

	# 树枝手臂：左手垂着、右手抬起托着蓄力雪球（不对称，避免「对称雪人」的呆板）
	_branch(root, wood, Vector3(-0.30 * s, 0.74 * s, 0.0), Vector3(-0.60 * s, 0.66 * s, 0.06 * s), 0.030 * s)
	_branch(root, wood, Vector3(-0.60 * s, 0.66 * s, 0.06 * s), Vector3(-0.68 * s, 0.80 * s, 0.06 * s), 0.020 * s)
	_branch(root, wood, Vector3(0.30 * s, 0.80 * s, 0.0), Vector3(0.62 * s, 1.04 * s, 0.08 * s), 0.030 * s)
	_ball(root, deep, Vector3(0.66 * s, 1.16 * s, 0.10 * s), 0.12 * s, 1.0)

	return root


static func _make_mat(albedo: Color, roughness: float, emission: Color = Color.BLACK, energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = roughness
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = energy
	return m


static func _ball(parent: Node3D, mat: Material, pos: Vector3, radius: float, squash: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0 * squash
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _branch(parent: Node3D, mat: Material, a: Vector3, b: Vector3, radius: float) -> void:
	var dir := b - a
	var length := dir.length()
	if length <= 0.0001:
		return
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius * 0.65
	cm.bottom_radius = radius
	cm.height = length
	cm.radial_segments = 6
	mi.mesh = cm
	mi.material_override = mat
	mi.position = (a + b) * 0.5
	var up := dir / length
	var axis := Vector3.UP.cross(up)
	if axis.length() > 0.0001:
		mi.basis = Basis(axis.normalized(), Vector3.UP.angle_to(up))
	elif up.y < 0.0:
		mi.basis = Basis(Vector3.RIGHT, PI)
	parent.add_child(mi)
