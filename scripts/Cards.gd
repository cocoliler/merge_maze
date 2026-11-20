class_name Cards
## Roguelike 强化卡池：每波结束三选一，效果永久叠加到本次 run。

const POOL := CardData.POOL


## 抽取 count 张互不重复的卡；unique 卡已被拿过则不再出现
static func offer(count: int, taken: Dictionary) -> Array:
	var candidates: Array = []
	for c in POOL:
		if bool(c["unique"]) and taken.has(c["id"]):
			continue
		candidates.append(c)

	var out: Array = []
	while out.size() < count and candidates.size() > 0:
		var i := randi() % candidates.size()
		out.append(candidates[i])
		candidates.remove_at(i)
	return out


## 数值平衡备注：强化卡是**永久叠加**的，一张 +40% 的卡拿两次就等于 +80%，
## 而敌人血量只是线性成长 —— 所以伤害类卡的单张幅度都压得比较小（10~30%），
## 想要强度就靠「拿得多」而不是「单张很强」。改这里记得同步 CardData 的 desc 文案。
static func apply(id: String, main) -> void:
	match id:
		"dmg":
			GameState.buffs["damage"] += 0.12
		"rate":
			GameState.buffs["rate"] += 0.13
		"rng":
			GameState.buffs["range"] += 0.15
		"gold":
			GameState.buffs["gold_wave"] += 30
		"life":
			GameState.lives += 3
			GameState.lives_changed.emit(GameState.lives)
		"slow":
			GameState.buffs["slow"] += 0.10
		"crit":
			GameState.buffs["crit"] += 0.07
		"splash":
			GameState.buffs["splash"] += 0.25
		"lvl":
			if main != null and main.has_method("upgrade_random_tower"):
				main.call("upgrade_random_tower")
		"arrow_mastery":
			_add_tower_dmg(Tower.Kind.ARROW, 0.30)
		"cannon_mastery":
			_add_tower_dmg(Tower.Kind.CANNON, 0.30)
		"tesla_mastery":
			_add_tower_dmg(Tower.Kind.TESLA, 0.30)
		"fury":
			GameState.buffs["damage"] += 0.24
			GameState.buffs["rate"] -= 0.10
		"greed":
			GameState.buffs["gold_wave"] += 60
			GameState.lives = max(GameState.lives - 2, 1)
			GameState.lives_changed.emit(GameState.lives)
		"int":
			GameState.buffs["interest"] += 0.05
		# ---- 元素反应强化：融化（喷火打结霜）/ 超载（喷火引爆感电）
		"melt":
			GameState.buffs["melt_dmg"] += 0.30
		"overload":
			GameState.buffs["overload_dmg"] += 0.35
		"reso":
			GameState.buffs["melt_dmg"] += 0.15
			GameState.buffs["overload_dmg"] += 0.15
		# ---- 子弹附加状态：拿卡后所有塔（含链式弹射的每一跳）都生效
		"poison":
			GameState.buffs["poison_dps"] += 7.0
		"bleed":
			GameState.buffs["bleed_dps"] += 8.0
		# ---- 命中类：破甲 / 易伤 / 处决（都是「让后面打得更疼」的乘算来源）
		"break":
			GameState.buffs["armor_break"] += 0.26
		"vuln":
			GameState.buffs["vuln"] += 0.10
		"exec":
			GameState.buffs["execute"] += 0.35
		# ---- 触发类 / 运营类
		"blast":
			GameState.buffs["death_blast"] += 0.12
		"night":
			GameState.buffs["life_regen"] += 1
		"scrap":
			GameState.buffs["refund"] += 0.15
		_:
			push_warning("未知卡牌: %s" % id)


## 塔专属卡：给某类型塔叠加伤害倍率
static func _add_tower_dmg(kind: int, amount: float) -> void:
	var td: Dictionary = GameState.buffs.get("tower_dmg", {})
	td[kind] = float(td.get(kind, 0.0)) + amount
	GameState.buffs["tower_dmg"] = td
