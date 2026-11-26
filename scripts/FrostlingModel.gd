extends RefCounted
class_name FrostlingModel
## 霜崽的 3D 造型（纯程序化几何）。尺寸以 s（EnemyData 的 size）为基准，底面贴在 y = 0。
##
## 原画是一张成品精灵，billboard 方片在能绕视角的 3D 场景里始终是纸片，
## 所以和雪人王一样改成真 3D，并且**刻意改造**，不和原画一一对应：
##   矮胖冰晶身体 + 后掠主冰角 + 一高一低的副角 + 深色发光眼 +
##   两只小冰拳 + 背后两根冰刺 + 脚下一圈碎冰。
## 霜崽会沉到冰面下游泳，所以**不用任何半透明材质**：
## ALPHA 材质不写深度，沉下去以后会从冰面里透出来（雪人王那条注释同理）。
## 主身体材质通过 meta("body_mat") 交给 Enemy，用于减速 / 中毒染色。

const BODY_COLOR := Color(0.74, 0.86, 1.0)
const ICE_COLOR := Color(0.56, 0.86, 1.0)
const DEEP_ICE := Color(0.34, 0.66, 0.98)


static func build(s: float, body_mat: StandardMaterial3D = null) -> Node3D:
	var root := Node3D.new()
	root.name = "FrostlingBody"
	root.set_meta("body_mat", body_mat if body_mat != null else _make_mat(BODY_COLOR, 0.50, Color(0.58, 0.88, 1.0), 0.32))

	var body: Material = root.get_meta("body_mat")
	var ice := _make_mat(ICE_COLOR, 0.22, Color(0.48, 0.86, 1.0), 0.85)
	var deep := _make_mat(DEEP_ICE, 0.15, Color(0.38, 0.78, 1.0), 1.35)
	var eye := _make_mat(Color(0.04, 0.08, 0.15), 0.12, Color(0.55, 0.90, 1.0), 0.70)

	# 主体：压扁的冰晶球（比正球矮胖，跑起来才像小怪而不是雪球）
	_ball(root, body, Vector3(0.0, 0.32 * s, 0.0), 0.30 * s, 0.72)

	# 两根**不对称**的冰角：主角向后掠、右角比左角大。
	# 别做三根对称尖 —— 那和雪人王的王冠撞型，同屏出现分不清谁是谁。
	_cone(root, ice, Vector3(0.0, 0.60 * s, -0.02 * s), 0.13 * s, 0.30 * s, Vector3(-0.28, 0.0, 0.0))
	_cone(root, ice, Vector3(0.19 * s, 0.54 * s, -0.02 * s), 0.07 * s, 0.20 * s, Vector3(-0.20, 0.0, -0.62))
	_cone(root, ice, Vector3(-0.17 * s, 0.56 * s, -0.02 * s), 0.06 * s, 0.13 * s, Vector3(-0.20, 0.0, 0.50))

	# 眼睛：深色底 + 一点冷光，必须顶出球面（该高度球面 z ≈ 0.29s）。
	# 半径别太大：0.06s 时眼睛会占掉半张脸，看着像表情包而不是小怪。
	for i in range(2):
		var sx2: float = 1.0 if i == 0 else -1.0
		_ball(root, eye, Vector3(0.112 * s * sx2, 0.405 * s, 0.278 * s), 0.043 * s, 1.0)

	# 嘴：三颗小冰粒，浅浅一道弧
	for i in range(3):
		var t := float(i) - 1.0
		_ball(root, deep, Vector3(0.048 * s * t, 0.262 * s - absf(t) * 0.010 * s, 0.292 * s), 0.019 * s, 1.0)

	# 两只小冰拳：短粗的球，比细长的爪子好读 —— 细长锥从正面看像「猫须」。
	for i in range(2):
		var sx3: float = 1.0 if i == 0 else -1.0
		_ball(root, ice, Vector3(0.30 * s * sx3, 0.215 * s, 0.10 * s), 0.085 * s, 0.90)

	# 背后两根冰刺：俯视 / 背影也有辨识度
	_cone(root, deep, Vector3(0.0, 0.46 * s, -0.24 * s), 0.055 * s, 0.22 * s, Vector3(-0.95, 0.0, 0.0))
	_cone(root, deep, Vector3(0.0, 0.30 * s, -0.26 * s), 0.045 * s, 0.17 * s, Vector3(-1.10, 0.0, 0.0))

	# 脚下一圈碎冰：不透明的小锥，替代「半透明冰雾」—— 沉到冰下时不会透出来
	for i in range(5):
		var ang := TAU * float(i) / 5.0 + 0.25
		_cone(root, ice, Vector3(cos(ang) * 0.26 * s, 0.06 * s, sin(ang) * 0.26 * s),
			0.045 * s, 0.13 * s, Vector3(sin(ang) * 0.35, 0.0, -cos(ang) * 0.35))

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
	sm.radial_segments = 14
	sm.rings = 7
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _cone(parent: Node3D, mat: Material, pos: Vector3, radius: float, height: float, tilt: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 5
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = tilt
	parent.add_child(mi)
	return mi


