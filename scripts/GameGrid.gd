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
## 破冰小径的半宽：只有路面的不到一半 —— 窄才像「被怪物从雪径凿进湖里的一道口子」
const BREACH_HALF := 0.78
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

## 路面视觉平滑：把「逐格折线」过一遍 Catmull-Rom，90° 拐角就不再是硬直角，
## 看起来更像参考图里那种绕着地形走的土路。敌人仍然走格心（逻辑完全不变），
## 平滑只会让路往拐角内侧收一点点（半个格子以内，半宽 1.6 足够盖住）。
const ROAD_SMOOTH := 3                # 每段插几个点（1 = 不平滑）

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

## 地形装饰 / 敌人路线 / 河道参数都不再写死在这里 —— 它们是「地图数据」，
## 统一放在 scripts/MapDefs.gd 的 MAPS 表里（R = 岩壁、T = 树丛、. = 草地）。
## GameGrid 只负责按数据把网格摊开；想加一张新地图不用改这个文件。

## 路线上的流动箭头（沿行进方向滚动，玩家一眼能看出怪往哪走）
const FLOW_ARROW_COUNT := 64
const FLOW_SPEED := 3.0               # 箭头滚动速度（格 / 秒）
const FLOW_Y := 0.14                  # 箭头离地高度（压在路面之上，避免 z-fighting）

## 雪面着色器：两层不同频率的噪声混出「压实雪 + 阴影处偏蓝」的质感。
## 关键点是噪声取**世界坐标**（MODEL_MATRIX * VERTEX），而不是每格各自的 UV ——
## 否则 588 块独立平面会各自重复一张噪声图，格子边界上能看出明显的接缝。
const SNOW_SHADER := [
	"shader_type spatial;",
	"uniform vec3 snow_a : source_color = vec3(0.74, 0.87, 1.0);",
	"uniform vec3 snow_b : source_color = vec3(0.47, 0.66, 0.92);",
	"varying vec3 wp;",
	"float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }",
	"float noise(vec2 p) {",
	"	vec2 i = floor(p);",
	"	vec2 f = fract(p);",
	"	f = f * f * (3.0 - 2.0 * f);",
	"	float a = hash(i);",
	"	float b = hash(i + vec2(1.0, 0.0));",
	"	float c = hash(i + vec2(0.0, 1.0));",
	"	float d = hash(i + vec2(1.0, 1.0));",
	"	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);",
	"}",
	"void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }",
	"void fragment() {",
	"	float n = noise(wp.xz * 0.32) * 0.62 + noise(wp.xz * 1.35) * 0.38;",
	"	vec3 col = mix(snow_b, snow_a, smoothstep(0.22, 0.86, n));",
	"	ALBEDO = col;",
	"	ROUGHNESS = 0.92;",
	"}",
]

## 融水着色器：亮青色的活水 + 细碎反光条。
## 和冰面的区别要在「一眼能看出来」的级别：冰是白裂纹的死板平面，融水是会动的浅青水。
const MELT_SHADER := [
	"shader_type spatial;",
	"render_mode unshaded, cull_disabled;",
	"uniform vec3 deep_col : source_color = vec3(0.04, 0.33, 0.48);",
	"uniform vec3 light_col : source_color = vec3(0.22, 0.70, 0.84);",
	"uniform vec3 foam : source_color = vec3(0.84, 0.97, 1.0);",
	"void fragment() {",
	# UV 是「8 世界单位 = 1」，这里再乘 6 → 一层波纹约 3 个世界单位宽。
	# 频率太低（之前 UV*2.2）会变成一整片几十单位宽的亮斑，看着像发光的地板而不是水。
	"	vec2 uv = UV * 6.0;",
	# 先按低频噪声把 uv 拧一下，不然整片水就是一条条等距的直条纹
	"	uv += vec2(sin(uv.y * 0.9 + TIME * 0.5), sin(uv.x * 0.7 - TIME * 0.4)) * 0.6;",
	"	float a = sin(uv.x * 2.6 + uv.y * 0.8 + TIME * 1.6) * 0.5 + 0.5;",
	"	float b = sin(uv.y * 3.2 - uv.x * 1.1 - TIME * 1.1) * 0.5 + 0.5;",
	"	float k = clamp(a * 0.55 + b * 0.45, 0.0, 1.0);",
	"	vec3 col = mix(deep_col, light_col, k);",
	"	float sparkle = smoothstep(0.88, 1.0, sin(uv.x * 4.3 + uv.y * 3.7 + TIME * 2.1) * 0.5 + 0.5);",
	"	col = mix(col, foam, sparkle * 0.45);",
	"	ALBEDO = col;",
	"	EMISSION = col * 0.12;",
	"}",
]

## 冻湖着色器：大片青蓝冰面 + 两层交错的白色裂纹，比河流的流动波纹更适合冰。
const ICE_SHADER := [
	"shader_type spatial;",
	"render_mode unshaded, cull_disabled;",
	"uniform vec3 base_col : source_color = vec3(0.34, 0.90, 0.97);",
	"uniform vec3 deep_col : source_color = vec3(0.06, 0.42, 0.70);",
	"uniform vec3 crack_col : source_color = vec3(0.88, 1.0, 1.0);",
	"void fragment() {",
	"	vec2 uv = UV * 1.6;",
	"	float n1 = sin(uv.x * 1.7 + sin(uv.y * 0.9) * 1.5) * 0.5 + 0.5;",
	"	float n2 = sin(uv.y * 2.3 + sin(uv.x * 1.3) * 1.2) * 0.5 + 0.5;",
	"	vec3 col = mix(deep_col, base_col, clamp(n1 * 0.6 + n2 * 0.4, 0.0, 1.0));",
	"	float c1 = abs(sin(uv.x * 2.3 + sin(uv.y * 1.9) * 2.7));",
	"	float c2 = abs(sin(uv.y * 1.7 + sin(uv.x * 2.1) * 2.2));",
	"	float crack = smoothstep(0.07, 0.0, c1) + smoothstep(0.06, 0.0, c2);",
	"	col = mix(col, crack_col, clamp(crack, 0.0, 0.75));",
	"	ALBEDO = col;",
	"	EMISSION = col * 0.25;",
	"}",
]

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
var _water_set := {}                  # 水域格（不可建塔 / 不可装饰）
var _melted := {}                     # 其中的「融水」格：不铺冰面，改铺流动水面
var _decor := {}                      # 格子 -> "R" 岩壁 / "T" 树丛 / "P" 占位道具
## 破冰小径：从雪径分岔、直插冰湖的窄道，**只有碎冰者会走**（普通怪仍然沿 lane）。
## 它同时会挡掉布防台和装饰，保证这条道永远是通的。
var _breach_lines: Array = []         # Array[Array[Vector2i]]：每条小径的逐格序列
var _breach_set := {}
## 碎冰者的「横穿水面路线」（地图数据 swim_cross 展开后的逐格序列，首尾都是雪径格）。
## 有它就不用 A* 自己挑近路了 —— 设计师画的那条线才是它该给玩家看到的场面。
var _swim_cross: Array[Vector2i] = []

# ---------------------------------------------------------------- 地图数据
## 由 Main 在 add_child() 之前写入（_ready() 里才读得到，所以不能挂到 _ready 之后再设）。
## 为空时回退到 MapDefs.DEFAULT_ID。
var map_id: String = ""
var map_def: Dictionary = {}          # MapDefs.MAPS[...] 的那一条（只读，不要改）
var _decor_map: Array = []            # 21 行地形字符表
var _lane_defs: Array = []            # 每条路线一串拐点
var _river_cfg: Dictionary = {}       # 河道参数（enabled=false 表示无河无桥）
var _props: Array = []                # 占位道具（模型未做之前先撑场面）

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
	_load_map()
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
	_build_breach_paths()
	_build_bridges()
	_build_spawn_markers()
	_build_home()
	_build_path_flow()
	_build_slot_markers()
	_build_props()
	GameState.lives_changed.connect(_on_lives_changed)
	_refresh_home_bar()
	refresh()


## 读地图数据。必须在 _ready 的其它初始化之前调用（lanes / 装饰 / 水都依赖它）。
func _load_map() -> void:
	if map_id == "":
		map_id = MapDefs.DEFAULT_ID
	map_def = MapDefs.get_map(map_id)
	_decor_map = map_def.get("decor", [])
	_lane_defs = map_def.get("lanes", [])
	_river_cfg = map_def.get("river", {})
	_props = map_def.get("props", [])
	_make_breach()
	_make_swim_cross()
	if _lane_defs.is_empty():
		push_error("GameGrid: 地图 %s 没有配置 lanes，敌人不会出现" % map_id)


## 破冰小径：数据里给一串拐点（从雪径拐角一路拐到湖岸），这里展开成逐格序列。
## 小径必须停在**最后一个岸上格** —— 水面那一段交给碎冰者自己砸开，
## 否则会画出一条悬在冰面上的窄路，看着像给普通怪铺的通道。
func _make_breach() -> void:
	_breach_lines = []
	_breach_set.clear()
	for line in map_def.get("breach", []):
		var cells: Array[Vector2i] = []
		for i in range(line.size() - 1):
			for c in _line_cells(Vector2i(line[i]), Vector2i(line[i + 1])):
				if cells.is_empty() or cells[cells.size() - 1] != c:
					cells.append(c)
		if cells.size() < 2:
			continue
		for c in cells:
			_breach_set[c] = true
		_breach_lines.append(cells)


## 碎冰者的横穿路线：把数据里的拐点折线展开成逐格序列。
## 拐点必须横平竖直（和 lanes / breach 一样），否则 _line_cells 会走成直角折线。
func _make_swim_cross() -> void:
	_swim_cross = []
	var pts: Array = map_def.get("swim_cross", [])
	for i in range(pts.size() - 1):
		for c in _line_cells(Vector2i(pts[i]), Vector2i(pts[i + 1])):
			if _swim_cross.is_empty() or _swim_cross[_swim_cross.size() - 1] != c:
				_swim_cross.append(c)


## 两格之间的逐格折线（先横后竖，和 _lane_from 的走法一致）
func _line_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = [a]
	var cur := a
	while cur != b:
		if cur.x != b.x:
			cur.x += signi(b.x - cur.x)
		elif cur.y != b.y:
			cur.y += signi(b.y - cur.y)
		out.append(cur)
	return out


## 基地位置：地图数据可以给一组格（2×2 / 2×1 都行），缺省是「最左侧、上下居中的 2×2」。
## 注意：敌人走到 lane 的最后一格就算冲线（见 Enemy._leak），所以每条 lane 的终点
## 必须与 home 四邻接，否则敌人会在家门口站着不走。
func _make_home_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in map_def.get("home", []):
		out.append(Vector2i(c))
	if out.is_empty():
		var cy := ROWS / 2
		out = [
			Vector2i(0, cy - 1), Vector2i(1, cy - 1),
			Vector2i(0, cy), Vector2i(1, cy),
		]
	return out


## 多路线主体：每条路线就是 MapDefs 里的一串拐点，展开成逐格序列。
## 拐点必须横平竖直；两条（或多条）路线最后都要汇进同一条通往水晶的主路。
func _make_lanes() -> Array:
	var out: Array = []
	for wps in _lane_defs:
		if wps is Array and wps.size() >= 2:
			out.append(_lane_from(wps))
	return out


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


## 河道走向：河心（2 格宽河道的中心列，浮点）在 river.mid 附近按两条正弦摆动，
## 21 行正好走完一个完整的 S 弯。参数全部来自地图数据（MapDefs.MAPS[*]["river"]），
## 不想让这张图有河，把 river.enabled 设成 false 即可。
func _river_x(y: int) -> float:
	var t := float(y)
	var freq := float(_river_cfg.get("freq", 0.26))
	var main := sin(t * freq) * float(_river_cfg.get("swing", 2.0))
	var wobble := sin(t * freq * 2.17 + 1.3) * float(_river_cfg.get("wobble", 0.5))
	return float(_river_cfg.get("mid", 15.5)) + main + wobble


## 水域有两种来源：
##   ① river.enabled = true → 沿 _river_x() 逐行铺一条 width 格宽的水带（裂谷的河）；
##   ② river.enabled = false → 改读地形表里的冰面字符：
##        I = 结冰（铺裂纹冰面）、W = 融化（铺流动水面）—— 一片湖可以一半冻一半化。
## lane 与水域相交的格子会自动变成桥位（仅河流模式需要）。
func _make_water_cells() -> Dictionary:
	var out := {}
	if not bool(_river_cfg.get("enabled", true)):
		_melted.clear()
		for y in range(mini(_decor_map.size(), ROWS)):
			var row := str(_decor_map[y])
			for x in range(mini(row.length(), COLS)):
				var ch := row[x]
				if ch != "I" and ch != "W":
					continue
				var c := Vector2i(x, y)
				out[c] = true
				if ch == "W":
					_melted[c] = true
		return out

	var w := maxi(int(_river_cfg.get("width", 2)), 1)
	var half := (float(w) - 1.0) * 0.5
	var rows: Array = _river_cfg.get("rows", [0, ROWS - 1])
	var y0 := 0
	var y1 := ROWS - 1
	if rows.size() > 0:
		y0 = int(rows[0])
	if rows.size() > 1:
		y1 = int(rows[1])
	for y in range(mini(y0, y1), maxi(y0, y1) + 1):
		var x0 := int(round(_river_x(y) - half))
		x0 = clampi(x0, 2, COLS - 1 - w)
		for dx in range(w):
			var c := Vector2i(x0 + dx, y)
			if in_bounds(c):
				out[c] = true
	return out


func _is_water(c: Vector2i) -> bool:
	return _water_set.has(c)


## 这张图有没有水域（决定波次里要不要放会破冰的敌人）
func has_water() -> bool:
	return not _water_set.is_empty()


## 解析地图的地形字符表：岩壁 / 树丛只长在空地上（不压路、不压基地、不落水）。
## 占位道具的格子额外标成 "P"：它本身不换瓦片，但同样会挡掉布防台
## （否则塔会和占位方块叠在一起）。
func _make_decor() -> Dictionary:
	var out := {}
	if _decor_map.size() != ROWS:
		push_warning("GameGrid: 地图 %s 的地形表行数 %d != %d" % [map_id, _decor_map.size(), ROWS])
	for y in range(mini(_decor_map.size(), ROWS)):
		var row := str(_decor_map[y])
		if row.length() != COLS:
			push_warning("GameGrid: 地图 %s 地形表第 %d 行长度 %d != %d" % [map_id, y, row.length(), COLS])
		for x in range(mini(row.length(), COLS)):
			var ch := row[x]
			if ch != "R" and ch != "T":
				continue
			var c := Vector2i(x, y)
			# 破冰小径上不长石头 / 树：碎冰者得能顺着它走到岸边
			if is_home(c) or is_path(c) or _is_water(c) or spawns.has(c) or _breach_set.has(c):
				continue
			out[c] = ch
	for p in _props:
		var c := Vector2i(p.get("cell", Vector2i(-1, -1)))
		if not in_bounds(c) or is_home(c) or is_path(c) or _is_water(c) or spawns.has(c):
			continue
		out[c] = "P"
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
	# 破冰小径也要留空：塔摆在上面挡的是碎冰者唯一的下水口
	if _breach_set.has(c):
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


## 铺设地面瓦片：内部草地（或冰原的雪面）、外圈岩石（提示这里不能建塔）、四角种树。
## 用 MultiMesh 合并同类瓦片，588 个瓦片只需几个 draw call。
func _build_ground() -> void:
	var root := Node3D.new()
	root.name = "Ground"
	add_child(root)

	# 冰原图（ground = "snow"）：草地瓦片换成一块压平的雪面 ——
	# Kenney 的草皮是绿的，靠 albedo 相乘染不成雪白，只能换几何 + 换材质。
	var snow: bool = str(map_def.get("ground", "grass")) == "snow"

	# kind -> Array[ {mesh, mat, rel, instances: Array[Transform3D]} ]
	var kinds := {}
	for y in range(ROWS):
		for x in range(COLS):
			var c := Vector2i(x, y)
			var kind := _tile_for(c)
			if not kinds.has(kind):
				kinds[kind] = _collect_snow_tile() if (snow and kind == "tile") else _collect_tile_meshes(kind)
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
			# 每种瓦片都可以被地图整体调色：裂谷的草地压黄绿（整片 mint 太平），
			# 冰原的岩壁压成深蓝（Kenney 的石头是灰的，压蓝就是冻岩）。
			var tint_col = _tile_tint(kind)
			var tint_grass: bool = kind == "tile" and tint_col != null and mat is BaseMaterial3D
			if tint_col != null and mat is BaseMaterial3D:
				var tinted: BaseMaterial3D = (mat as BaseMaterial3D).duplicate()
				tinted.albedo_color = tint_col
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


## 地图给某一类瓦片的整体色调（没有配置就返回 null，用模型原色）
func _tile_tint(kind: String) -> Variant:
	var p: Dictionary = map_def.get("palette", {})
	var key := ""
	match kind:
		"tile": key = "grass"
		"tile-rock": key = "rock"
		"tile-tree": key = "tree"
	if key != "" and p.has(key):
		return p[key]
	return null


## 雪地瓦片：不用 GLB，直接给每格铺一块 1×1 平面（乘 SCALE 后正好 2×2 = 一格），
## 顶面落在 SURFACE_Y。雪面着色器用「世界坐标」算噪声，格子之间不会出现接缝。
func _collect_snow_tile() -> Array:
	var pm := PlaneMesh.new()
	pm.size = Vector2(CELL / ModelLib.SCALE, CELL / ModelLib.SCALE)
	var sh := Shader.new()
	sh.code = "\n".join(SNOW_SHADER)
	var mat := ShaderMaterial.new()
	mat.shader = sh
	return [{
		"mesh": pm, "mat": mat,
		"rel": Transform3D(Basis(), Vector3(0.0, (SURFACE_Y - GROUND_Y) / ModelLib.SCALE, 0.0)),
		"instances": [],
	}]


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
		# 冰原图没有树：四角也用岩石（压成深蓝就是洞窟的岩壁）
		return "tile-tree" if bool(map_def.get("corner_tree", true)) else "tile-rock"
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

## 水面总入口：河（沿折线的带子）和冻湖（逐格铺）是两种完全不同的画法，
## 用哪种由地图数据决定，外面（_ready）不用关心。
func _build_water() -> void:
	# 完全没有水域：连节点都不建
	if _water_set.is_empty():
		return
	if bool(_river_cfg.get("enabled", true)):
		_build_river_water()
	else:
		_build_ice_field()


## 河面：沿河心生成一条带状 mesh（比逐格铺贴片更顺，也不会出现同格重叠的 z-fighting）。
## 河岸比河面宽 0.45 露出一圈浅沙，河面再压在上面。总宽度来自地图数据（width 格）。
func _build_river_water() -> void:
	# 逐行中点是一条「楼梯」折线，过一遍 Catmull-Rom 才是一条自然的河。
	# 摆动加大以后每行能横向跳 1~2 格，所以每段插 6 个点，弯道才不会被切成折线。
	var center := _smooth_centerline(_river_centerline(), 6)
	if center.size() < 2:
		return

	var half := float(_river_cfg.get("width", 2)) * CELL * 0.5
	var bank_col: Color = _river_cfg.get("bank_color", Color(0.60, 0.52, 0.34))

	var root := Node3D.new()
	root.name = "Water"
	add_child(root)

	var bank := SurfaceTool.new()
	bank.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_polyline_ribbon(bank, center, half + 0.45, SURFACE_Y + BANK_Y, 8.0, false, PackedFloat32Array(), 0.0)
	var bank_mi := MeshInstance3D.new()
	bank_mi.name = "Bank"
	bank_mi.mesh = bank.commit()
	var bank_mat := StandardMaterial3D.new()
	bank_mat.albedo_color = bank_col
	bank_mat.roughness = 1.0
	bank_mi.material_override = bank_mat
	bank_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(bank_mi)

	var water := SurfaceTool.new()
	water.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_polyline_ribbon(water, center, half, SURFACE_Y + WATER_Y, 8.0, false, PackedFloat32Array(), 0.0)

	var mi := MeshInstance3D.new()
	mi.name = "River"
	mi.mesh = water.commit()
	mi.material_override = _water_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## 冻湖（逐格模式）：地形表里 "I" 铺冰面、"W" 铺流动水面 —— 一片湖可以一半结冰一半融化。
## 为什么不用河那条带子：湖要在中间挖出湖湾和「舌头」，带子的宽度是恒定的，
## 只能画出等宽的河；逐格铺才能完全照着地形表画形状，代价是边缘是格子台阶。
## UV 取世界坐标（不是每格 0..1），所以冰面的裂纹 / 水面的波纹都是连续的一整片。
func _build_ice_field() -> void:
	var frozen := SurfaceTool.new()
	frozen.begin(Mesh.PRIMITIVE_TRIANGLES)
	var melted := SurfaceTool.new()
	melted.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := CELL * 0.5
	for k in _water_set.keys():
		var c := Vector2i(k)
		var w := cell_to_world(c)
		# 融水比冰面低 0.02：俯视角下冰面像一整块浮着的壳，水面沉在下面
		var y := SURFACE_Y + WATER_Y + (0.0 if _melted.has(c) else 0.02)
		var p := Vector3(w.x, y, w.z)
		var st: SurfaceTool = melted if _melted.has(c) else frozen
		_add_quad_uv(st,
			p + Vector3(-half, 0.0, -half), p + Vector3(-half, 0.0, half),
			p + Vector3(half, 0.0, half), p + Vector3(half, 0.0, -half),
			8.0)

	var root := Node3D.new()
	root.name = "Water"
	add_child(root)
	_add_water_surface(root, "IceField", frozen.commit(), _ice_mat())
	# 融水用单独的亮青活水 shader：比冰面暗一档、还会动，一眼就能看出哪半边化了
	_add_water_surface(root, "Meltwater", melted.commit(), _melt_mat())


## 把一块水面 mesh 挂成不投影的实例（空 mesh 直接跳过）
func _add_water_surface(root: Node3D, nm: String, mesh: ArrayMesh, mat: Material) -> void:
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## 铺一块朝上的方片，UV 直接由世界坐标算出（scale = 多少世界单位对应 1 个 UV）
func _add_quad_uv(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3,
		scale: float) -> void:
	_quad(st, p0, p1, p2, p3,
		Vector2(p0.x, p0.z) / scale, Vector2(p1.x, p1.z) / scale,
		Vector2(p2.x, p2.z) / scale, Vector2(p3.x, p3.z) / scale)


## 冰面材质：青蓝底 + 白色裂纹，unshaded 保证俯视角下颜色稳定（和河面同一套路）
func _ice_mat() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = "\n".join(ICE_SHADER)
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


## 融水材质：亮青活水 + 流动反光
func _melt_mat() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = "\n".join(MELT_SHADER)
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


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

	# 路面配色由地图给（palette）：裂谷是棕色土路，冰原是雪白古道。
	# 自发光统一按「底色 × road_glow」算，裂谷的 glow=0.4 正好还原原来的四个发光值。
	var pal: Dictionary = map_def.get("palette", {})
	var glow := float(pal.get("road_glow", 0.4))
	var c_shoulder: Color = pal.get("road_shoulder", Color(0.31, 0.23, 0.15))
	var c_road: Color = pal.get("road", Color(0.55, 0.41, 0.25))
	var c_edge: Color = pal.get("road_edge", Color(0.68, 0.54, 0.35))
	var c_rut: Color = pal.get("road_rut", Color(0.40, 0.29, 0.17))

	# 路肩只铺在岸上：它比桥面宽，跟着过河会悬在水面上，在桥头收住最干净
	_add_ribbon(root, "RoadShoulder", ROAD_SHOULDER_HALF, SHOULDER_Y,
		c_shoulder, "path", c_shoulder * glow * 0.4, 0.2, false)
	# 路面一路铺过河，Y 跟着桥拱走
	_add_ribbon(root, "Road", ROAD_HALF, ROAD_Y,
		c_road, "path", c_road * glow, 0.32, true)

	# 左右各铺一对：外侧是比路面浅一档的干土毛边（土路和草地的交界不再是一条硬直线），
	# 内侧是两道压深、压暗的车辙（路面才有「被反复碾过」的时间感）
	for side in [-1.0, 1.0]:
		var tag: String = "L" if float(side) < 0.0 else "R"
		_add_road_strip(root, "RoadEdge" + tag, float(side) * ROAD_EDGE_LAT, ROAD_EDGE_W, 0.004,
			c_edge, c_edge * glow, 0.30, "path")
		_add_road_strip(root, "RoadRut" + tag, float(side) * RUT_LAT, RUT_W, 0.008,
			c_rut, c_rut * glow * 0.82, 0.26, "")


## 破冰小径：从雪径分岔、直插湖岸的窄道，只有碎冰者会走（普通怪仍然沿 lane）。
## 比路面窄一半、颜色更冷更深，一眼就能和雪径区分 —— 玩家看到它该想到
## 「会有东西从这里下水」，而不是以为它是第二条主路。
func _build_breach_paths() -> void:
	if _breach_lines.is_empty():
		return
	var root := Node3D.new()
	root.name = "BreachPath"
	add_child(root)
	# 底槽更深更宽，上面压一层亮冰色：像被硬生生凿出来的一道沟
	_breach_ribbon(root, "BreachBase", BREACH_HALF + 0.18, ROAD_Y + 0.006,
		Color(0.09, 0.28, 0.44), 0.12)
	_breach_ribbon(root, "BreachCore", BREACH_HALF, ROAD_Y + 0.010,
		Color(0.40, 0.72, 0.88), 0.34)


func _breach_ribbon(root: Node3D, nm: String, half_w: float, y: float,
		col: Color, emis_e: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cells in _breach_lines:
		if cells.size() < 2:
			continue
		var pts := PackedVector3Array()
		for cc in cells:
			pts.append(cell_to_world(cc))
		pts = _smooth_centerline(pts, ROAD_SMOOTH)
		# 尾巴朝水面方向多伸小半格：小径和冰面之间不能留一条雪缝，
		# 否则看上去还是「走到岸边就断了」。skip_water 关掉才不会被这一截截掉。
		var last := pts[pts.size() - 1]
		var prev := pts[pts.size() - 2]
		var d := Vector3(last.x - prev.x, 0.0, last.z - prev.z)
		if d.length() > 0.001:
			pts.append(last + d.normalized() * CELL * 0.45)
		_add_polyline_ribbon(st, pts, half_w, SURFACE_Y + y, 4.0, false,
			PackedFloat32Array(), 0.0)
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
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = emis_e
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


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
		pts = _smooth_centerline(pts, ROAD_SMOOTH)
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
		pts = _smooth_centerline(pts, ROAD_SMOOTH)
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
	# 没有河就没有桥位，整个子树可以省掉
	if _water_set.is_empty():
		return
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
const SLOT_SNOW_H := 0.07             # 雪地图的雪台厚度（台面顶 ≈ 0.866，和石台版齐平）


## 布防台：石砌矮台 + 木板台面 + 台脚一线青光。
## 石台 / 木板都开 use_colors 做逐块明暗抖动（和草地同一个套路），不然一片纯色像塑料。
func _build_slot_markers() -> void:
	if build_slots.is_empty():
		return
	# 雪地图（MapDefs 里 ground = "snow"）用白雪台：石台 + 木板在整张白蓝的雪原上是
	# 唯一的灰 / 暖褐色块，扎眼得像贴了别人的素材。草地地图保持原样。
	if str(map_def.get("ground", "grass")) == "snow":
		_build_snow_slots()
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


## 雪地图的布防台：一块压实积雪的白色圆台 + 台脚一线青光。
## 造型说明：上窄下宽的斜边是「积雪堆出来」的关键 —— 上下一样粗的圆柱看起来像塑料块；
## 颜色比地面亮一档、略偏蓝（雪地反光偏蓝，纯白反而像发光），靠明度差和青边区分「能建塔」。
## 最外圈再加一道很淡的冷色投影：纯靠明度差的话，白台会像「贴」在雪面上的贴纸。
## 三种几何各自合批，3 个 draw call（原来的石台版也是 3 个）。
func _build_snow_slots() -> void:
	var count := build_slots.size()

	# 接地的淡投影：比雪台大一圈，只露最外沿
	var shadow_mm := MultiMesh.new()
	shadow_mm.transform_format = MultiMesh.TRANSFORM_3D
	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius = CELL * 0.50
	shadow_mesh.bottom_radius = CELL * 0.50
	shadow_mesh.height = 0.010
	shadow_mesh.radial_segments = 20
	shadow_mm.mesh = shadow_mesh
	shadow_mm.instance_count = count
	var shadow_mat := StandardMaterial3D.new()
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_mat.albedo_color = Color(0.10, 0.34, 0.52, 0.22)
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	# 台脚光边：和石台版同样的青线，只是改成圆的
	var rim_mm := MultiMesh.new()
	rim_mm.transform_format = MultiMesh.TRANSFORM_3D
	var rim_mesh := CylinderMesh.new()
	rim_mesh.top_radius = CELL * 0.45
	rim_mesh.bottom_radius = CELL * 0.45
	rim_mesh.height = 0.014
	rim_mesh.radial_segments = 20
	rim_mm.mesh = rim_mesh
	rim_mm.instance_count = count
	var rim_mat := _flat_mat(Color(0.40, 0.86, 1.0, 0.50), 0.7)
	rim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# 雪台：台面顶和石台版齐平（≈0.866），塔底照样陷进去一点，不会看着浮在雪上
	var pad_mm := MultiMesh.new()
	pad_mm.transform_format = MultiMesh.TRANSFORM_3D
	pad_mm.use_colors = true
	var pad_mesh := CylinderMesh.new()
	pad_mesh.top_radius = CELL * 0.38
	pad_mesh.bottom_radius = CELL * 0.43
	pad_mesh.height = SLOT_SNOW_H
	pad_mesh.radial_segments = 20
	pad_mm.mesh = pad_mesh
	pad_mm.instance_count = count
	var pad_mat := StandardMaterial3D.new()
	# 别用纯白：霜渊的环境光很亮，纯白会直接过曝成一个没有体积感的圆片。
	# 略压一档 + 偏蓝，才能看出「压实的雪」，同时和地面的雪面拉开一点明度差。
	pad_mat.albedo_color = Color(0.80, 0.88, 0.98)
	pad_mat.roughness = 0.95
	pad_mat.metallic = 0.0
	pad_mat.vertex_color_use_as_albedo = true

	for i in range(count):
		var w := cell_to_world(build_slots[i])
		shadow_mm.set_instance_transform(i, Transform3D(Basis(), w + Vector3(0.0, 0.002, 0.0)))
		rim_mm.set_instance_transform(i, Transform3D(Basis(), w + Vector3(0.0, 0.007, 0.0)))
		pad_mm.set_instance_transform(i,
			Transform3D(Basis(), w + Vector3(0.0, SLOT_SNOW_H * 0.5 - 0.004, 0.0)))
		# 每块雪的明暗差一点点：一整片纯白会糊成一整块，看不出「一格一格」
		var v: float = 0.88 + 0.14 * _hash01(float(build_slots[i].x) * 12.9898
			+ float(build_slots[i].y) * 78.233)
		pad_mm.set_instance_color(i, Color(v * 0.96, v * 0.99, v))

	_add_multimesh("SlotShadows", shadow_mm, shadow_mat)
	_add_multimesh("SlotRims", rim_mm, rim_mat)
	_add_multimesh("SlotSnow", pad_mm, pad_mat)


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


## 占位道具：专属模型还没做的地图先摆几块几何体撑场面，别让整张图空成一片草地。
## kind：pad = 「待建区域」标记、obelisk = 方尖碑（地图地标）。
## 这些格子已经在 _make_decor 里记成 "P"，不会和布防台 / 塔重叠。
func _build_props() -> void:
	if _props.is_empty():
		return
	var root := Node3D.new()
	root.name = "Props"
	root.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(root)
	for p in _props:
		var c := Vector2i(p.get("cell", Vector2i(-1, -1)))
		if not in_bounds(c):
			continue
		var base := cell_to_world(c)
		match str(p.get("kind", "pad")):
			"obelisk":
				_build_obelisk(root, base)
			"crystal":
				_build_crystal(root, base)
			"spike":
				_build_ice_spikes(root, base)
			_:
				_build_placeholder_pad(root, base)


## 「待建区域」：一块半透明青方砖 + 亮色描边 + 悬浮文字。
## 全图视角下 0.2 高的字只有几像素，所以字号按世界尺寸给到约 0.5 高，缩到最远也读得出来。
func _build_placeholder_pad(root: Node3D, base: Vector3) -> void:
	var slab := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(CELL * 0.9, 0.05, CELL * 0.9)
	slab.mesh = bm
	var mat := _flat_mat(Color(0.35, 0.78, 1.0, 0.38), 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	slab.material_override = mat
	slab.position = base + Vector3(0.0, 0.05, 0.0)
	slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(slab)

	# 描边：比方砖再大一圈的薄框，让占位区域在满屏草地上一眼能找到
	var rim := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(CELL * 0.94, 0.02, CELL * 0.94)
	rim.mesh = rm
	var rim_mat := _flat_mat(Color(0.55, 0.95, 1.0, 0.85), 1.0)
	rim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rim.material_override = rim_mat
	rim.position = base + Vector3(0.0, 0.02, 0.0)
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(rim)

	var label := Label3D.new()
	label.text = "待建区域"
	label.font_size = 64
	label.pixel_size = 0.0075
	label.outline_size = 14
	label.modulate = Color(0.72, 0.96, 1.0)
	label.no_depth_test = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = base + Vector3(0.0, 1.2, 0.0)
	root.add_child(label)


## 方尖碑：三块方石逐层收窄，顶上一颗发光的小棱柱 —— 纯几何体地标，等模型到位再替换。
func _build_obelisk(root: Node3D, base: Vector3) -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.40, 0.37, 0.34)
	stone.roughness = 0.95
	var sizes := [Vector3(2.2, 1.8, 2.2), Vector3(1.6, 1.5, 1.6), Vector3(1.0, 1.3, 1.0)]
	var y := 0.0
	for i in range(sizes.size()):
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = sizes[i]
		mi.mesh = bm
		mi.material_override = stone
		mi.position = base + Vector3(0.0, y + float(sizes[i].y) * 0.5, 0.0)
		mi.rotation.y = 0.16 * float(i)
		root.add_child(mi)
		y += float(sizes[i].y)

	var glow := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.42
	cm.height = 0.7
	cm.radial_segments = 6
	glow.mesh = cm
	glow.material_override = _flat_mat(Color(1.0, 0.72, 0.38), 1.2)
	glow.position = base + Vector3(0.0, y + 0.34, 0.0)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glow)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.70, 0.40)
	light.light_energy = 1.4
	light.omni_range = 8.0
	light.position = base + Vector3(0.0, y + 0.6, 0.0)
	root.add_child(light)


## 冰晶群：复用 Kenney 的大水晶模型（和水晶基地同一个），染成冰蓝 + 一盏冷光。
## 对应参考图右上角那丛蓝色晶柱。
func _build_crystal(root: Node3D, base: Vector3) -> void:
	var n := ModelLib.instance("detail-crystal-large")
	if n != null:
		n.scale = Vector3(3.6, 3.6, 3.6)
		ModelLib.tint(n, Color(0.50, 0.92, 1.0))
		n.position = base + Vector3(0.0, 0.02, 0.0)
		n.rotation_degrees = Vector3(0.0, 24.0, 0.0)
		root.add_child(n)
	# 旁边再插一根细的，别像单独一根柱子
	var small := ModelLib.instance("detail-crystal-large")
	if small != null:
		small.scale = Vector3(1.9, 2.4, 1.9)
		ModelLib.tint(small, Color(0.62, 0.96, 1.0))
		small.position = base + Vector3(0.85, 0.0, 0.55)
		small.rotation_degrees = Vector3(0.0, -32.0, 0.0)
		root.add_child(small)
	var light := OmniLight3D.new()
	light.light_color = Color(0.45, 0.88, 1.0)
	light.light_energy = 1.6
	light.omni_range = 8.0
	light.position = base + Vector3(0.0, 1.4, 0.0)
	root.add_child(light)


## 冰刺：几根白色锥体从雪里斜刺出来（参考图下缘那种碎冰）。
## 形状用格子世界坐标做稳定伪随机，重开一局不会换一套。
func _build_ice_spikes(root: Node3D, base: Vector3) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.97, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.45, 0.85, 1.0)
	mat.emission_energy_multiplier = 0.25
	mat.roughness = 0.55
	var seed_f := _hash01(base.x * 0.7 + base.z * 1.3)
	for i in range(4):
		var t := float(i)
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.34 + 0.28 * _hash01(t * 7.1 + seed_f)
		cm.height = 1.5 + 1.2 * _hash01(t * 3.7 + seed_f * 2.0)
		cm.radial_segments = 5
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = mat
		var a := t * 1.9 + seed_f * 6.28
		var r := 0.30 + 0.55 * _hash01(t * 5.3 + seed_f)
		mi.position = base + Vector3(cos(a) * r, cm.height * 0.5 - 0.05, sin(a) * r)
		mi.rotation_degrees = Vector3(7.0 * sin(a), 0.0, 7.0 * cos(a))
		root.add_child(mi)


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
		# 和路面用同一套平滑，箭头才不会在拐角和路面错开
		pts = _smooth_centerline(pts, ROAD_SMOOTH)
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
	return cells_to_world(path_home_cells_from(c))


## 逐格序列 → 世界坐标序列（破冰路线和普通路线共用同一套换算）
func cells_to_world(cells: Array[Vector2i]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for cc in cells:
		out.append(cell_to_world(cc))
	return out


## 碎冰者专用：可以**穿过湖面**的寻路。
## 普通敌人只能沿 lane 走，它会在冰上砸开一条直线过去，所以这里不能再用 lane，
## 而是直接在整张网格上跑一次带权最短路：
##   陆地格：只要没有岩壁 / 树 / 占位道具就能走（塔不算障碍，塔本来就建在路外）；
##   水面格：全部可走，但每格多算 WATER_COST ——
##           这样「绕湖更短」时它还是走岸上，只有过湖确实近才会下水。
## 返回 {"cells": Array[Vector2i], "from": int, "to": int}：
##   cells 是从入口到水晶的逐格序列，from / to 是其中「水面连续段」的首尾下标（没有水就是 -1）。
func swim_route_home(from: Vector2i) -> Dictionary:
	var out := {}
	if home_cells.is_empty() or not in_bounds(from):
		return out
	# 地图里画了横穿路线就完全照它走（见 MapDefs 的 swim_cross）：
	# 玩家看到的是「从破冰小径下水 → 横穿湖面 → 另一侧上岸」，而不是 A* 挑的贴岸切角。
	if _swim_cross.size() >= 2:
		var via := _route_via_swim_cross(from)
		if not via.is_empty():
			return via
	# 起点不在路 / 小径 / 水上（上帝模式点的是空地）：先走到最近的可走格，
	# 再把「原来那一格」补在路线最前面 —— 看起来就是它先走上路面，再决定要不要下水。
	var lead: Array[Vector2i] = []
	var begin_cell := from
	if not _swim_passable(begin_cell):
		begin_cell = _nearest_swim_cell(from)
		if begin_cell == from:
			return out
		lead.append(from)

	# 水面**更便宜**：这个权重表达的不是「走多快」，而是「它愿不愿意下水」。
	# 用 1.0 时，绕湖的雪径和穿湖的距离差不多，A* 会挑中绕湖 → 碎冰者根本不湿身；
	# 调到 0.85，只要过湖不比绕路明显更远，它就会砸冰横穿。
	const WATER_COST := 0.85
	var total := COLS * ROWS
	var g := PackedFloat32Array()
	g.resize(total)
	g.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(total)
	prev.fill(-1)
	var done := PackedByteArray()
	done.resize(total)

	var goals := {}
	for h in home_cells:
		goals[idx(h)] = true

	var start := idx(begin_cell)
	g[start] = 0.0
	var open: Array[int] = [start]
	var goal := -1
	while not open.is_empty():
		# 格子只有 588 个，线性扫最小 f 比维护堆更省事，也足够快（每波最多调几十次）
		var best_i := 0
		var best_f := INF
		for i in range(open.size()):
			var oi: int = open[i]
			var f: float = g[oi] + _swim_h(oi, goals)
			if f < best_f:
				best_f = f
				best_i = i
		var cur: int = open[best_i]
		open.remove_at(best_i)
		if done[cur] != 0:
			continue
		done[cur] = 1
		if goals.has(cur):
			goal = cur
			break
		var cc := Vector2i(cur % COLS, cur / COLS)
		for dir in DIRS:
			var n: Vector2i = cc + dir
			if not _swim_passable(n):
				continue
			var ni := idx(n)
			if done[ni] != 0:
				continue
			var step := 1.0
			if _is_water(n):
				step = WATER_COST
			elif _breach_set.has(n):
				# 破冰小径就是给它修的：让它一定从画出来的那道口子下水，
				# 不然路线和画面各走各的，玩家会看到它从雪坡上「凭空入水」。
				step = 0.5
			var ng: float = g[cur] + step
			if ng + 0.0001 < g[ni]:
				g[ni] = ng
				prev[ni] = cur
				open.append(ni)
	if goal < 0:
		return out

	var cells: Array[Vector2i] = []
	var walk := goal
	while walk >= 0:
		cells.append(Vector2i(walk % COLS, walk / COLS))
		walk = prev[walk]
	cells.reverse()

	# 水面连续段：取最长的一段（正常就是一整段，保险起见防兜底路径来回上岸）
	var best_from := -1
	var best_to := -1
	var run_from := -1
	for i in range(cells.size()):
		if _is_water(cells[i]):
			if run_from < 0:
				run_from = i
			if best_from < 0 or i - run_from > best_to - best_from:
				best_from = run_from
				best_to = i
		else:
			run_from = -1
	# 补上「从原地先走到路面」那一段：水面段下标整体后移，Enemy 才知道哪几格在水里
	if not lead.is_empty():
		var merged: Array[Vector2i] = []
		merged.append_array(lead)
		merged.append_array(cells)
		cells = merged
		if best_from >= 0:
			best_from += lead.size()
			best_to += lead.size()
	out["cells"] = cells
	out["from"] = best_from
	out["to"] = best_to
	return out


## 按地图数据画好的横穿路线拼一条「雪径 → 横穿水面 → 另一条雪径」的路线。
##   lane 前缀：当前这条雪径从起点走到分岔口（含分岔口）
##   横穿段：  swim_cross 展开的逐格
##   lane 后缀：从出口格沿着它所属的雪径走到基地
## 起点所在的雪径不经过分岔口（比如怪已经走过分岔口了）时返回空，交给 A* 兜底。
func _route_via_swim_cross(from: Vector2i) -> Dictionary:
	var out := {}
	if _swim_cross.size() < 2:
		return out
	var head: Vector2i = _swim_cross[0]
	var tail: Vector2i = _swim_cross[_swim_cross.size() - 1]
	var lane := path_home_cells_from(from)
	var cut := lane.find(head)
	if cut < 0:
		return out
	var tail_lane := path_home_cells_from(tail)
	if tail_lane.is_empty():
		return out

	var cells: Array[Vector2i] = []
	for i in range(cut + 1):
		cells.append(lane[i])
	for i in range(1, _swim_cross.size()):
		cells.append(_swim_cross[i])
	for i in range(1, tail_lane.size()):
		cells.append(tail_lane[i])

	# 水面段：横穿路线里落在水上的那一截（正常就是连续的一段）
	var best_from := -1
	var best_to := -1
	for i in range(cells.size()):
		if _is_water(cells[i]):
			if best_from < 0:
				best_from = i
			best_to = i
	out["cells"] = cells
	out["from"] = best_from
	out["to"] = best_to
	return out


## 碎冰者的可走判定：水面一律可走（它能砸冰），陆地**只走固定路线和破冰小径**。
##
## 这里原来写的是「陆地只要没装饰就算可走」，A* 于是直接从草地上抄直线：
## 实测从 (20,3) 出发，整条 20 格的路里有 17 格在草坪上、一滴水都没下 ——
## 玩家看到的就是一只巨魔横穿草坪走向基地。它该给玩家的印象是
## 「沿雪径走，只在湖面那一段砸冰抄近道」，所以陆地必须收窄到路面。
func _swim_passable(c: Vector2i) -> bool:
	if not in_bounds(c):
		return false
	if _is_water(c):
		return true
	if is_home(c):
		return true
	return _path_set.has(c) or _breach_set.has(c)


## 离 c 最近的一格「碎冰者站得住」的位置。
## 上帝模式会把怪直接放在空地上，A* 的起点得先落回可走格，否则整条路都算不出来。
## **优先吸附到路面**（和小怪一样先走上雪径），附近实在没有路才直接落水 ——
## 否则点在山坡上会看到它斜着走进湖里，像是从岸上凭空入水。
func _nearest_swim_cell(c: Vector2i) -> Vector2i:
	if not in_bounds(c):
		return c
	var on_road := _bfs_swim_cell(c, true)
	if on_road != c:
		return on_road
	var in_water := _bfs_swim_cell(c, false)
	if in_water != c:
		return in_water
	return c


func _bfs_swim_cell(c: Vector2i, road_only: bool) -> Vector2i:
	var queue: Array[Vector2i] = [c]
	var seen := {idx(c): true}
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var ok := _is_water(cur) if not road_only \
			else (is_home(cur) or _path_set.has(cur) or _breach_set.has(cur))
		if ok:
			return cur
		for dir in DIRS:
			var n: Vector2i = cur + dir
			if not in_bounds(n) or seen.has(idx(n)):
				continue
			seen[idx(n)] = true
			queue.append(n)
	return c


## A* 的启发式：到最近水晶格的曼哈顿距离（水面格子也一样，只是代价更高）
func _swim_h(i: int, goals: Dictionary) -> float:
	var c := Vector2i(i % COLS, i / COLS)
	var best := 1 << 30
	for hi in goals.keys():
		var h := Vector2i(int(hi) % COLS, int(hi) / COLS)
		var d := absi(h.x - c.x) + absi(h.y - c.y)
		if d < best:
			best = d
	return float(best)


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
