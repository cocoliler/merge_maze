extends Node3D
class_name IceBeam
## 冰塔的「持续冰冻射线」表现层。
##
## 和子弹的区别：子弹是「飞过去 + 命中一次就消失」，射线是「锁住不放 + 按秒结算」。
## 所以这里每帧重画一条从塔顶冰晶连到目标身上的发光带，而不是生成 / 销毁一堆节点。
##
## 画法（对齐素材 go_towers_engineer_kr1-1 里那道冰冻闪电的观感）：
##   1. 两条三角带：外圈青蓝光晕（宽而淡）+ 内圈近白核心（窄而亮），ADD 叠加，
##      亮度叠加处自然发白，末端再张开一点，呼应素材里「射线到敌人身上炸开」的形状。
##   2. 顶点沿相机的 right / up 展开，所以无论俯视还是转向，绸带永远正对镜头。
##   3. 路径上叠正弦扰动（两端按 sin(pi*f) 收拢），直棍像激光笔，扭起来才像冰冻能量束。
##   4. 命中点 + 塔口各挂一团脉动的径向光斑（程序化生成，不需要外部贴图）。

const SEGMENTS := 18

## 两层宽度（世界单位）：光晕宽而淡、核心窄而亮
const GLOW_WIDTH := 0.44
const CORE_WIDTH := 0.13

## 扭动幅度（世界单位）。两端会自动收拢，保证射线始终咬着塔口和敌人
const WAVE_AMP := 0.13
## 扭动的波数：沿着射线上下来回几次。太少像弓，太多又变成高频噪点
const WAVE_CYCLES := 3.2

## 起手渐亮速度：约 0.15 秒从无到有，避免换目标时「啪」地闪一下
const FADE_IN := 7.0

var _mesh: ImmediateMesh
var _ray: MeshInstance3D
var _flare: MeshInstance3D
var _flare_mat: StandardMaterial3D
var _flare_quad: QuadMesh
var _muzzle: MeshInstance3D
var _muzzle_mat: StandardMaterial3D
var _muzzle_quad: QuadMesh

var _core_col := Color(0.90, 0.99, 1.0)
var _glow_col := Color(0.34, 0.78, 1.0)
var _width_mul := 1.0
var _t := 0.0
var _strength := 0.0

## 径向柔光贴图（光斑用）：全工程共用一张，64×64 足够，径向渐变不需要更高分辨率
static var _radial: GradientTexture2D


func _ready() -> void:
	visible = false
	_build()


# ---------------------------------------------------------------- 对外接口

## 画一帧射线。from / to 都是世界坐标；delta 用来推进扭动动画。
func fire(from: Vector3, to: Vector3, delta: float) -> void:
	_t += delta
	_strength = minf(_strength + delta * FADE_IN, 1.0)
	if not visible:
		visible = true
	_rebuild(from, to)
	_update_glow(from, to)


## 停止开火：射线整条消失（换目标 / 目标死亡 / 被首领压制时调这个）
func stop() -> void:
	_strength = 0.0
	_t = 0.0
	if visible:
		visible = false
	if _mesh != null:
		_mesh.clear_surfaces()


## 换颜色：核心色固定近白，光晕色跟着冰塔的变异色调走，一眼能看出选了哪条路线
func set_colors(core: Color, glow: Color) -> void:
	_core_col = core
	_glow_col = glow


## 射线粗细倍率：等级越高冰晶越大，射线也跟着变粗一点
func set_width_mul(v: float) -> void:
	_width_mul = maxf(v, 0.2)


# ---------------------------------------------------------------- 构造

func _build() -> void:
	if _mesh != null:
		return

	_mesh = ImmediateMesh.new()
	_ray = MeshInstance3D.new()
	_ray.name = "Ray"
	_ray.mesh = _mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 颜色逐顶点写入（外层淡、内层亮），所以材质本体保持纯白
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	_ray.material_override = mat
	_ray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ray)

	_flare_quad = QuadMesh.new()
	_flare = _make_glow(_flare_quad)
	_flare.name = "ImpactGlow"
	_flare_mat = _flare.material_override
	add_child(_flare)

	_muzzle_quad = QuadMesh.new()
	_muzzle = _make_glow(_muzzle_quad)
	_muzzle.name = "MuzzleGlow"
	_muzzle_mat = _muzzle.material_override
	add_child(_muzzle)


## 一团永远朝着镜头的柔光方片。billboard 在顶点着色器里会丢掉节点缩放，
## 所以尺寸只能改 QuadMesh.size（和 Fx.burst 里踩过的坑一样）。
func _make_glow(quad: QuadMesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = _radial_tex()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ---------------------------------------------------------------- 绘制

func _rebuild(a: Vector3, b: Vector3) -> void:
	if _mesh == null:
		return
	var axis := b - a
	if axis.length_squared() < 0.0001:
		_mesh.clear_surfaces()
		return

	# 绸带要正对镜头：宽度方向 = 相机右向量，扭动方向 = 相机上向量
	var right := Vector3.RIGHT
	var up := Vector3.UP
	var cam := _camera()
	if cam != null:
		var cb := cam.global_transform.basis.orthonormalized()
		right = cb.x
		up = cb.y

	_mesh.clear_surfaces()
	_draw_layer(a, b, right, up, GLOW_WIDTH * _width_mul, _glow_col, 0.42)
	_draw_layer(a, b, right, up, CORE_WIDTH * _width_mul, _core_col, 0.95)


func _draw_layer(a: Vector3, b: Vector3, right: Vector3, up: Vector3,
		width: float, col: Color, alpha: float) -> void:
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(SEGMENTS + 1):
		var f := float(i) / float(SEGMENTS)
		var p := a.lerp(b, f)
		# 两端收拢：起点必须贴着塔口、终点必须咬着敌人，中间才随便扭
		var taper := sin(PI * f)
		var phase := f * TAU * WAVE_CYCLES
		var wx := sin(phase + _t * 9.0) * WAVE_AMP * taper
		var wy := sin(phase * 0.65 + _t * 6.0) * WAVE_AMP * 0.7 * taper
		p += right * wx + up * wy
		# 越靠近命中点越张开一点，对应素材里「末端炸开」的形状
		var w: float = width * lerpf(1.0, 1.5, pow(f, 3.0)) * _strength
		var c := Color(col.r, col.g, col.b, alpha * _strength)
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(p - right * w)
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(p + right * w)
	_mesh.surface_end()


func _update_glow(a: Vector3, b: Vector3) -> void:
	if _flare == null or _muzzle == null:
		return
	# 命中光斑往相机方向挪一点：否则会被敌人身体的一半埋住，看着像光斑被切了
	var to_cam := Vector3.ZERO
	var cam := _camera()
	if cam != null:
		# 相机看向 -Z，所以 basis.z 就是「由场景指向相机」的方向
		to_cam = cam.global_transform.basis.z.normalized()

	var pulse := 0.88 + 0.10 * sin(_t * 19.0) + 0.06 * sin(_t * 31.0 + 1.7)
	var size: float = 1.30 * pulse * _width_mul * _strength
	_flare_quad.size = Vector2(size, size)
	_flare_mat.albedo_color = Color(_core_col.r, _core_col.g, _core_col.b, 0.85 * _strength)
	_flare.global_position = b + to_cam * 0.30

	var m_size: float = 0.60 * (0.9 + 0.1 * sin(_t * 26.0)) * _width_mul * _strength
	_muzzle_quad.size = Vector2(m_size, m_size)
	_muzzle_mat.albedo_color = Color(_glow_col.r, _glow_col.g, _glow_col.b, 0.70 * _strength)
	_muzzle.global_position = a


func _camera() -> Camera3D:
	if not is_inside_tree():
		return null
	var vp := get_viewport()
	if vp == null:
		return null
	return vp.get_camera_3d()


## 径向柔光贴图：中心白 → 边缘透明的平滑衰减，光斑 / 塔口闪光都用它。
static func _radial_tex() -> GradientTexture2D:
	if _radial != null:
		return _radial
	var g := Gradient.new()
	# 默认 2 个点，先删一个再加，避免 offsets / colors 数量对不上导致颜色错位
	g.remove_point(1)
	g.set_offset(0, 0.0)
	g.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	g.add_point(0.28, Color(1.0, 1.0, 1.0, 0.70))
	g.add_point(0.60, Color(1.0, 1.0, 1.0, 0.20))
	g.add_point(1.00, Color(1.0, 1.0, 1.0, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	_radial = t
	return t
