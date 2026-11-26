extends RefCounted
class_name PineBossModel
## 霜松（第二张图第 5 波小首领）的 3D 造型。尺寸以 s（EnemyData 的 size）为基准，底面贴在 y = 0。
##
## 原型是一棵「会走路的松树怪」：三层树冠 + 树枝手臂 + 树根脚。改成 3D 后做了这些改造，
## 不和原图一一对应：
##   树顶冰晶（原图是树尖）、深绿到墨绿的分层树冠、红色发光眼 + 獠牙、
##   二号树冠上的雪块与金色装饰球、树根分开成四只「脚」。
## 主树冠材质通过 meta("body_mat") 交给 Enemy，用于减速 / 中毒染色。

const NEEDLE := Color(0.13, 0.40, 0.27)
const NEEDLE_LIGHT := Color(0.18, 0.48, 0.32)
const WOOD := Color(0.30, 0.20, 0.13)
const SNOW := Color(0.90, 0.95, 1.0)
const GOLD := Color(1.0, 0.80, 0.28)
const ICE := Color(0.55, 0.88, 1.0)


static func build(s: float, body_mat: StandardMaterial3D = null) -> Node3D:
	var root := Node3D.new()
	root.name = "PineBossBody"
	root.set_meta("body_mat", body_mat if body_mat != null else _make_mat(NEEDLE, 0.85, Color(0.10, 0.34, 0.22), 0.12))

	var needle: Material = root.get_meta("body_mat")
	var needle_light := _make_mat(NEEDLE_LIGHT, 0.80, Color(0.12, 0.38, 0.25), 0.10)
	var wood := _make_mat(WOOD, 0.90)
	var snow := _make_mat(SNOW, 0.70, Color(0.60, 0.80, 1.0), 0.10)
	var gold := _make_mat(GOLD, 0.35, Color(1.0, 0.68, 0.20), 0.80)
	var ice := _make_mat(ICE, 0.20, Color(0.40, 0.80, 1.0), 1.30)
	var eye := _make_mat(Color(0.55, 0.04, 0.04), 0.15, Color(1.0, 0.10, 0.08), 2.20)
	var fang := _make_mat(Color(0.94, 0.92, 0.84), 0.45)

	# 树干：露在树冠下面的那一截
	_cyl(root, wood, Vector3(0.0, 0.30 * s, 0.0), 0.11 * s, 0.58 * s)

	# 树根脚：四根短柱从树干底部向外撑开，走路时像四只爪子
	for i in range(4):
		var ang := TAU * float(i) / 4.0 + PI * 0.25
		var foot := Vector3(cos(ang) * 0.30 * s, 0.02 * s, sin(ang) * 0.30 * s)
		_limb(root, wood, Vector3(cos(ang) * 0.09 * s, 0.16 * s, sin(ang) * 0.09 * s), foot, 0.055 * s)

	# 三层树冠：底层最宽，往上收；中层用略亮的绿，分层才看得出来
	_cone(root, needle, 0.50 * s, 0.62 * s, 0.52 * s)
	_cone(root, needle_light, 0.88 * s, 0.46 * s, 0.46 * s)
	_cone(root, needle, 1.20 * s, 0.32 * s, 0.42 * s)

	# 树顶冰晶：两颗四棱锥对顶（原图是树尖，换成冰晶更符合霜渊）
	_cone(root, ice, 1.47 * s, 0.10 * s, 0.20 * s, Vector3(0.0, PI * 0.25, 0.0))
	_cone(root, ice, 1.38 * s, 0.10 * s, 0.14 * s, Vector3(PI, PI * 0.25, 0.0))

	# 红眼 + 獠牙：树冠正面，必须顶出锥面（该高度锥面 z ≈ 0.21s）
	for i in range(2):
		var sx: float = 1.0 if i == 0 else -1.0
		_ball(root, eye, Vector3(0.105 * s * sx, 0.92 * s, 0.215 * s), 0.062 * s, 1.0)
		cone_fang(root, fang, Vector3(0.115 * s * sx, 0.80 * s, 0.225 * s), 0.034 * s, 0.11 * s)

	# 树枝手臂：肩 → 肘 → 手，两只都往上举，手端再分三根长枝。
	# 肩要扎进树冠里（0.24s 处正好被底层树冠盖住），否则看起来像两根扫把悬在树旁边。
	for i in range(2):
		var sx2: float = 1.0 if i == 0 else -1.0
		var shoulder := Vector3(0.24 * s * sx2, 0.74 * s, 0.02 * s)
		var elbow := Vector3(0.52 * s * sx2, 1.02 * s, 0.05 * s)
		var hand := Vector3(0.62 * s * sx2, 1.28 * s, 0.07 * s)
		_limb(root, wood, shoulder, elbow, 0.048 * s)
		_limb(root, wood, elbow, hand, 0.034 * s)
		# 手腕关节球：没有它，手臂看起来像两截断开的棍子
		_ball(root, wood, hand, 0.055 * s, 1.0)
		for j in range(3):
			var spread := (float(j) - 1.0)
			var tip := hand + Vector3(spread * 0.20 * s * sx2, 0.26 * s - absf(spread) * 0.06 * s,
				spread * 0.22 * s)
			_limb(root, wood, hand, tip, 0.020 * s)

	# 雪块 + 金色装饰球：贴着各层锥面固定摆几个，别用随机数（每只长得不一样会很怪）。
	# 每项 = [角度, 高度, 到中轴的水平距离, 球半径, 是否雪块]；水平距离要跟着该高度的锥面半径走，
	# 写死一个系数的话球会飘在树冠外或整个埋进去。
	var deco := [
		[0.35, 0.40, 0.48, 0.055, true], [1.55, 0.34, 0.46, 0.050, false],
		[2.60, 0.44, 0.44, 0.060, true], [0.90, 0.36, 0.42, 0.048, false],
		[2.20, 0.30, 0.40, 0.052, true], [0.60, 0.86, 0.26, 0.042, false],
		[2.40, 0.80, 0.25, 0.045, true],
	]
	for d in deco:
		var ang2: float = float(d[0])
		var dy: float = float(d[1])
		var dist: float = float(d[2])
		var r: float = float(d[3])
		var mat: Material = snow if bool(d[4]) else gold
		_ball(root, mat, Vector3(cos(ang2) * dist * s, dy * s, sin(ang2) * dist * s), r * s, 0.85)

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
	sm.radial_segments = 10
	sm.rings = 5
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _cyl(parent: Node3D, mat: Material, pos: Vector3, radius: float, height: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 8
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## 竖直圆锥（树冠层）。CylinderMesh 的 +Y 是顶，top_radius = 0 就是尖顶。
static func _cone(parent: Node3D, mat: Material, y: float, radius: float, height: float, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 10
	mi.mesh = cm
	mi.material_override = mat
	mi.position = Vector3(0.0, y, 0.0)
	mi.rotation = rot
	parent.add_child(mi)
	return mi


## 獠牙：朝下的小锥
static func cone_fang(parent: Node3D, mat: Material, pos: Vector3, radius: float, height: float) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 5
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation.z = PI
	parent.add_child(mi)


## 两点之间的圆柱（树干 / 树枝 / 树根）
static func _limb(parent: Node3D, mat: Material, a: Vector3, b: Vector3, radius: float) -> void:
	var dir := b - a
	var length := dir.length()
	if length <= 0.0001:
		return
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius * 0.7
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
