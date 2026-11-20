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


## 该波是不是压轴大首领波（最后一波，以及无尽模式每 10 波）
static func is_big_boss_wave(wave: int) -> bool:
	return wave == TOTAL or (wave > 0 and wave % 10 == 0)


## 该波是不是小首领波（每 5 波，大首领波除外）
static func is_mini_boss_wave(wave: int) -> bool:
	return wave > 0 and wave % 5 == 0 and not is_big_boss_wave(wave)


## 下一波的首领名字；没有首领返回空串。给「开始第 N 波」按钮做战前预告用。
static func boss_name(wave: int) -> String:
	if is_big_boss_wave(wave):
		return str(Enemy.DATA[Enemy.Kind.BOSS]["name"])
	if is_mini_boss_wave(wave):
		return str(Enemy.DATA[Enemy.Kind.MINI_BOSS]["name"])
	return ""


## 返回本波要生成的敌人种类列表（已打乱，首领排在最后）
static func plan(wave: int) -> Array:
	var list: Array = []
	var n := wave

	for i in range(6 + n * 2):
		list.append(Enemy.Kind.GRUNT)
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
		# 最后一波（以及无尽模式每 10 波）：重甲开路 + 1 个小首领护卫 + 压轴大首领
		for i in range(clampi(n - 3, 2, 8)):
			list.append(Enemy.Kind.TANK)
		list.append(Enemy.Kind.MINI_BOSS)
		list.append(Enemy.Kind.BOSS)
	elif is_mini_boss_wave(n):
		# 每 5 波：重甲开路 + 小首领
		for i in range(clampi(n - 3, 2, 8)):
			list.append(Enemy.Kind.TANK)
		list.append(Enemy.Kind.MINI_BOSS)

	return list


## 波次预览文字
static func preview(wave: int) -> String:
	var p := plan(wave)
	var counts := {}
	for k in p:
		counts[k] = int(counts.get(k, 0)) + 1
	var parts: Array[String] = []
	for k in counts.keys():
		parts.append("%s x%d" % [Enemy.DATA[k]["name"], counts[k]])
	return "、".join(parts)
