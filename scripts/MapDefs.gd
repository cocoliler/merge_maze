class_name MapDefs
extends RefCounted
## 地图表（纯数据，不挂节点）。
##
## 一张地图 = 一份「怎么摆」的描述：地形字符表、敌人固定路线拐点、河道参数、占位道具。
## 真正的几何 / 渲染全部由 GameGrid 的通用代码完成，所以**新增地图不用写新脚本、不用新场景**，
## 只要在 MAPS 里加一条，再在地图切换器里就能直接选到。
##
## 唯一约束：所有地图共用同一套网格尺寸（GameGrid.COLS × ROWS × CELL），
## 因为相机自适应、坐标换算、距离场都直接用这三个常量。想换尺寸要连 GameGrid 一起改。
##
## 字段说明：
##   name / short  切换器与 HUD 上显示的全名 / 短名
##   order         切换器排序 & 「下一张地图」的判定依据（按 order 顺延）
##   desc          一句话简介（切换器里显示）
##   decor         21 行 × 28 字符的地形表：R = 岩壁 / 冻岩、T = 树丛、I = 冻湖、. = 地面
##   lanes         敌人固定路线的拐点（必须横平竖直，最后一段汇入基地前的公共主路）
##   river         enabled = true 走「河」：width = 格宽、rows = [y0, y1] 只在这些行生成；
##                 enabled = false 时改读地形表里的 I 当水域（冻湖，形状随时手改）
##   props         占位 / 地标道具：pad = 待建平台、obelisk = 方尖碑、crystal = 冰晶、spike = 冰刺
##   ground        "snow" 把草地瓦片换成雪面（缺省草地）
##   corner_tree   四角是否种树（缺省 true；冰原图设 false，四角用岩石）
##   palette       瓦片 / 路面配色：grass / rock / tree + road / road_edge / road_rut /
##                 road_shoulder / road_glow（自发光 = 底色 × glow）
##   env           背景色 / 环境光 / 阳光颜色
##   breach        破冰小径的拐点（一串 [起点, 终点] 的格子折线）：从雪径分岔、拐到湖岸，
##                 画成一条窄道，**只有碎冰者会走**。终点必须停在最后一个岸上格，
##                 水面那一段由碎冰者自己砸开；这些格子不放布防台、不长石头。
##   swim_cross    碎冰者横穿水面的折线（[起点, 拐点..., 出口]，首尾都必须是雪径格）；
##                 不写就用 A* 自己挑「水面更便宜」的近路
##   icebreaker    波次里是否混入「碎冰者」（会砸冰横穿水域的怪；只有带冰湖的图才该开）
##                 开了它以后，波次里会自动带上「霜崽」（跟着冰洞游过去的小怪）
##   frostweaver   波次里是否混入「霜语者」（给同伴套冰甲的辅助怪）
##   hint          信息面板里的这张图的说明（不含「下一波」，那部分由 Main 拼）

const DEFAULT_ID := "rift"

## 唯一的游戏场景：切地图不换场景文件，只换这里的目标 id 再重载它。
const MAIN_SCENE := "res://scenes/Main.tscn"

## 运行期「下一张要进的地图」。change_scene_to_file() 不能传参，所以
## 切换器 / 通关跳转都先把目标写在这里，Main._ready() 读走并清空。
static var pending_id: String = ""


static var MAPS := {
	"rift": {
		"name": "裂谷 · 守誓台",
		"short": "裂谷",
		"order": 0,
		"desc": "一条断流的河把战场切成两半，两道古道在西侧汇流。",
		"decor": [
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
		],
		"lanes": [
			[Vector2i(27, 3), Vector2i(22, 3), Vector2i(22, 7),
				Vector2i(8, 7), Vector2i(8, 10), Vector2i(2, 10)],
			[Vector2i(27, 17), Vector2i(22, 17), Vector2i(22, 13),
				Vector2i(8, 13), Vector2i(8, 10), Vector2i(2, 10)],
		],
		"river": {"enabled": true, "mid": 15.5, "swing": 2.0, "freq": 0.26, "wobble": 0.5},
		"props": [],
		# 草地压一点黄绿：整片 mint 色太平了
		"palette": {"grass": Color(1.0, 0.98, 0.60)},
		"env": {"bg": Color(0.045, 0.055, 0.085), "ambient": Color(0.34, 0.42, 0.60),
			"sun": Color(1.0, 0.97, 0.92)},
		"hint": "守住左侧水晶！敌人从右侧两条土路分头压上，中途汇成一路。\n塔只能建在土路旁的蓝色布防台上（数量有限），路径格不可建塔",
	},

	"frost": {
		"name": "霜渊 · 永冻湖",
		"short": "霜渊",
		"order": 1,
		"desc": "冰封的洞窟：中央一片半冻半融的湖，雪径绕着湖岸拐到右下角的守誓台。",
		# 地形表：R = 冻岩 / I = 结冰的湖面 / W = 融化的水面 / . = 雪地
		#   湖占 7~13 行，左半 I（冻）、右半 W（融）；上方 y=5、下方 y=15 留给布防台。
		"decor": [
			"RRRRRRRRRRRRRRRRRRRRRRRRRRRR",
			"RRRRR..................RRRRR",
			"RRR......................RRR",
			"RR..........................",
			"RR..........................",
			"R..........................R",
			"R......RR..........RR......R",
			"R.......IIIIIIIIII.........R",
			"R......IIIIIIIWWWWW........R",
			"R.....IIIIIIIIWWWWWW.......R",
			"R.....IIIIIIIWWWWWWW.......R",
			"R.....IIIIIIIWWWWWWW.......R",
			"R......IIIIIIIWWWWW........R",
			"R........IIIIWWWW..........R",
			"R......RR..........RR......R",
			"R..........................R",
			"R..........................R",
			"RRR........................R",
			"RRRRR.......................",
			"RRRRRRRR...........RRRRRRRRR",
			"RRRRRRRRRRRRRRRRRRRRRRRRRRRR",
		],
		# 两条雪径，水晶在右下角（home）：
		#   A：洞顶 (8,0) 下来 → 沿 y=3 往东 → 沿 x=20 往南（贴冻湖右岸）→ 从北面进家 (25,16)
		#   B：左侧岩壁 (0,10) 进来 → 沿 x=4 往南 → 沿 y=17 往东（贴湖底）→ 从西面进家 (24,17)
		# 两条 lane 的终点必须与 home 四邻接，否则敌人会在门口停住（Enemy._leak 看的是路径终点）。
		"home": [Vector2i(25, 17), Vector2i(26, 17), Vector2i(25, 18), Vector2i(26, 18)],
		"lanes": [
			[Vector2i(8, 0), Vector2i(8, 3), Vector2i(20, 3),
				Vector2i(20, 15), Vector2i(25, 15), Vector2i(25, 16)],
			[Vector2i(0, 10), Vector2i(4, 10), Vector2i(4, 17), Vector2i(24, 17)],
		],
		# 无河（不走带子那条代码），水域由地形表里的 I / W 逐格给出
		"river": {"enabled": false},
		# 参考图里的地标：洞顶一丛蓝冰晶，湖四角的碎冰刺
		"props": [
			{"cell": Vector2i(21, 1), "kind": "crystal"},
			{"cell": Vector2i(8, 6), "kind": "spike"},
			{"cell": Vector2i(18, 6), "kind": "spike"},
			{"cell": Vector2i(8, 14), "kind": "spike"},
			{"cell": Vector2i(17, 14), "kind": "spike"},
		],
		"ground": "snow",          # 草地瓦片换成雪面
		"corner_tree": false,      # 四角不种树，改岩石（压成深蓝就是洞窟岩壁）
		# 雪径必须在雪地上看得出来：路面留白、路肩压成深蓝，靠明度差勾出边界
		"palette": {
			"rock": Color(0.30, 0.42, 0.60),          # 灰色 Kenney 岩石压成冻岩
			"road": Color(1.0, 1.0, 1.0),             # 雪径（比雪地更白）
			"road_edge": Color(0.62, 0.86, 1.0),      # 亮青毛边
			"road_rut": Color(0.55, 0.76, 0.94),      # 压深的淡蓝车辙
			"road_shoulder": Color(0.20, 0.36, 0.60), # 深蓝路肩：雪径的「描边」
			"road_glow": 0.10,                        # 雪面不需要土路那种强自发光
		},
		"env": {"bg": Color(0.03, 0.07, 0.12), "ambient": Color(0.34, 0.54, 0.78),
			"ambient_energy": 0.5, "sun": Color(0.88, 0.96, 1.0)},
		# 碎冰者：不沿雪径走，砸开冰面横穿湖面抄近路。只有带冰湖的图该开这个开关。
		"icebreaker": true,
		# 霜语者：给周围同伴套冰甲（火属性破得特别快）。纯辅助单位，和冰原主题配。
		"frostweaver": true,
		# 破冰小径（只有碎冰者会走）：从两条雪径各分出一条窄道直插冰湖。
		#   A：洞顶雪径 (9,3) 往南 3 格 → (9,6) 停下，下一格 (9,7) 就是冰面；
		#   B：左侧雪径 (4,10) 往东 1 格 → (5,10) 停下，下一格 (6,10) 就是冰面。
		# 终点千万别写进水里：水面那段是「砸开」的，画出来会变成一条悬在冰上的路。
		"breach": [
			[Vector2i(9, 3), Vector2i(9, 6)],
			[Vector2i(4, 10), Vector2i(5, 10)],
		],
		# 碎冰者的横穿路线（拐点折线，首尾必须落在雪径上）：
		#   从洞顶雪径的分岔口 (9,3) 沿第 9 列下水 → 到湖心的第 10 行 →
		#   再**向东**横穿到东岸 (20,10)，从那里接回雪径回基地。
		# 出口只有一个：东岸（右侧）。(4,10) 那条西侧破冰小径是**进水口**，不是出口 ——
		# 碎冰者可以左进，但绝不能左出。
		"swim_cross": [Vector2i(9, 3), Vector2i(9, 10), Vector2i(20, 10)],
		"hint": "守住右下角的水晶！雪径从洞顶和左侧岩壁绕冰湖压来，最后在东南角汇合。\n冻湖右半边已经融化，别把塔位都堆在冰面上（冰面 / 水面都不能建塔）。\n第 2 波起会出现霜崽：冰面没通时它们跟小兵一样绕湖；碎冰者一凿穿冰面，它们就跟着冰洞游过去抄近路。\n第 3 波起会出现碎冰者：它砸开冰面横穿冻湖，冰面上没有塔位，只能靠湖岸的塔在它上岸时集火。\n第 4 波起会出现霜语者：它给周围同伴套冰甲，火属性破甲快 2.6 倍 —— 留一座喷火塔拆甲。",
	},
}


## 按 order 排好的地图 id 列表（切换器 / 顺序跳转都用它）
static func ids() -> Array[String]:
	var out: Array[String] = []
	for k in MAPS.keys():
		out.append(str(k))
	out.sort_custom(func(a: String, b: String) -> bool:
		return int(MAPS[a].get("order", 0)) < int(MAPS[b].get("order", 0)))
	return out


static func has(id: String) -> bool:
	return id != "" and MAPS.has(id)


## 把空 / 未知 id 归一化成一张真实存在的地图：
## 优先用参数，其次用 pending_id，最后退回默认图（启动时的空场景就是这样落到 rift 的）。
static func resolve_id(id: String) -> String:
	if has(id):
		return id
	if has(pending_id):
		return pending_id
	return DEFAULT_ID


static func get_map(id: String) -> Dictionary:
	return MAPS.get(resolve_id(id), MAPS[DEFAULT_ID])


static func name_of(id: String) -> String:
	return str(get_map(id).get("name", id))


static func short_of(id: String) -> String:
	var d := get_map(id)
	return str(d.get("short", d.get("name", id)))


## 下一张地图（按 order 顺延）；已经是最后一张就返回空串。
## 「打完第 10 波可以前往」就是问这里 —— 有返回值才在结算面板上出现跳转按钮。
static func next_id(id: String) -> String:
	var order := ids()
	var cur := resolve_id(id)
	var i := order.find(cur)
	if i < 0 or i + 1 >= order.size():
		return ""
	return str(order[i + 1])
