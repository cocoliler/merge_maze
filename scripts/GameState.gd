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
	gold = START_GOLD
	lives = START_LIVES
	wave = 0
	running = true
	wave_active = false
	total_kills = 0
	total_leaks = 0
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
