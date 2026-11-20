extends Node

## 本周改动的逻辑冒烟测试：在正常场景模式下运行（autoload 可用），
## 验证首领波次规则与元素联动常量，然后按结果退出。
func _ready() -> void:
	var ok := true
	var p5: Array = Waves.plan(5)
	var p10: Array = Waves.plan(10)
	# 变异数据完整性：7 种塔必须各有 3 个方向，否则满级后会出现选不满的情况
	var mut_ok := true
	for k in TowerData.MUTATIONS:
		if TowerData.MUTATIONS[k].size() != 3:
			mut_ok = false
	var r := {
		"plan5_has_mini": p5.has(Enemy.Kind.MINI_BOSS),
		"plan10_has_big": p10.has(Enemy.Kind.BOSS),
		"plan10_has_mini": p10.has(Enemy.Kind.MINI_BOSS),
		"boss_name_5": Waves.boss_name(5),
		"boss_name_10": Waves.boss_name(10),
		"boss_name_4": Waves.boss_name(4),
		"chill_bonus": TowerData.CHILL_DMG_BONUS,
		"shock_time": TowerData.SHOCK_TIME,
		"blast_radius": TowerData.SHOCK_BLAST_RADIUS,
		"blast_mult": TowerData.SHOCK_BLAST_MULT,
		"total_waves": Waves.TOTAL,
		"plan10_size": p10.size(),
		"max_level": TowerData.MAX_LEVEL,
		"mutation_kinds": TowerData.MUTATIONS.size(),
		"mutation_ok": mut_ok,
	}
	for k in r:
		print("SMOKE ", k, " = ", str(r[k]))
	if not bool(r["plan5_has_mini"]) or not bool(r["plan10_has_big"]) or not bool(r["plan10_has_mini"]):
		ok = false
	if int(r["max_level"]) != 3 or not bool(r["mutation_ok"]):
		ok = false
	if str(r["boss_name_5"]) != "小首领" or str(r["boss_name_10"]) != "大首领" or str(r["boss_name_4"]) != "":
		ok = false
	print("SMOKE RESULT = ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
