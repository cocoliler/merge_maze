extends Node3D
class_name FlameJet
## 喷火塔的持续火柱。
##
## 和冰塔的持续射线（IceBeam）是同一类东西：挂在塔身上、top_level = true、变换为单位阵，
## 顶点直接用世界坐标画 —— 塔身换模型 / 重新染色 / 重建都不会影响它。
##
## 区别在于这里喷的是**一股有形状的火舌**：贴图 res://textures/fx_flame_jet_0…10 是一股
## 完整火舌（喷嘴在左边缘、火焰向右铺开、末端带四散火星），所以把它的左端钉在枪口、
## 右端拉到火柱末端就行。长度和方向都由 Tower 决定，并且**整轮喷射里保持不变**
## （方向一变就会变成「追踪火柱」，那不是喷火）；这里只负责摆位置、播序列帧。

## 序列帧数量与播放帧率：0.55 秒走完一轮，比 1.5 秒的喷射短，所以一轮里会循环两圈多
const FRAMES := 11
const FPS := 20.0

## 厚度倍率：贴图本身偏细长，稍微加厚一点才像「喷」出来的
const THICK := 1.15

## 高度上限（世界单位）：射程末端不再无限变粗，否则近处细、远处像一堵墙
const MAX_H := 2.4

var _mi: MeshInstance3D
var _quad: QuadMesh
var _mat: StandardMaterial3D
var _aspect := 0.53        # 贴图高/宽；所有帧画布同尺寸，用它就不会逐帧跳动
var _t := 0.0
var _frame := -1

## 横向倍率：1.0 = 普通火柱；变异「火墙」会把它拉到和命中半径一样的 2.2 倍。
## 连高度上限一起乘，所以不是「稍微粗一点」，而是整条火舌按比例放大成超大喷射火焰
## —— 否则会出现「地上的火明显宽了、喷出去的火还是原来那根」的割裂感。
var width_mul := 1.0


func set_width_mul(m: float) -> void:
	width_mul = clampf(m, 0.3, 4.0)


## 建节点。没放贴图返回 false —— 调用方据此回退到旧的「火球」逻辑，工程永远能跑。
func setup() -> bool:
	var tex := TextureLib.get_texture("fx_flame_jet_0")
	if tex == null:
		return false
	_aspect = float(tex.get_height()) / maxf(float(tex.get_width()), 1.0)

	_quad = QuadMesh.new()
	_quad.size = Vector2(1.0, _aspect)
	_mi = MeshInstance3D.new()
	_mi.mesh = _quad
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_texture = tex
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 火舌自带颜色，这里只补一点自发光：压在明亮草地/路面上才有「烫」的感觉
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.66, 0.30)
	_mat.emission_energy_multiplier = 0.85
	_mi.material_override = _mat
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mi)
	visible = false
	return true


## 熄火：喷完 / 被压制 / 游戏暂停时调用。帧计时归零，下一轮从第一帧重新开始。
func stop() -> void:
	visible = false
	_t = 0.0
	_frame = -1


## 每帧调用：muzzle 是枪口世界坐标，dir 是这一轮锁死的方向，length 是锁死的火柱长度。
## 方片手动摆 basis（不能用 billboard：那会把旋转整个换掉，火舌就永远朝屏幕右边）。
func fire(muzzle: Vector3, dir: Vector3, length: float, delta: float) -> void:
	if _mi == null:
		return
	visible = true
	var mid := muzzle + dir * (length * 0.5)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var z := cam.global_position - mid
	if z.length_squared() < 0.0001:
		return
	z = z.normalized()
	# 火柱方向投影到「垂直于视线」的平面上：屏幕上看过去火舌才正好指向火头
	var flat := dir - z * dir.dot(z)
	if flat.length_squared() < 0.0001:
		return
	flat = flat.normalized()
	var x := flat                 # 贴图喷嘴在左边缘：+X 指向火头，左端正好落在枪口
	var y := z.cross(x)
	_mi.global_basis = Basis(x, y, z)
	_mi.global_position = mid
	# 先按「普通火柱」算出高度（射程末端封顶），再整体乘上横向倍率
	_quad.size = Vector2(length, minf(length * _aspect * THICK, MAX_H) * width_mul)

	# 帧序列：改贴图即可（TextureLib 自带缓存，不会反复 load）
	_t += delta
	var f := int(_t * FPS) % FRAMES
	if f != _frame:
		var t := TextureLib.get_texture("fx_flame_jet_%d" % f)
		if t != null:
			_frame = f
			_mat.albedo_texture = t
