extends Node3D
class_name Enemy
## 敌人：沿 GameGrid 生成的固定路线行进，支持减速、血条、漏怪扣血。
## 固定路线下建塔不会改变行进路径，所以战斗中不再重算；repath() 仅作兜底保留。

enum Kind { GRUNT, RUNNER, TANK, BOSS, FLYER, SHIELD, HEALER, SPLITTER, CLOAK, MINI_BOSS, ICEBREAKER, FROSTWEAVER, FROSTLING, SNOWKING, PINELORD }

const DATA := EnemyData.DATA

const BAR_WIDTH := 1.15

const HEAL_RADIUS := 2.8
const HEAL_INTERVAL := 0.6

## 「连锁爆破」卡的爆炸半径（伤害 = 死亡敌人最大生命 × buffs["death_blast"]）
const DEATH_BLAST_RADIUS := 2.4

const CLOAK_HIDDEN := 2.6
const CLOAK_VISIBLE := 1.0

## 碎冰者游泳：身体要**整个沉到冰面以下**（冰面是不透明的，只沉半截看起来就像在冰上滑行）。
## 下沉量按身体实际高度算（_body_h + 0.25），见 _start_swim()；
## SWIM_SPEED：水里比岸上慢 —— 游得比走得慢，玩家才有时间把塔调去它上岸的那一侧。
const SWIM_SPEED := 0.78
## 冰面比敌人脚下（SURFACE_Y）高这么多：暗影 / 波纹要贴在这个高度上才浮在冰面外侧
const ICE_LIFT := 0.055

## 血条着色器。
## 为什么不直接用 scale.x 表示血量：
##   StandardMaterial3D 的 billboard 是在顶点着色器里用相机基向量替换掉模型旋转的
##   （MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0..2], MODEL_MATRIX[3])），
##   只保留位移、丢掉缩放，所以 scale.x 对这个材质是无效的——血条会一直满格。
## 这里改成用 uniform ratio 在片元阶段裁剪填充宽度。
## 注意：Godot 4 的自定义着色器没有 billboard 这个 render_mode（写了会直接编译失败），
##      所以「正对镜头」改成在 GDScript 里手动对齐相机朝向，见 _face_bar_to_camera()。
const BAR_SHADER := [
	"shader_type spatial;",
	"render_mode unshaded, cull_disabled;",
	"uniform float ratio : hint_range(0.0, 1.0) = 1.0;",
	"uniform vec3 full_color : source_color = vec3(0.36, 0.92, 0.44);",
	"uniform vec3 low_color : source_color = vec3(0.95, 0.32, 0.28);",
	"uniform vec3 back_color : source_color = vec3(0.10, 0.11, 0.16);",
	"uniform vec3 frame_color : source_color = vec3(0.04, 0.05, 0.08);",
	"void fragment() {",
	"	float pad = 0.035;",
	"	vec3 col = frame_color;",
	"	if (UV.x > pad && UV.x < 1.0 - pad && UV.y > 0.20 && UV.y < 0.80) {",
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

## 冰甲外壳：菲涅尔边缘光。
## 试过纯半透明的青色球壳，在雪原这种亮背景下几乎看不见（白底上叠 30% 的青 =
## 一块脏白），所以改成「中间全透、只让轮廓发亮」——俯视角下就是一整圈冰蓝色光边，
## 既能看清圈里有甲，又不会把怪糊住。
const SHIELD_SHADER := [
	"shader_type spatial;",
	"render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;",
	"uniform vec3 rim_col : source_color = vec3(0.28, 0.86, 1.0);",
	"uniform float rim_strength : hint_range(0.0, 1.0) = 0.9;",
	"uniform float base_alpha : hint_range(0.0, 1.0) = 0.10;",
	"void fragment() {",
	"	float f = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));",
	"	ALBEDO = rim_col;",
	"	ALPHA = clamp(base_alpha + pow(f, 1.6) * rim_strength, 0.0, 1.0);",
	"}",
]

var kind: int = Kind.GRUNT
var max_hp: float = 1.0
var hp: float = 1.0
var base_speed: float = 2.0
var reward: int = 0
var progress: float = 0.0       # 已行进距离，用于塔选择「最靠前」的目标
var flying: bool = false        # 飞行怪：无视地形，直线飞向基地
var armor: float = 0.0          # 护甲：减伤比例（0~1）
var heal: float = 0.0           # 治疗怪：每次治疗量
var split: int = 0              # 分裂怪：死亡后分裂数量
var cloak: bool = false         # 隐身怪：塔无法直接锁定
var icebreak: bool = false      # 碎冰者：路线里含水路段，走到那里会砸冰下水游过去
var underwater: bool = false    # 霜崽：能游水下段，但自己砸不开冰面（要等碎冰者先开路）
var iceshield: bool = false     # 霜语者：会周期性给同伴套冰甲
var slow_cap: float = 1.0       # 减速抗性：一次减速最多只能削到该比例（首领 < 1.0）
var direct_target: Vector3 = Vector3.ZERO
var regen: float = 0.0           # 精英词条：每秒回血
var elites: Array = []           # 精英词条列表
var wave_no: int = 1             # 生成时的波次（召唤援军要沿用同一套血量成长）
var hp_scale_v: float = 1.0      # 生成时的血量成长系数

var _haste: float = 0.0          # 战吼：移速加成（0.3 = +30%）
var _haste_timer: float = 0.0
var _skill_timer: float = 0.0    # 首领技能的冷却计时
var _enraged: bool = false       # 大首领是否已进入狂暴阶段
var _summoned: bool = false      # 半血召唤是否已触发

var _heal_timer: float = 0.0
var _cloaked: bool = false       # 隐身怪：当前是否处于隐身阶段
var _cloak_timer: float = 0.0

## 冰甲（霜语者给的护盾）：ice_shield > 0 时所有伤害先削它，
## 火属性按 EnemyData.ICE_FIRE_MULT 倍削 —— 这是冰甲唯一的破绽。
var ice_shield: float = 0.0
var ice_shield_max: float = 0.0
var _ice_shield_timer: float = 0.0
var _shield_fx_cd: float = 0.0
var _shield_dome: MeshInstance3D
var _shield_mat: ShaderMaterial
var _cast_timer: float = 0.0     # 霜语者的施法冷却

## 碎冰者：path_world 里「水面段」的首尾下标（-1 = 整条路都不下水）。
## path_world[0] 是出生点，所以调用方传进来的是 cells 的下标，这里统一 +1。
var _swim_from: int = -1
var _swim_to: int = -1
var _swimming: bool = false
var _body_h: float = 1.6        # 身体视觉高度（游泳下沉量按它算）
var _swim_sink: float = 1.85    # 游泳时身体下沉多少：要沉到冰面以下
var _wake: MeshInstance3D       # 游泳时冰面上那圈波纹
var _swim_shadow: MeshInstance3D # 冰下暗影：冰面不透明，靠它 + 波纹圈读出它走到哪了
var _wake_t: float = 0.0
var _dot_dps: float = 0.0        # 燃烧：每秒伤害
var _dot_timer: float = 0.0
var _dot_tick: float = 0.0
var _shock_timer: float = 0.0    # 感电：闪电塔挂的标记，喷火塔命中会引爆
var _poison_dps: float = 0.0     # 中毒（强化卡给所有塔子弹附带的持续伤害，无视护甲）
var _poison_timer: float = 0.0
var _poison_tick: float = 0.0
var _bleed_dps: float = 0.0      # 流血（同上，但吃护甲减免）
var _bleed_timer: float = 0.0
var _bleed_tick: float = 0.0
var _armor_break: float = 0.0    # 破甲：被「破甲弹头」削掉的护甲值
var _armor_break_timer: float = 0.0
var _vuln: float = 0.0           # 易伤：受到伤害提高的比例
var _vuln_timer: float = 0.0

var path_world: Array[Vector3] = []
var path_idx: int = 0

var slow_factor: float = 1.0
var slow_timer: float = 0.0
## 额外减速乘区（震地雷泥潭这类「地面减速」）：和 slow_factor **乘算**，
## 1.0 = 没踩到泥潭。冰塔 -22% 与泥潭 -16% 同时在场时，实际速度 = 0.78 × 0.84。
var slow_extra: float = 1.0
var _slow_extra_timer: float = 0.0
var _dying: bool = false

var _body: Node3D
var _bar_root: Node3D
var _bar_mat: ShaderMaterial
var _mat: StandardMaterial3D

## 血条 / 冰甲外壳的 Shader：**全工程共用一份**（材质仍然是每只怪一个，各自带自己的 ratio）。
## 以前是每刷一只怪就 `Shader.new()` 一次：挂机打上几千只怪，就会攒下几千个 Shader 资源，
## 渲染端每个都要建一份管线/参数对象，内存一路涨 —— 这是「玩久了越来越卡」的主要来源之一。
static var _bar_shader: Shader
static var _shield_shader: Shader
## 状态染色回落到哪个底色：程序化敌人是 DATA 里的 color，贴图精灵是白色（= 不改变原画）
var _tint_base: Color = Color.WHITE
var _cam: Camera3D

var _marker_root: Node3D        # 首领头顶的悬浮标记
var _marker_gem: MeshInstance3D # 标记里旋转的宝石
var _marker_base_y: float = 0.0
var _marker_t: float = 0.0

## 被雪人王的「滚雪球」卷进去：整只怪收进球里 —— 无敌、不可锁定、不移动。
var _rolled: bool = false

## 雪人王「滚雪球」状态机：0 = 空闲（走冷却），1 = 聚球（吸附附近的怪），2 = 滚动。
var _roll_state: int = 0
var _roll_timer: float = 0.0
var _roll_gather: float = 0.0
var _roll_absorb_t: float = 0.0
var _roll_radius: float = 0.5
var _roll_ball: Node3D
var _roll_mesh: MeshInstance3D
var _roll_guests: Array = []          # 被卷进球的敌人（释放时逐个放出来）
var _roll_wp: Array[Vector3] = []     # 雪球要滚过的路点
var _roll_idx: int = 0
var _roll_locked: bool = false        # 路程过半后封存技能：一旦判定就永久失效，不再每帧重试

## 入口驻守：雪人王开波就登场，蹲在洞口不走，等这一波出一半才动身。
## 时长由 Main 按本波长度算好传进来（Waves.entrance_hold），Enemy 自己不猜波次信息。
var _hold_timer: float = 0.0
var _hold_t: float = 0.0

# ---------------------------------------------------------------- 生成

## swim：碎冰者的「水面段」在 cells 里的首尾下标（Vector2i(-1,-1) = 全程不下水）。
## 传 cells 下标而不是 path_world 下标，是因为调用方本来就是按格子算的；
## 这里统一 +1 换成 path_world 下标（[0] 是出生点）。
func spawn(k: int, start_pos: Vector3, world_path: Array[Vector3], hp_scale: float, wave: int,
		swim: Vector2i = Vector2i(-1, -1), hold: float = 0.0) -> void:
	_init_enemy(k, start_pos, world_path, hp_scale, wave, -1, swim, hold)


func _init_enemy(k: int, start_pos: Vector3, world_path: Array[Vector3], hp_scale: float, wave: int,
		reward_override: int, swim: Vector2i = Vector2i(-1, -1), hold: float = 0.0) -> void:
	kind = k
	var d: Dictionary = DATA[k]
	max_hp = float(d["hp"]) * hp_scale
	hp = max_hp
	base_speed = float(d["speed"])
	if reward_override >= 0:
		reward = reward_override
	else:
		reward = int(round(float(d["reward"]) * Waves.reward_scale(wave)))
	flying = bool(d.get("flying", false))
	icebreak = bool(d.get("icebreak", false))
	underwater = bool(d.get("underwater", false))
	iceshield = bool(d.get("iceshield", false))
	armor = float(d.get("armor", 0.0))
	heal = float(d.get("heal", 0.0))
	split = int(d.get("split", 0))
	cloak = bool(d.get("cloak", false))
	slow_cap = float(d.get("slow_cap", 1.0))
	regen = 0.0
	elites = []
	wave_no = wave
	hp_scale_v = hp_scale
	_haste = 0.0
	_haste_timer = 0.0
	_enraged = false
	_summoned = false
	_skill_timer = _first_skill_delay()
	# 雪人王的第三个技能：登场 7 秒后开始滚第一次雪球
	_rolled = false
	_roll_state = 0
	_roll_gather = 0.0
	_roll_absorb_t = 0.0
	_roll_guests.clear()
	_roll_wp.clear()
	_roll_idx = 0
	_roll_locked = false
	_roll_timer = float(EnemyData.ROLL_FIRST_DELAY) if k == Kind.SNOWKING else 0.0
	# 入口驻守（只有被 Main 指定了时长才会 > 0，上帝模式刷出来的照常走）
	_hold_timer = maxf(hold, 0.0)
	_hold_t = 0.0
	_cloaked = false
	_cloak_timer = 0.0
	_dot_dps = 0.0
	_dot_timer = 0.0
	_dot_tick = 0.0
	_shock_timer = 0.0
	_poison_dps = 0.0
	_poison_timer = 0.0
	_poison_tick = 0.0
	_bleed_dps = 0.0
	_bleed_timer = 0.0
	_bleed_tick = 0.0
	_armor_break = 0.0
	_armor_break_timer = 0.0
	_vuln = 0.0
	_vuln_timer = 0.0
	ice_shield = 0.0
	ice_shield_max = 0.0
	_ice_shield_timer = 0.0
	_shield_fx_cd = 0.0
	# 霜语者登场先走一小段再开始施法：一出生就套甲玩家会认为是 bug
	_cast_timer = 1.8 if iceshield else 0.0
	slow_factor = 1.0
	slow_timer = 0.0
	slow_extra = 1.0
	_slow_extra_timer = 0.0
	global_position = start_pos
	var wp: Array[Vector3] = [start_pos]
	# 路面加宽到 3.2 之后，每只怪在路面内随机偏一点：
	# 一群怪会自然铺成两三列往前走，而不是全部踩在同一条细线上。
	# 体型越大偏心越小（平方衰减）：大首领几乎踩中线，不会半个身子压在路肩 / 桥栏上。
	var body_s: float = maxf(float(d["size"]), 1.0)
	var spread: float = 0.42 * clampf(pow(1.4 / body_s, 2.0), 0.05, 1.0)
	var lat := Vector3(randf_range(-spread, spread), 0.0, randf_range(-spread, spread))
	for p in world_path:
		wp.append(p + lat)
	path_world = wp
	path_idx = 0
	progress = 0.0
	# 水面段下标（path_world[0] 是出生点，所以要 +1）
	_swim_from = -1
	_swim_to = -1
	_swimming = false
	if swim.x >= 0 and swim.y >= swim.x:
		_swim_from = swim.x + 1
		_swim_to = swim.y + 1
	if flying and world_path.size() > 0:
		direct_target = world_path[world_path.size() - 1]
	name = "%s" % d["name"]
	add_to_group("enemies")
	_roll_elites(wave)
	_build(d)
	if cloak:
		_cloaked = true
		_apply_cloak_visual()


## 精英词条：随波次概率给非首领敌人挂随机强化
func _roll_elites(wave: int) -> void:
	# 首领不吃随机精英词条：它们本身就是被设计好的强度节点
	if is_boss():
		return
	var chance := clampf(0.06 + 0.035 * float(wave - 1), 0.0, 0.45)
	if randf() > chance:
		return
	var pool: Array = ["fast", "regen", "armored", "giant"]
	var count := 1
	if wave >= 6 and randf() < 0.4:
		count = 2
	for i in range(count):
		if pool.is_empty():
			break
		var idx := randi() % pool.size()
		elites.append(pool[idx])
		pool.remove_at(idx)
	_apply_elites()


func _apply_elites() -> void:
	if elites.is_empty():
		return
	for e in elites:
		match e:
			"fast":
				base_speed *= 1.35
			"regen":
				regen = max_hp * 0.03
			"armored":
				# 上限压到 0.6：护盾怪本身带护甲，再叠「坚甲」词条时不能叠加成
				# 「打不动」的怪物（0.85 减伤 = 有效血量 6.7 倍，玩家会觉得卡关）
				armor = minf(armor + 0.25, 0.6)
			"giant":
				max_hp *= 1.6
				hp = max_hp
				reward = int(reward * 1.5)
				scale = Vector3(1.3, 1.3, 1.3)

# ---------------------------------------------------------------- 首领技能
## 首领不再是「血更厚的木桩」：小首领靠战吼 / 集结带动整波冲锋，
## 大首领靠压制脉冲打断防线、半血狂暴决定战斗的后半段节奏。
## 数值全在 EnemyData 里，这里只负责表现与结算。

## 首领是「有技能的那几只」：小首领（战吼 / 集结）、霜松（战吼 / 扎根）、大首领（脉冲 / 狂暴）、
## 雪人王（雪球 / 暴雪）
func is_boss() -> bool:
	return kind == Kind.BOSS or kind == Kind.MINI_BOSS or kind == Kind.SNOWKING or kind == Kind.PINELORD


## 第一次放技能的延迟：首领登场先走一小段，给玩家一点反应时间
func _first_skill_delay() -> float:
	if kind == Kind.MINI_BOSS or kind == Kind.PINELORD:
		return float(EnemyData.WARCRY_INTERVAL) * 0.6
	if kind == Kind.BOSS:
		return float(EnemyData.BOSS_PULSE_INTERVAL) * 0.5
	if kind == Kind.SNOWKING:
		return float(EnemyData.SNOWBALL_INTERVAL) * 0.5
	return 0.0


## 战吼加速：可被更长的 / 更强的战吼覆盖（取最大值，不叠乘）
func apply_haste(amount: float, time: float) -> void:
	_haste = maxf(_haste, amount)
	_haste_timer = maxf(_haste_timer, time)


func _tick_haste(delta: float) -> void:
	if _haste_timer <= 0.0:
		return
	_haste_timer -= delta
	if _haste_timer <= 0.0:
		_haste = 0.0


func _tick_boss_skill(delta: float) -> void:
	# 半血事件（一次性）：大小首领都会召唤援军，大首领额外进入狂暴
	if not _summoned and hp <= max_hp * float(EnemyData.SUMMON_HP_RATIO):
		_summoned = true
		_on_half_hp()

	_skill_timer -= delta
	if _skill_timer > 0.0:
		return
	if kind == Kind.MINI_BOSS or kind == Kind.PINELORD:
		_skill_timer = float(EnemyData.WARCRY_INTERVAL)
		_warcry()
	elif kind == Kind.SNOWKING:
		_skill_timer = snowball_interval()
		_throw_snowball()
	else:
		_skill_timer = float(EnemyData.BOSS_PULSE_INTERVAL)
		_pulse()


## 雪球冷却：半血「暴雪」之后砸得更勤
func snowball_interval() -> float:
	var base := float(EnemyData.SNOWBALL_INTERVAL)
	if _enraged:
		base *= float(EnemyData.SNOWBALL_ENRAGE_COEF)
	return base


## 雪人王「雪球」：朝射程内**等级最高**的一座塔扔一颗雪球（同等级取最近的）。
## 为什么挑等级最高的：压攻速的价值和这座塔的输出成正比 —— 砸满级塔才有意义，
## 砸一座刚建的一级塔等于白扔；而且这样玩家能读懂「它在针对我的主力塔」。
## 射程内没有塔就只做一次抬手动作，1 秒后重试，不把 6 秒冷却浪费掉。
func _throw_snowball() -> void:
	var radius := float(EnemyData.SNOWBALL_RANGE)
	var best = null
	var best_score := -1.0
	for t in get_tree().get_nodes_in_group("towers"):
		if t == null or not is_instance_valid(t):
			continue
		var d: float = t.global_position.distance_to(global_position)
		if d > radius:
			continue
		# 先比等级，再比远近（近的略优先）
		var score: float = float(t.level) * 100.0 - d
		if score > best_score:
			best_score = score
			best = t
	var parent := get_parent()
	if best == null:
		_skill_timer = 1.0
		Fx.ring(parent, global_position, Color(0.72, 0.92, 1.0), 1.2, 0.35)
		return
	# 抬手：一圈冷光 + 手部闪光，然后才是雪球飞出去
	Fx.flash(parent, global_position + Vector3(0.0, _body_h * 0.75, 0.0), Color(0.80, 0.95, 1.0), 1.1, 0.28)
	Sound.play("hit", -12.0)
	var ball := Snowball.new()
	ball.name = "Snowball"
	parent.add_child(ball)
	ball.launch(best, global_position + Vector3(0.0, _body_h * 0.75, 0.0),
		float(EnemyData.SNOWBALL_SLOW), float(EnemyData.SNOWBALL_TIME))


## 雪人王「滚雪球」：每 ROLL_INTERVAL 秒把 ROLL_RADIUS 内至多 3 只杂兵卷进球里，
## 向前滚 ROLL_POINTS 个路点后炸开。被卷的怪全程**无敌、不可锁定、不移动**，
## 滚完从球里散出来 —— 等于被雪人王白送了一段路。
## 为什么是「送兵」而不是伤害：它已经有「砸塔降攻速」的压制，
## 再来一条纯伤害技能只是数值；滚雪球改变的是**漏怪压力** ——
## 玩家得在它把杂兵卷起来之前先清场，否则一群怪会突然出现在防线更前面。
## 但它自己走过 ROLL_MAX_PATH_RATIO（一半路程）后就封存技能：这时候再送，
## 怪会直接落在基地门口，变成「看不见的漏怪」，玩家再清场也来不及。
func _tick_roll(delta: float) -> void:
	if _roll_state == 0:
		if _roll_locked:
			return
		_roll_timer -= delta
		if _roll_timer <= 0.0:
			if not _can_roll_here():
				_roll_locked = true
				return
			_start_gather()
		return
	if _roll_state == 1:
		_roll_gather -= delta
		_roll_absorb_t += delta
		# 聚球阶段：球悬在雪人王胸前，边吸边变大
		if _roll_ball != null and is_instance_valid(_roll_ball):
			var fwd := _body.global_transform.basis.z
			fwd.y = 0.0
			if fwd.length() > 0.0001:
				fwd = fwd.normalized()
			_roll_ball.global_position = global_position + Vector3(0.0, _body_h * 0.62, 0.0) + fwd * 1.15
		if _roll_absorb_t >= float(EnemyData.ROLL_ABSORB_TICK):
			_roll_absorb_t = 0.0
			_absorb_one()
		if _roll_guests.size() >= int(EnemyData.ROLL_MAX_GUESTS) or _roll_gather <= 0.0:
			if _roll_guests.is_empty():
				_cancel_roll()
			else:
				_begin_roll()
		return
	if _roll_state == 2:
		_roll_move(delta)


## 只有前半程能滚雪球：它已经走过 ROLL_MAX_PATH_RATIO 之后，球会把怪直接送到基地门口。
## 用路点下标比值算路程：path_world 每个路点就是一格，横向偏移是给整条路径统一加的，
## 不会改变各段长度的比例，所以下标比值就等于路程比值。
func _can_roll_here() -> bool:
	if path_world.size() < 3:
		return false
	var ratio := float(path_idx) / float(maxi(path_world.size() - 1, 1))
	return ratio <= float(EnemyData.ROLL_MAX_PATH_RATIO)


func _start_gather() -> void:
	if _roll_state != 0 or _dying or _roll_locked:
		return
	if not _can_roll_here():
		_roll_locked = true
		return
	_roll_state = 1
	_roll_gather = float(EnemyData.ROLL_GATHER_TIME)
	_roll_absorb_t = float(EnemyData.ROLL_ABSORB_TICK)   # 第一只立刻吸，不用再等 0.25 秒
	_roll_guests.clear()
	_roll_radius = float(EnemyData.ROLL_BASE_RADIUS)
	if _roll_ball == null or not is_instance_valid(_roll_ball):
		_build_roll_ball()
	_apply_roll_size()
	Fx.ring(get_parent(), global_position, Color(0.72, 0.90, 1.0), float(EnemyData.ROLL_RADIUS) * 0.6, 0.4)


## 吸一只附近最近的杂兵。首领 / 飞行 / 碎冰者都不卷：
## 碎冰者的水陆状态由 path 决定，被卷走再放出来会打断「沉下去游泳」的表演。
func _absorb_one() -> void:
	if _roll_guests.size() >= int(EnemyData.ROLL_MAX_GUESTS):
		return
	var radius := float(EnemyData.ROLL_RADIUS)
	var best = null
	var best_d := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e) or e == self:
			continue
		if e._rolled or e.is_boss() or e.flying or e.icebreak:
			continue
		if e.hp <= 0.0:
			continue
		var d: float = e.global_position.distance_to(global_position)
		if d > radius or d >= best_d:
			continue
		best_d = d
		best = e
	if best == null:
		return
	best.become_rolled()
	_roll_guests.append(best)
	_apply_roll_size()
	Fx.flash(get_parent(), global_position + Vector3(0.0, _body_h * 0.6, 0.0), Color(0.80, 0.95, 1.0), 0.9, 0.22)


func _apply_roll_size() -> void:
	_roll_radius = float(EnemyData.ROLL_BASE_RADIUS) + float(EnemyData.ROLL_RADIUS_STEP) * float(_roll_guests.size())
	if _roll_mesh != null and is_instance_valid(_roll_mesh):
		_roll_mesh.scale = Vector3.ONE * _roll_radius


## 球够大了：落到地面，沿雪人王剩下的路点向前滚 ROLL_POINTS 个。
## 终点卡在倒数第二个路点：直接把怪送到基地等于「免费漏怪」，惩罚太重。
func _begin_roll() -> void:
	if path_world.size() < 2 or path_idx >= path_world.size() - 2:
		_cancel_roll()
		return
	_roll_state = 2
	_roll_idx = 0
	_roll_wp.clear()
	# 从「球前面最近的路点」起滚，而不是死用 path_idx：球悬在雪人王胸前时已经越过当前
	# 路点一格多了，直接从 path_idx 开始会让球先往回滚一小段 —— 入口驻守时看得特别明显。
	# 只在 path_idx..path_idx+2 里找，避免路线拐弯时把球吸到远处另一段路上。
	var from := path_idx
	if _roll_ball != null and is_instance_valid(_roll_ball):
		var probe := _roll_ball.global_position
		probe.y = 0.0
		var best := INF
		for j in range(path_idx, mini(path_idx + 2, path_world.size() - 1) + 1):
			var d := path_world[j].distance_squared_to(probe)
			if d < best:
				best = d
				from = j
	var last := mini(from + int(EnemyData.ROLL_POINTS), path_world.size() - 2)
	for j in range(from, last + 1):
		_roll_wp.append(path_world[j])
	if _roll_wp.is_empty() or _roll_ball == null or not is_instance_valid(_roll_ball):
		_release_roll()
		return
	var p := _roll_ball.global_position
	p.y = _roll_radius
	_roll_ball.global_position = p
	Sound.play("hit", -8.0)


func _roll_move(delta: float) -> void:
	if _roll_ball == null or not is_instance_valid(_roll_ball):
		_release_roll()
		return
	if _roll_idx >= _roll_wp.size():
		_release_roll()
		return
	var dest: Vector3 = _roll_wp[_roll_idx]
	dest.y = _roll_radius
	var dir := dest - _roll_ball.global_position
	dir.y = 0.0
	var step := float(EnemyData.ROLL_SPEED) * delta
	if dir.length() <= step:
		_roll_ball.global_position = dest
		_roll_idx += 1
		if _roll_idx >= _roll_wp.size():
			_release_roll()
			return
	else:
		_roll_ball.global_position += dir.normalized() * step
	# 滚动的视觉：球体绕自身 X 轴转，转速跟着线速度
	if _roll_mesh != null and is_instance_valid(_roll_mesh):
		_roll_mesh.rotation.x -= step / maxf(_roll_radius, 0.1)


func _build_roll_ball() -> void:
	var parent := get_parent()
	if parent == null:
		return
	_roll_ball = Node3D.new()
	_roll_ball.name = "RollSnowball"
	parent.add_child(_roll_ball)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 18
	sm.rings = 10
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.92, 0.96, 1.0)
	mat.roughness = 0.55
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.85, 1.0)
	mat.emission_energy_multiplier = 0.35
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_roll_ball.add_child(mi)
	_roll_mesh = mi


## 一只怪都没吸到：球直接散掉，不进入滚动，短冷却后重试
func _cancel_roll() -> void:
	if _roll_ball != null and is_instance_valid(_roll_ball):
		_roll_ball.queue_free()
	_roll_ball = null
	_roll_mesh = null
	_roll_guests.clear()
	_roll_state = 0
	_roll_timer = 5.0


## 球炸开：被卷的怪散在落点，恢复普通状态继续走
func _release_roll() -> void:
	var pos := global_position
	if _roll_ball != null and is_instance_valid(_roll_ball):
		pos = _roll_ball.global_position
	var n := _roll_guests.size()
	for i in range(n):
		var e = _roll_guests[i]
		if e == null or not is_instance_valid(e):
			continue
		var ang := TAU * float(i) / maxf(1.0, float(n))
		e.release_rolled(pos + Vector3(cos(ang), 0.0, sin(ang)) * 0.55)
	var parent := get_parent()
	if parent != null:
		Fx.flash(parent, pos, Color(0.85, 0.96, 1.0), 1.8, 0.4)
		Fx.ring(parent, pos, Color(0.75, 0.92, 1.0), 2.2, 0.5)
	if _roll_ball != null and is_instance_valid(_roll_ball):
		_roll_ball.queue_free()
	_roll_ball = null
	_roll_mesh = null
	_roll_guests.clear()
	_roll_state = 0
	var coef := float(EnemyData.ROLL_ENRAGE_COEF) if _enraged else 1.0
	_roll_timer = float(EnemyData.ROLL_INTERVAL) * coef
	Sound.play("explosion", -12.0)


## 小首领「潮主」· 战吼：半径内的小怪集体加速，逼玩家先处理首领
func _warcry() -> void:
	var radius := float(EnemyData.WARCRY_RADIUS)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e) or e == self:
			continue
		if e.is_boss():
			continue
		if e.global_position.distance_to(global_position) > radius:
			continue
		e.apply_haste(float(EnemyData.WARCRY_HASTE), float(EnemyData.WARCRY_TIME))
	var parent := get_parent()
	Fx.ring(parent, global_position, Color(1.0, 0.62, 0.22), radius * 0.8, 0.45)
	Fx.flash(parent, global_position + Vector3(0.0, 1.4, 0.0), Color(1.0, 0.72, 0.30), 1.0, 0.32)
	Sound.play("wave", -6.0)


## 大首领「终焉之影」· 压制脉冲：范围内所有塔暂时熄火（不摧毁，只是停火）
func _pulse() -> void:
	var radius := float(EnemyData.BOSS_PULSE_RADIUS)
	for t in get_tree().get_nodes_in_group("towers"):
		if t == null or not is_instance_valid(t):
			continue
		if t.global_position.distance_to(global_position) > radius:
			continue
		t.suppress(float(EnemyData.BOSS_PULSE_TIME))
	var parent := get_parent()
	Fx.ring(parent, global_position, Color(0.62, 0.35, 1.0), radius, 0.55)
	Fx.flash(parent, global_position + Vector3(0.0, 1.6, 0.0), Color(0.72, 0.42, 1.0), 1.8, 0.42)
	Sound.play("explosion", -8.0)


## 半血：召唤援军；大首领额外狂暴
func _on_half_hp() -> void:
	var parent := get_parent()
	if kind == Kind.BOSS:
		_enraged = true
		base_speed *= 1.0 + float(EnemyData.BOSS_ENRAGE_HASTE)
		armor = minf(armor + float(EnemyData.BOSS_ENRAGE_ARMOR), 0.9)
		_update_tint()
		Fx.flash(parent, global_position + Vector3(0.0, 1.6, 0.0), Color(1.0, 0.25, 0.32), 2.2, 0.5)
		Fx.ring(parent, global_position, Color(1.0, 0.25, 0.35), 3.6, 0.65)
		Fx.damage_number(parent, global_position + Vector3(0.0, 2.9, 0.0), "狂暴", Color(1.0, 0.35, 0.35), true)
		Sound.play("wave")
		_summon_guards(int(EnemyData.BOSS_SUMMON))
	elif kind == Kind.SNOWKING:
		# 雪人王半血「暴雪」：雪球冷却缩短到 60%，并叫 2 只霜崽上来帮忙
		_enraged = true
		_update_tint()
		Fx.flash(parent, global_position + Vector3(0.0, 1.8, 0.0), Color(0.72, 0.92, 1.0), 2.4, 0.5)
		Fx.ring(parent, global_position, Color(0.60, 0.88, 1.0), 3.8, 0.7)
		Fx.damage_number(parent, global_position + Vector3(0.0, 3.0, 0.0), "暴雪", Color(0.70, 0.92, 1.0), true)
		Sound.play("wave")
		_summon_guards(int(EnemyData.SNOWBALL_SUMMON), Kind.FROSTLING)
	elif kind == Kind.PINELORD:
		# 霜松「扎根」：抖落一圈雪 + 叫 2 只霜崽，而不是通用小兵 —— 冰原主题要统一
		Fx.flash(parent, global_position + Vector3(0.0, 1.6, 0.0), Color(0.55, 0.92, 0.70), 2.0, 0.45)
		Fx.ring(parent, global_position, Color(0.42, 0.82, 0.55), 3.4, 0.6)
		Fx.damage_number(parent, global_position + Vector3(0.0, 2.6, 0.0), "扎根", Color(0.62, 0.94, 0.74), false)
		Sound.play("wave")
		_summon_guards(int(EnemyData.PINE_SUMMON), Kind.FROSTLING)
	else:
		Fx.ring(parent, global_position, Color(1.0, 0.55, 0.25), 2.6, 0.5)
		Fx.damage_number(parent, global_position + Vector3(0.0, 1.8, 0.0), "集结", Color(1.0, 0.72, 0.35), false)
		_summon_guards(int(EnemyData.MINI_BOSS_SUMMON))


## 召唤援军：复用「剩余路径」逻辑（和分裂怪同一套），保证召唤物顺着原路线走
## spawn_kind 默认是小兵；雪人王叫的是霜崽（冰原杂兵，才会跟得上冰面）
func _summon_guards(count: int, spawn_kind: int = Kind.GRUNT) -> void:
	var parent_node := get_parent()
	if parent_node == null or count <= 0:
		return
	var remaining: Array[Vector3] = []
	for j in range(path_idx, path_world.size()):
		remaining.append(path_world[j])
	if remaining.is_empty():
		return
	for i in range(count):
		var e := Enemy.new()
		parent_node.add_child(e)
		var ang := TAU * float(i) / float(count)
		var off := Vector3(cos(ang) * 1.1, 0.0, sin(ang) * 1.1)
		e._init_enemy(spawn_kind, global_position + off, remaining, hp_scale_v * float(EnemyData.SUMMON_HP_COEF), wave_no, -1)
	Fx.ring(parent_node, global_position, Color(1.0, 0.55, 0.75), 2.2, 0.45)


func _build(d: Dictionary) -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)

	var col: Color = d["color"]
	var s: float = float(d["size"])

	# 霜崽 / 雪人王都是**真 3D 造型**（FrostlingModel / SnowkingModel），不再用原画精灵：
	# billboard 方片在能绕视角的 3D 场景里一转就露馅；造型也刻意改造过，不和原画一一对应。
	var sprite_ok := false
	if kind == Kind.FROSTLING:
		_build_frostling_body(s)
		sprite_ok = true
	elif kind == Kind.SNOWKING:
		_build_snowking_body(s)
		sprite_ok = true
	elif kind == Kind.PINELORD:
		_build_pinelord_body(s)
		sprite_ok = true

	# 优先用 res://models/enemies/enemy_<类型>.glb（放了模型就不再用程序化几何）
	if not sprite_ok and not _build_custom_body(s):
		var mesh: Mesh
		if kind == Kind.RUNNER:
			var cm := CylinderMesh.new()
			cm.top_radius = 0.16 * s
			cm.bottom_radius = 0.30 * s
			cm.height = 1.15 * s
			mesh = cm
		elif kind == Kind.BOSS:
			var bm := BoxMesh.new()
			bm.size = Vector3(1.05 * s, 1.15 * s, 1.05 * s)
			mesh = bm
		elif kind == Kind.MINI_BOSS:
			var mm := BoxMesh.new()
			mm.size = Vector3(0.85 * s, 0.95 * s, 0.85 * s)
			mesh = mm
		elif kind == Kind.FLYER:
			var bm := BoxMesh.new()
			bm.size = Vector3(0.7 * s, 0.5 * s, 0.7 * s)
			mesh = bm
		else:
			var sm := SphereMesh.new()
			sm.radius = 0.35 * s
			sm.height = 0.80 * s
			sm.radial_segments = 12
			mesh = sm

		_body_h = mesh.get_aabb().size.y
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = col
		_tint_base = col
		_mat.roughness = 0.55
		_mat.emission_enabled = true
		_mat.emission = col
		_mat.emission_energy_multiplier = 0.12
		# 可选贴图：res://textures/enemy_grunt.png / enemy_runner / enemy_tank / enemy_boss
		if TextureLib.dress(_mat, "enemy_%s" % slot_suffix()):
			_mat.emission = Color.WHITE
			_mat.emission_energy_multiplier = 0.05
		if cloak:
			_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = _mat
		mi.position.y = 0.45 * s
		_body.add_child(mi)

	# 首领体型更大，血条同步加宽，远看也能盯住它的血线
	var bar_w := BAR_WIDTH
	if kind == Kind.BOSS or kind == Kind.SNOWKING:
		bar_w = BAR_WIDTH * 2.0
	elif kind == Kind.MINI_BOSS:
		bar_w = BAR_WIDTH * 1.5
	# 血条离地高度跟着体型走：身体顶面大约在 0.85~1.03 倍体型处，
	# 1.05*s+0.25 让大小怪的血条都贴着脑袋，不会因为放大而飘到半空。
	# 3D 造型（霜崽 / 雪人王 / 霜松）的头顶就是 _body_h，用同一套公式会飘出去一截。
	var bar_y := 1.05 * s + 0.25
	if kind == Kind.FROSTLING or kind == Kind.SNOWKING or kind == Kind.PINELORD:
		bar_y = _body_h + 0.20
	_build_bar(bar_y, bar_w)

	if kind == Kind.SHIELD:
		_build_shield_ring(s)
	if kind == Kind.HEALER:
		_build_heal_ring(s)
	if kind == Kind.BOSS:
		_build_boss_ring(s, Color(1.0, 0.22, 0.48))
		_build_boss_marker(s, Color(1.0, 0.28, 0.52), "BOSS")
	elif kind == Kind.SNOWKING:
		# 雪人王：冰蓝光环 + 头顶「BOSS」，和白底雪地也能拉开
		_build_boss_ring(s, Color(0.42, 0.80, 1.0))
		_build_boss_marker(s, Color(0.55, 0.86, 1.0), "BOSS")
	elif kind == Kind.MINI_BOSS:
		_build_boss_ring(s, Color(1.0, 0.62, 0.22))
		_build_boss_marker(s, Color(1.0, 0.64, 0.24), "MINI BOSS")
	elif kind == Kind.PINELORD:
		# 霜松：松绿光环 + 头顶「MINI BOSS」，和通用小首领的橙环区分开
		_build_boss_ring(s, Color(0.36, 0.86, 0.52))
		_build_boss_marker(s, Color(0.44, 0.94, 0.60), "MINI BOSS")
	if not elites.is_empty():
		_build_elite_ring(s)


## 雪人王：程序化 3D 造型（组成见 SnowkingModel）
func _build_snowking_body(s: float) -> void:
	_attach_model_body(SnowkingModel.build(s), 1.42 * s)


## 霜崽：程序化 3D 造型（组成见 FrostlingModel）。
## 它要沉到冰面下游泳，_body_h 尤其不能估错 —— 下沉量就是 _body_h + 0.25。
func _build_frostling_body(s: float) -> void:
	_attach_model_body(FrostlingModel.build(s), 0.86 * s)


## 霜松（小 boss）：程序化 3D 造型（组成见 PineBossModel）
func _build_pinelord_body(s: float) -> void:
	_attach_model_body(PineBossModel.build(s), 1.57 * s)


## 把程序化 3D 造型挂到 _body 上：
## 主材质交给 _mat（减速 / 中毒 / 受击染色都改这一个），高度用实测包围盒（血条、游泳下沉都靠它）。
func _attach_model_body(model: Node3D, fallback_h: float) -> void:
	var bm = model.get_meta("body_mat", null)
	if bm is StandardMaterial3D:
		_mat = bm as StandardMaterial3D
		_tint_base = _mat.albedo_color
	_body_h = ModelLib.height_of(model)
	if _body_h <= 0.01:
		_body_h = fallback_h
	_body.add_child(model)


## 贴图精灵外观：把 res://textures/<slot>.png 贴在一张永远正对镜头的方片上。
## 目前没有敌人走这条路（霜崽 / 雪人王都已改成 3D 造型），留作「塞一张原画就能换皮」的备用入口：
## 想临时试某张图，在 _build() 里加 `_build_sprite_body(...)` 分支即可。
## 为什么用方片：这类原画是「已经打好光的成品精灵」，
## 贴到球 / 立方体上会被二次打光、边缘糊成一团；billboard 方片能原样还原，而且只有 1 个 draw call。
## 透明用 ALPHA_SCISSOR 而不是 ALPHA：半透明材质会被排进透明队列、不写深度，
## 下沉到冰面下的身体会从冰面里透出来（碎冰者那套「完全沉下去」的观感就毁了）。
## pixel = true 时用 NEAREST 采样，像素画放大后不会糊成一团马赛克边。
func _build_sprite_body(s: float, slot: String, pixel: bool = false) -> bool:
	var tex := TextureLib.get_texture(slot)
	if tex == null:
		return false
	var h: float = 0.95 * s
	_body_h = h
	var quad := MeshInstance3D.new()
	quad.name = "Sprite"
	var qm := QuadMesh.new()
	qm.size = Vector2(h, h)
	quad.mesh = qm
	_mat = StandardMaterial3D.new()
	_mat.albedo_texture = tex
	_mat.albedo_color = Color.WHITE
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_mat.alpha_scissor_threshold = 0.45
	_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if pixel:
		_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	quad.material_override = _mat
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 方片原点在正中：抬到「底边贴地」
	quad.position.y = h * 0.5
	_body.add_child(quad)
	_tint_base = Color.WHITE
	return true


## 当前敌人类型对应的贴图槽位后缀
## 用外部模型替换敌人外形：把任意 GLB 命名为
## `res://models/enemies/enemy_grunt.glb`（runner / tank / boss / flyer / shield 同理）即可，
## 这里会自动按身高缩放到和原程序化敌人一致、底部贴地、水平居中。
## 找不到文件返回 false —— 回退到程序化几何，工程永远能跑。
func _build_custom_body(s: float) -> bool:
	# 隐身怪要靠材质透明度做隐身效果，用外部模型会失效，所以直接走程序化外观
	if cloak:
		return false
	var path := "res://models/enemies/enemy_%s.glb" % slot_suffix()
	var model := ModelLib.instance_path(path)
	if model == null:
		return false
	var box := ModelLib.aabb_of(model)
	var base := model.scale
	var cur_h: float = box.size.y * absf(base.y)
	if cur_h <= 0.0001:
		model.queue_free()
		return false
	var target_h: float = 0.80 * s
	if kind == Kind.BOSS:
		target_h = 1.15 * s
	elif kind == Kind.MINI_BOSS:
		target_h = 0.95 * s
	var k := target_h / cur_h
	model.scale = base * Vector3(k, k, k)
	_body_h = target_h
	# 让模型底部贴地（y=0）、水平居中到格子中心
	var c := box.get_center()
	model.position = Vector3(-c.x * base.x * k, -box.position.y * base.y * k, -c.z * base.z * k)
	_body.add_child(model)
	return true


func slot_suffix() -> String:
	match kind:
		Kind.RUNNER:
			return "runner"
		Kind.TANK:
			return "tank"
		Kind.BOSS:
			return "boss"
		Kind.SNOWKING:
			return "snowking"
		Kind.PINELORD:
			return "pinelord"
		Kind.MINI_BOSS:
			return "miniboss"
		Kind.FLYER:
			return "flyer"
		Kind.SHIELD:
			return "shield"
		Kind.HEALER:
			return "healer"
		Kind.SPLITTER:
			return "splitter"
		Kind.ICEBREAKER:
			return "icebreaker"
		Kind.FROSTWEAVER:
			return "frostweaver"
		Kind.FROSTLING:
			return "frostling"
		_:
			return "grunt"


## 共享 Shader 的懒加载：第一次用到时才编译，之后所有怪都复用同一份
static func _shared_bar_shader() -> Shader:
	if _bar_shader == null:
		var sh := Shader.new()
		sh.code = "\n".join(BAR_SHADER)
		_bar_shader = sh
	return _bar_shader


static func _shared_shield_shader() -> Shader:
	if _shield_shader == null:
		var sh := Shader.new()
		sh.code = "\n".join(SHIELD_SHADER)
		_shield_shader = sh
	return _shield_shader


func _build_bar(y: float, width: float = BAR_WIDTH) -> void:
	_bar_root = Node3D.new()
	_bar_root.name = "HealthBar"
	_bar_root.position.y = y
	add_child(_bar_root)

	_bar_mat = ShaderMaterial.new()
	_bar_mat.shader = _shared_bar_shader()

	# 外框 + 底槽 + 填充全部由着色器一次画完，所以只要一个 quad
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(width + 0.06, 0.20)
	quad.mesh = qm
	quad.material_override = _bar_mat
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar_root.add_child(quad)

	_update_bar()
	_face_bar_to_camera()


## 护盾怪：加一个半透明护盾环
func _build_shield_ring(s: float) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42 * s
	tm.outer_radius = 0.55 * s
	ring.mesh = tm
	ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.35, 0.75, 0.95, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = mat
	ring.position.y = 0.55 * s
	_body.add_child(ring)


## 治疗怪：绿色光环，示意治疗范围
func _build_heal_ring(s: float) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = HEAL_RADIUS * 0.94
	tm.outer_radius = HEAL_RADIUS
	ring.mesh = tm
	ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.40, 0.90, 0.55, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = mat
	ring.position.y = 0.25
	_body.add_child(ring)


## 首领光环：脚下常亮一圈专属色环，一眼能从怪堆里认出来
func _build_boss_ring(s: float, col: Color) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	# 光环按体型放大，但跟着身体走而不是按 s 死乘：
	# 旧写法 0.82~1.0*s 在 s=3 时会变成直径 6 的地面大圆圈，直接铺满整条路。
	tm.inner_radius = 0.58 * s
	tm.outer_radius = 0.72 * s
	tm.rings = 48
	tm.ring_segments = 6
	ring.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(col.r, col.g, col.b, 0.55)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 0.9
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = mat
	ring.position.y = 0.08
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(ring)


## 首领头顶的悬浮标记：文字 + 旋转宝石，血条上方一直悬浮，怪再多也能一眼锁定
func _build_boss_marker(s: float, col: Color, text: String) -> void:
	_marker_root = Node3D.new()
	_marker_root.name = "BossMarker"
	# 悬在血条上方：血条高度可能是 1.05*s+0.25，也可能按 _body_h 抬高（精灵 / 3D 造型），
	# 所以直接读 _bar_root 的实际高度，别让首领标记压到血条上。
	var bar_y := 1.05 * s + 0.25
	if _bar_root != null and is_instance_valid(_bar_root):
		bar_y = _bar_root.position.y
	_marker_base_y = bar_y + 0.60
	_marker_root.position.y = _marker_base_y
	add_child(_marker_root)

	var label := Label3D.new()
	label.text = text
	label.font_size = 96
	label.pixel_size = 0.0032
	label.outline_size = 18
	label.outline_modulate = Color(0.05, 0.02, 0.06, 0.85)
	label.modulate = col.lightened(0.30)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	_marker_root.add_child(label)

	_marker_gem = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.11 * s
	sm.height = 0.11 * s * 2.4
	sm.radial_segments = 4       # 4 段 2 环 = 八面体，看起来像一颗悬浮宝石
	sm.rings = 2
	_marker_gem.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 1.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_marker_gem.material_override = mat
	_marker_gem.position.y = 0.62
	_marker_gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker_root.add_child(_marker_gem)


## 标记上下轻微浮动 + 宝石自转，静止的图标容易被怪堆淹没
func _animate_boss_marker(delta: float) -> void:
	if _marker_root == null or not is_instance_valid(_marker_root):
		return
	_marker_t += delta
	_marker_root.position.y = _marker_base_y + sin(_marker_t * 2.6) * 0.10
	if _marker_gem != null and is_instance_valid(_marker_gem):
		_marker_gem.rotation.y += delta * 2.4


## 精英怪：金色光环标识（词条不同仅属性差异，视觉统一）
func _build_elite_ring(s: float) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.55 * s
	tm.outer_radius = 0.68 * s
	ring.mesh = tm
	ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.75, 0.25, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = mat
	ring.position.y = 0.12
	_body.add_child(ring)

# ---------------------------------------------------------------- 移动

func _process(delta: float) -> void:
	if not _dying:
		_face_bar_to_camera()
		_animate_boss_marker(delta)
		_animate_wake(delta)
	if not GameState.running or _dying:
		return
	# 被雪人王的滚雪球卷着：收在球里，等球炸开再继续走
	if _rolled:
		return

	if slow_timer > 0.0:
		slow_timer -= delta
		if slow_timer <= 0.0:
			slow_factor = 1.0
			_update_tint()

	# 泥潭的额外减速：单独计时，走出泥潭后自己恢复，不影响冰塔那一层
	if _slow_extra_timer > 0.0:
		_slow_extra_timer -= delta
		if _slow_extra_timer <= 0.0:
			slow_extra = 1.0

	if _shock_timer > 0.0:
		_shock_timer -= delta
		if _shock_timer <= 0.0:
			_update_tint()

	# 战吼加速与首领技能：都跟着普通 _process 走，暂停 / 波间休整时不会空转
	_tick_haste(delta)
	if is_boss():
		_tick_boss_skill(delta)
	# 滚雪球是雪人王独有的额外技能，和「扔雪球 / 暴雪」各自计时，互不占用冷却
	if kind == Kind.SNOWKING:
		_tick_roll(delta)
	_tick_ice_armor(delta)

	if heal > 0.0:
		_heal_timer -= delta
		if _heal_timer <= 0.0:
			_heal_timer = HEAL_INTERVAL
			_heal_aura()

	if cloak:
		_cloak_timer += delta
		var was := _cloaked
		if _cloaked:
			if _cloak_timer >= CLOAK_HIDDEN:
				_cloaked = false
				_cloak_timer = 0.0
		elif _cloak_timer >= CLOAK_VISIBLE:
			_cloaked = true
			_cloak_timer = 0.0
		if was != _cloaked:
			_apply_cloak_visual()

	if regen > 0.0 and hp < max_hp:
		hp = minf(hp + regen * delta, max_hp)
		_update_bar()

	if _dot_timer > 0.0:
		_dot_timer -= delta
		_dot_tick -= delta
		if _dot_tick <= 0.0:
			_dot_tick = 0.5
			# 灼烧本身也是火：打冰甲时同样按火属性加速破甲
			take_damage(_dot_dps * 0.5, false, false, "fire")
		if _dot_timer <= 0.0:
			# 烧完了：清掉状态并还原外观（可能还带着冰塔的减速蓝色）
			_dot_dps = 0.0
			_update_tint()

	# 中毒 / 流血：塔的附加状态，和燃烧一样每 0.5 秒结算一次
	if _poison_timer > 0.0:
		_poison_timer -= delta
		_poison_tick -= delta
		if _poison_tick <= 0.0:
			_poison_tick = 0.5
			_take_raw(_poison_dps * 0.5)   # 毒无视护甲
		if _poison_timer <= 0.0:
			_poison_dps = 0.0
			_update_tint()

	if _bleed_timer > 0.0:
		_bleed_timer -= delta
		_bleed_tick -= delta
		if _bleed_tick <= 0.0:
			_bleed_tick = 0.5
			take_damage(_bleed_dps * 0.5, false, false)   # 流血吃护甲
		if _bleed_timer <= 0.0:
			_bleed_dps = 0.0
			_update_tint()

	# 破甲 / 易伤：只影响后续命中，到期自动复原
	if _armor_break_timer > 0.0:
		_armor_break_timer -= delta
		if _armor_break_timer <= 0.0:
			_armor_break = 0.0
	if _vuln_timer > 0.0:
		_vuln_timer -= delta
		if _vuln_timer <= 0.0:
			_vuln = 0.0

	# 入口驻守（雪人王）：蹲在洞口不动，但技能照放 —— 滚雪球卷的就是这半波刚出门的杂兵。
	# 必须放在技能 tick 之后、位移之前：卡在技能前面它就不会聚球，卡在位移之后它已经走了。
	if _hold_timer > 0.0:
		_hold_timer -= delta
		_hold_t += delta
		if _hold_timer > 0.0:
			# 站着也要有点活气：轻轻起伏，否则看起来像卡住了
			_body.position.y = sin(_hold_t * 2.4) * 0.05
			return

	if flying:
		# 飞行怪：直线飞向基地，无视地形阻挡
		var fdir := direct_target - global_position
		fdir.y = 0.0
		var fdist := fdir.length()
		var fstep := base_speed * speed_mul() * delta
		if fdist <= fstep:
			progress += fdist
			_leak()
			return
		global_position += fdir.normalized() * fstep
		progress += fstep
		if fdist > 0.0001:
			_body.rotation.y = atan2(fdir.x, fdir.z)
		_body.position.y = sin(progress * 3.0) * 0.08 + 0.3
		return

	if path_idx >= path_world.size():
		return

	_update_swim_state()

	var dest: Vector3 = path_world[path_idx]
	var dir := dest - global_position
	dir.y = 0.0
	var dist := dir.length()
	# 游泳比走路慢：玩家有时间把塔的火力挪到它上岸的那一侧
	# 游泳系数乘在减速下限**外面**：泡在水里的怪即使已经到 0.25 倍速下限，
	# 也仍然要比岸上的同类慢 —— 下限只约束「减速」这一层，不该把地形惩罚一起吃掉。
	var spd := base_speed * (SWIM_SPEED if _swimming else 1.0)
	var step := spd * speed_mul() * delta

	if dist <= step:
		progress += dist
		if dist > 0.0001:
			global_position += dir.normalized() * dist
		path_idx += 1
		_update_swim_state()
		if path_idx >= path_world.size():
			_leak()
			return
	else:
		progress += step
		global_position += dir.normalized() * step

	if dist > 0.0001:
		_body.rotation.y = atan2(dir.x, dir.z)
	# 岸上轻微上下浮动；游泳时整个身体沉到冰面以下（冰面不透明，露半截就像在冰上滑），
	# 冰面上只剩 _wake 波纹圈 + _swim_shadow 暗影告诉玩家它游到哪了。
	if _swimming:
		_body.position.y = -_swim_sink + sin(progress * 2.0) * 0.05
	else:
		_body.position.y = sin(progress * 3.0) * 0.06

# ---------------------------------------------------------------- 破冰 / 游泳

## 根据「下一个路点」判断是不是走在水面上，只在状态翻转时触发一次特效。
## 路线是 GameGrid.swim_route_home() 给的（穿过湖面的最短路），
## 水面段首尾下标见 _swim_from / _swim_to。
func _update_swim_state() -> void:
	if not icebreak and not underwater:
		return
	var now := _swim_from >= 0 and path_idx >= _swim_from and path_idx <= _swim_to
	if now == _swimming:
		return
	if now:
		_start_swim()
	else:
		_end_swim()


## 到岸了：一拳砸开冰面下水。冰面是静态几何，砸不出真正的洞，
## 所以用「碎冰序列帧 + 一圈白冰碴冲击环 + 原地留一个深色冰洞」来表现。
func _start_swim() -> void:
	_swimming = true
	# 沉到冰面以下：头顶也得在水面下，否则俯视角看就是「站在冰上滑」。
	# 0.25 是余量，保证身体顶端低于冰面（冰面在脚下 +ICE_LIFT）。
	_swim_sink = _body_h + 0.25
	if _wake == null:
		_build_wake()
	if _wake != null:
		_wake_t = 0.0
		_wake.visible = true
	if _swim_shadow != null:
		_swim_shadow.visible = true
	# 冰面是碎冰者砸开的：霜崽只是「跟着从现成的冰洞游过去」，不再重复砸一次冰。
	# 顺手把「湖已经通了」记到全局 —— 后面的霜崽生成时才敢走水下路线。
	if not icebreak:
		var par := get_parent()
		if par != null:
			Fx.ring(par, global_position, Color(0.86, 0.98, 1.0), 1.6, 0.35)
			Sound.play("hit", -14.0)
		return
	GameState.ice_opened = true
	var parent := get_parent()
	var p := global_position
	# 冰洞砸在「它和下一格水面之间」，而不是脚下，看起来才是破开冰往前走
	var nxt := p
	if path_idx < path_world.size():
		nxt = path_world[path_idx]
	var hole := Vector3((p.x + nxt.x) * 0.5, p.y, (p.z + nxt.z) * 0.5)
	if not Fx.burst_seq(parent, hole + Vector3(0.0, 0.3, 0.0), "fx_ice", 2, 3.2, 0.5, 0.16,
			Color(0.62, 0.92, 1.0), Color(0.92, 0.99, 1.0)):
		Fx.flash(parent, hole + Vector3(0.0, 0.35, 0.0), Color(0.85, 0.97, 1.0), 1.1, 0.28)
	Fx.ring(parent, hole, Color(0.88, 0.99, 1.0), 3.0, 0.5)
	Fx.ring(parent, hole, Color(0.30, 0.72, 0.92), 1.9, 0.7)
	_spawn_ice_hole(hole)
	Sound.play("explosion", -12.0)


## 爬上对岸：溅一下水，身体重新站直
func _end_swim() -> void:
	_swimming = false
	if _wake != null:
		_wake.visible = false
	if _swim_shadow != null:
		_swim_shadow.visible = false
	var parent := get_parent()
	var p := global_position
	if not Fx.burst_seq(parent, p + Vector3(0.0, 0.3, 0.0), "fx_ice", 2, 2.4, 0.4, 0.14,
			Color(0.72, 0.95, 1.0)):
		Fx.flash(parent, p + Vector3(0.0, 0.3, 0.0), Color(0.86, 0.98, 1.0), 0.8, 0.22)
	Fx.ring(parent, p, Color(0.90, 0.99, 1.0), 2.2, 0.45)
	Sound.play("hit", -8.0)


## 冰面上的窟窿：一块深色水面 + 一圈白冰碴。挂在敌人根节点下，
## 波次 / 换图时随场景一起清掉，不用自己管生命周期。
func _spawn_ice_hole(p: Vector3) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var r := 0.85 + 0.22 * float(DATA[kind]["size"])
	var y := p.y + 0.07     # 比冰面（水面 + 0.02）再高一点点，免得和冰面 z-fighting

	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.02
	cm.radial_segments = 16
	disc.mesh = cm
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.albedo_color = Color(0.04, 0.30, 0.42, 0.95)
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc.material_override = dmat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(disc)
	disc.global_position = Vector3(p.x, y, p.z)

	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r * 0.92
	tm.outer_radius = r * 1.08
	tm.rings = 20
	tm.ring_segments = 5
	rim.mesh = tm
	rim.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.albedo_color = Color(0.86, 0.97, 1.0, 0.9)
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	rim.material_override = rmat
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(rim)
	rim.global_position = Vector3(p.x, y, p.z)


## 游泳时贴在水面上的波纹环（省掉每帧新建特效节点）
func _build_wake() -> void:
	var s := float(DATA[kind]["size"])
	_wake = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.52 * s
	tm.outer_radius = 0.70 * s
	tm.rings = 24
	tm.ring_segments = 6
	_wake.mesh = tm
	_wake.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.84, 0.99, 1.0, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = Color(0.68, 0.94, 1.0)
	mat.emission_energy_multiplier = 0.35
	_wake.material_override = mat
	_wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 挂在 self 上（不是 _body）：身体会沉下去，波纹得留在水面高度
	_wake.position.y = ICE_LIFT + 0.005
	_wake.visible = false
	add_child(_wake)

	# 冰下暗影：冰面不透明，人整个沉下去以后就只剩这块贴冰面的暗影 + 上面的波纹圈
	# 能告诉玩家它走到哪了 —— 没有它就成了「怪物凭空消失」。
	_swim_shadow = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.74 * s
	disc.bottom_radius = 0.74 * s
	disc.height = 0.012
	disc.radial_segments = 20
	_swim_shadow.mesh = disc
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.albedo_color = Color(0.03, 0.20, 0.32, 0.52)
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_swim_shadow.material_override = dmat
	_swim_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_swim_shadow.position.y = ICE_LIFT - 0.004    # 压在波纹圈下面一点，浮在冰面外侧
	_swim_shadow.visible = false
	add_child(_swim_shadow)


## 波纹轻微一张一缩，静止的圆环看不出「在动」
func _animate_wake(delta: float) -> void:
	if _wake == null or not is_instance_valid(_wake):
		return
	if not _wake.visible:
		return
	_wake_t += delta
	var k := 1.0 + sin(_wake_t * 3.4) * 0.10
	_wake.scale = Vector3(k, 1.0, k)

# ---------------------------------------------------------------- 冰甲（霜语者）

## 每帧推进两件事：霜语者的施法冷却、以及冰甲的剩余时长。
func _tick_ice_armor(delta: float) -> void:
	if _cast_timer > 0.0:
		_cast_timer -= delta
		if _cast_timer <= 0.0:
			_cast_timer = float(EnemyData.ICE_ARMOR_INTERVAL) if iceshield else 0.0
			if iceshield:
				_ice_armor_aura()
	if _ice_shield_timer > 0.0:
		_ice_shield_timer -= delta
		if _ice_shield_timer <= 0.0 and ice_shield > 0.0:
			# 到期自然融化，和被打碎走同一套表现
			_break_shield()
	if _shield_fx_cd > 0.0:
		_shield_fx_cd -= delta


## 霜语者的光环：给半径内**还没甲**的非首领同伴套一层冰甲。
## 自己不套 —— 「先点掉那个萨满」才是这一波的解法。
func _ice_armor_aura() -> void:
	var radius := float(EnemyData.ICE_ARMOR_RADIUS)
	var ratio := float(EnemyData.ICE_ARMOR_RATIO)
	var dur := float(EnemyData.ICE_ARMOR_TIME)
	var cast := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e) or e == self:
			continue
		if e.global_position.distance_to(global_position) > radius:
			continue
		if e.is_boss() or not e.has_method("grant_ice_shield"):
			continue
		if e.has_ice_shield():
			continue
		e.grant_ice_shield(e.max_hp * ratio, dur)
		cast += 1
	var parent := get_parent()
	if parent == null:
		return
	# 不管有没有套到人，施法本身都要看得见：一圈冰环从法杖扩散出去
	Fx.ring(parent, global_position + Vector3(0.0, 1.05, 0.0), Color(0.55, 0.92, 1.0),
		radius * 0.55, 0.55)
	Fx.flash(parent, global_position + Vector3(0.30, 1.30, 0.15),
		Color(0.78, 0.97, 1.0), 0.75, 0.30)
	if cast > 0:
		Sound.play("levelup", -12.0)


## 套冰甲：已有的不叠加，只把数值补到更高、时长刷新。
## 护盾量由调用方按「挨打那只怪的最大生命」算，所以它能跟着波次血量成长。
func grant_ice_shield(amount: float, duration: float) -> void:
	if _dying or amount <= 0.0:
		return
	if _shield_dome == null:
		_build_shield_dome()
	ice_shield = maxf(ice_shield, amount)
	ice_shield_max = maxf(ice_shield_max, ice_shield)
	_ice_shield_timer = maxf(_ice_shield_timer, duration)
	_update_shield_dome()


func has_ice_shield() -> bool:
	return ice_shield > 0.0


## 冰甲外形：一层边缘发亮的冰蓝球壳（材质见 SHIELD_SHADER）。
func _build_shield_dome() -> void:
	var s := float(DATA[kind]["size"])
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.72 * s
	sm.height = 1.24 * s
	sm.radial_segments = 18
	sm.rings = 10
	mi.mesh = sm
	_shield_mat = ShaderMaterial.new()
	_shield_mat.shader = _shared_shield_shader()
	mi.material_override = _shield_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.55 * s
	mi.visible = false
	add_child(mi)
	_shield_dome = mi


## 甲越薄轮廓越暗、越小：玩家不看数字也能判断还剩多少
func _update_shield_dome() -> void:
	if _shield_dome == null or _shield_mat == null or not is_instance_valid(_shield_dome):
		return
	if ice_shield <= 0.0:
		_shield_dome.visible = false
		return
	var ratio := clampf(ice_shield / maxf(ice_shield_max, 0.001), 0.0, 1.0)
	_shield_dome.visible = true
	_shield_mat.set_shader_parameter("rim_strength", 0.25 + 0.55 * ratio)
	_shield_mat.set_shader_parameter("base_alpha", 0.04 + 0.10 * ratio)
	var k := 0.90 + 0.10 * ratio
	_shield_dome.scale = Vector3(k, k, k)


## 破甲：碎冰序列帧 + 冲击环 + 一声脆响（到期自然融化也走这里）
func _break_shield() -> void:
	ice_shield = 0.0
	if _shield_dome != null and is_instance_valid(_shield_dome):
		_shield_dome.visible = false
	var parent := get_parent()
	if parent == null:
		return
	var s := float(DATA[kind]["size"])
	var p := global_position + Vector3(0.0, 0.55 * s, 0.0)
	if not Fx.burst_seq(parent, p, "fx_ice", 2, 2.6, 0.42, 0.14,
			Color(0.65, 0.94, 1.0), Color(0.95, 1.0, 1.0)):
		Fx.flash(parent, p, Color(0.80, 0.97, 1.0), 0.9, 0.22)
	Fx.ring(parent, global_position, Color(0.70, 0.95, 1.0), 1.8, 0.4)
	Sound.play("hit", -6.0)


## 甲被打中的反馈：火是「嗤」的一下白汽，其它属性是冰蓝小闪光。
## 用冷却压一下 —— 喷火塔 3 发/秒，每发都放会糊屏。
func _shield_hit_fx(element: String, dmg: float) -> void:
	if _shield_fx_cd > 0.0 or dmg < 1.0:
		return
	_shield_fx_cd = 0.14
	var parent := get_parent()
	if parent == null:
		return
	var col := Color(1.0, 0.98, 0.92) if element == "fire" else Color(0.70, 0.95, 1.0)
	Fx.flash(parent, global_position + Vector3(0.0, 0.7, 0.0), col, 0.45, 0.14)

# ---------------------------------------------------------------- 受击

## element：伤害属性（"" = 物理，"fire" = 火）。目前只有冰甲关心它 ——
## 火属性削冰甲时 ×EnemyData.ICE_FIRE_MULT，其它属性 1 倍。
## 返回值 = 这一次命中是否把这只怪打死了。
## 冰塔的「碎冰」变异要据此在尸体位置放冰爆（见 Tower._beam_apply），
## 所以这里不能只是 void —— 但所有老调用点忽略返回值也完全兼容。
func take_damage(amount: float, crit: bool = false, show_number: bool = true,
		element: String = "") -> bool:
	if _dying or _rolled:
		return false
	# 破甲先扣护甲，易伤再放大伤害：两个都只影响「这一次命中之后」的攻击
	var eff_armor := maxf(armor - _armor_break, 0.0)
	if eff_armor > 0.0:
		amount *= (1.0 - eff_armor)
	if _vuln > 0.0:
		amount *= 1.0 + _vuln

	# 冰甲：全额吸收，火属性按倍率加速拆除。吸收完还有富余才轮到血量，
	# 富余部分要除以倍率还原——否则火塔能「顺便」把血也打掉一截。
	if ice_shield > 0.0:
		var mul := float(EnemyData.ICE_FIRE_MULT) if element == "fire" else 1.0
		var on_shield := amount * mul
		if on_shield < ice_shield:
			ice_shield -= on_shield
			_update_shield_dome()
			_shield_hit_fx(element, on_shield)
			if show_number and on_shield >= 8.0:
				Fx.damage_number(get_parent(), global_position + Vector3(0.0, 0.9, 0.0),
					str(int(round(on_shield))), Color(0.60, 0.94, 1.0), false)
			return false
		var overflow := (on_shield - ice_shield) / mul
		ice_shield = 0.0
		_break_shield()
		amount = overflow
		if amount <= 0.0:
			return false

	hp -= amount
	_update_bar()
	if crit and _mat != null:
		_mat.emission_energy_multiplier = 1.0
	# 小额伤害不飘字：喷火/箭塔每发都飘会把屏幕糊满，也省掉大量 Label3D
	if show_number and (crit or amount >= 8.0):
		Fx.damage_number(get_parent(), global_position + Vector3(0.0, 0.7, 0.0), str(int(round(amount))), Color(1.0, 0.35, 0.35) if crit else Color(1.0, 0.9, 0.7), crit)
	if hp <= 0.0:
		_die()
		return true
	return false


## 无视护甲的真实伤害（中毒的结算入口）：护甲只挡「被打」的部分，挡不住毒性
func _take_raw(amount: float) -> void:
	if _dying:
		return
	hp -= amount
	_update_bar()
	if hp <= 0.0:
		_die()


func apply_slow(factor: float, time: float) -> void:
	# 首领的减速抗性：一次减速最多只能削到 slow_cap，冰塔不能把它冻成不动靶子
	factor = minf(factor, slow_cap)
	# 直接减速的统一上限：多层减速之间是「取最强」，再套一层 50% 的硬顶。
	# 霜环被强化卡顶到 55%、或者以后加更狠的减速塔时，玩家看到的上限始终是 50%。
	factor = minf(factor, float(EnemyData.MAX_DIRECT_SLOW))
	slow_factor = maxf(minf(slow_factor, 1.0 - factor), float(EnemyData.MIN_SPEED_MUL))
	slow_timer = maxf(slow_timer, time)
	_update_tint()


## 当前的速度倍率（**不含** base_speed、也不含游泳系数）：
## 塔层减速 × 地形减速 × 加速词条，合流之后兜一个全局下限 MIN_SPEED_MUL。
## 单独抽成一个函数是因为地面 / 飞行两条移动分支原来各写一遍连乘，
## 以后再加光环减速时很容易只改一处 —— 现在只有一个入口，下限也只会生效一次。
func speed_mul() -> float:
	var m := slow_factor * slow_extra * (1.0 + _haste)
	return maxf(m, float(EnemyData.MIN_SPEED_MUL))


## 地形减速（震地雷的泥潭）：**乘算**叠在冰塔减速之上，互不覆盖。
## 例：冰塔 -22%（slow_factor 0.78）+ 泥潭 -16%（slow_extra 0.84）→ 实际 0.655 倍速。
## 走的是独立乘区，所以不会被 apply_slow 的「取更强」逻辑吞掉。
func apply_extra_slow(factor: float, time: float) -> void:
	if _dying:
		return
	var f := clampf(factor, 0.0, 0.9)
	slow_extra = minf(slow_extra, 1.0 - f)
	_slow_extra_timer = maxf(_slow_extra_timer, time)


## 是否处于「冰塔减速」状态。喷火塔的联动加成按这个状态判定
## 注意：只看冰塔那一层，踩泥潭不算「被冻住」，不会触发融化反应
func is_chilled() -> bool:
	return slow_timer > 0.0


## 是否正在燃烧（喷火塔的持续伤害）
func is_burning() -> bool:
	return _dot_timer > 0.0


## 是否感电（被闪电塔命中，喷火塔可以引爆）
func is_shocked() -> bool:
	return _shock_timer > 0.0


## 闪电塔命中时挂上感电标记
func apply_shock(duration: float) -> void:
	if _dying:
		return
	_shock_timer = maxf(_shock_timer, duration)
	_update_tint()


## 引爆感电：引爆成功后清除标记，避免喷火塔每一发都触发爆炸
func consume_shock() -> bool:
	if _shock_timer <= 0.0:
		return false
	_shock_timer = 0.0
	_update_tint()
	return true


## 治疗：由治疗怪的光环调用，回满为止
func heal_hp(amount: float) -> void:
	if _dying:
		return
	hp = minf(hp + amount, max_hp)
	_update_bar()
	Fx.damage_number(get_parent(), global_position + Vector3(0.0, 0.9, 0.0), "+%d" % int(round(amount)), Color(0.40, 0.95, 0.55), false)


## 治疗光环：每跳治疗周围友军（不含自己）
func _heal_aura() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e) or e == self:
			continue
		if e.global_position.distance_to(global_position) <= HEAL_RADIUS:
			e.heal_hp(heal)


## 燃烧：喷火塔施加的持续伤害
func apply_dot(dps: float, duration: float) -> void:
	if _dying:
		return
	_dot_dps = maxf(_dot_dps, dps)
	_dot_timer = maxf(_dot_timer, duration)
	_dot_tick = 0.0
	_update_tint()


## 中毒（强化卡「淬毒弹头」）：每秒伤害，**无视护甲**
func apply_poison(dps: float, duration: float) -> void:
	if _dying:
		return
	_poison_dps = maxf(_poison_dps, dps)
	_poison_timer = maxf(_poison_timer, duration)
	_poison_tick = 0.0
	_update_tint()


## 流血（强化卡「放血锋刃」）：每秒伤害，吃护甲减免，但基础值更高
func apply_bleed(dps: float, duration: float) -> void:
	if _dying:
		return
	_bleed_dps = maxf(_bleed_dps, dps)
	_bleed_timer = maxf(_bleed_timer, duration)
	_bleed_tick = 0.0
	_update_tint()


func is_poisoned() -> bool:
	return _poison_timer > 0.0


func is_bleeding() -> bool:
	return _bleed_timer > 0.0


## 破甲（强化卡「破甲弹头」）：临时削掉一部分护甲，对护盾怪 / 重甲收益最大。
## 用 maxf 而不是累加 —— 同一批塔互相刷新，不该因为射速高就无限叠。
func apply_armor_break(amount: float, duration: float) -> void:
	if _dying:
		return
	_armor_break = maxf(_armor_break, amount)
	_armor_break_timer = maxf(_armor_break_timer, duration)


## 易伤（强化卡「易伤标记」）：受到的所有伤害提高，同样取最大值不叠加
func apply_vuln(amount: float, duration: float) -> void:
	if _dying:
		return
	_vuln = maxf(_vuln, amount)
	_vuln_timer = maxf(_vuln_timer, duration)


## 塔锁定目标时判断：隐身怪在隐身阶段、被雪球卷着的怪都不可被直接锁定
func is_hidden() -> bool:
	return (cloak and _cloaked) or _rolled


## 被雪人王的滚雪球卷进球里：整只怪收起来，等雪球炸开再放出来
func become_rolled() -> void:
	if _rolled or _dying:
		return
	_rolled = true
	visible = false


## 雪球炸开：显形、落到落点，从「剩余路点」里最近的一个继续走
func release_rolled(pos: Vector3) -> void:
	if not _rolled:
		return
	_rolled = false
	visible = true
	global_position = pos
	if path_world.is_empty():
		return
	# 只在剩余路点里找最近的：不能倒退，也不许一步跳到终点（否则等于白送一只漏怪）
	var best := path_idx
	var best_d := INF
	for j in range(path_idx, path_world.size()):
		var d: float = path_world[j].distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = j
	path_idx = clampi(best, path_idx, maxi(path_world.size() - 2, path_idx))


func _update_tint() -> void:
	if _mat == null:
		return
	if slow_timer > 0.0:
		if _dot_timer > 0.0:
			# 冰火两重天：又冻又烧 → 泛白，提示喷火塔正在吃联动加成
			_mat.albedo_color = Color(0.90, 0.96, 1.0)
			_mat.emission = Color(0.70, 0.88, 1.0)
			_mat.emission_energy_multiplier = 1.0
		else:
			_mat.albedo_color = Color(0.55, 0.80, 1.0)
			_mat.emission = Color(0.30, 0.60, 1.0)
			_mat.emission_energy_multiplier = 0.5
	elif _shock_timer > 0.0:
		# 感电：淡紫色，提示「喷火塔打它会引爆」
		_mat.albedo_color = Color(0.80, 0.72, 1.0)
		_mat.emission = Color(0.60, 0.42, 1.0)
		_mat.emission_energy_multiplier = 0.75
	elif _bleed_timer > 0.0:
		# 流血：暗红，和中毒用颜色区分开
		_mat.albedo_color = Color(0.98, 0.42, 0.38)
		_mat.emission = Color(0.95, 0.20, 0.18)
		_mat.emission_energy_multiplier = 0.70
	elif _poison_timer > 0.0:
		# 中毒：墨绿
		_mat.albedo_color = Color(0.62, 0.92, 0.42)
		_mat.emission = Color(0.40, 0.95, 0.30)
		_mat.emission_energy_multiplier = 0.60
	else:
		var d: Dictionary = DATA[kind]
		_mat.albedo_color = _tint_base
		_mat.emission = _tint_base
		_mat.emission_energy_multiplier = 0.12
		if _enraged:
			var base_col: Color = _tint_base
			if kind == Kind.SNOWKING:
				# 雪人王「暴雪」：不是狂暴冲锋，而是雪体冻成更深的冰蓝，一眼看出进入第二阶段
				_mat.albedo_color = base_col.lerp(Color(0.55, 0.85, 1.0), 0.60)
				_mat.emission = Color(0.42, 0.80, 1.0)
				_mat.emission_energy_multiplier = 1.0
			else:
				# 狂暴：底色压向暗红并常亮，一眼看出大首领进入了第二阶段
				_mat.albedo_color = base_col.lerp(Color(1.0, 0.18, 0.22), 0.55)
				_mat.emission = Color(1.0, 0.25, 0.30)
				_mat.emission_energy_multiplier = 0.95
		if cloak:
			_apply_cloak_visual()


## 隐身怪：根据当前隐身状态调整身体透明度与血条可见性
func _apply_cloak_visual() -> void:
	if _mat != null:
		_mat.albedo_color.a = 0.16 if _cloaked else 1.0
		_mat.emission.a = 0.16 if _cloaked else 1.0
	if _bar_root != null:
		_bar_root.visible = not _cloaked


func _update_bar() -> void:
	if _bar_mat == null:
		return
	# 受击瞬间立即生效：改的是 shader 参数，不依赖节点缩放
	_bar_mat.set_shader_parameter("ratio", clampf(hp / max_hp, 0.0, 1.0))


## 让血条正对镜头。
## 不用 StandardMaterial3D 的 billboard：它会在顶点阶段用相机基向量替换模型旋转，
## 顺带把节点缩放丢掉（血条就永远满格了）。这里改成手动把血条的方向对齐相机。
func _face_bar_to_camera() -> void:
	if _bar_root == null or not is_inside_tree():
		return
	if _cam == null or not is_instance_valid(_cam):
		_cam = get_viewport().get_camera_3d()
	if _cam == null:
		return
	var t := _bar_root.global_transform
	# orthonormalized 去掉相机可能带的缩放，免得血条被一起拉大
	t.basis = _cam.global_transform.basis.orthonormalized()
	_bar_root.global_transform = t


func _die() -> void:
	_dying = true
	# 雪人王死在滚雪球途中：先把球里的怪放出来，否则它们会永远卡在无敌状态
	if _roll_state != 0:
		_release_roll()
	GameState.add_gold(reward)
	GameState.on_kill()
	remove_from_group("enemies")
	if _bar_root != null:
		_bar_root.visible = false
	if _marker_root != null:
		_marker_root.visible = false
	Sound.play("death")
	if is_boss():
		# 首领倒下：更大的爆闪 + 冲击环，给足击杀反馈
		Fx.flash(get_parent(), global_position, Color(1.0, 0.45, 0.55), 1.4, 0.45)
		Fx.ring(get_parent(), global_position, Color(1.0, 0.45, 0.55), 2.4, 0.7)
		Fx.ring(get_parent(), global_position, Color(1.0, 0.85, 0.45), 1.6, 0.5)
	else:
		Fx.flash(get_parent(), global_position, Color(1.0, 0.6, 0.3), 0.4, 0.2)
		Fx.ring(get_parent(), global_position, Color(1.0, 0.6, 0.3), 0.4, 0.25)
	if split > 0:
		_spawn_split_children()
	# 「连锁爆破」：死亡炸开一圈（伤害按自身最大生命的比例算，天然跟着波次成长）
	var blast := float(GameState.buffs.get("death_blast", 0.0))
	if blast > 0.0:
		_death_blast(blast)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(0.02, 0.02, 0.02), 0.18)
	tw.parallel().tween_property(self, "position:y", position.y + 0.5, 0.18)
	tw.tween_callback(queue_free)


## 「连锁爆破」的爆炸结算。用 take_damage 结算（会吃护甲/易伤），
## 每个敌人只会在自己死亡时炸一次，所以不会无限连锁。
func _death_blast(ratio: float) -> void:
	var dmg := max_hp * ratio
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e):
			continue
		if e.global_position.distance_to(global_position) > DEATH_BLAST_RADIUS:
			continue
		e.take_damage(dmg, false, false)
	Fx.ring(get_parent(), global_position, Color(1.0, 0.55, 0.20), DEATH_BLAST_RADIUS, 0.3)
	Fx.flash(get_parent(), global_position + Vector3(0.0, 0.5, 0.0), Color(1.0, 0.60, 0.25), DEATH_BLAST_RADIUS * 0.7, 0.2)


## 分裂怪：死亡后沿剩余路径分裂成若干小兵（不额外给奖励，避免刷金）。
## 小兵血量按「当前波血量成长 × 0.55」结算 —— 否则后期分裂出来的小兵还是开局强度，
## 血量成长就只对原生怪物生效，线性曲线会断掉。
func _spawn_split_children() -> void:
	var parent_node := get_parent()
	if parent_node == null or split <= 0:
		return
	var remaining: Array[Vector3] = []
	for j in range(path_idx, path_world.size()):
		remaining.append(path_world[j])
	for i in range(split):
		var e := Enemy.new()
		parent_node.add_child(e)
		var off := Vector3((randf() - 0.5) * 0.6, 0.0, (randf() - 0.5) * 0.6)
		e._init_enemy(Kind.GRUNT, global_position + off, remaining, hp_scale_v * 0.55, wave_no, 0)


func _leak() -> void:
	if _dying:
		return
	_dying = true
	remove_from_group("enemies")
	GameState.on_leak()
	GameState.lose_life(1)
	Sound.play("leak")
	queue_free()

# ---------------------------------------------------------------- 重新寻路

func repath(grid: GameGrid) -> void:
	if _dying:
		return
	var c := grid.world_to_cell(global_position)
	if not grid.in_bounds(c):
		c = Vector2i(clampi(c.x, 0, GameGrid.COLS - 1), clampi(c.y, 0, GameGrid.ROWS - 1))
	if grid.is_blocked(c):
		c = grid.nearest_reachable(c)
	var cells := grid.path_home_cells_from(c)
	if cells.is_empty():
		return
	var wp: Array[Vector3] = [global_position]
	for cc in cells:
		wp.append(grid.cell_to_world(cc))
	path_world = wp
	path_idx = 0
