class_name CardData
## 强化卡池配置（外置数据文件）。增删卡牌、改描述只改这里。

const POOL := [
	{"id": "dmg",   "name": "锐化弹头", "desc": "所有塔伤害 +12%",        "unique": false},
	{"id": "rate",  "name": "润滑齿轮", "desc": "所有塔攻速 +13%",        "unique": false},
	{"id": "rng",   "name": "加长炮管", "desc": "所有塔射程 +15%",        "unique": false},
	{"id": "gold",  "name": "战争税",   "desc": "每波结束额外 +30 金币",  "unique": false},
	{"id": "life",  "name": "加固城墙", "desc": "生命 +3 并立刻回复 3",   "unique": false},
	{"id": "slow",  "name": "极寒核心", "desc": "减速效果 +10%",          "unique": false},
	{"id": "crit",  "name": "致命瞄准", "desc": "暴击率 +7%（暴击 2 倍）", "unique": false},
	{"id": "splash", "name": "高爆装药", "desc": "溅射范围 +25%",         "unique": false},
	{"id": "arrow_mastery", "name": "箭术精通", "desc": "箭塔伤害 +30%", "unique": false},
	{"id": "cannon_mastery", "name": "重炮强化", "desc": "炮塔伤害 +30%", "unique": false},
	{"id": "tesla_mastery", "name": "雷电增幅", "desc": "闪电塔伤害 +30%", "unique": false},
	{"id": "fury", "name": "狂暴之血", "desc": "所有塔伤害 +24%，但攻速 -10%", "unique": false},
	{"id": "greed", "name": "贪婪契约", "desc": "每波额外 +60 金币，但失去 2 生命", "unique": false},
	{"id": "lvl",   "name": "军械升级", "desc": "随机一座塔等级 +1",      "unique": true},
	{"id": "int",   "name": "复利存款", "desc": "每波结束获得当前金币 5%（单波上限 150）", "unique": true},
	# ---- 元素反应强化
	{"id": "melt", "name": "熔核共鸣", "desc": "融化反应伤害 +30%（喷火塔命中结霜目标时）", "unique": false},
	{"id": "overload", "name": "过载增幅", "desc": "超载爆炸伤害 +35%（喷火塔引爆感电目标时）", "unique": false},
	{"id": "reso", "name": "元素共鸣", "desc": "融化与超载反应伤害各 +15%", "unique": false},
	# ---- 子弹附加状态（对所有塔生效）
	{"id": "poison", "name": "淬毒弹头", "desc": "所有塔的子弹附带中毒：每秒 7 点，持续 3 秒（无视护甲）", "unique": false},
	{"id": "bleed", "name": "放血锋刃", "desc": "所有塔的子弹附带流血：每秒 8 点，持续 2.5 秒", "unique": false},
	# ---- 命中类：让「后续的攻击」更疼
	{"id": "break", "name": "破甲弹头", "desc": "命中的敌人护甲 -26%，持续 3 秒（克制重甲 / 护盾怪）", "unique": false},
	{"id": "vuln", "name": "易伤标记", "desc": "命中的敌人受到伤害 +10%，持续 3 秒", "unique": false},
	{"id": "exec", "name": "处决协议", "desc": "对生命低于 35% 的敌人伤害 +35%", "unique": false},
	# ---- 触发类 / 运营类
	{"id": "blast", "name": "连锁爆破", "desc": "敌人死亡时爆炸：对半径 2.4 内的敌人造成其自身最大生命 12% 的伤害", "unique": false},
	{"id": "night", "name": "守夜人", "desc": "每波结束回复 1 点生命（不超过 20）", "unique": false},
	{"id": "scrap", "name": "废料回收", "desc": "出售返还比例 +15%（基础 50%，上限 90%）", "unique": false},
]
