extends Node3D
class_name FrostFog
## 变异「霜环」的地面冰雾：把整座塔的射程圈铺满一层缓慢流动的雾。
##
## 为什么用「圆盘」而不是一张大方片：
##   方片的四个角会捅到射程圈外面，看着像糊在地上的塑料布。圆盘天然把雾裁成正圆，
##   玩家一眼就能读出「站在圈里就会被减速」。
##
## 为什么形状要写在顶点色里：
##   素材本身只是一团软边云，直接铺开只占中间一小块；靠 StandardMaterial3D 没法做径向遮罩
##   （那需要自定义 shader）。这里把「中心浓、边缘淡」烘进圆盘网格的顶点 alpha
##   （vertex_color_use_as_albedo 会把顶点 alpha 乘进 ALPHA），再用 UV 缩放把贴图拉满，
##   就得到「整圈都是雾、边缘自然淡出、没有硬切边」的效果。
##
## 三层叠在一起：主雾体 + 细节层 + 淡淡的高光丝，转速各不相同 —— 静止的雾看着像贴纸。

const SEGMENTS := 44

## 圆盘的同心环：[半径, 顶点 alpha]。半径 1 = 射程圈，最后一行必须是 0 才能淡出
## alpha 曲线决定「雾有多厚到多薄才散」：中间段给得高一点，边缘才不会只剩一小圈浓雾
const RINGS := [0.0, 0.42, 0.74, 1.0]
const RING_ALPHA := [1.0, 0.94, 0.66, 0.0]

## 冰雾本体颜色：比塔身光环更深一档的蓝。
## 素材本身接近纯白，直接用（白 × 浅色）铺在浅灰路面上几乎看不出来
const FOG_COLOR := Color(0.34, 0.60, 0.98)

## 贴图槽位（res://textures/fx_frost_fog.png，缺图时退化成纯色雾团）
const TEX_SLOT := "fx_frost_fog"

## 离地高度（相对塔的 y = GameGrid.SURFACE_Y 0.8）。
## 必须高于路面顶（0.8+0.06=0.86）和拱桥顶（0.8+0.08+0.06≈0.94），否则雾会被路埋掉 ——
## 泥潭那一版就是栽在这个高度上。
const GROUND_Y := 0.20

## 每层的 [贴图 UV 缩放, 透明度, 自转速度, 相对半径]
## 透明度别吝啬：叠三层后边缘仍然很淡，给低了整片雾会像没开
const LAYERS := [
	[0.52, 0.62, 0.045, 1.00],
	[0.92, 0.44, -0.085, 0.78],
	[1.55, 0.26, 0.135, 0.56],
]

static var _disc: ArrayMesh

var _layers: Array[MeshInstance3D] = []
var _mats: Array[StandardMaterial3D] = []
var _base_alpha: Array[float] = []
var _spins: Array[float] = []
var _t := 0.0


## 按射程铺满：radius = 塔的 range_v
func setup(radius: float, tint: Color) -> void:
	scale = Vector3(maxf(radius, 0.5), 1.0, maxf(radius, 0.5))
	position.y = GROUND_Y
	var tex := TextureLib.get_texture(TEX_SLOT)
	for cfg in LAYERS:
		_add_layer(float(cfg[0]), float(cfg[1]), float(cfg[2]), float(cfg[3]), tint, tex)


func _add_layer(zoom: float, alpha: float, spin: float, size: float,
		tint: Color, tex: Texture2D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _disc_mesh()
	mi.scale = Vector3(size, 1.0, size)
	mi.rotation.y = randf() * TAU
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 透明地面覆盖层不写深度：免得和路面 / 射程圈抢 Z
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	# 形状靠顶点 alpha，颜色靠这里：贴图是白的，乘上淡蓝就是冰雾
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(tint.r, tint.g, tint.b, alpha)
	if tex != null:
		mat.albedo_texture = tex
		# 以贴图中心为基准缩放：concentric zoom 才不会把雾团推偏
		mat.uv1_scale = Vector3(zoom, zoom, 1.0)
		mat.uv1_offset = Vector3((1.0 - zoom) * 0.5, (1.0 - zoom) * 0.5, 0.0)
	# 自发光只留一点点：unshaded 材质下 emission 等于直接往上加亮度，
	# 加多了雾会重新发白，又回到「看不出来」的老问题
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 0.08
	mi.material_override = mat

	add_child(mi)
	_layers.append(mi)
	_mats.append(mat)
	_base_alpha.append(alpha)
	_spins.append(spin)


func _process(delta: float) -> void:
	if _layers.is_empty():
		return
	_t += delta
	for i in _layers.size():
		var mi := _layers[i]
		if mi == null or not is_instance_valid(mi):
			continue
		# 慢慢自转 + 呼吸：两层反向转，交界处才像雾在翻涌
		mi.rotation.y += _spins[i] * delta
		var mat := _mats[i]
		mat.albedo_color.a = _base_alpha[i] * (0.86 + 0.14 * sin(_t * 0.8 + float(i) * 2.1))


## 圆盘网格（所有冰雾塔共用一份）
static func _disc_mesh() -> ArrayMesh:
	if _disc != null:
		return _disc
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()

	for r_i in RINGS.size():
		var r: float = RINGS[r_i]
		var a: float = RING_ALPHA[r_i]
		for s in range(SEGMENTS + 1):
			var ang := TAU * float(s) / float(SEGMENTS)
			var p := Vector3(cos(ang) * r, 0.0, sin(ang) * r)
			verts.append(p)
			uvs.append(Vector2(0.5 + p.x * 0.5, 0.5 + p.z * 0.5))
			cols.append(Color(1.0, 1.0, 1.0, a))
			norms.append(Vector3.UP)

	var stride := SEGMENTS + 1
	for r_i in range(RINGS.size() - 1):
		for s in range(SEGMENTS):
			var a := r_i * stride + s
			var b := a + 1
			var c := (r_i + 1) * stride + s
			var d := c + 1
			idx.append(a)
			idx.append(c)
			idx.append(b)
			idx.append(b)
			idx.append(c)
			idx.append(d)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_disc = m
	return m
