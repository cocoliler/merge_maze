extends Node3D
## 喷火方向地块上的「火烧地」：一股火喷在地上留下的燃烧带。
##
## **纯视觉，不造成任何伤害** —— 伤害全部在 Tower._flame_tick() 里按火柱结算，
## 这层只是让玩家看见「这一片地被点着了」。
##
## 生命周期 = 喷射周期 2.5 秒（喷 1.5 秒 + 残留 1 秒），时间到自动淡出、销毁；
## 塔每喷一轮就生成一条，所以连喷时前后两条会在时间上首尾相接（残留的那 1 秒正好接上下一轮）。
##
## 画法：贴图 res://textures/fx_flame_field_0…6 是一张「地上一摊摊小火」的方片，
## 平铺在地面上（世界 XY 平面 → 绕 X 转平），沿火柱方向按 TILE 世界单位循环铺满整条燃烧带。
## 不用粒子：这张素材本身就是火焰形状，铺一张方片就够了，也省得几十个节点。

const FRAMES := 7
const FPS := 16.0          # 7 帧 ≈ 0.44 秒一轮，2.5 秒里循环 5~6 圈

## 总寿命：和 Tower.FLAME_CYCLE 对齐（喷 1.5s + 残留 1s）
const LIFE := 2.5
const FADE_IN := 0.12      # 点火瞬间快速亮起，不要「啪」地出现
const FADE_OUT := 0.55     # 最后半秒烧尽淡出

## 平铺尺度：贴图的一个循环覆盖 2.0 × 2.0 世界单位（按贴图宽高比折算纵向）
const TILE := 2.0

## 抬离地面的高度。地面不是平的：草地顶面 0.8 / 路肩 0.84 / 路面 0.86 / 桥拱顶 0.92。
## 一旦低于 0.06（= 0.86）火烧地就会被路面挡住 —— 敌人走的那条路上一片漆黑，
## 只有草地和布防台上看得见火（这就是「路上没有火」的原因）。
## 0.15 高过桥拱（0.92）留 0.03 余量，比冰雾（0.20）低一档，斜着看过去不会觉得飘。
const LIFT := 0.15

var _quad: QuadMesh
var _mat: StandardMaterial3D
var _t := 0.0
var _frame := -1


## 摆好姿态与材质。没放贴图返回 false（调用方直接丢弃这个节点，别的表现照常）。
func setup(origin: Vector3, hdir: Vector3, length: float, width: float) -> bool:
	var tex := TextureLib.get_texture("fx_flame_field_0")
	if tex == null:
		return false
	var tex_w := float(maxi(tex.get_width(), 1))
	var tex_h := float(maxi(tex.get_height(), 1))
	var tile_h := TILE * tex_h / tex_w     # 保持像素在世界里是方的，别把火苗拉长

	var x := Vector3(hdir.x, 0.0, hdir.z)
	if x.length_squared() < 0.0001:
		return false
	x = x.normalized()
	# QuadMesh 的法线是 +Z：把 +Z 朝上，方片就是一块贴地的「地被」
	var z := Vector3.UP
	var y := z.cross(x)

	_quad = QuadMesh.new()
	_quad.size = Vector2(maxf(length, 0.5), maxf(width, 0.5))
	var mi := MeshInstance3D.new()
	mi.name = "Field"
	mi.mesh = _quad
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_texture = tex
	_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 贴在地面上：不写深度，免得和路面 / 射程圈抢深度
	_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.55, 0.22)
	_mat.emission_energy_multiplier = 0.75
	# 沿火柱方向平铺：一条燃烧带由好几张方片首尾相接构成
	_mat.texture_repeat = true
	_mat.uv1_scale = Vector3(maxf(length, 0.5) / TILE, maxf(width, 0.5) / tile_h, 1.0)
	# 每条燃烧带的贴图起点随机一点：同一块地上连喷两轮也不会看出是同一张图在重复
	_mat.uv1_offset = Vector3(randf(), randf(), 0.0)
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	global_basis = Basis(x, y, z)
	# 抬高 LIFT：必须高过路面（0.86）和桥拱（0.92），否则火会被「路」整段挡掉
	global_position = origin + Vector3(0.0, LIFT, 0.0) + x * (length * 0.5)
	return true


func _process(delta: float) -> void:
	_t += delta
	# 帧序列：改贴图即可（TextureLib 自带缓存，不会反复 load）
	var f := int(_t * FPS) % FRAMES
	if f != _frame:
		var t := TextureLib.get_texture("fx_flame_field_%d" % f)
		if t != null:
			_frame = f
			_mat.albedo_texture = t

	# 淡入 → 常亮 → 烧尽淡出
	var a := 1.0
	if _t < FADE_IN:
		a = _t / FADE_IN
	elif _t > LIFE - FADE_OUT:
		a = maxf((LIFE - _t) / FADE_OUT, 0.0)
	_mat.albedo_color = Color(1.0, 1.0, 1.0, a * 0.92)

	if _t >= LIFE:
		queue_free()
