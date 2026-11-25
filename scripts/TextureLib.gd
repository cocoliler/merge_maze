extends RefCounted
class_name TextureLib
## 贴图热插拔工具（Texture Hot-Swap）。
##
## 用法：把图片丢进工程根目录的 res://textures/ 文件夹，文件名按约定命名即可自动生效。
## 找不到对应图片时，各处材质保持原本的「程序化纯色 + 自发光」外观——所以工程永远能跑，
## 你可以一个槽位一个槽位地慢慢替换，不用一次凑齐所有图。
##
## 支持格式：png / jpg / jpeg / webp / svg / bmp / tga / tres / res
## 约定文件名与含义见 res://textures/README.md
##
## 注意：新丢进去的图片需要让 Godot 编辑器扫一次（切回编辑器窗口即可，或菜单
## 「项目 → 重新加载当前项目」），否则资源还没被导入，运行时 load() 会拿不到。

const DIR := "res://textures/"
const EXTS := ["png", "jpg", "jpeg", "webp", "svg", "bmp", "tga", "tres", "res"]

## 工程当前真正会去读的槽位（文件名去掉扩展名 = 槽位名）。
## 没放图的槽位自动回退到程序化外观，所以可以一个槽位一个槽位地替换。
const SLOTS := [
	"sky",          # 天空盒（等距柱状全景图）
	"path",         # 敌人土路路面（需要可平铺）
	"spawn_pad",    # 出生踏板
	"bullet",       # 子弹（所有塔共用的球体贴图）
	"bullet_stone", # 炮塔专用的石块弹丸（billboard 方片，带透明通道）
	"fx_explosion", # 炮塔命中的爆炸（billboard 方片，带透明通道）
	"fx_explosion_l2", # 二级及以上炮塔命中的爆炸（碎石 + 浓烟版）
	# 变异「攻城巨炮」命中爆炸的序列帧：落石 → 聚拢 → 爆燃，按 _0 → _8 顺序播放
	"fx_siege_0", "fx_siege_1", "fx_siege_2", "fx_siege_3", "fx_siege_4",
	"fx_siege_5", "fx_siege_6", "fx_siege_7", "fx_siege_8",
	# 变异「震地雷」泥潭的序列帧（平铺在地面，1.5 秒内按 _0 → _6 走完一遍）
	"fx_mud_0", "fx_mud_1", "fx_mud_2", "fx_mud_3", "fx_mud_4", "fx_mud_5", "fx_mud_6",
	# 冰塔冰冻射线命中的碎冰序列帧（冰块炸开，0.3 秒内按 _0 → _1 播完）
	"fx_ice_0", "fx_ice_1",
	# 变异「霜环」铺在地面上的冰雾（圆形平铺，方形画布、雾团居中、四周透明）
	"fx_frost_fog",
	"enemy_grunt", "enemy_runner", "enemy_tank", "enemy_boss",
	"enemy_flyer", "enemy_shield",
	# 霜崽：原画精灵（billboard 方片，带透明通道），见 Enemy._build_sprite_body()
	# 雪人王不走贴图：它是程序化 3D 造型（scripts/SnowkingModel.gd）
	"enemy_frostling",
]

static var _index := {}        # 小写槽位名 -> 完整路径
static var _scanned := false
static var _cache := {}        # 小写槽位名 -> Texture2D


## 强制重新扫描目录（运行时新放了图可调用，正常不用管）
static func rescan() -> void:
	_scanned = false
	_index.clear()
	_cache.clear()
	_scan()


static func _scan() -> void:
	if _scanned:
		return
	_scanned = true
	var d := DirAccess.open(DIR)
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if not d.current_is_dir() and not f.begins_with("."):
			if EXTS.has(f.get_extension().to_lower()):
				_index[f.get_basename().to_lower()] = DIR + f
		f = d.get_next()
	d.list_dir_end()


## 这个槽位有没有放图
static func has(slot: String) -> bool:
	_scan()
	return _index.has(slot.to_lower())


## 取一张贴图，没有就返回 null
static func get_texture(slot: String) -> Texture2D:
	_scan()
	var key := slot.to_lower()
	if not _index.has(key):
		return null
	if _cache.has(key):
		return _cache[key]
	var res = load(_index[key])
	if res is Texture2D:
		_cache[key] = res
		return res
	return null


## 给一个已有材质套上贴图。
## uv        —— 平铺次数
## white_base —— 有贴图时把 albedo_color 刷白，免得底色调和贴图颜色打架
## 返回 false 表示没找到图，材质保持原样（程序化外观）。
static func dress(mat: BaseMaterial3D, slot: String, uv: float = 1.0, white_base: bool = true) -> bool:
	var tex := get_texture(slot)
	if tex == null:
		return false
	mat.albedo_texture = tex
	mat.uv1_scale = Vector3(uv, uv, 1.0)
	if white_base:
		mat.albedo_color = Color.WHITE
	return true


## 当前已经放了哪些图（用于调试 / 自检）
static func slot_list() -> PackedStringArray:
	_scan()
	var out := PackedStringArray()
	for k in _index.keys():
		out.append(str(k))
	out.sort()
	return out


## 还没放图的槽位：开局打印一次，告诉玩家还能补哪些图
static func missing_slots() -> PackedStringArray:
	var out := PackedStringArray()
	for s in SLOTS:
		if not has(s):
			out.append(s)
	return out
