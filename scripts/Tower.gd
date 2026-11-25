extends Node3D
class_name Tower
## 防御塔：7 种类型 × 3 个等级；满级（Lv.3）后从 3 个「变异」方向里选一个，决定最终形态。
## 升级只走金币路线（不提供塔对塔的合成）。

enum Kind { ARROW, CANNON, FROST, SNIPER, TESLA, FLAME, BOUNCE, POISON }

enum Priority { FRONT, STRONG, WEAK, CLOSE }
const PRIORITY_NAMES := ["最前", "最血多", "最血少", "最近"]

const MAX_LEVEL := TowerData.MAX_LEVEL

## 等级 → [底部, 中部, 顶部, 屋顶] 各用 a/b/c 哪个变体；空串表示不装屋顶
const LVL_PARTS := [
	["a", "a", "a", ""],
	["a", "b", "a", ""],
	["b", "b", "b", ""],
	["b", "c", "b", "a"],
	["c", "c", "c", "c"],
]

## 塔的色调（乘在 colormap 贴图上，让一眼能分清塔的类型）
const KIND_TINT := TowerData.KIND_TINT

## 外部模型接管时，各等级塔的目标身高（世界单位）。
## 参考原来 Kenney 部件堆叠出来约 4.9 高、底宽 2.0，这里保持同一量级。
const TOWER_HEIGHT := [4.0, 4.4, 4.8]

## 炮口高度占塔高的比例（不同塔的"出弹点"位置不一样，子弹才不会从塔肚子里飞出来）
const MUZZLE_RATIO := {
	Kind.ARROW: 0.88,
	Kind.CANNON: 0.72,
	Kind.FROST: 0.90,
	Kind.SNIPER: 0.84,
	Kind.TESLA: 0.92,
	Kind.FLAME: 0.78,
	Kind.BOUNCE: 0.86,
	# 毒瓶塔的出手点是坩埚口（比塔身矮一截），瓶子从这里抛出去才对得上
	Kind.POISON: 0.62,
}

## 顶部武器会跟着目标走的塔：模型里带独立 Turret 节点，塔身不动、只有炮管/弩臂/发射槽转。
## 箭塔（靶心木屋）、冰塔（冰晶）、电塔（电球）、火塔（火盆）都是全向的，不需要转向。
## 毒瓶塔的 Turret 是「炼金师举着瓶子的那条手臂」，转起来像在瞄着往哪扔。
const AIMING := [Kind.CANNON, Kind.SNIPER, Kind.BOUNCE, Kind.POISON]

## 转向速度：越大越快；14 大约 0.25 秒转 90°，看起来有份量又不拖沓
const AIM_TURN := 14.0

## 重新挑目标的间隔（秒）：没必要每帧扫一遍全场敌人
const AIM_REFRESH := 0.12

const DATA := TowerData.DATA
const UNLOCK := TowerData.UNLOCK


## 该塔从第几波开始可以建造
static func unlock_wave(k: int) -> int:
	return int(TowerData.UNLOCK.get(k, 1))


## 当前是否可以建造该塔。
## 战斗中按「当前波」判断，波间休整则按「下一波」判断 —— 这样新塔会在
## 上一波结束的瞬间开放，玩家有时间在开下一波前把它造好。
static func is_unlocked(k: int) -> bool:
	var reach := GameState.wave + (0 if GameState.wave_active else 1)
	return reach >= unlock_wave(k)


## 恰好在某一波解锁的塔（用于「新解锁」提示）
static func unlocked_at(wave: int) -> Array[int]:
	var out: Array[int] = []
	for k in TowerData.UNLOCK:
		if int(TowerData.UNLOCK[k]) == wave:
			out.append(int(k))
	return out

var kind: int = Kind.ARROW
var level: int = 1
var cell: Vector2i = Vector2i.ZERO
var value: int = 0          # 累计投入金币（用于出售返还）

var damage: float = 0.0
var fire_rate: float = 0.0
var range_v: float = 0.0
var splash: float = 0.0
var slow: float = 0.0
var chain: int = 0
var dot: float = 0.0

var priority: int = Priority.FRONT

var mutation: String = ""     # 变异 id；空串表示还没变异
var crit_bonus: float = 0.0   # 变异带来的塔级暴击加成（叠加在全局 crit 上）

## 被大首领「压制脉冲」命中的剩余时间：压制期间冷却照常走完，但不开火（塔不会被摧毁）
var suppress_timer: float = 0.0

var cooldown: float = 0.0
var muzzle_y: float = 1.5
var _recoil: float = 0.0
var _spin: float = 0.0

var _base: Node3D
var _body_root: Node3D
var _body_base_y: float = 0.0
var _custom_body: bool = false   # 塔身是否由外部 GLB 接管（决定要不要自转/染色）
var _turret: Node3D              # 顶部可转向武器（外部模型的 Turret 节点 / 部件堆叠的武器）
var _turret_yaw: float = 0.0     # 当前朝向（弧度），只在能转向的塔上生效
var _aim_target = null           # 正在瞄的敌人（不必每帧重新挑）
var _aim_timer: float = 0.0
var _ring: MeshInstance3D        # 射程圈：半透明圆盘
var _ring_edge: MeshInstance3D   # 射程圈：描边圆环（让边界一眼可见）
var _suppress_ring: MeshInstance3D # 压制提示圈：被首领脉冲熄火时脚下亮紫圈
var _pip_root: Node3D
var _selected: bool = false
var _hovered: bool = false

## 持续射线（冰塔）：射线本体 + 锁定状态。没有目标时 _beam 保持隐藏，不销毁。
var _beam: IceBeam
var _beam_target = null
var _beam_scan: float = 0.0      # 下一次重挑目标的倒计时
var _beam_tick: float = 0.0      # 距离下一次「打出一发」还差多久（等价于原来的 cooldown）

## 光环塔（变异「霜环」）：完全不打伤害，只在射程内铺一层冰雾并持续减速
var _fog: FrostFog
var _fog_tick: float = 0.0

# ---------------------------------------------------------------- 生命周期

func setup(k: int, c: Vector2i) -> void:
	kind = k
	cell = c
	level = 1
	value = int(DATA[k]["cost"])
	global_position = cell_to_world(c)
	add_to_group("towers")     # 首领的压制脉冲按这个组找塔
	_build_base()
	recalc_and_rebuild()


func cell_to_world(c: Vector2i) -> Vector3:
	# 与 GameGrid 的换算保持一致（y 对齐到草地顶面）
	return Vector3(
		(c.x - (GameGrid.COLS - 1) * 0.5) * GameGrid.CELL,
		GameGrid.SURFACE_Y,
		(c.y - (GameGrid.ROWS - 1) * 0.5) * GameGrid.CELL
	)


func _process(delta: float) -> void:
	if not GameState.running:
		# 暂停 / 波间休整：射线必须立刻断掉，否则会留一条挂在敌人身上的死线
		if _beam != null and is_instance_valid(_beam):
			_beam.stop()
		return

	if suppress_timer > 0.0:
		suppress_timer -= delta
		if suppress_timer <= 0.0 and _suppress_ring != null and is_instance_valid(_suppress_ring):
			_suppress_ring.visible = false

	if _recoil > 0.0:
		_recoil = maxf(_recoil - delta * 4.0, 0.0)
		if _body_root != null:
			_body_root.position.y = _body_base_y - _recoil * 0.18

	_update_aim(delta)

	# 箭塔/冰塔轻微旋转，增加画面活力（外部模型是完整建筑，转起来会露馅，所以不转；
	# 会瞄准的塔也不转 —— 它们靠 Turret 节点转向目标）
	if not _custom_body and not can_aim() and _body_root != null:
		_spin += delta * (0.5 + 0.1 * level)
		_body_root.rotation.y = _spin

	# 光环型（霜环）：完全没有攻击方式，只负责在射程内铺雾 + 减速
	if is_aura():
		_update_aura(delta)
		return

	# 持续射线型（冰塔）：没有冷却、不打子弹，走另一条更新路径
	if is_beam():
		_update_beam(delta)
		return

	cooldown -= delta
	if cooldown > 0.0:
		return
	# 被大首领压制：冷却照常走完，但打不出去（压制结束后立刻恢复火力）
	if suppress_timer > 0.0:
		return
	var target = _find_target()
	if target == null:
		return
	cooldown = 1.0 / maxf(fire_rate, 0.05)
	_shoot(target)

# ---------------------------------------------------------------- 瞄准

## 这座塔的顶部武器是否会转向目标
func can_aim() -> bool:
	return kind in AIMING


## 顶部武器转向当前目标。每 AIM_REFRESH 秒重挑一次目标（不必每帧扫全场敌人），
## 角度用 lerp_angle 平滑插值，不会瞬移；没目标时保持上一次朝向，看起来像在警戒。
func _update_aim(delta: float) -> void:
	if _turret == null or not is_instance_valid(_turret):
		return
	_aim_timer -= delta
	if _aim_timer <= 0.0:
		_aim_timer = AIM_REFRESH
		_aim_target = _find_target()
	if _aim_target != null and not is_instance_valid(_aim_target):
		_aim_target = null
	if _aim_target == null:
		return
	var d: Vector3 = _aim_target.global_position - global_position
	if d.x * d.x + d.z * d.z < 0.0001:
		return
	var want := atan2(d.x, d.z)          # 模型正面朝 +Z，所以是 atan2(x, z)
	_turret_yaw = lerp_angle(_turret_yaw, want, clampf(delta * AIM_TURN, 0.0, 1.0))
	_turret.rotation.y = _turret_yaw

# ---------------------------------------------------------------- 数值

func recalc_and_rebuild() -> void:
	_recalc()
	_build_body()


func _recalc() -> void:
	var d: Dictionary = DATA[kind]
	var lv := level - 1
	var tdmg: Dictionary = GameState.buffs.get("tower_dmg", {})
	var kind_bonus := float(tdmg.get(kind, 0.0))
	damage = float(d["dmg"]) * (1.0 + TowerData.LV_DMG_GROWTH * lv) * float(GameState.buffs["damage"]) * (1.0 + kind_bonus)
	range_v = float(d["range"]) * (1.0 + TowerData.LV_RANGE_GROWTH * lv) * float(GameState.buffs["range"])
	fire_rate = float(d["rate"]) * (1.0 + TowerData.LV_RATE_GROWTH * lv) * float(GameState.buffs["rate"])
	splash = float(d["splash"]) * float(GameState.buffs["splash"])
	slow = float(d["slow"]) * (1.0 + TowerData.LV_SLOW_GROWTH * lv) * float(GameState.buffs["slow"])
	chain = int(d.get("chain", 0))
	dot = float(d.get("dot", 0.0)) * float(GameState.buffs["damage"])
	# 毒瓶塔的 dot 就是毒池的每秒伤害，必须跟着等级一起长 ——
	# 喷火塔的 dot 走的是「灼烧 tick」，一直是 Lv1 数值，两者别混用同一套口径。
	if kind == Kind.POISON:
		dot *= (1.0 + TowerData.LV_DMG_GROWTH * lv)
	crit_bonus = 0.0

	# 变异：在基础数值结算完之后再乘/加一层，保证卡牌 buff 和变异能叠加
	var suffix := ""
	if mutation != "":
		var m := mutation_def()
		if not m.is_empty():
			var mods: Dictionary = m["mods"]
			damage *= float(mods.get("dmg_mul", 1.0))
			fire_rate *= float(mods.get("rate_mul", 1.0))
			range_v *= float(mods.get("range_mul", 1.0))
			splash += float(mods.get("splash_add", 0.0))
			# 减速有两种写法：slow_add 是加值（普通变异），slow_set 是定死（霜环那种光环塔 ——
			# 它没有冰弹了，减速完全来自冰雾，不该再叠基础塔的 0.22）
			var slow_set := float(mods.get("slow_set", -1.0))
			if slow_set >= 0.0:
				slow = slow_set * float(GameState.buffs["slow"])
			else:
				slow = maxf(0.0, slow + float(mods.get("slow_add", 0.0)))
			chain = maxi(0, chain + int(mods.get("chain_add", 0)))
			dot *= float(mods.get("dot_mul", 1.0))
			crit_bonus = float(mods.get("crit_add", 0.0))
			suffix = "·" + str(m.get("name", ""))
	name = "%s%s_L%d" % [d["name"], suffix, level]


func level_up() -> void:
	if level >= MAX_LEVEL:
		return
	level += 1
	recalc_and_rebuild()


## 花金币直接升一级的造价；已满级返回 -1。
## 造价 = 建塔成本 × UPGRADE_COST_COEF × 当前等级，等级越高越贵。
func upgrade_cost() -> int:
	if level >= MAX_LEVEL:
		return -1
	return int(round(float(DATA[kind]["cost"]) * TowerData.UPGRADE_COST_COEF * float(level)))


## 该类型塔可选的 3 个变异方向
static func mutations_for(k: int) -> Array:
	return TowerData.MUTATIONS.get(k, [])


## 当前变异的数据（未变异返回空字典）
func mutation_def() -> Dictionary:
	if mutation == "":
		return {}
	for m in mutations_for(kind):
		if str(m["id"]) == mutation:
			return m
	return {}


## 满级且还没变异 —— 浮窗会把「升级」按钮换成「变异」入口
func can_mutate() -> bool:
	return level >= MAX_LEVEL and mutation == ""


## 变异要花的钱（造价的固定比例）；不能变异时返回 -1
func mutation_cost() -> int:
	if not can_mutate():
		return -1
	return int(round(float(DATA[kind]["cost"]) * TowerData.MUTATION_COST_COEF))


## 变异一次定终身：选了就不能改
func apply_mutation(id: String) -> void:
	if id == "" or mutation != "":
		return
	mutation = id
	recalc_and_rebuild()

# ---------------------------------------------------------------- 战斗

func _find_target():
	var best = null
	var best_score := -INF
	var range_sq := range_v * range_v
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e):
			continue
		if e.is_hidden():
			continue
		var p: Vector3 = e.global_position
		var dx := p.x - global_position.x
		var dz := p.z - global_position.z
		var dsq := dx * dx + dz * dz
		if dsq > range_sq:
			continue
		var score := _target_score(e, dsq)
		if score > best_score:
			best_score = score
			best = e
	return best


func _target_score(e, dsq: float) -> float:
	match priority:
		Priority.FRONT:
			return float(e.progress)
		Priority.STRONG:
			return float(e.hp)
		Priority.WEAK:
			return -float(e.hp)
		Priority.CLOSE:
			return -dsq
	return float(e.progress)


func cycle_priority() -> void:
	priority = (priority + 1) % 4


func priority_name() -> String:
	return PRIORITY_NAMES[priority]


func _shoot(target) -> void:
	var is_crit: bool = randf() < float(GameState.buffs["crit"]) + crit_bonus
	var muzzle := global_position + Vector3(0.0, muzzle_y, 0.0)
	var b := Bullet.new()
	b.name = "Bullet"
	get_parent().add_child(b)
	b.global_position = muzzle
	b.configure(target, damage, splash, slow, TowerData.SLOW_TIME, is_crit, float(DATA[kind]["bullet"]), chain, dot, kind, level, mutation)
	_recoil = 1.0
	Sound.play("shoot")
	Fx.flash(get_parent(), muzzle, Color(1.0, 0.9, 0.5), 0.22, 0.08)

# ---------------------------------------------------------------- 持续射线（冰塔）

## 射线塔的规则（目前只有冰塔）：外观是连续锁定的，但**伤害节奏完全沿用原来的攻速** ——
## 每 1/攻速 秒打出一发满额伤害，而不是把伤害摊平成「每秒多少」。
## 所以单发数值、射速、暴击、升级收益都和改造前一模一样，变的只有「子弹飞过去」那段过程。

## 冰塔命中特效的序列帧数量：res://textures/fx_ice_0.png、fx_ice_1.png …（缺帧自动跳过）
const ICE_FX_FRAMES := 2

## 光环塔（变异「霜环」）刷减速的间隔：没必要每帧遍历全场敌人
const AURA_TICK := 0.2

## 这座塔是不是「持续射线」型：外观上锁定目标一直照射，但伤害仍按原攻速一发一发结算。
## 由 TowerData 里的 "beam": true 决定，以后加别的射线塔只改数据，不用动逻辑。
func is_beam() -> bool:
	return bool(DATA[kind].get("beam", false))


## 这座塔是不是「只减速、不攻击」的光环塔（变异「霜环」）。
## 由变异数据里的 "aura": true 决定 —— 它同时也是 is_beam() 的塔，所以判断要先看这一条。
func is_aura() -> bool:
	return bool(mutation_def().get("aura", false))


## 光环塔的每帧更新：射程内的敌人一直挂着减速，自己不打任何伤害。
## 冰雾本体是 FrostFog 节点，挂载见 _build_body()。
func _update_aura(delta: float) -> void:
	# 没有任何攻击方式：射线必须彻底关掉（霜环是从射线塔变异来的，别留一条残线）
	if _beam != null and is_instance_valid(_beam):
		_beam.stop()

	# 被首领脉冲压制：雾暂时熄灭，玩家一眼就能看出这座塔被「熄火」了
	var live := suppress_timer <= 0.0
	if _fog != null and is_instance_valid(_fog):
		_fog.visible = live
	if not live:
		return

	_fog_tick -= delta
	if _fog_tick > 0.0:
		return
	_fog_tick = AURA_TICK
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e) or e.is_hidden():
			continue
		if not _in_range(e):
			continue
		# 只挂减速：毒 / 流血这些「弹药词条」本质上属于攻击，不造成伤害的塔不触发
		e.apply_slow(slow, TowerData.SLOW_TIME)


## 两发之间的间隔（秒）：直接用原来的攻速（1/攻速），改造前是多少现在就还是多少。
func shot_interval() -> float:
	return 1.0 / maxf(fire_rate, 0.05)


## 持续射线的每帧更新：挑目标 → 画射线 → 到点就打出一发（伤害本身不走「每秒摊平」）。
## 目标死亡 / 走出射程 / 进入隐身都会自动换下一个；被首领压制时整条射线断掉。
func _update_beam(delta: float) -> void:
	if _beam == null or not is_instance_valid(_beam):
		return

	_beam_scan -= delta
	var tgt = _beam_target
	# hp <= 0 也要立刻换人：死亡动画会拖 0.2 秒，不然射线会对着尸体再烧一会儿
	if tgt != null and (not is_instance_valid(tgt) or tgt.is_hidden()
			or tgt.hp <= 0.0 or not _in_range(tgt)):
		tgt = null
	if tgt == null and _beam_scan <= 0.0:
		_beam_scan = AIM_REFRESH
		tgt = _find_target()
	var had := _beam_target != null
	_beam_target = tgt

	if tgt == null or suppress_timer > 0.0:
		_beam.stop()
		_beam_tick = 0.0
		return

	var muzzle := global_position + Vector3(0.0, muzzle_y, 0.0)
	var tip: Vector3 = tgt.global_position + Vector3(0.0, 0.7, 0.0)
	# 起点朝目标方向挪一点：射线看起来才是从冰晶尖端射出去的，而不是从塔心穿出来
	var flat := tip - muzzle
	flat.y = 0.0
	if flat.length() > 0.01:
		muzzle += flat.normalized() * 0.24
	if not had:
		# 刚锁上目标：和原来「冷却归零时立刻开一枪」一样，第一发马上打出去
		Sound.play("shoot", -14.0)
		_beam_tick = shot_interval()
	_beam.fire(muzzle, tip, delta)

	_beam_tick += delta
	var interval := shot_interval()
	if _beam_tick < interval:
		return
	# 用减法而不是清零：掉帧时也不会把射速吃掉，长期 DPS 和配置一致
	_beam_tick -= interval
	_beam_apply(tgt)


## 打出一发：单发伤害 = 面板上的 damage（暴击 ×2），规则和子弹命中完全一致
## （溅射衰减、护甲、易伤、处决协议都在 take_damage 里）。
func _beam_apply(tgt) -> void:
	var crit: bool = randf() < float(GameState.buffs["crit"]) + crit_bonus
	var dmg: float = damage * (2.0 if crit else 1.0)
	var pos: Vector3 = tgt.global_position
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e) or e.is_hidden():
			continue
		var coef := 1.0
		if e != tgt:
			if splash <= 0.0 or e.global_position.distance_squared_to(pos) > splash * splash:
				continue
			coef = float(TowerData.SPLASH_DMG_COEF)
		e.take_damage(dmg * coef, crit, true)
		# 每次命中都刷一次减速时长：只要敌人还在射线里，就一直是冻住的
		Bullet.apply_on_hit_status(e, slow, TowerData.SLOW_TIME)

	_spawn_ice_hit(pos)


## 冰冻射线打中敌人时的特效：冰块炸开的序列帧（res://textures/fx_ice_0…1）。
## 只放在主目标身上 —— 溅射圈里的其他人由射线本身提示，一人一团会把屏幕糊满。
## 没放贴图时回退成程序化的冰蓝闪光 + 小冲击环，工程照样能跑。
func _spawn_ice_hit(pos: Vector3) -> void:
	var parent := get_parent()
	if parent == null:
		return
	# 抬到敌人胸口高度再往镜头方向推：这张素材的冰渣全挤在画布下半部，
	# 原来挂在 pos + 0.45 时，下半截被敌人身体挡住、最底下还压到路面（0.86）以下，
	# 剩下能看见的只有顶部那颗几像素的小冰晶 —— 看起来就像「特效没出」。
	var p := pos + Vector3(0.0, 0.85, 0.0)
	p += _cam_dir() * 0.55
	# 素材本身接近纯白，白对白一片糊：贴图乘一层更深的冰蓝，再补一颗亮芯闪光。
	# 尺寸 / 时长都比普通命中特效更大更长 —— 射线每发都要「打得响」。
	if Fx.burst_seq(parent, p, "fx_ice", ICE_FX_FRAMES, 3.4, 0.45, 0.16,
			Color(0.80, 0.96, 1.0), Color(0.55, 0.86, 1.0)):
		Fx.flash(parent, p, Color(0.85, 0.97, 1.0), 0.70, 0.18)
		return
	Fx.flash(parent, p, Color(0.62, 0.90, 1.0), 0.6, 0.18)
	Fx.ring(parent, pos + Vector3(0.0, 0.2, 0.0), Color(0.55, 0.85, 1.0), 0.7, 0.22)


## 「由场景指向相机」的单位向量：特效往这个方向偏一点就不会被目标身体挡住
func _cam_dir() -> Vector3:
	if not is_inside_tree():
		return Vector3.ZERO
	var vp := get_viewport()
	if vp == null:
		return Vector3.ZERO
	var cam := vp.get_camera_3d()
	if cam == null:
		return Vector3.ZERO
	# 相机看 -Z，所以 basis.z 就是朝向相机的那一侧
	return cam.global_transform.basis.z.normalized()


## 目标是否还在射程内（只算水平距离，和 _find_target 的口径一致）
func _in_range(e) -> bool:
	if e == null or not is_instance_valid(e):
		return false
	var p: Vector3 = e.global_position
	var dx := p.x - global_position.x
	var dz := p.z - global_position.z
	return dx * dx + dz * dz <= range_v * range_v


## 跟着等级 / 变异同步射线的粗细和颜色：升级后冰晶变大，射线也该更粗；
## 选了变异就用变异色调（霜环淡蓝、碎冰亮白、寒潮深蓝），和脚下的光环对得上。
func _sync_beam_look() -> void:
	if not is_beam() or _beam == null or not is_instance_valid(_beam):
		return
	var glow := Color(0.34, 0.78, 1.0)
	var core := Color(0.90, 0.99, 1.0)
	var md := mutation_def()
	if md.has("tint"):
		glow = md["tint"]
	_beam.set_colors(core, glow)
	_beam.set_width_mul(1.0 + 0.10 * float(level - 1))


# ---------------------------------------------------------------- 外观

func _build_base() -> void:
	_base = ModelLib.instance("tower-round-base")
	_base.name = "Base"
	_base.scale = Vector3(ModelLib.SCALE, ModelLib.SCALE, ModelLib.SCALE)
	add_child(_base)

	_ring = MeshInstance3D.new()
	_ring.name = "RangeRing"
	var rm := CylinderMesh.new()
	rm.top_radius = 1.0
	rm.bottom_radius = 1.0
	rm.height = 0.02
	rm.radial_segments = 48
	_ring.mesh = rm
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.albedo_color = Color(0.40, 0.85, 1.0, 0.16)
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring.material_override = rmat
	# 抬到 0.12：高于土路路面（路面顶在 SURFACE_Y + 0.09），射程圈才不会被路盖住
	_ring.position.y = 0.12
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)

	# 外圈描边：只靠半透明圆盘很难看清边界，加一圈亮边
	_ring_edge = MeshInstance3D.new()
	_ring_edge.name = "RangeRingEdge"
	var tm := TorusMesh.new()
	tm.inner_radius = 0.98
	tm.outer_radius = 1.0
	tm.rings = 56
	tm.ring_segments = 6
	_ring_edge.mesh = tm
	var emat := StandardMaterial3D.new()
	emat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	emat.albedo_color = Color(0.45, 0.92, 1.0, 0.85)
	emat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	emat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_edge.material_override = emat
	_ring_edge.position.y = 0.13
	_ring_edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring_edge.visible = false
	add_child(_ring_edge)

	# 压制提示圈：被大首领脉冲打中时脚下亮紫圈，告诉玩家「这座塔只是熄火了，没被拆」
	_suppress_ring = MeshInstance3D.new()
	_suppress_ring.name = "SuppressRing"
	var sm := TorusMesh.new()
	sm.inner_radius = 0.86
	sm.outer_radius = 1.04
	sm.rings = 32
	sm.ring_segments = 6
	_suppress_ring.mesh = sm
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(0.62, 0.38, 1.0, 0.95)
	smat.emission_enabled = true
	smat.emission = Color(0.55, 0.30, 1.0)
	smat.emission_energy_multiplier = 1.4
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_suppress_ring.material_override = smat
	_suppress_ring.position.y = 0.14
	_suppress_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_suppress_ring.visible = false
	add_child(_suppress_ring)

	_pip_root = Node3D.new()
	_pip_root.name = "Pips"
	add_child(_pip_root)

	# 持续射线型（冰塔）：射线节点挂在塔身上，但 top_level = true 且变换为单位阵，
	# 这样顶点直接用世界坐标画，塔身换模型 / 重建塔身都不会影响它。
	if is_beam():
		_beam = IceBeam.new()
		_beam.name = "IceBeam"
		_beam.top_level = true
		_beam.transform = Transform3D.IDENTITY
		add_child(_beam)


func _build_body() -> void:
	if _body_root != null and is_instance_valid(_body_root):
		_body_root.free()
	_turret = null
	_body_root = Node3D.new()
	_body_root.name = "Body"
	add_child(_body_root)

	# 优先用外部 GLB（放了模型就整座塔换掉，含石基座）；没有就回退部件堆叠
	_custom_body = _build_custom_tower()
	if not _custom_body:
		_build_stacked_body()
	if _turret != null:
		_turret.rotation.y = _turret_yaw

	var pip_col := Color(1.0, 0.92, 0.45)
	var md := mutation_def()
	if md.has("tint"):
		pip_col = md["tint"]
	_build_pips(pip_col)
	_build_mutation_aura()
	_sync_beam_look()
	_rebuild_fog()
	_ring.scale = Vector3(range_v, 1.0, range_v)
	_ring_edge.scale = Vector3(range_v, 1.0, range_v)
	_update_ring_visibility()


## 冰雾：只有光环塔（霜环）才有。射程会随升级 / 变异 / 卡牌变化，
## 所以每次重建塔身都按当前 range_v 重新铺一遍，保证雾圈和射程圈严丝合缝。
func _rebuild_fog() -> void:
	if _fog != null and is_instance_valid(_fog):
		_fog.free()
		_fog = null
	_fog_tick = 0.0
	if not is_aura():
		return
	# 底子用雾自己的深蓝，只掺一点变异色：直接拿变异的 tint（偏白的浅蓝）会糊在浅色路面上
	var col := FrostFog.FOG_COLOR
	var md := mutation_def()
	if md.has("tint"):
		col = col.lerp(md["tint"] as Color, 0.3)
	_fog = FrostFog.new()
	_fog.name = "FrostFog"
	add_child(_fog)
	_fog.setup(range_v, col)


## 外部模型接管整座塔：把任意 GLB 命名为
## `res://models/towers/tower_<类型>_l<等级>.glb`（如 tower_frost_l2.glb）即可，
## 约定和敌人模型一致：原点在脚底、+Y 向上、正面 +Z，这里按身高自动缩放、贴地、居中。
## 模型自带石基座，所以连 Kenney 的 tower-round-base 一起隐藏。
## 找不到文件返回 false —— 回退部件堆叠，工程永远能跑。
##
## 变异专属外观：`tower_<类型>_l<等级>_<变异短名>.glb`（如 cannon_twin 满级 →
## tower_cannon_l3_twin.glb）存在时优先使用，没有就还是用普通模型。
func _build_custom_tower() -> bool:
	var model := ModelLib.instance_path(_custom_model_path())
	if model == null:
		return false
	var box := ModelLib.aabb_of(model)
	var base := model.scale
	var cur_h: float = box.size.y * absf(base.y)
	if cur_h <= 0.0001:
		model.queue_free()
		return false

	var target_h: float = float(TOWER_HEIGHT[mini(level, TOWER_HEIGHT.size()) - 1])
	var k := target_h / cur_h
	model.scale = base * k
	var c := box.get_center()
	model.position = Vector3(-c.x * base.x * k, -box.position.y * base.y * k, -c.z * base.z * k)
	_body_root.add_child(model)

	# 生成器把炮管/弩臂/发射槽单独做成 Turret 节点，转它才是"炮塔转向"
	_turret = model.find_child("Turret", true, false) as Node3D

	_body_base_y = 0.0
	_body_root.position.y = 0.0
	if _base != null and is_instance_valid(_base):
		_base.visible = false
	muzzle_y = target_h * float(MUZZLE_RATIO.get(kind, 0.88))
	return true


## 原来的实现：把 Kenney 的 tower-round-* 按等级逐层堆起来
func _build_stacked_body() -> void:
	# 底座顶部作为堆叠起点（底座不随塔身旋转）
	_body_base_y = ModelLib.height_of(_base) * ModelLib.SCALE
	_body_root.position.y = _body_base_y

	var y := 0.0
	var parts: Array = LVL_PARTS[level - 1]
	y = _stack("tower-round-bottom-%s" % parts[0], y)
	y = _stack("tower-round-middle-%s" % parts[1], y)
	y = _stack("tower-round-top-%s" % parts[2], y)
	if str(parts[3]) != "":
		y = _stack("tower-round-roof-%s" % parts[3], y)
	if level >= MAX_LEVEL:
		_stack("tower-round-crystals", y - 0.05)

	# 塔顶武器：三种塔各配一种，靠它区分类型
	var wpn := ModelLib.instance(_weapon())
	if wpn != null:
		wpn.scale = Vector3(ModelLib.SCALE, ModelLib.SCALE, ModelLib.SCALE)
		_body_root.add_child(wpn)
		wpn.position.y = y
		# 没有外部模型时，塔顶武器本身就是可转向的部件
		if can_aim():
			_turret = wpn
		muzzle_y = _body_base_y + y + ModelLib.height_of(wpn) * ModelLib.SCALE + 0.15
	else:
		muzzle_y = _body_base_y + y + 0.15

	# 用色调区分塔类型（乘在调色板贴图上，底座也一起染）
	var tc: Color = KIND_TINT.get(kind, Color.WHITE)
	if tc != Color.WHITE:
		ModelLib.tint(_body_root, tc)
		ModelLib.tint(_base, tc)


## 往塔身上叠一个部件，返回叠完后的累计高度（已乘 SCALE）
func _stack(model: String, y: float) -> float:
	var part := ModelLib.instance(model)
	if part == null:
		return y
	part.scale = Vector3(ModelLib.SCALE, ModelLib.SCALE, ModelLib.SCALE)
	_body_root.add_child(part)
	part.position.y = y
	return y + ModelLib.height_of(part) * ModelLib.SCALE


## 变异后的外观：脚下发光光环 + 塔身换成变异色，远远一看就知道这座塔选了哪条路
func _build_mutation_aura() -> void:
	var md := mutation_def()
	if md.is_empty():
		return
	var col: Color = md["tint"]

	# 先换塔身颜色，再挂光环：ModelLib.tint 会遍历所有 MeshInstance3D，
	# 顺序反了会把光环材质也一起改成不透明纯色。
	# 外部模型自带上色（多种材质），染成纯色会毁掉造型，所以只给加法几何用。
	if not _custom_body:
		ModelLib.tint(_body_root, col)

	var aura := MeshInstance3D.new()
	aura.name = "MutationAura"
	var tm := TorusMesh.new()
	tm.inner_radius = 0.92
	tm.outer_radius = 1.06
	tm.rings = 44
	tm.ring_segments = 6
	aura.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(col.r, col.g, col.b, 0.85)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 1.8
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	aura.material_override = mat
	aura.position.y = 0.16
	aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body_root.add_child(aura)


## 外部模型的实际路径。变异有专属外观时优先：
## cannon_twin（双管齐射）→ tower_cannon_l3_twin.glb（工具脚本 tools/gen_tower_models.py 生成）。
func _custom_model_path() -> String:
	var base := "res://models/towers/tower_%s_l%d" % [kind_suffix(), level]
	var tag := mutation_short()
	if tag != "":
		var alt := "%s_%s.glb" % [base, tag]
		if ResourceLoader.exists(alt):
			return alt
	return base + ".glb"


## 变异 id 的短名："cannon_twin" → "twin"，用于拼模型文件名
func mutation_short() -> String:
	if mutation == "":
		return ""
	var parts: PackedStringArray = mutation.split("_")
	return parts[parts.size() - 1]


## 塔类型 → 外部模型槽位后缀（res://models/towers/tower_<后缀>_l<等级>.glb）
func kind_suffix() -> String:
	match kind:
		Kind.CANNON:
			return "cannon"
		Kind.FROST:
			return "frost"
		Kind.SNIPER:
			return "sniper"
		Kind.TESLA:
			return "tesla"
		Kind.FLAME:
			return "flame"
		Kind.BOUNCE:
			return "bounce"
		Kind.POISON:
			return "poison"
		_:
			return "arrow"


## 塔类型 → 顶部武器模型（仅部件堆叠模式用）
func _weapon() -> String:
	match kind:
		Kind.CANNON:
			return "weapon-cannon"
		Kind.FROST, Kind.TESLA, Kind.FLAME, Kind.POISON:
			return "weapon-turret"
		_:
			return "weapon-ballista"


func _build_pips(col: Color) -> void:
	for c in _pip_root.get_children():
		c.free()
	for i in range(level):
		var pip := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.09
		sm.height = 0.18
		pip.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.92, 0.45)
		pip.material_override = mat
		var ang := TAU * float(i) / float(MAX_LEVEL)
		pip.position = Vector3(cos(ang) * 1.0, 0.5, sin(ang) * 1.0)
		_pip_root.add_child(pip)


## 被大首领的「压制脉冲」命中：塔在 time 秒内不开火（不摧毁、不降级）。
## 冷却会继续走完，压制结束后第一发几乎是立刻打出去的，玩家的感受是「熄火一下」。
func suppress(time: float) -> void:
	if suppress_timer <= 0.0:
		Fx.flash(get_parent(), global_position + Vector3(0.0, muzzle_y * 0.6, 0.0), Color(0.65, 0.42, 1.0), 0.8, 0.3)
	suppress_timer = maxf(suppress_timer, time)
	if _suppress_ring != null and is_instance_valid(_suppress_ring):
		_suppress_ring.visible = true


func set_selected(v: bool) -> void:
	_selected = v
	_update_ring_visibility()


## 鼠标悬停时也显示射程圈：不用先点选就能比较两个塔位的覆盖范围
func set_hovered(v: bool) -> void:
	_hovered = v
	_update_ring_visibility()


func _update_ring_visibility() -> void:
	var on := _selected or _hovered
	if _ring != null and is_instance_valid(_ring):
		_ring.visible = on
	if _ring_edge != null and is_instance_valid(_ring_edge):
		_ring_edge.visible = on


## 元素联动说明（只在有联动的塔上显示），尽量压成一行，避免信息面板被撑爆
func synergy_text() -> String:
	var parts: Array[String] = []
	# 融化反应的加成 = 基础值 + 强化卡「熔核共鸣 / 元素共鸣」的加成，面板跟着一起变
	var melt := float(TowerData.CHILL_DMG_BONUS) + float(GameState.buffs.get("melt_dmg", 0.0))
	var pct := int(round(melt * 100.0))
	if pct > 0:
		if kind == Kind.FLAME:
			parts.append("冰塔减速 → 伤害 +%d%%" % pct)
		elif kind == Kind.FROST:
			parts.append("被你减速的敌人吃喷火 +%d%% 伤害" % pct)
	if kind == Kind.FLAME:
		parts.append("闪电感电 → 命中后小范围爆炸")
	elif kind == Kind.TESLA:
		parts.append("感电目标被喷火命中 → 小范围爆炸")
	if parts.is_empty():
		return ""
	return "\n联动：" + " · ".join(parts)


func info_text() -> String:
	var d: Dictionary = DATA[kind]
	var extra := ""
	if dot > 0.0:
		extra = "（灼烧 %.0f/s）" % dot
	var tip := ""
	var title_name := str(d["name"])
	if level >= MAX_LEVEL:
		if can_mutate():
			tip = "已满级 · 点「变异」选择最终形态（三选一，不可更改）"
		else:
			var mn := str(mutation_def().get("name", ""))
			tip = "已变异：%s（最终形态）" % mn
			title_name += "·" + mn
	else:
		tip = "升级到 Lv.%d：%d 金（浮窗「升级」按钮）\n满级 Lv.%d 后可变异，决定这座塔的最终形态" % [level + 1, upgrade_cost(), MAX_LEVEL]
	if suppress_timer > 0.0:
		tip = "⚠ 正被首领脉冲压制：%.1fs 内无法开火\n%s" % [suppress_timer, tip]

	# 光环塔没有伤害和攻速，面板换成「范围减速」的说法，免得玩家以为它坏了
	var line := "伤害 %.0f%s · 射程 %.1f · 攻速 %.2f/s" % [damage, extra, range_v, fire_rate]
	if is_aura():
		line = "冰雾光环：射程 %.1f 内减速 %.0f%% · 不造成伤害" % [range_v, slow * 100.0]
	return "[%s Lv.%d]\n%s\n%s\n目标优先级：%s（Q 切换）\n%s%s" % [
		title_name, level, line, d["desc"], priority_name(), tip, synergy_text()
	]
