extends Node
## 全局游戏状态（Autoload，单例名为 GameState）
## 负责：金币、生命、波次，以及 Roguelike 的永久增益 buff。

signal gold_changed(value: int)
signal lives_changed(value: int)
signal wave_changed(value: int)

const START_GOLD := 300
const START_LIVES := 20
const SAVE_PATH := "user://save.cfg"

var gold: int = START_GOLD
var lives: int = START_LIVES
var wave: int = 0
var running: bool = true
var wave_active: bool = false   # 当前是否处于一波战斗中间（用于判断塔的解锁时机）

var total_kills: int = 0
var total_leaks: int = 0
var best_wave: int = 0

## 冰湖是否已经被凿穿（碎冰者第一次下水时置 true）。
## 霜崽自己砸不开冰面：只有这张图上的冰面通过一次以后，它才会选水下路线。
## 换图 / 重开都会走 reset()，所以这个标记天然按「一局一张图」重置。
var ice_opened: bool = false

## 上帝模式：水晶无敌 —— 敌人漏进基地照常消失、照常记漏怪数，但不扣生命。
## 开发用开关，由上帝模式面板控制；换图 / 重开走 reset() 自动关掉。
var crystal_invincible: bool = false

## 跨地图继承：进入下一张地图前由 Main 写入，reset() 消费一次后清空（-1 = 不继承）。
## 只带金币 / 生命 —— 塔和卡牌 buff 不继承，新地图从零布防。
var carry_gold: int = -1
var carry_lives: int = -1

## Roguelike 全局增益，卡牌会修改这里的值
var buffs := {
	"damage": 1.0,   # 伤害倍率
	"range": 1.0,    # 射程倍率
	"rate": 1.0,     # 攻速倍率
	"slow": 1.0,     # 减速效果倍率
	"splash": 1.0,   # 溅射范围倍率
	"gold_wave": 0,  # 每波结束额外金币
	"crit": 0.0,     # 暴击概率
	"interest": 0.0, # 每波结束金币利息比例
	"tower_dmg": {}, # 按塔类型(Tower.Kind)的额外伤害倍率
	"melt_dmg": 0.0,     # 融化反应（喷火塔打结霜目标）额外加成
	"overload_dmg": 0.0, # 超载反应（喷火塔引爆感电）额外加成
	"poison_dps": 0.0,   # 所有塔子弹附带的中毒每秒伤害（0 = 无）
	"poison_time": 3.0,
	"bleed_dps": 0.0,    # 所有塔子弹附带的流血每秒伤害（0 = 无）
	"bleed_time": 2.5,
	"armor_break": 0.0,  # 命中后的破甲量（敌人护甲 -X，叠加时取最大值）
	"vuln": 0.0,         # 命中后的易伤（敌人受到伤害 +X%）
	"execute": 0.0,      # 处决：目标残血时的额外伤害倍率
	"death_blast": 0.0,  # 敌人死亡时爆炸，伤害 = 自身最大生命 × 该比例
	"life_regen": 0,     # 每波结束回复的生命
	"refund": 0.5,       # 出售返还比例
}


func reset() -> void:
	gold = carry_gold if carry_gold >= 0 else START_GOLD
	lives = carry_lives if carry_lives >= 0 else START_LIVES
	carry_gold = -1
	carry_lives = -1
	wave = 0
	running = true
	wave_active = false
	total_kills = 0
	total_leaks = 0
	ice_opened = false
	crystal_invincible = false
	buffs = {
		"damage": 1.0,
		"range": 1.0,
		"rate": 1.0,
		"slow": 1.0,
		"splash": 1.0,
		"gold_wave": 0,
		"crit": 0.0,
		"interest": 0.0,
		"tower_dmg": {},
		"melt_dmg": 0.0,
		"overload_dmg": 0.0,
		"poison_dps": 0.0,
		"poison_time": 3.0,
		"bleed_dps": 0.0,
		"bleed_time": 2.5,
		"armor_break": 0.0,
		"vuln": 0.0,
		"execute": 0.0,
		"death_blast": 0.0,
		"life_regen": 0,
		"refund": 0.5,
	}
	gold_changed.emit(gold)
	lives_changed.emit(lives)
	wave_changed.emit(wave)


func add_gold(v: int) -> void:
	gold += v
	gold_changed.emit(gold)


func spend(v: int) -> bool:
	if gold < v:
		return false
	gold -= v
	gold_changed.emit(gold)
	return true


func lose_life(v: int = 1) -> void:
	# 上帝模式：水晶无敌。漏怪照样消失、照样计入漏怪数（on_leak 在 Enemy._leak 里先调），
	# 只是不扣生命 —— 于是 game_over 永远触发不了，可以放心压测后期波次。
	if crystal_invincible:
		return
	lives = max(lives - v, 0)
	lives_changed.emit(lives)
	if lives <= 0:
		running = false


func set_wave(v: int) -> void:
	wave = v
	wave_changed.emit(wave)


func on_kill() -> void:
	total_kills += 1


func on_leak() -> void:
	total_leaks += 1


func load_save() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		best_wave = int(cf.get_value("game", "best_wave", 0))


func save_best() -> void:
	var cf := ConfigFile.new()
	cf.set_value("game", "best_wave", best_wave)
	cf.save(SAVE_PATH)
