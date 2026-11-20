class_name TowerData
## 防御塔数值配置（外置数据文件）。调整造价/伤害/射程/描述只改这里。
## 注意：Kind 枚举顺序需与 Tower.gd 中的 enum 保持完全一致。

enum Kind { ARROW, CANNON, FROST, SNIPER, TESLA, FLAME, BOUNCE }

const MAX_LEVEL := 3          # 最高等级：满级后可以「变异」（见 MUTATIONS）

## 每升 1 级的成长系数。
## 平衡目标：满级塔的「每金币 DPS」只比 Lv.1 高 10~20% —— 升级的收益来自
## 「省塔位 + 省操作」，而不是纯粹的性价比碾压，否则最优解永远是只堆一两座塔，
## 中期之后金币一溢出就没有压力了。
## 实测「塔明显偏强」之后整体压过一次：伤害成长 0.95 → 0.72（Lv.3 由 ×2.90 降到 ×2.44），
## 减速成长 0.20 → 0.12（冰塔 Lv.3 的减速不再比 Lv.1 高出一大截）。
const LV_DMG_GROWTH := 0.72     # 伤害：每级 +72% 基础值
const LV_RATE_GROWTH := 0.16    # 攻速：每级 +16% 基础值
const LV_RANGE_GROWTH := 0.16   # 射程：每级 +16% 基础值
const LV_SLOW_GROWTH := 0.12    # 减速：每级 +12% 基础值

## 升级造价系数：升到 Lv.N 要花 cost × UPGRADE_COST_COEF × (N-1)。
## 调大 = 升级更贵、更鼓励铺塔；调小 = 更鼓励集中升级。
const UPGRADE_COST_COEF := 0.85

## 变异造价（相对塔的建造成本）。这是后期主要的金币出口：
## 满级塔全部变异一遍 ≈ 再花掉 60% 的造塔预算，正好吃掉后期溢出的收入。
const MUTATION_COST_COEF := 0.6

## 塔的解锁波次：开局只有箭塔 / 炮塔，随着波次推进逐步开放。
## 改这里就能调整解锁节奏（数值 = 从第几波开始可以建造）。
const UNLOCK := {
	Kind.ARROW: 1,
	Kind.CANNON: 1,
	Kind.FROST: 3,
	Kind.FLAME: 4,
	Kind.TESLA: 5,
	Kind.SNIPER: 6,
	Kind.BOUNCE: 7,
}

## 溅射伤害衰减：爆炸半径内「非直接命中目标」只吃该比例的伤害。
## 1.0 = 全员满额（原来的一炮清场），调小 = 溅射更偏向「顺手刮一下」，
## 炮塔的定位变成「单体高伤 + 少量范围补刀」。想加强炮塔就把这个数往 1.0 调。
const SPLASH_DMG_COEF := 0.55

## 减速持续时间（秒）：冰塔子弹给敌人挂的减速时长。
## 配合塔数据里的 slow（减速比例）一起决定冰塔的控场强度。
const SLOW_TIME := 1.15

## 元素联动「冰火两重天」：喷火塔命中正被冰塔减速（结霜）的敌人时，
## 直接伤害额外提高的比例。想调强度只改这一个数（0.0 即关闭联动）。
const CHILL_DMG_BONUS := 0.6

## 元素联动「火电引爆」：闪电塔命中会给目标挂「感电」，
## 喷火塔命中感电目标时会引爆一次小范围爆炸（爆炸后消耗感电，需要重新打电）。
const SHOCK_TIME := 2.5              # 感电持续时间（秒）
const SHOCK_BLAST_RADIUS := 2.2      # 爆炸半径（世界单位，1 格 = 2.0）
const SHOCK_BLAST_MULT := 1.4        # 爆炸伤害 = 这次喷火命中的伤害 × 该倍率

## 变异「震地雷」：命中不再直接把敌人减速，而是在落点炸出一个泥潭，
## 站在泥潭里的敌人被减速——想控场就得把泥潭铺在敌人必经的路上。
const MUD_RADIUS := 1.7              # 泥潭半径（世界单位，1 格 = 2.0）
const MUD_TIME := 1.5                # 泥潭存在时间（秒），到点自行干涸
const MUD_SLOW := 0.16               # 泥潭内的减速比例

## 变异（Mutation）：塔升到满级（MAX_LEVEL）后，从 3 个方向里选一个，
## 永久决定这座塔的最终形态 —— 同一座塔只能变异一次，选完不能再改。
## mods 的字段含义（全部由 Tower._recalc() 统一结算）：
##   dmg_mul / rate_mul / range_mul / dot_mul → 乘在对应数值上（1.0 = 不变）
##   splash_add / slow_add / chain_add / crit_add → 加在对应数值上
##   slow_set → 把减速**定死**在这个值（不叠基础塔的减速；霜环这类光环塔用）
## 顶层 "aura": true 表示这座塔变异后完全没有攻击方式，只在射程内铺冰雾 + 持续减速
## （见 Tower.is_aura() / Tower._update_aura()）。
## tint 用来给变异后的塔身和脚下光环染色，一眼看出选的是哪条路线。
const MUTATIONS := {
	Kind.ARROW: [
		{
			"id": "arrow_gale", "name": "疾风弩",
			"desc": "攻速 +45%，单发伤害 -18%\n用密集箭雨淹没整条古道",
			"mods": {"rate_mul": 1.45, "dmg_mul": 0.82},
			"tint": Color(0.55, 1.0, 0.72),
		},
		{
			"id": "arrow_pierce", "name": "裂空箭",
			"desc": "伤害 +35%，射程 +10%\n一箭贯穿，专治重甲",
			"mods": {"dmg_mul": 1.35, "range_mul": 1.1},
			"tint": Color(0.85, 1.0, 0.50),
		},
		{
			"id": "arrow_split", "name": "穿云矢",
			"desc": "箭矢命中后向邻近敌人弹射 2 次\n适合贴着拐角覆盖成群的怪",
			"mods": {"chain_add": 2},
			"tint": Color(0.45, 0.95, 1.0),
		},
	],
	Kind.CANNON: [
		{
			"id": "cannon_heavy", "name": "攻城巨炮",
			"desc": "伤害 +40%，溅射范围 +1.2，攻速 -22%\n一炮清空半条路",
			"mods": {"dmg_mul": 1.4, "splash_add": 1.2, "rate_mul": 0.78},
			"tint": Color(1.0, 0.60, 0.30),
		},
		{
			"id": "cannon_quake", "name": "震地雷",
			"desc": "溅射范围 +1.8，命中处炸出泥潭\n踏入泥潭的敌人减速 16%（持续 1.5 秒）",
			"mods": {"splash_add": 1.8},
			"tint": Color(0.95, 0.75, 0.40),
		},
		{
			"id": "cannon_twin", "name": "双管齐射",
			"desc": "攻速 +35%，单发伤害 -18%\n用弹幕代替单发重击",
			"mods": {"rate_mul": 1.35, "dmg_mul": 0.82},
			"tint": Color(1.0, 0.80, 0.45),
		},
	],
	Kind.FROST: [
		{
			"id": "frost_field", "name": "霜环",
			"desc": "彻底放弃攻击：射程内铺满冰雾\n圈内敌人减速 50%，自身不造成任何伤害",
			"mods": {"dmg_mul": 0.0, "slow_set": 0.50},
			"aura": true,
			"tint": Color(0.55, 0.85, 1.0),
		},
		{
			"id": "frost_shard", "name": "碎冰",
			"desc": "伤害 +45%，减速 -10%\n冰塔也能当输出塔用",
			"mods": {"dmg_mul": 1.45, "slow_add": -0.10},
			"tint": Color(0.72, 0.95, 1.0),
		},
		{
			"id": "frost_tide", "name": "寒潮",
			"desc": "射程 +25%，攻速 +12%\n覆盖更远，铺场更稳",
			"mods": {"range_mul": 1.25, "rate_mul": 1.12},
			"tint": Color(0.40, 0.70, 1.0),
		},
	],
	Kind.SNIPER: [
		{
			"id": "sniper_death", "name": "死兆",
			"desc": "伤害 +35%，暴击率 +18%\n专点首领和重甲",
			"mods": {"dmg_mul": 1.35, "crit_add": 0.18},
			"tint": Color(1.0, 0.55, 0.55),
		},
		{
			"id": "sniper_rapid", "name": "速射狙",
			"desc": "攻速 +50%，单发伤害 -25%\n牺牲单发换取持续压制",
			"mods": {"rate_mul": 1.5, "dmg_mul": 0.75},
			"tint": Color(1.0, 0.85, 0.55),
		},
		{
			"id": "sniper_scope", "name": "鹰眼",
			"desc": "射程 +25%，伤害 +12%\n从地图另一头点杀",
			"mods": {"range_mul": 1.25, "dmg_mul": 1.12},
			"tint": Color(0.95, 0.95, 0.70),
		},
	],
	Kind.TESLA: [
		{
			"id": "tesla_storm", "name": "雷暴",
			"desc": "链式目标 +2，单发伤害 -8%\n闪电串起整条路上的敌人",
			"mods": {"chain_add": 2, "dmg_mul": 0.92},
			"tint": Color(0.70, 0.60, 1.0),
		},
		{
			"id": "tesla_overload", "name": "过载",
			"desc": "伤害 +35%，攻速 -12%\n单点爆发，配合感电引爆更狠",
			"mods": {"dmg_mul": 1.35, "rate_mul": 0.88},
			"tint": Color(0.85, 0.55, 1.0),
		},
		{
			"id": "tesla_field", "name": "静电场",
			"desc": "溅射范围 +1.4，射程 +8%\n感电覆盖面积更大",
			"mods": {"splash_add": 1.4, "range_mul": 1.08},
			"tint": Color(0.60, 0.70, 1.0),
		},
	],
	Kind.FLAME: [
		{
			"id": "flame_burn", "name": "焚尽",
			"desc": "灼烧伤害 +60%\n让敌人边走边被烧死",
			"mods": {"dot_mul": 1.6},
			"tint": Color(1.0, 0.45, 0.25),
		},
		{
			"id": "flame_blaze", "name": "烈焰",
			"desc": "伤害 +30%，攻速 +12%，射程 -8%\n贴脸喷射，短时间高爆发",
			"mods": {"dmg_mul": 1.3, "rate_mul": 1.12, "range_mul": 0.92},
			"tint": Color(1.0, 0.70, 0.30),
		},
		{
			"id": "flame_wall", "name": "火墙",
			"desc": "获得溅射（+1.6），射程 +10%\n喷出一条火墙而不是火柱",
			"mods": {"splash_add": 1.6, "range_mul": 1.1},
			"tint": Color(1.0, 0.90, 0.45),
		},
	],
	Kind.BOUNCE: [
		{
			"id": "bounce_ricochet", "name": "跳弹",
			"desc": "弹射目标 +2\n一颗子弹扫过整排敌人",
			"mods": {"chain_add": 2},
			"tint": Color(0.85, 1.0, 0.55),
		},
		{
			"id": "bounce_heavy", "name": "钝击",
			"desc": "伤害 +35%，弹射目标 -1\n少弹一次，但每次更重",
			"mods": {"dmg_mul": 1.35, "chain_add": -1},
			"tint": Color(1.0, 0.90, 0.55),
		},
		{
			"id": "bounce_scatter", "name": "散射",
			"desc": "攻速 +30%，伤害 -8%，弹射 -1\n用频率弥补单发",
			"mods": {"rate_mul": 1.3, "dmg_mul": 0.92, "chain_add": -1},
			"tint": Color(1.0, 0.85, 0.60),
		},
	],
}

const KIND_TINT := {
	Kind.ARROW: Color(1.0, 1.0, 1.0),
	Kind.CANNON: Color(1.0, 0.84, 0.60),
	Kind.FROST: Color(0.58, 0.76, 1.0),
	Kind.SNIPER: Color(0.95, 0.90, 0.45),
	Kind.TESLA: Color(0.62, 0.52, 1.0),
	Kind.FLAME: Color(1.0, 0.55, 0.30),
	Kind.BOUNCE: Color(1.0, 0.95, 0.45),
}

## 射程基线说明：布防台离路中心线 SLOT_GAP = 2 格（4.0 世界单位），路面半宽 1.6。
## 塔对「路中心线」的有效覆盖 = sqrt(range² - 4²)，路面加宽后按这个口径统一上调过一轮：
## 现在各塔在路边能覆盖约 4~6 单位（2~3 格）的路段，射程圈看上去才和宽路匹配。
## 再调速射程只改下面的 range；注意喷火塔/冰塔这类短射程塔别低于 5.2，否则又会打不到路。
const DATA := {
	Kind.ARROW: {
		"name": "箭塔", "cost": 50, "dmg": 13.0, "rate": 1.45, "range": 7.0,
		"splash": 0.0, "slow": 0.0, "chain": 0, "color": Color(0.36, 0.86, 0.52),
		"bullet": 26.0, "desc": "单体高频，性价比高"
	},
	Kind.CANNON: {
		"name": "炮塔", "cost": 85, "dmg": 29.0, "rate": 0.62, "range": 6.2,
		"splash": 1.6, "slow": 0.0, "chain": 0, "color": Color(0.96, 0.56, 0.26),
		"bullet": 18.0, "desc": "单体重击，附带小范围溅射"
	},
	Kind.FROST: {
		"name": "冰塔", "cost": 70, "dmg": 9.0, "rate": 1.05, "range": 5.8,
		"splash": 1.9, "slow": 0.22, "chain": 0, "color": Color(0.45, 0.72, 1.0),
		"bullet": 20.0, "beam": true,
		"desc": "持续冰冻射线：锁定一个敌人一直照射，按原攻速结算伤害并挂减速；被它冻住的敌人更怕喷火塔"
	},
	Kind.SNIPER: {
		"name": "狙击塔", "cost": 120, "dmg": 112.0, "rate": 0.30, "range": 10.8,
		"splash": 0.0, "slow": 0.0, "chain": 0, "color": Color(0.95, 0.90, 0.45),
		"bullet": 34.0, "desc": "超远单体，一击重伤"
	},
	Kind.TESLA: {
		"name": "闪电塔", "cost": 100, "dmg": 19.0, "rate": 0.85, "range": 6.6,
		"splash": 3.5, "slow": 0.0, "chain": 4, "color": Color(0.62, 0.52, 1.0),
		"bullet": 20.0, "desc": "链式闪电，弹射多个目标"
	},
	Kind.FLAME: {
		"name": "喷火塔", "cost": 90, "dmg": 5.0, "rate": 3.0, "range": 5.6,
		"splash": 0.0, "slow": 0.0, "chain": 0, "dot": 13.0, "color": Color(1.0, 0.55, 0.30),
		"bullet": 20.0, "desc": "点燃目标持续灼烧；命中被冰塔减速的敌人时伤害大幅提高"
	},
	Kind.BOUNCE: {
		"name": "弹射塔", "cost": 75, "dmg": 16.0, "rate": 1.0, "range": 6.2,
		"splash": 0.0, "slow": 0.0, "chain": 2, "color": Color(1.0, 0.95, 0.45),
		"bullet": 30.0, "desc": "子弹在敌人间弹射"
	},
}
