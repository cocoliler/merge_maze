extends Node3D
class_name GameGrid
## 棋盘网格：左侧水晶基地 + 右侧双入口涌敌 + 建筑自由放置。
##
## 敌人走「固定路线」：lanes 里每一行都是「一条从右侧入口通往左侧水晶」的格子序列，
## 北线 / 南线各走一大圈，最后在地图左中侧汇成一条主路再撞向水晶 —— 路线有分叉、
## 有汇流，玩家必须两头兼顾，不能只堵一条线。路径格禁止建塔，所以建塔/出售不会改变
## 行进路线；另外仍保留一份「到基地的 BFS 距离场」，用于把卡住/越界的敌人拉回可行格。

signal grid_changed()

const COLS := 28
const ROWS := 21
const CELL := 2.0

## 瓦片底面高度。Kenney 的 tile.glb 顶点 y ∈ [0, 0.2]，乘 SCALE=2 后瓦片本体厚 0.4，
## 从这一层往上长，所以草地顶面在 SURFACE_Y = 0.8（岩石/树更高，围成边界）。
const GROUND_Y := 0.4

## 草地顶面高度：所有「站在地上」的东西（塔 / 敌人 / 路面 / 标记）都从这一层开始。
## 注意别用 GROUND_Y —— 那是瓦片底面，直接用它会导致所有东西陷进地里 0.4。
const SURFACE_Y := 0.8

## 路面尺寸（世界单位，1 格 = 2.0）。路总宽 3.2 ≈ 1.6 格，比原来整整宽了一倍：
## 敌人、子弹、特效都有地方铺开，远处看才像「一条路」，而不是贴着格子画的一条线。
const ROAD_HALF := 1.6
const ROAD_SHOULDER_HALF := 1.95      # 路肩（更深的湿土），比路面再宽一圈，像镶在草地里
const ROAD_Y := 0.06                  # 相对 SURFACE_Y
const SHOULDER_Y := 0.04
## 路面细节：两侧一条更浅的干土毛边 + 路中间两道压深的车辙。
## 都是在路面上再贴 0.004 / 0.006 的窄带（真去挖凹槽要重做路面几何，
## 俯视角下和贴一条深色窄带没有区别，但代码简单得多），横向位置见 ROAD_EDGE_LAT / RUT_LAT。
const ROAD_EDGE_W := 0.16                       # 毛边半宽
const ROAD_EDGE_LAT := ROAD_HALF - ROAD_EDGE_W  # 毛边中心离路心的距离（正好吃到路沿）
const RUT_LAT := 0.62                           # 车辙离路心
const RUT_W := 0.20                             # 车辙半宽
const WATER_Y := 0.03                 # 河面：低于路面，被木桥盖住
const BANK_Y := 0.018                 # 河岸浅沙（比草地高 0.018，避免 z-fighting）

## 木桥是一座浅拱，而且过河那段「路面直接铺在桥面上」，两者共用同一个拱形
## （见 _crown_lift）—— 所以路面的坡度和桥面的坡度天然一致，桥头不再出现
## 一条悬空的直切口。桥面顶永远比路面低 0.02，藏在路面底下，接缝冒不出木色台阶。
## 敌人仍踩在 SURFACE_Y 上走，桥心那一格会陷进去 0.14（拱高 0.08 + 路面抬升 0.06），
## 和走路自带的 0.06 上下浮动同一量级，远看几乎看不出来。
const BRIDGE_END := ROAD_Y - 0.02     # 桥头桥面高度（相对 SURFACE_Y，比路面低 0.02）
const BRIDGE_CROWN := 0.08            # 拱顶相对桥头的抬升
const BRIDGE_DECK_EXTRA := 0.25       # 桥面比路面每侧多出的木边（让木色从路边露出来）
const BRIDGE_SPAN_CELLS := 1.3        # 桥面比水面两端各多伸出的格数（插进岸上的路面底下）
const BRIDGE_THICK := 0.08            # 桥板厚度（拱顶底面也比水面高，不会切进水里）
const BRIDGE_RAIL_Y := 0.34           # 护栏横梁离桥面的高度

## 布防台离「路中心线」的格数：2 格 = 4.0 世界单位。
## 路面半宽 1.6 + 塔底半径 1.0，中间还能剩下 1.4 单位草地缓冲 —— 塔不再贴着路站。
## 注意：斜距固定 4.0，塔对路面的覆盖长度 = sqrt(射程² - 4²)，所以路面加宽后
## 塔的射程也跟着上调了一轮（喷火塔 4.4 → 5.6，详见 TowerData.DATA 的射程基线说明），
## 否则短射程塔会变成「建了几乎打不到」的死位。
const SLOT_GAP := 2

## 布防台离水面至少几格：贴着河岸的台子会让塔看起来像浮在水上、或者压在桥头，
## 直接不生成。1 = 水格及其 8 邻域都不放塔，给河岸留一圈草地。
const SLOT_WATER_GAP := 1

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## 地形装饰：R = 岩壁、T = 树丛、. = 普通草地（河流由 _make_water_cells 单独生成）。
## 关卡设计师改地图只需要动这张图和 _make_lanes 里的拐点。
const DECOR_MAP := [
	"RRRRRRRR.......~~....TTTTTTT",
	"RRRRRRR.........~~....TTTTTT",
	"RRRRRR...........~~.....TTTT",
	"RRRRR............~~.........",
	"RRRR..............~~........",
	"RRR...............~~........",
	".TT...............~~........",
	"TTT...............~~........",
	"..TT..............~~........",
	".................~~.........",
	".................~~.........",
	"................~~..........",
	"................~~.......TT.",
	"...............~~...........",
	".TT...........~~............",
	"..TT.........~~.............",
	"TTTT........~~..............",
	"TTTTTT.....~~...............",
	"TTTTTTTT...~~...............",
	"TTTTTTT.....~~..........TTTT",
	"TTTTTT......~~........TTTTTT",
]

## 路线上的流动箭头（沿行进方向滚动，玩家一眼能看出怪往哪走）
const FLOW_ARROW_COUNT := 64
const FLOW_SPEED := 3.0               # 箭头滚动速度（格 / 秒）
const FLOW_Y := 0.14                  # 箭头离地高度（压在路面之上，避免 z-fighting）

## 水晶血条着色器：和敌人血条同一套思路 —— 用 ratio 在片元阶段裁出填充宽度。
## 不能靠 scale.x：billboard 会在顶点阶段丢掉节点缩放，血条会永远满格。
const HOME_BAR_SHADER := [
	"shader_type spatial;",
	"render_mode unshaded, cull_disabled;",
	"uniform float ratio : hint_range(0.0, 1.0) = 1.0;",
	"uniform vec3 full_color : source_color = vec3(0.36, 0.90, 1.0);",
	"uniform vec3 low_color : source_color = vec3(1.0, 0.34, 0.30);",
	"uniform vec3 back_color : source_color = vec3(0.08, 0.11, 0.18);",
	"uniform vec3 frame_color : source_color = vec3(0.03, 0.04, 0.07);",
	"void fragment() {",
	"	float pad = 0.03;",
	"	vec3 col = frame_color;",
	"	if (UV.x > pad && UV.x < 1.0 - pad && UV.y > 0.24 && UV.y < 0.76) {",
	"		float inner = (UV.x - pad) / (1.0 - pad * 2.0);",
	"		if (inner <= ratio) {",
	"			col = mix(low_color, full_color, smoothstep(0.0, 0.75, ratio));",
	"		} else {",
	"			col = back_color;",
	"		}",
	"	}",
	"	ALBEDO = col;",
	"}",
]

var blocked := PackedByteArray()      # 只表示「被塔占据」
var towers := {}                      # key: int(idx) -> Tower
var home_cells: Array[Vector2i] = []
var spawns: Array[Vector2i] = []      # 每条 lane 的入口格（现在是两个：右上方 / 右下方）
var lanes: Array = []                 # Array[Array[Vector2i]]：多条敌人固定路线
var path_cells: Array[Vector2i] = []  # 所有 lane 的并集（路径格不可建塔）
var _path_set := {}                   # path_cells 的快速索引
var _water_set := {}                  # 河面格（不可建塔 / 不可装饰）
var _decor := {}                      # 格子 -> "R" 岩壁 / "T" 树丛

## 可建造的「布防台」：不是整张地图都能放塔，只有这些固定的点能建。
## 生成规则见 _make_build_slots()（离路恰好 SLOT_GAP 格 + 稀疏采样），改 SLOT_MOD 调数量。
var build_slots: Array[Vector2i] = []
var _slot_set := {}
## 稀疏采样步长：2 = 棋盘格密度，3 = 大约再少 1/3，4 更稀。
const SLOT_MOD := 3

var _dist := PackedInt32Array()       # 距离场：-1 表示到不了基地

var _flow_mm: MultiMesh
var _flow_mi: MultiMeshInstance3D      # 箭头节点本体（准备阶段才显示，见 set_flow_visible）
var _flow_t: float = 0.0
var _flow_sets: Array = []            # 每条路线一份箭头：[{route, count, gap}]
var _routes: Array = []               # [{pts, cum, len}]，每个 lane 一条

var _home_root: Node3D
var _crystal: Node3D
var _home_ring: MeshInstance3D
var _t: float = 0.0

var _bar_root: Node3D              # 水晶血条（始终朝向相机）
var _bar_mat: ShaderMaterial
var _bar_label: Label3D
var _max_hp: int = 0               # 水晶最大生命（等于见过的最高生命值）
var _cam: Camera3D

# ---------------------------------------------------------------- 初始化

func _ready() -> void:
	blocked.resize(COLS * ROWS)
	for i in range(blocked.size()):
		blocked[i] = 0
	home_cells = _make_home_cells()
	lanes = _make_lanes()
	path_cells = []
	_path_set.clear()
	for lane in lanes:
		for pc in lane:
			if _path_set.has(pc):
				continue
			_path_set[pc] = true
			path_cells.append(pc)
	spawns = []
	for lane in lanes:
		if not lane.is_empty():
			spawns.append(lane[0])
	_water_set = _make_water_cells()
	_decor = _make_decor()
	build_slots = _make_build_slots()
	_slot_set.clear()
	for s in build_slots:
		_slot_set[s] = true
	_max_hp = maxi(GameState.START_LIVES, GameState.lives)
	_build_ground()
	_build_water()
	_build_roads()
	_build_bridges()
	_build_spawn_markers()
	_build_home()
	_build_path_flow()
	_build_slot_markers()
	GameState.lives_changed.connect(_on_lives_changed)
	_refresh_home_bar()
	refresh()


## 基地：贴在最左侧、上下居中的 2×2（蓝色水晶就守在地图左边缘）
func _make_home_cells() -> Array[Vector2i]:
	var cy := ROWS / 2
	return [
		Vector2i(0, cy - 1), Vector2i(1, cy - 1),
		Vector2i(0, cy), Vector2i(1, cy),
	]


## 多路线主体：两条从右边缘切入的路线各自先绕一段再折回来，最后在地图左中侧
## 汇合成一条主路撞向水晶。
##   北线：右上入口 → 沿 y=3 向西 → 在 x=22 向下 → 沿 y=7 向西 → 在 x=8 向下 → 主路
##   南线：右下入口 → 沿 y=17 向西 → 在 x=22 向上 → 沿 y=13 向西 → 在 x=8 向上 → 主路
## 两条线之间的整片草地是「双面火力区」，中间的河与两座木桥又把地图切成两半，
## 和参考图里「两条土路 + 河 + 两座桥」的构图一致。
func _make_lanes() -> Array:
	var north := _lane_from([
		Vector2i(COLS - 1, 3), Vector2i(22, 3), Vector2i(22, 7),
		Vector2i(8, 7), Vector2i(8, 10), Vector2i(2, 10),
	])
	var south := _lane_from([
		Vector2i(COLS - 1, ROWS - 4), Vector2i(22, ROWS - 4), Vector2i(22, ROWS - 8),
		Vector2i(8, ROWS - 8), Vector2i(8, 10), Vector2i(2, 10),
	])
	return [north, south]


## 把一串「横平竖直」的拐点展开成逐格序列（拐点只出现一次，方便敌人沿格推进）
func _lane_from(wps: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in range(wps.size() - 1):
		var a: Vector2i = wps[i]
		var b: Vector2i = wps[i + 1]
		if out.is_empty():
			out.append(a)
		if a.x != b.x and a.y != b.y:
			push_error("GameGrid: lane 拐点必须横平竖直 %s -> %s" % [a, b])
			continue
		var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
		var cur := a
		while cur != b:
			cur += step
			out.append(cur)
	return out


## 河道走向：河心（2 格宽河道的中心列，浮点）在 RIVER_MID 附近按两条正弦摆动。
## 原来只有一个 ±1.2 格的低频正弦，几乎是一条直河；现在主波 ±3.3 格 + 次波 ±0.5 格，
## 21 行正好走完一个完整的 S 弯，俯视角下能明显看出「河在绕」。
## 峰值落在 11~19 列、河面最右到 20 列，既不会压到 x=22 的竖路，也不会顶到左边基地。
const RIVER_MID := 15.5
const RIVER_SWING :=2.0
const RIVER_FREQ := 0.26
const RIVER_WOBBLE := 0.5


func _river_x(y: int) -> float:
	var t := float(y)
	var main := sin(t * RIVER_FREQ) * RIVER_SWING
	var wobble := sin(t * RIVER_FREQ * 2.17 + 1.3) * RIVER_WOBBLE
	return RIVER_MID + main + wobble


## 河流：从地图上方蜿蜒流到下方，宽两格。两条 lane 与河相交的格子自动变成桥位。
func _make_water_cells() -> Dictionary:
	var out := {}
	for y in range(ROWS):
		var x0 := int(round(_river_x(y) - 0.5))
		x0 = clampi(x0, 2, COLS - 4)
		for dx in range(2):
			var c := Vector2i(x0 + dx, y)
			if in_bounds(c):
				out[c] = true
	return out


func _is_water(c: Vector2i) -> bool:
	return _water_set.has(c)


## 解析 DECOR_MAP：岩壁 / 树丛只长在空地上（不压路、不压基地、不落水）。
func _make_decor() -> Dictionary:
	var out := {}
	if DECOR_MAP.size() != ROWS:
		push_warning("GameGrid: DECOR_MAP 行数 %d != %d" % [DECOR_MAP.size(), ROWS])
	for y in range(mini(DECOR_MAP.size(), ROWS)):
		var row: String = DECOR_MAP[y]
		if row.length() != COLS:
			push_warning("GameGrid: DECOR_MAP 第 %d 行长度 %d != %d" % [y, row.length(), COLS])
		for x in range(mini(row.length(), COLS)):
			var ch := row[x]
			if ch != "R" and ch != "T":
				continue
			var c := Vector2i(x, y)
			if is_home(c) or is_path(c) or _is_water(c) or spawns.has(c):
				continue
			out[c] = ch
	return out


func decor_at(c: Vector2i) -> String:
	return _decor.get(c, "")


## 格子到「最近路格」的曼哈顿距离（没有路返回 999）
func _path_gap(c: Vector2i) -> int:
	var best := 999
	for pc in path_cells:
		var d := absi(pc.x - c.x) + absi(pc.y - c.y)
		if d < best:
			best = d
			if best <= 1:
				return best
	return best


## 可建造的布防台：离路面正好 SLOT_GAP 格（而不是贴着路），再按 (x+y)%SLOT_MOD 采样。
## 好处是塔和路之间永远隔着一条草地，视觉上不再「糊在路边」；
## 数量仍然有限，玩家必须挑位置。想换密度只改 SLOT_MOD（当前 3；2 更密、4 更稀）。
func _make_build_slots() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(ROWS):
		for x in range(COLS):
			var c := Vector2i(x, y)
			if _path_gap(c) != SLOT_GAP:
				continue
			if not _is_slot_candidate(c):
				continue
			if (x + y) % SLOT_MOD != 0:
				continue
			out.append(c)
	return out


func _is_slot_candidate(c: Vector2i) -> bool:
	if not in_bounds(c):
		return false
	if is_border(c) or is_home(c) or is_path(c):
		return false
	if _is_water(c) or _decor.has(c):
		return false
	# 河岸不放布防台：离水面 SLOT_WATER_GAP 格以内（含斜角）全部排除
	for dy in range(-SLOT_WATER_GAP, SLOT_WATER_GAP + 1):
		for dx in range(-SLOT_WATER_GAP, SLOT_WATER_GAP + 1):
			if _is_water(c + Vector2i(dx, dy)):
				return false
	# 8 邻域里也不能有路面：斜对角的格子一样算「贴着路」，塔摆上去还是会显得挤
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			if is_path(c + Vector2i(dx, dy)):
				return false
	return true


## 某格是不是布防台（只有布防台能建塔）
func is_build_slot(c: Vector2i) -> bool:
	return _slot_set.has(c)


func _process(delta: float) -> void:
	# 路线箭头只在准备阶段显示（由 Main 调 set_flow_visible），暂停时也照常流动
	_update_flow(delta)
	_face_home_bar()
	if _crystal == null:
		return
	_t += delta
	_crystal.rotation.y += delta * 0.9
	_crystal.position.y = 0.35 + sin(_t * 2.2) * 0.12
	if _home_ring != null:
		_home_ring.rotation.y -= delta * 0.35


## 敌人漏进基地时，在水晶处放红色闪光（由 Main 在 lives_changed 时调用）
func on_base_hit() -> void:
	if _crystal != null and is_instance_valid(_crystal):
		Fx.flash(self, _crystal.global_position, Color(1.0, 0.3, 0.3), 0.8, 0.25)
		Fx.ring(self, _crystal.global_position, Color(1.0, 0.3, 0.3), 0.6, 0.3)


## 铺设 Kenney 草地瓦片：内部草地、外圈岩石（提示这里不能建塔）、四角种树。
## 用 MultiMesh 合并同类瓦片，588 个瓦片只需几个 draw call。
func _build_ground() -> void:
	var root := Node3D.new()
	root.name = "Ground"
	add_child(root)

	# kind -> Array[ {mesh, mat, rel, instances: Array[Transform3D]} ]
	var kinds := {}
	for y in range(ROWS):
		for x in range(COLS):
			var c := Vector2i(x, y)
			var kind := _tile_for(c)
			if not kinds.has(kind):
				kinds[kind] = _collect_tile_meshes(kind)
			# 瓦片按「底面」摆放（cell_to_world 给的是顶面高度，这里要退回到 GROUND_Y）
			var w := cell_to_world(c)
			var cell_tf := Transform3D(
				Basis().scaled(Vector3(ModelLib.SCALE, ModelLib.SCALE, ModelLib.SCALE)),
				Vector3(w.x, GROUND_Y, w.z)
			)
			for info in kinds[kind]:
				info["instances"].append(cell_tf * info["rel"])

	for kind in kinds:
		for info in kinds[kind]:
			var insts: Array = info["instances"]
			var mat = info["mat"]
			# 草地：整片 mint 色太平了，压一点蓝、加一点黄绿，再按格子随机微调亮度，
			# 远看就是一块一块的草皮（和参考图那种草地质感接近）。
			var tint_grass: bool = kind == "tile" and mat is BaseMaterial3D
			if tint_grass:
				var tinted: BaseMaterial3D = (mat as BaseMaterial3D).duplicate()
				tinted.albedo_color = Color(1.0, 0.98, 0.60)
				tinted.vertex_color_use_as_albedo = true
				mat = tinted

			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = info["mesh"]
			mm.use_colors = tint_grass
			mm.instance_count = insts.size()
			for i in range(insts.size()):
				mm.set_instance_transform(i, insts[i])
				if tint_grass:
					var tf: Transform3D = insts[i]
					var n := sin(tf.origin.x * 12.9898 + tf.origin.z * 78.233) * 43758.5453
					var f: float = n - floor(n)
					var v := 0.965 + 0.065 * f
					mm.set_instance_color(i, Color(v, v * (0.995 + 0.02 * f), v * 0.97))
			var mmi := MultiMeshInstance3D.new()
			mmi.name = kind
			mmi.multimesh = mm
			mmi.material_override = mat
			root.add_child(mmi)


## 收集某瓦片模型的所有 mesh（含相对偏移与材质），返回 info 字典数组
func _collect_tile_meshes(kind: String) -> Array:
	var out: Array = []
	var node := ModelLib.instance(kind)
	if node == null:
		return out
	_collect_meshes_rec(node, Transform3D(), out)
	node.free()
	return out


func _collect_meshes_rec(n: Node, acc: Transform3D, out: Array) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mesh: Mesh = mi.mesh
		if mesh != null and mesh.get_surface_count() > 0:
			var mat = mi.material_override
			if mat == null:
				mat = mesh.surface_get_material(0)
			out.append({"mesh": mesh, "mat": mat, "rel": acc, "instances": []})
	for c in n.get_children():
		var child_tf := acc
		if c is Node3D:
			child_tf = acc * (c as Node3D).transform
		_collect_meshes_rec(c, child_tf, out)


func _tile_for(c: Vector2i) -> String:
	# 基地贴在最左边，把那 2×2 的岩石换成草地，水晶才像「嵌在城墙里的核心」
	if is_home(c):
		return "tile"
	# 入口格也换成草地，边界岩墙在这里留一个「城门」，出生踏板才看得见
	if spawns.has(c):
		return "tile"
	# 河床：草瓦片打底，水与河岸由 _build_water 铺在上面
	if _is_water(c):
		return "tile"
	var d := decor_at(c)
	if d == "R":
		return "tile-rock"
	if d == "T":
		return "tile-tree"
	var corner := (c.x == 0 or c.x == COLS - 1) and (c.y == 0 or c.y == ROWS - 1)
	if corner:
		return "tile-tree"
	if is_border(c):
		return "tile-rock"
	return "tile"


func _build_spawn_markers() -> void:
	var root := Node3D.new()
	root.name = "SpawnMarkers"
	add_child(root)
	for s in spawns:
		var pad := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(CELL * 0.7, 0.10, CELL * 0.7)
		pad.mesh = bm
		pad.material_override = _flat_mat(Color(0.95, 0.28, 0.35), 0.7, "spawn_pad")
		pad.position = cell_to_world(s) + Vector3(0.0, 0.05, 0.0)
		root.add_child(pad)

		# 朝内指的箭头（锥体默认朝 +Y，先让它朝 -Z，再用 look_at 指向基地）
		var pivot := Node3D.new()
		pivot.position = cell_to_world(s) + Vector3(0.0, 0.35, 0.0)
		root.add_child(pivot)

		var arrow := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.30
		cm.height = 0.55
		cm.radial_segments = 8
		arrow.mesh = cm
		arrow.material_override = _flat_mat(Color(1.0, 0.45, 0.45), 0.9)
		arrow.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		pivot.add_child(arrow)

		var d := _inward_dir(s)
		pivot.look_at(pivot.position + Vector3(float(d.x), 0.0, float(d.y)), Vector3.UP)


func _inward_dir(c: Vector2i) -> Vector2i:
	var d := Vector2i.ZERO
	if c.x <= 0:
		d.x = 1
	elif c.x >= COLS - 1:
		d.x = -1
	if c.y <= 0:
		d.y = 1
	elif c.y >= ROWS - 1:
		d.y = -1
	return d


func _build_home() -> void:
	_home_root = Node3D.new()
	_home_root.name = "Home"
	var center := Vector3.ZERO
	for h in home_cells:
		center += cell_to_world(h)
	center /= float(home_cells.size())
	_home_root.position = center + Vector3(0.0, 0.02, 0.0)
	add_child(_home_root)

	# 左侧水晶：Kenney 的大水晶模型（放大 + 染成蓝色 + 浮空 + 旋转）
	_crystal = ModelLib.instance("detail-crystal-large")
	if _crystal != null:
		_crystal.scale = Vector3(3.2, 3.2, 3.2)
		ModelLib.tint(_crystal, Color(0.45, 0.90, 1.0))
		_home_root.add_child(_crystal)
		_crystal.position.y = 0.35

	_home_ring = MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 1.85
	rm.bottom_radius = 1.85
	rm.height = 0.04
	rm.radial_segments = 40
	_home_ring.mesh = rm
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.albedo_color = Color(0.30, 0.85, 1.0, 0.35)
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_home_ring.material_override = rmat
	_home_ring.position.y = 0.05
	_home_root.add_child(_home_ring)

	var light := OmniLight3D.new()
	light.light_color = Color(0.35, 0.85, 1.0)
	light.light_energy = 2.2
	light.omni_range = 10.0
	light.position.y = 1.6
	_home_root.add_child(light)

	_build_home_bar()


## 水晶头顶的血条：一块始终正对相机的 quad，填充宽度由着色器 ratio 控制，
## 上方再跟一个「当前 / 最大」的数字，血条与数字都随生命值实时变化。
func _build_home_bar() -> void:
	_bar_root = Node3D.new()
	_bar_root.name = "CrystalHealthBar"
	var bar_y := 0.35
	if _crystal != null:
		bar_y += ModelLib.height_of(_crystal) * 3.2 + 0.55
	_bar_root.position = Vector3(0.0, bar_y, 0.0)
	_home_root.add_child(_bar_root)

	var sh := Shader.new()
	sh.code = "\n".join(HOME_BAR_SHADER)
	_bar_mat = ShaderMaterial.new()
	_bar_mat.shader = sh

	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(3.2, 0.34)
	quad.mesh = qm
	quad.material_override = _bar_mat
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar_root.add_child(quad)

	_bar_label = Label3D.new()
	_bar_label.text = "%d / %d" % [GameState.lives, _max_hp]
	_bar_label.font_size = 44
	_bar_label.pixel_size = 0.0036
	_bar_label.outline_size = 10
	_bar_label.modulate = Color(0.88, 0.97, 1.0)
	_bar_label.no_depth_test = true
	_bar_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bar_label.position = Vector3(0.0, 0.30, 0.0)
	_bar_root.add_child(_bar_label)


## 生命值变化：只有「刷新出的新高」才会抬高上限（卡牌回血不会让血条超出 100%）
func _on_lives_changed(v: int) -> void:
	_max_hp = maxi(_max_hp, v)
	_refresh_home_bar()


func _refresh_home_bar() -> void:
	if _bar_mat == null:
		return
	var cap := maxi(_max_hp, 1)
	var hp := clampi(GameState.lives, 0, cap)
	_bar_mat.set_shader_parameter("ratio", float(hp) / float(cap))
	if _bar_label != null:
		_bar_label.text = "%d / %d" % [hp, cap]


## 手动把血条朝向相机：自定义着色器不能用 billboard（会丢掉缩放），
## 但血条不需要缩放，直接套相机基向量即可 —— 和敌人血条的做法一致。
func _face_home_bar() -> void:
	if _bar_root == null or not is_inside_tree():
		return
	if _cam == null or not is_instance_valid(_cam):
		_cam = get_viewport().get_camera_3d()
	if _cam == null:
		return
	var t := _bar_root.global_transform
	t.basis = _cam.global_transform.basis.orthonormalized()
	_bar_root.global_transform = t


# ---------------------------------------------------------------- 地面 / 水 / 路 / 桥

## 河面：沿河心生成一条带状 mesh（比逐格铺贴片更顺，也不会出现同格重叠的 z-fighting）。
## 河岸比河面宽 0.45 露出一圈浅沙，河面再压在上面。
func _build_water() -> void:
	# 逐行中点是一条「楼梯」折线，过一遍 Catmull-Rom 才是一条自然的河。
	# 摆动加大以后每行能横向跳 1~2 格，所以每段插 6 个点，弯道才不会被切成折线。
	var center := _smooth_centerline(_river_centerline(), 6)
	if center.size() < 2:
		return

	var root := Node3D.new()
	root.name = "Water"
	add_child(root)

	var bank := SurfaceTool.new()
	bank.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_polyline_ribbon(bank, center, CELL + 0.45, SURFACE_Y + BANK_Y, 8.0, false, PackedFloat32Array(), 0.0)
	var bank_mi := MeshInstance3D.new()
	bank_mi.name = "Bank"
	bank_mi.mesh = bank.commit()
	var bank_mat := StandardMaterial3D.new()
	bank_mat.albedo_color = Color(0.60, 0.52, 0.34)
	bank_mat.roughness = 1.0
	bank_mi.material_override = bank_mat
	bank_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(bank_mi)

	var water := SurfaceTool.new()
	water.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_polyline_ribbon(water, center, CELL, SURFACE_Y + WATER_Y, 8.0, false, PackedFloat32Array(), 0.0)

	var mi := MeshInstance3D.new()
	mi.name = "River"
	mi.mesh = water.commit()
	mi.material_override = _water_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## 河心线：逐行取河面两格的中点，得到一条从地图上方蜿蜒到下方的折线
func _river_centerline() -> PackedVector3Array:
	var pts := PackedVector3Array()
	for y in range(ROWS):
		var lo := COLS
		var hi := -1
		for x in range(COLS):
			if _is_water(Vector2i(x, y)):
				lo = mini(lo, x)
				hi = maxi(hi, x)
		if hi < 0:
			continue
		var mid := (float(lo) + float(hi)) * 0.5
		pts.append(Vector3(
			(mid - (COLS - 1) * 0.5) * CELL,
			SURFACE_Y,
			(float(y) - (ROWS - 1) * 0.5) * CELL
		))
	return pts


## Catmull-Rom 加密：把楼梯折线变成圆滑的河道曲线（steps = 每段插几个点）
func _smooth_centerline(pts: PackedVector3Array, steps: int) -> PackedVector3Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector3Array()
	for i in range(pts.size() - 1):
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, pts.size() - 1)]
		for s in range(steps):
			var t := float(s) / float(steps)
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * (
				(2.0 * p1) +
				(-p0 + p2) * t +
				(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
				(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
			))
	out.append(pts[pts.size() - 1])
	return out


## 水面色：深浅两层青蓝 + 两层错相流动的波纹，Unshaded 保证俯视角下颜色稳定
func _water_mat() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = "\n".join([
		"shader_type spatial;",
		"render_mode unshaded, cull_disabled;",
		"uniform vec3 deep_col : source_color = vec3(0.13, 0.40, 0.55);",
		"uniform vec3 light_col : source_color = vec3(0.42, 0.76, 0.88);",
		"void fragment() {",
		"	vec2 uv = UV * 6.2831;",
		"	float a = sin(uv.x * 0.9 + uv.y * 0.6 + TIME * 1.1);",
		"	float b = sin(uv.y * 1.5 - uv.x * 1.2 - TIME * 0.8);",
		"	float k = clamp(0.5 + 0.26 * a + 0.20 * b, 0.0, 1.0);",
		"	vec3 col = mix(deep_col, light_col, k * 0.6 + 0.2);",
		"	ALBEDO = col;",
		"	EMISSION = col * 0.18;",
		"}",
	])
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


## 土路：沿 lane 折线生成一条加宽的带状 mesh（转角两端各延长半个路宽，严丝合缝）。
## 路面 3.2 宽、路肩 3.9 宽，比原来一格宽的「贴片路」宽了近一倍。
## 过河的格子不再断开：路面直接铺到桥面上，高度由 _road_ys 跟着桥拱抬起来，
## 所以「路面走过的坡」和「桥面的坡」是同一条曲线（桥面比它低 0.02，藏在底下）。
func _build_roads() -> void:
	var root := Node3D.new()
	root.name = "Roads"
	add_child(root)

	# 路肩只铺在岸上：它比桥面宽，跟着过河会悬在水面上，在桥头收住最干净
	_add_ribbon(root, "RoadShoulder", ROAD_SHOULDER_HALF, SHOULDER_Y,
		Color(0.31, 0.23, 0.15), "path", Color(0.05, 0.035, 0.02), 0.2, false)
	# 路面一路铺过河，Y 跟着桥拱走
	_add_ribbon(root, "Road", ROAD_HALF, ROAD_Y,
		Color(0.55, 0.41, 0.25), "path", Color(0.22, 0.16, 0.09), 0.32, true)

	# 左右各铺一对：外侧是比路面浅一档的干土毛边（土路和草地的交界不再是一条硬直线），
	# 内侧是两道压深、压暗的车辙（路面才有「被反复碾过」的时间感）
	for side in [-1.0, 1.0]:
		var tag: String = "L" if float(side) < 0.0 else "R"
		_add_road_strip(root, "RoadEdge" + tag, float(side) * ROAD_EDGE_LAT, ROAD_EDGE_W, 0.004,
			Color(0.68, 0.54, 0.35), Color(0.27, 0.20, 0.12), 0.30, "path")
		_add_road_strip(root, "RoadRut" + tag, float(side) * RUT_LAT, RUT_W, 0.008,
			Color(0.40, 0.29, 0.17), Color(0.13, 0.09, 0.05), 0.26, "")


func _add_ribbon(root: Node3D, nm: String, half_w: float, y: float,
		col: Color, slot: String, emis: Color, emis_e: float, cross_river: bool) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for lane in lanes:
		if lane.size() < 2:
			continue
		var pts := PackedVector3Array()
		for cc in lane:
			pts.append(cell_to_world(cc))
		if cross_river:
			_add_polyline_ribbon(st, pts, half_w, SURFACE_Y + y, 4.0, false, _road_ys(pts, y), 0.0)
		else:
			_add_polyline_ribbon(st, pts, half_w, SURFACE_Y + y, 4.0, true, PackedFloat32Array(), 0.0)
	var mesh: ArrayMesh = st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return

	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.96
	mat.metallic = 0.0
	if slot != "":
		TextureLib.dress(mat, slot, 1.0)
	mat.emission_enabled = true
	mat.emission = emis
	mat.emission_energy_multiplier = emis_e
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## 路面上的窄装饰带（毛边 / 车辙）：和路面共用同一套逐点高度（过桥要跟着拱走），
## lat 是相对路中心线的横向偏移 —— 左右各铺一条就成了对称的一对。
## dy 只把带子抬高一点点避免 z-fighting，不参与几何计算。
func _add_road_strip(root: Node3D, nm: String, lat: float, half_w: float, dy: float,
		col: Color, emis: Color, emis_e: float, slot: String) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for lane in lanes:
		if lane.size() < 2:
			continue
		var pts := PackedVector3Array()
		for cc in lane:
			pts.append(cell_to_world(cc))
		_add_polyline_ribbon(st, pts, half_w, SURFACE_Y + ROAD_Y + dy, 4.0, false,
			_road_ys(pts, ROAD_Y + dy), lat)
	var mesh: ArrayMesh = st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return

	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.98
	mat.metallic = 0.0
	# white_base = false：有 path 贴图时保留这个暗色调，让车辙仍然是「压深的那一道」
	if slot != "":
		TextureLib.dress(mat, slot, 1.0, false)
	mat.emission_enabled = true
	mat.emission = emis
	mat.emission_energy_multiplier = emis_e
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## 桥面拱高（相对桥头）：两端 0、正中 BRIDGE_CROWN。
## 用 cos 而不是抛物线 —— 桥头和拱顶两处的斜率都是连续变化的，
## 路面压在上面不会在桥头看见一条折痕。
func _crown_lift(z: float, half_len: float) -> float:
	var t := clampf(absf(z) / maxf(half_len, 0.0001), 0.0, 1.0)
	return BRIDGE_CROWN * cos(t * PI * 0.5)


## 折线上「连续的过河格」区间（首尾下标）。桥面和过河路面必须按同一段几何算拱形，
## 否则两边坡度对不上，桥头就会错开 —— 所以两处共用这一个扫描。
func _water_runs(pts: PackedVector3Array) -> Array:
	var runs: Array = []
	var i0 := -1
	for i in range(pts.size() + 1):
		var wet: bool = i < pts.size() and _is_water(world_to_cell(pts[i]))
		if wet and i0 < 0:
			i0 = i
		elif not wet and i0 >= 0:
			runs.append([i0, i - 1])
			i0 = -1
	return runs


## 路面逐点高程：岸上就是 SURFACE_Y + off；落在某座桥的跨度内则加上桥拱的抬升。
## 半长和 _add_bridge 完全一致（水面跨度 + 两端各伸 BRIDGE_SPAN_CELLS 格），
## 所以路面在桥上的高度永远等于「桥面顶 + 0.02」，正好压在木板上。
func _road_ys(pts: PackedVector3Array, off: float) -> PackedFloat32Array:
	var n := pts.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var base := SURFACE_Y + off
	for i in range(n):
		out[i] = base
	for run in _water_runs(pts):
		var center: Vector3 = (pts[run[0]] + pts[run[1]]) * 0.5
		var half: float = pts[run[0]].distance_to(pts[run[1]]) * 0.5 + CELL * BRIDGE_SPAN_CELLS
		var dir: Vector3 = pts[run[1]] - pts[run[0]]
		dir.y = 0.0
		if dir.length() < 0.001:
			continue
		dir = dir.normalized()
		for i in range(n):
			var d: Vector3 = pts[i] - center
			d.y = 0.0
			# 只认「在桥的走向上、并且确实在桥面宽度附近」的点：
			# 同一层 lane 折回来时，垂距会把远处那段路误判成桥面
			if absf(d.cross(dir).y) > CELL * 1.5:
				continue
			var z := d.dot(dir)
			if absf(z) > half:
				continue
			out[i] = base + _crown_lift(z, half)
	return out


## 沿折线生成一条带宽度的带状 mesh。
## 每个点都算一条横截面（转角处用 miter 拉长），相邻横截面之间连成四边形 ——
## 这样 90° 拐角是干净的斜切、曲线段外侧不裂口，比「每段各画一个方块」整齐得多。
## ys   非空时逐点用它当高度（路面过桥要拱起来），否则整条带子压在 y 上。
## lat  沿横截面方向的横向偏移：0 = 以折线为中心，±1 = 偏到半宽那么远。
##      车辙 / 毛边这类「贴在路面上的窄条」靠它平移，平移也走同一条 miter 法向，
##      所以拐角处窄条和路面边缘始终是平行的。
func _add_polyline_ribbon(st: SurfaceTool, pts: PackedVector3Array, half_w: float,
		y: float, uv_scale: float, skip_water: bool, ys: PackedFloat32Array,
		lat: float) -> void:
	var n := pts.size()
	if n < 2:
		return

	var cum := PackedFloat32Array()
	cum.append(0.0)
	for i in range(1, n):
		cum.append(cum[i - 1] + Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length())

	# 每个点的 miter 法向（长度可能 > 1，转角处靠它把宽度补回来），下面乘 half_w / lat
	var nors: Array[Vector3] = []
	for i in range(n):
		var prev := pts[maxi(i - 1, 0)]
		var next := pts[mini(i + 1, n - 1)]
		var dir := Vector3(next.x - prev.x, 0.0, next.z - prev.z)
		if dir.length() < 0.0001:
			dir = Vector3(0.0, 0.0, 1.0)
		dir = dir.normalized()
		var nor := Vector3(-dir.z, 0.0, dir.x)
		if i > 0 and i < n - 1:
			var d0 := Vector3(pts[i].x - pts[i - 1].x, 0.0, pts[i].z - pts[i - 1].z).normalized()
			var d1 := Vector3(pts[i + 1].x - pts[i].x, 0.0, pts[i + 1].z - pts[i].z).normalized()
			var n0 := Vector3(-d0.z, 0.0, d0.x)
			var n1 := Vector3(-d1.z, 0.0, d1.x)
			var m := n0 + n1
			if m.length() < 0.0001:
				m = n1
			m = m.normalized()
			# 用投影把斜切后的宽度还原成 half_w，夹角太尖时夹住避免拉飞
			nor = m / maxf(m.dot(n1), 0.35)
		nors.append(nor)

	var w := (half_w * 2.0) / uv_scale
	var use_ys := ys.size() == n
	for i in range(n - 1):
		if skip_water and (_is_water(world_to_cell(pts[i])) or _is_water(world_to_cell(pts[i + 1]))):
			continue
		var a := pts[i] + nors[i] * lat
		var b := pts[i + 1] + nors[i + 1] * lat
		a.y = ys[i] if use_ys else y
		b.y = ys[i + 1] if use_ys else y
		var oa := nors[i] * half_w
		var ob := nors[i + 1] * half_w
		var u0 := cum[i] / uv_scale
		var u1 := cum[i + 1] / uv_scale
		_quad(st, a + oa, b + ob, b - ob, a - oa,
			Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, w), Vector2(u0, w))


## 两个三角形拼一块朝上的方片。
## 注意绕序：Godot 的正面是「顺时针」，从上方（+Y 俯视）看 p0→p3→p2→p1 才是正向，
## 反过来写会被背面剔除 —— 路面 / 河面会整片消失（排查过一次的坑）。
func _quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3,
		uv0: Vector2, uv1: Vector2, uv2: Vector2, uv3: Vector2) -> void:
	for tri in [[p0, uv0], [p3, uv3], [p2, uv2], [p0, uv0], [p2, uv2], [p1, uv1]]:
		st.set_normal(Vector3.UP)
		st.set_uv(tri[1])
		st.add_vertex(tri[0])


## 木桥：每条 lane 与河相交的那几格自动架一座，桥面比河面长，两端搭在岸上。
func _build_bridges() -> void:
	var root := Node3D.new()
	root.name = "Bridges"
	add_child(root)
	for lane in lanes:
		var i0 := -1
		for i in range(lane.size() + 1):
			var wet: bool = i < lane.size() and _is_water(lane[i])
			if wet and i0 < 0:
				i0 = i
			elif not wet and i0 >= 0:
				_add_bridge(root, lane, i0, i - 1)
				i0 = -1


func _add_bridge(root: Node3D, lane: Array, i0: int, i1: int) -> void:
	var a: Vector3 = cell_to_world(lane[i0])
	var b: Vector3 = cell_to_world(lane[i1])
	var dir := b - a
	dir.y = 0.0
	if dir.length() < 0.01:
		dir = Vector3.RIGHT
	dir = dir.normalized()

	var center := (a + b) * 0.5
	# 节点原点压在「桥头高程」上，子节点的 y 直接就是拱高（_crown_lift）
	center.y = SURFACE_Y + BRIDGE_END
	var span_len: float = a.distance_to(b) + CELL        # 水面本身跨度（护栏用这个长度）
	# 桥面比水面两端各多伸 BRIDGE_SPAN_CELLS 格：插到岸上的路面底下，接缝被路面盖住。
	# 这个半长必须和 _road_ys 里算的一模一样，路面的坡才对得上桥面的坡。
	var deck_len: float = a.distance_to(b) + CELL * BRIDGE_SPAN_CELLS * 2.0
	var half := deck_len * 0.5
	# 桥面比路面每侧宽 BRIDGE_DECK_EXTRA：木色从路边露出来，才看得出「这是座桥」
	var deck_w := ROAD_HALF * 2.0 + BRIDGE_DECK_EXTRA * 2.0

	var node := Node3D.new()
	node.name = "Bridge"
	node.position = center
	node.rotation.y = atan2(dir.x, dir.z)
	root.add_child(node)

	var wood := _wood_mat()
	# 桥面：拆成十几块木板顺着拱形铺，每块按自己的局部坡度倾斜 ——
	# 一块平板做不出拱，硬掰又会和路面错开
	var segs := maxi(8, int(round(deck_len / 0.5)))
	var step := deck_len / float(segs)
	for i in range(segs):
		# 两端各多铺 2cm，斜口接缝不会漏出缝来
		var z0 := -half + step * float(i) - 0.02
		var z1 := -half + step * float(i + 1) + 0.02
		_beam(node, deck_w, BRIDGE_THICK,
			Vector3(0.0, _crown_lift(z0, half) - BRIDGE_THICK * 0.5, z0),
			Vector3(0.0, _crown_lift(z1, half) - BRIDGE_THICK * 0.5, z1), wood)

	# 两侧护栏：横梁 + 立柱。横梁也分段跟着拱走（一整根直的会从拱顶穿出来），
	# 长度只取水面跨度，别跟着桥面伸到岸上的路面里，否则路面上会凭空多出两截栏杆。
	for side in [-1.0, 1.0]:
		var x: float = side * (deck_w * 0.5 - 0.10)
		var spans := maxi(4, int(round(span_len / 0.9)))
		var rstep := span_len / float(spans)
		for i in range(spans):
			var z0 := -span_len * 0.5 + rstep * float(i)
			var z1 := z0 + rstep
			_beam(node, 0.10, 0.10,
				Vector3(x, _crown_lift(z0, half) + BRIDGE_RAIL_Y, z0),
				Vector3(x, _crown_lift(z1, half) + BRIDGE_RAIL_Y, z1), wood)
		for k in range(-1, 2):
			var z: float = float(k) * span_len * 0.40
			_bridge_part(node, Vector3(0.14, 0.40, 0.14),
				Vector3(x, _crown_lift(z, half) + 0.17, z), wood)


## 一段顺着 p0→p1 的方梁（桥板 / 护栏共用）：BoxMesh 的 Z 轴直接对准两点连线，
## 于是每块板都按拱形的坡度倾斜，接缝是连续斜口而不是一级级台阶。
func _beam(parent: Node3D, w: float, h: float, p0: Vector3, p1: Vector3, mat: Material) -> void:
	var d := p1 - p0
	var ln := d.length()
	if ln < 0.0001:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, ln)
	mi.mesh = bm
	mi.material_override = mat
	mi.transform = Transform3D(Basis.looking_at(d / ln, Vector3.UP), (p0 + p1) * 0.5)
	parent.add_child(mi)


func _bridge_part(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _wood_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.46, 0.31, 0.18)
	m.roughness = 0.88
	m.metallic = 0.0
	TextureLib.dress(m, "path", 1.0)
	return m


## 布防台的尺寸：一块压得很低的方石台 + 台面铺四条木板，
## 台脚再露一线青光表示「这一格能建塔」。三种几何各自合批，21 个台子 3 个 draw call。
const SLOT_BASE_H := 0.04             # 石台厚度（台面顶 = 0.84）
const SLOT_PLANK_W := 0.36            # 木板宽（沿 X）
const SLOT_PLANK_H := 0.02            # 木板厚：铺完台面顶 0.86，塔底陷进去 0.06，看不出来
const SLOT_PLANK_GAP := 0.03          # 木板缝
const SLOT_PLANK_LEN := CELL * 0.78   # 木板长（沿 Z）


## 布防台：石砌矮台 + 木板台面 + 台脚一线青光。
## 石台 / 木板都开 use_colors 做逐块明暗抖动（和草地同一个套路），不然一片纯色像塑料。
func _build_slot_markers() -> void:
	if build_slots.is_empty():
		return
	var count := build_slots.size()

	# 台脚光边：比石台大一圈，四周露出来的一道青线就是「可建造」提示
	var rim_mm := MultiMesh.new()
	rim_mm.transform_format = MultiMesh.TRANSFORM_3D
	var rim_mesh := BoxMesh.new()
	rim_mesh.size = Vector3(CELL * 0.92, 0.014, CELL * 0.92)
	rim_mm.mesh = rim_mesh
	rim_mm.instance_count = count
	var rim_mat := _flat_mat(Color(0.40, 0.86, 1.0, 0.50), 0.7)
	rim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# 石台
	var base_mm := MultiMesh.new()
	base_mm.transform_format = MultiMesh.TRANSFORM_3D
	base_mm.use_colors = true
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(CELL * 0.86, SLOT_BASE_H, CELL * 0.86)
	base_mm.mesh = base_mesh
	base_mm.instance_count = count
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.53, 0.54, 0.56)
	base_mat.roughness = 1.0
	base_mat.metallic = 0.0
	base_mat.vertex_color_use_as_albedo = true

	# 木板台面：每个台子 4 条
	var deck_mm := MultiMesh.new()
	deck_mm.transform_format = MultiMesh.TRANSFORM_3D
	deck_mm.use_colors = true
	var deck_mesh := BoxMesh.new()
	deck_mesh.size = Vector3(SLOT_PLANK_W, SLOT_PLANK_H, SLOT_PLANK_LEN)
	deck_mm.mesh = deck_mesh
	deck_mm.instance_count = count * 4
	var deck_mat := StandardMaterial3D.new()
	deck_mat.albedo_color = Color(0.56, 0.41, 0.25)
	deck_mat.roughness = 0.9
	deck_mat.metallic = 0.0
	deck_mat.vertex_color_use_as_albedo = true

	var pitch := SLOT_PLANK_W + SLOT_PLANK_GAP
	for i in range(count):
		var w := cell_to_world(build_slots[i])
		rim_mm.set_instance_transform(i, Transform3D(Basis(), w + Vector3(0.0, 0.007, 0.0)))
		base_mm.set_instance_transform(i,
			Transform3D(Basis(), w + Vector3(0.0, SLOT_BASE_H * 0.5 - 0.004, 0.0)))
		# 每块石头的明暗差一点点，远看才像一块块凿出来的石板而不是一整块灰塑料
		var bv: float = 0.90 + 0.14 * _hash01(float(build_slots[i].x) * 12.9898 + float(build_slots[i].y) * 78.233)
		base_mm.set_instance_color(i, Color(bv, bv, bv * 1.02))
		for k in range(4):
			var slot := i * 4 + k
			var x: float = (float(k) - 1.5) * pitch
			deck_mm.set_instance_transform(slot, Transform3D(Basis(),
				w + Vector3(x, SLOT_BASE_H + SLOT_PLANK_H * 0.5 - 0.004, 0.0)))
			var pv: float = 0.88 + 0.18 * _hash01(float(slot) * 3.71 + 1.7)
			deck_mm.set_instance_color(slot, Color(pv, pv * 0.99, pv * 0.95))

	_add_multimesh("SlotRims", rim_mm, rim_mat)
	_add_multimesh("SlotBases", base_mm, base_mat)
	_add_multimesh("SlotDecks", deck_mm, deck_mat)


## 把一份 MultiMesh + 材质挂成一个不投影的实例（地面 / 布防台共用这个套路）
func _add_multimesh(nm: String, mm: MultiMesh, mat: Material) -> void:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## 0..1 的稳定伪随机（同样的输入永远同样的输出，重开一局台面不会跳色）
func _hash01(v: float) -> float:
	var n := sin(v) * 43758.5453
	return n - floor(n)


## 路线方向的流动箭头：两条 lane 各一串沿「入口 → 水晶」方向滚动的三角形，
## 比静态路面更直观地告诉玩家敌人会从哪边走、在哪汇合。
func _build_path_flow() -> void:
	_routes.clear()
	for lane in lanes:
		if lane.size() < 2:
			continue
		var pts := PackedVector3Array()
		for cc in lane:
			pts.append(cell_to_world(cc))
		# 箭头是「压在路面上」的，路面过桥会拱起来，箭头的高度也得跟着抬，
		# 否则桥心那几格箭头会直接陷进路面里看不见
		var ys := _road_ys(pts, ROAD_Y)
		for i in range(pts.size()):
			pts[i].y = ys[i]
		var cum := PackedFloat32Array()
		var acc := 0.0
		for i in range(pts.size()):
			if i > 0:
				acc += pts[i].distance_to(pts[i - 1])
			cum.append(acc)
		if acc <= 0.0:
			continue
		_routes.append({"pts": pts, "cum": cum, "len": acc})
	if _routes.is_empty():
		return

	var total := 0.0
	for r in _routes:
		total += float(r["len"])
	_flow_sets.clear()
	var count := 0
	for i in range(_routes.size()):
		var ln := float(_routes[i]["len"])
		var cnt := maxi(4, int(round(float(FLOW_ARROW_COUNT) * ln / maxf(total, 0.001))))
		_flow_sets.append({"route": i, "count": cnt, "gap": ln / float(cnt)})
		count += cnt
	if count <= 0:
		return

	_flow_mm = MultiMesh.new()
	_flow_mm.transform_format = MultiMesh.TRANSFORM_3D
	_flow_mm.mesh = _make_arrow_mesh()
	_flow_mm.instance_count = count
	_flow_mm.visible_instance_count = count

	# 箭头用暖白色：压在棕色土路上对比最大，不会和路面糊在一起
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.94, 0.76)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.86, 0.55)
	mat.emission_energy_multiplier = 1.1
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "PathFlowArrows"
	mmi.multimesh = _flow_mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_flow_mi = mmi

	_update_flow(0.0)


## 路面箭头：一个扁平的三角形（尖端朝 +Z），用 SurfaceTool 直接拼出来
func _make_arrow_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	st.add_vertex(Vector3(0.0, 0.0, 0.42))
	st.set_normal(Vector3.UP)
	st.add_vertex(Vector3(-0.28, 0.0, -0.14))
	st.set_normal(Vector3.UP)
	st.add_vertex(Vector3(0.28, 0.0, -0.14))
	return st.commit()


## 路线箭头只在「准备阶段」当提示用：开波之后敌人自己会走，箭头反而变成挡视线的杂色。
## 由 Main 每帧按 wave_active 同步（内部有变化才真的赋值，重复调用没有成本）。
func set_flow_visible(on: bool) -> void:
	if _flow_mi != null and _flow_mi.visible != on:
		_flow_mi.visible = on


## 箭头每秒沿各自路线前进，形成「流向水晶」的动画
func _update_flow(delta: float) -> void:
	if _flow_mm == null or _routes.is_empty():
		return
	# 隐藏时连实例变换都不写，省下每帧 60 多次 set_instance_transform
	if _flow_mi != null and not _flow_mi.visible:
		return
	_flow_t = fposmod(_flow_t + delta * FLOW_SPEED * CELL, 4096.0)
	var slot := 0
	for fs in _flow_sets:
		var r: Dictionary = _routes[int(fs["route"])]
		var pts: PackedVector3Array = r["pts"]
		var cum: PackedFloat32Array = r["cum"]
		var route_len: float = float(r["len"])
		var cnt: int = int(fs["count"])
		var gap: float = float(fs["gap"])
		for j in range(cnt):
			var s := fposmod(_flow_t + gap * float(j), route_len)
			var seg := _seg_at(cum, s)
			var a: Vector3 = pts[seg]
			var b: Vector3 = pts[seg + 1]
			var seg_len: float = maxf(cum[seg + 1] - cum[seg], 0.001)
			var k := clampf((s - cum[seg]) / seg_len, 0.0, 1.0)
			var dir := b - a
			dir.y = 0.0
			if dir.length_squared() < 0.0001:
				_flow_mm.set_instance_transform(slot, Transform3D(Basis().scaled(Vector3.ZERO), a))
				slot += 1
				continue
			# 从入口「长出来」、在水晶前收小消失，避免箭头糊在基地上
			var fade := clampf(s / (CELL * 1.5), 0.0, 1.0) * clampf((route_len - s) / (CELL * 1.2), 0.0, 1.0)
			var sc := 0.15 + 0.85 * fade
			var basis := Basis(Vector3.UP, atan2(dir.x, dir.z)).scaled(Vector3(sc, 1.0, sc))
			_flow_mm.set_instance_transform(slot, Transform3D(basis, a.lerp(b, k) + Vector3(0.0, FLOW_Y, 0.0)))
			slot += 1


## s（沿路线的弧长）落在第几段上
func _seg_at(cum: PackedFloat32Array, s: float) -> int:
	var i := clampi(int(s / CELL), 0, cum.size() - 2)
	while i > 0 and cum[i] > s:
		i -= 1
	while i < cum.size() - 2 and cum[i + 1] <= s:
		i += 1
	return i


func _flat_mat(col: Color, energy: float = 0.6, slot: String = "") -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	if slot != "":
		TextureLib.dress(m, slot)
	return m

# ---------------------------------------------------------------- 坐标

func idx(c: Vector2i) -> int:
	return c.y * COLS + c.x


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < COLS and c.y < ROWS


func cell_to_world(c: Vector2i) -> Vector3:
	return Vector3(
		(c.x - (COLS - 1) * 0.5) * CELL,
		SURFACE_Y,
		(c.y - (ROWS - 1) * 0.5) * CELL
	)


func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(
		int(round(p.x / CELL + (COLS - 1) * 0.5)),
		int(round(p.z / CELL + (ROWS - 1) * 0.5))
	)


func is_border(c: Vector2i) -> bool:
	return c.x == 0 or c.y == 0 or c.x == COLS - 1 or c.y == ROWS - 1


func is_home(c: Vector2i) -> bool:
	for h in home_cells:
		if h == c:
			return true
	return false


## 某出生格的刷怪点（在棋盘外一点）
func spawn_world_for(c: Vector2i) -> Vector3:
	var p := cell_to_world(c)
	if c.x == 0:
		p.x -= CELL * 1.4
	elif c.x == COLS - 1:
		p.x += CELL * 1.4
	if c.y == 0:
		p.z -= CELL * 1.4
	elif c.y == ROWS - 1:
		p.z += CELL * 1.4
	return p

# ---------------------------------------------------------------- 占位

func is_blocked(c: Vector2i) -> bool:
	if not in_bounds(c):
		return true
	return blocked[idx(c)] != 0


func set_blocked(c: Vector2i, v: bool) -> void:
	if not in_bounds(c):
		return
	blocked[idx(c)] = 1 if v else 0


func tower_at(c: Vector2i):
	if not in_bounds(c):
		return null
	return towers.get(idx(c), null)


## 只能建在「布防台」上：外圈、基地、路线格与普通草地都不行
func can_place(c: Vector2i) -> bool:
	if not in_bounds(c):
		return false
	if is_border(c):
		return false
	if is_home(c):
		return false
	if is_path(c):
		return false
	if not is_build_slot(c):
		return false
	if is_blocked(c):
		return false
	if has_enemy_in_cell(c):
		return false
	return true


## 该格是否属于敌人固定路线
func is_path(c: Vector2i) -> bool:
	return _path_set.has(c)


func has_enemy_in_cell(c: Vector2i) -> bool:
	var w := cell_to_world(c)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e):
			continue
		var p: Vector3 = e.global_position
		if abs(p.x - w.x) < CELL * 0.65 and abs(p.z - w.z) < CELL * 0.65:
			return true
	return false

# ---------------------------------------------------------------- 路径 / 距离场

func rebuild_flow() -> void:
	_dist = _compute_dist()


func _compute_dist() -> PackedInt32Array:
	var total := COLS * ROWS
	var d := PackedInt32Array()
	d.resize(total)
	for i in range(total):
		d[i] = -1

	var queue: Array = []
	for h in home_cells:
		var hi := idx(h)
		d[hi] = 0
		queue.append(h)

	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var ci := idx(cur)
		for dir in DIRS:
			var n: Vector2i = cur + dir
			if not in_bounds(n):
				continue
			var ni := idx(n)
			if d[ni] != -1 or blocked[ni] != 0:
				continue
			d[ni] = d[ci] + 1
			queue.append(n)
	return d


## 固定路线：入口始终可达
func reachable_spawns() -> Array[Vector2i]:
	return spawns


## 从 c 出发沿固定路线走到基地，返回格子序列（含起点与基地格）。
## c 是某个入口 → 直接返回那条 lane；其它情况走兜底：挑「离 c 最近的路线格」，
## 从那一格顺着它所属的 lane 继续走到基地。
func path_home_cells_from(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if lanes.is_empty():
		return out
	for lane in lanes:
		if not lane.is_empty() and lane[0] == c:
			for pc in lane:
				out.append(pc)
			return out

	var best_lane := 0
	var best_i := 0
	var best_d := 1 << 30
	for li in range(lanes.size()):
		var lane: Array = lanes[li]
		for i in range(lane.size()):
			var pc: Vector2i = lane[i]
			var d := absi(pc.x - c.x) + absi(pc.y - c.y)
			if d < best_d:
				best_d = d
				best_lane = li
				best_i = i
	var lane_out: Array = lanes[best_lane]
	for i in range(best_i, lane_out.size()):
		out.append(lane_out[i])
	return out


func path_home_world_from(c: Vector2i) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for cc in path_home_cells_from(c):
		out.append(cell_to_world(cc))
	return out


## 找到离 c 最近的「能走到基地」的格子（兜底，避免敌人卡死）
func nearest_reachable(c: Vector2i) -> Vector2i:
	if not in_bounds(c):
		return home_cells[0]
	var queue: Array = [c]
	var seen := {}
	seen[idx(c)] = true
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		if _dist[idx(cur)] >= 0:
			return cur
		for dir in DIRS:
			var n: Vector2i = cur + dir
			if not in_bounds(n):
				continue
			var ni := idx(n)
			if seen.has(ni):
				continue
			seen[ni] = true
			queue.append(n)
	return home_cells[0]


## 路线 / 路面是静态几何（建塔不会改路），这里只需要重算距离场再广播一次
func refresh() -> void:
	rebuild_flow()
	grid_changed.emit()
