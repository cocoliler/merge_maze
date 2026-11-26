extends Node3D
class_name FrostFog
## 变异「霜环」的地面冰雾：把整座塔的射程圈铺满一层缓慢流动的雾，雾里散着碎冰块。
##
## 为什么用「圆盘」而不是一张大方片：
##   方片的四个角会捅到射程圈外面，看着像糊在地上的塑料布。圆盘天然把雾裁成正圆，
##   玩家一眼就能读出「站在圈里就会被减速」。
##
## 为什么形状要写在顶点色里：
##   素材本身只是一团软边云，靠 StandardMaterial3D 没法做径向遮罩（那需要自定义 shader）。
##   这里把「中心浓、边缘淡」烘进圆盘网格的顶点 alpha（vertex_color_use_as_albedo 会把
##   顶点 alpha 乘进 ALPHA），整圈就有了柔和的外轮廓。
##
## **贴图必须平铺（tiling），不能放大**：
##   第一版把贴图放大铺满整圈，等于只采样到云团最中间那块最平的区域 —— 结果整片雾变成
##   一层纯蓝滤镜，看不出任何纹理。现在改成每层用 2~5 次重复 + 不同偏移，雾团轮廓
##   （边缘亮、中间更亮的那圈）就散开成一块块可见的雾斑，读起来才像「雾」而不是「蓝色蒙版」。

const SEGMENTS := 44

## 圆盘的同心环：[半径, 顶点 alpha]。半径 1 = 射程圈，最后一行必须是 0 才能淡出
const RINGS := [0.0, 0.42, 0.74, 1.0]
const RING_ALPHA := [1.0, 0.94, 0.66, 0.0]

## 冰雾本体颜色：淡冰蓝。太深会像给地面套了个蓝色滤镜，太浅又和草地混成一片
const FOG_COLOR := Color(0.66, 0.88, 1.0)

## 贴图槽位（res://textures/fx_frost_fog.png，缺图时退化成纯色雾团）
const TEX_SLOT := "fx_frost_fog"

## 离地高度（相对塔的 y = GameGrid.SURFACE_Y 0.8）。
## 必须高于路面顶（0.8+0.06=0.86）和拱桥顶（0.8+0.08+0.06≈0.94），否则雾会被路埋掉 ——
## 泥潭那一版就是栽在这个高度上。
const GROUND_Y := 0.20

## 每层：[贴图重复次数, 透明度, 自转速度, 相对半径, UV 偏移]
## 重复次数越大，雾斑越碎；三层各不相同，叠起来才不像同一张图复制三遍
const LAYERS := [
	{"uv": 2.2, "alpha": 0.52, "spin": 0.045, "size": 1.00, "off": Vector2(0.13, 0.37)},
	{"uv": 3.4, "alpha": 0.38, "spin": -0.085, "size": 0.78, "off": Vector2(0.51, 0.09)},
	{"uv": 4.9, "alpha": 0.24, "spin": 0.135, "size": 0.58, "off": Vector2(0.73, 0.62)},
]

## 雾里平躺的碎冰：直接用冰塔命中特效的那张图，让冰雾有实体细节而不是纯色蒙版
const DEBRIS_SLOT := "fx_ice_0"
const DEBRIS_COUNT := 8
## 单块碎冰的边长（相对射程：0.13 × range_v，Lv.3 约 0.75 世界单位）
const DEBRIS_SIZE := 0.13
const DEBRIS_COLOR := Color(0.74, 0.92, 1.0)

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
		_add_layer(cfg, tint, tex)
	_add_debris()


func _add_layer(cfg: Dictionary, tint: Color, tex: Texture2D) -> void:
	var zoom := float(cfg["uv"])
	var alpha := float(cfg["alpha"])
	var size := float(cfg["size"])

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
		# 重复采样（平铺）而不是放大：只放大就会采样到云团最平的核心，整圈变成纯色
		mat.texture_repeat = true
		mat.uv1_scale = Vector3(zoom, zoom, 1.0)
		mat.uv1_offset = Vector3(cfg["off"].x, cfg["off"].y, 0.0)
	# 自发光只留一点点：unshaded 材质下 emission 等于直接往上加亮度，
	# 加多了雾会重新发白，又回到「看不出来」的老问题
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 0.10
	mi.material_override = mat

	add_child(mi)
	_layers.append(mi)
	_mats.append(mat)
	_base_alpha.append(alpha)
	_spins.append(float(cfg["spin"]))


## 雾里散落的碎冰块：平躺在地面上、随机朝向，给「冰雾」一点实体细节。
## 尺寸写的是相对射程的比例，所以射程变大时碎冰会跟着变大，不会突然显得像碎屑。
func _add_debris() -> void:
	var tex := TextureLib.get_texture(DEBRIS_SLOT)
	if tex == null:
		return
	var aspect := float(tex.get_height()) / maxf(float(tex.get_width()), 1.0)
	for i in DEBRIS_COUNT:
		var ang := randf() * TAU
		# sqrt 让分布均匀铺在圆面上而不是挤在圆心
		var r := sqrt(randf()) * 0.72
		var jitter := 0.75 + randf() * 0.6
		var quad := QuadMesh.new()
		quad.size = Vector2(DEBRIS_SIZE * jitter, DEBRIS_SIZE * jitter * aspect)

		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.position = Vector3(cos(ang) * r, 0.012, sin(ang) * r)
		mi.rotation_degrees = Vector3(-90.0, randf() * 360.0, 0.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mat.albedo_texture = tex
		mat.albedo_color = Color(DEBRIS_COLOR.r, DEBRIS_COLOR.g, DEBRIS_COLOR.b, 0.85)
		mat.emission_enabled = true
		mat.emission = DEBRIS_COLOR
		mat.emission_energy_multiplier = 0.18
		mi.material_override = mat
		add_child(mi)


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
