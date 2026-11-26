class_name Waves
## 波次配置：10 波，敌人数量/种类随波次增长。
## 首领节点：第 5 波出「小首领」，第 10 波（压轴）出「大首领」；
## 无尽模式沿用同一规律 —— 每 5 波一个小首领，每 10 波一个大首领。

const TOTAL := 10


## 每波血量成长 —— **线性**：第 N 波 = 1 + HP_SCALE_STEP × (N-1)。
## 第 1 波 ×1.0、第 5 波 ×4.0、第 10 波 ×7.75（无尽模式继续往上加）。
## 线性而不是指数：玩家的塔位与升级都是线性投入，指数血量会让中期直接崩盘。
const HP_SCALE_STEP := 0.75


## 击杀奖励 = EnemyData 里的基础 reward × reward_scale(wave)。
## reward_scale 由两部分组成：
##   ① 波次曲线（先涨后跌）：1~5 波每波 +3%，第 6 波起每波 -2.5%；
##   ② 全局系数 REWARD_COEF：整体再乘一个系数，直接决定「打怪能拿多少钱」。
## 为什么不能一直涨：敌人「数量」本身也随波次线性增长，单价再涨就是平方级收入，
## 而玩家支出上限是有限的塔位 —— 后期金币会直接溢出、难度形同虚设。
## 当前实际系数 = REWARD_COEF × 曲线：
##   第 1 波 ×0.88 → 第 5 波 ×0.99（峰值）→ 第 10 波 ×0.88 → 第 15 波 ×0.77 → 第 20 波 ×0.66。
## 经济节奏备忘：0.75 时前中期明显偏紧（塔都不敢升级），所以回调到 0.88 ——
## 比最早的 1.0 仍然低 12%，但足够让玩家在第 3~5 波攒出第一座满级塔。
const REWARD_COEF := 0.88
const REWARD_EARLY_STEP := 0.03
const REWARD_LATE_STEP := -0.025
const REWARD_PEAK_WAVE := 5


static func hp_scale(wave: int) -> float:
	return 1.0 + HP_SCALE_STEP * float(maxi(wave, 1) - 1)


## 击杀奖励的波次系数（见上面的 REWARD_* 常量）
static func reward_scale(wave: int) -> float:
	var w := maxi(wave, 1)
	var curve: float
	if w <= REWARD_PEAK_WAVE:
		curve = 1.0 + REWARD_EARLY_STEP * float(w - 1)
	else:
		curve = 1.0 + REWARD_EARLY_STEP * float(REWARD_PEAK_WAVE - 1) + REWARD_LATE_STEP * float(w - REWARD_PEAK_WAVE)
	return curve * REWARD_COEF


static func interval(wave: int) -> float:
	return maxf(0.80 - 0.045 * float(wave - 1), 0.32)


## 「入口驻守」时长：这一波出怪总时长的一半（plan_size 含首领自己那一只）。
## 霜渊的雪人王开波就登场、蹲在入口滚雪球，等到这一波出一半才动身往里走 ——
## 所以它滚的球里装的正是这半波刚从洞口出来的杂兵，而不是已经在半路上的漏网之鱼。
static func entrance_hold(wave: int, plan_size: int) -> float:
	return 0.5 * float(maxi(plan_size, 1)) * interval(wave)


## 该波是不是压轴大首领波（最后一波，以及无尽模式每 10 波）
static func is_big_boss_wave(wave: int) -> bool:
	return wave == TOTAL or (wave > 0 and wave % 10 == 0)


## 该波是不是小首领波（每 5 波，大首领波除外）
static func is_mini_boss_wave(wave: int) -> bool:
	return wave > 0 and wave % 5 == 0 and not is_big_boss_wave(wave)


## 本图的压轴首领：默认「大首领」，地图可以在 opts 里换成自己的（例如霜渊的雪人王）
static func big_boss_kind(opts: Dictionary = {}) -> int:
	return int(opts.get("big_boss", Enemy.Kind.BOSS))


## 本图的小首领：默认「小首领」，地图可以换成自己的（例如霜渊的霜松）
static func mini_boss_kind(opts: Dictionary = {}) -> int:
	return int(opts.get("mini_boss", Enemy.Kind.MINI_BOSS))


## 下一波的首领名字；没有首领返回空串。给「开始第 N 波」按钮做战前预告用。
static func boss_name(wave: int, opts: Dictionary = {}) -> String:
	if is_big_boss_wave(wave):
		return str(Enemy.DATA[big_boss_kind(opts)]["name"])
	if is_mini_boss_wave(wave):
		return str(Enemy.DATA[mini_boss_kind(opts)]["name"])
	return ""


## 返回本波要生成的敌人种类列表（已打乱，首领排在最后）。
## opts 是**地图级**的开关（MapDefs 里同名标记），目前三个：
##   "icebreaker"  本图有冰湖 → 混入会破冰游泳的「碎冰者」。它不沿雪径走，
##                 数量不能多：每波最多 4 只，第 3 波起出现。
##   "frostweaver" 本图有霜语者 → 混入会套冰甲的辅助单位。它是纯辅助，
##                 比碎冰者更少：每波最多 3 只，第 4 波起出现。
##   "frostling"   本图有霜崽（冰原小怪）→ 混入小杂兵，每波最多 8 只，第 2 波起出现。
##                 它**自己砸不开冰面**，要等碎冰者把湖凿开以后才走水下段。
##   "big_boss"    第 10 波（以及无尽每 10 波）的压轴首领换成谁，默认 Enemy.Kind.BOSS。
##                 霜渊用 Enemy.Kind.SNOWKING（雪人王：丢雪球压塔攻速）。
static func plan(wave: int, opts: Dictionary = {}) -> Array:
	var list: Array = []
	var n := wave
	var icebreak := bool(opts.get("icebreaker", false))
	var weaver := bool(opts.get("frostweaver", false))
	var frostling := bool(opts.get("frostling", false))
	var boss_kind := big_boss_kind(opts)
	var mini_kind := mini_boss_kind(opts)

	for i in range(6 + n * 2):
		list.append(Enemy.Kind.GRUNT)
	if icebreak and n >= 3:
		for i in range(clampi(n - 3, 1, 4)):
			list.append(Enemy.Kind.ICEBREAKER)
	if weaver and n >= 4:
		for i in range(clampi(n - 4, 1, 3)):
			list.append(Enemy.Kind.FROSTWEAVER)
	if frostling and n >= 2:
		# 体型小、跑得快，靠数量压人：上限 8 只，别把一波塞成「霜崽海」
		for i in range(clampi(n - 1, 2, 8)):
			list.append(Enemy.Kind.FROSTLING)
	if n >= 3:
		for i in range(n * 2):
			list.append(Enemy.Kind.RUNNER)
		for i in range(n - 1):
			list.append(Enemy.Kind.SHIELD)
		for i in range(n - 2):
			list.append(Enemy.Kind.HEALER)
	if n >= 4:
		# 飞行怪（FLYER）暂时停用：无视地形直线飞行太强，先不放出来。
		# 想恢复只需要把下面这行循环加回来：
		# for i in range(n - 2):
		# 	list.append(Enemy.Kind.FLYER)
		for i in range(n - 3):
			list.append(Enemy.Kind.SPLITTER)
	if n >= 5:
		for i in range(n - 3):
			list.append(Enemy.Kind.TANK)
		for i in range(n - 4):
			list.append(Enemy.Kind.CLOAK)

	list.shuffle()

	if is_big_boss_wave(n):
		# 最后一波（以及无尽模式每 10 波）：重甲开路 + 1 个小首领护卫 + 压轴首领
		# 大小首领都按地图换（霜渊是霜松 + 雪人王），没配置就是原来的通用首领
		for i in range(clampi(n - 3, 2, 8)):
			list.append(Enemy.Kind.TANK)
		list.append(mini_kind)
		# 会「入口驻守」的首领（霜渊的雪人王）**第一个登场**：它蹲在洞口滚雪球，
		# 等这波出一半才动身；标记是写在 EnemyData 里的，别的图想这么玩也只需要打标记。
		if bool(Enemy.DATA[boss_kind].get("entrance_wait", false)):
			list.push_front(boss_kind)
		else:
			list.append(boss_kind)
	elif is_mini_boss_wave(n):
		# 每 5 波：重甲开路 + 小首领（霜渊是霜松）
		for i in range(clampi(n - 3, 2, 8)):
			list.append(Enemy.Kind.TANK)
		list.append(mini_kind)

	return list


## 波次预览文字
static func preview(wave: int, opts: Dictionary = {}) -> String:
	var p := plan(wave, opts)
	var counts := {}
	for k in p:
		counts[k] = int(counts.get(k, 0)) + 1
	var parts: Array[String] = []
	for k in counts.keys():
		parts.append("%s x%d" % [Enemy.DATA[k]["name"], counts[k]])
	return "、".join(parts)
