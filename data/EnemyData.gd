class_name EnemyData
## 敌人数值配置（外置数据文件）。调整血量/速度/奖励/颜色/描述只改这里。
## 注意：Kind 枚举顺序需与 Enemy.gd 中的 enum 保持完全一致。

enum Kind { GRUNT, RUNNER, TANK, BOSS, FLYER, SHIELD, HEALER, SPLITTER, CLOAK, MINI_BOSS }

## ---------------------------------------------------------------- 首领专属技能
## 技能逻辑在 Enemy._tick_boss_skill() 里，这里只管数值 —— 想调强度只改下面这些常量。

## 小首领「潮主」· 战吼：每 WARCRY_INTERVAL 秒，给半径内的小怪 +WARCRY_HASTE 移速，
## 持续 WARCRY_TIME 秒。配合重甲护卫一起冲锋，逼玩家先处理首领。
const WARCRY_INTERVAL := 8.0
const WARCRY_RADIUS := 7.0
const WARCRY_HASTE := 0.30
const WARCRY_TIME := 3.0

## 半血触发（一次性）：血量首次跌到 SUMMON_HP_RATIO 时召唤援军。
## 召唤物是小兵，血量按当前波血量成长 × SUMMON_HP_COEF 结算，不会白送奖励上限。
const SUMMON_HP_RATIO := 0.5
const SUMMON_HP_COEF := 0.6
const MINI_BOSS_SUMMON := 2
const BOSS_SUMMON := 3

## 大首领「终焉之影」· 压制脉冲：每 BOSS_PULSE_INTERVAL 秒，让半径内的塔停火
## BOSS_PULSE_TIME 秒（塔本身不会被摧毁，只是暂时熄火）。
const BOSS_PULSE_INTERVAL := 11.0
const BOSS_PULSE_RADIUS := 7.5
const BOSS_PULSE_TIME := 1.5

## 大首领 · 狂暴（半血时一次性）：移速 +BOSS_ENRAGE_HASTE、护甲 +BOSS_ENRAGE_ARMOR。
const BOSS_ENRAGE_HASTE := 0.35
const BOSS_ENRAGE_ARMOR := 0.10

## size 是体型系数（程序化几何与外部模型的缩放都按它算身高）。
## 路面加宽到 3.2 世界单位后，原来 0.8~1.0 的体型在宽路上显小，
## 整体放大到约 1.45 倍；首领再额外拉高，撑满路面才有压迫感（大首领身宽≈路宽）。
## slow_cap：首领的减速抗性，一次减速最多只能削到该比例（0.5 = 最高半速的一半），
## 避免冰塔把首领冻成不动靶子。
const DATA := {
	Kind.GRUNT: {"name": "小兵", "hp": 62.0, "speed": 2.30, "reward": 8, "color": Color(0.88, 0.38, 0.42), "size": 1.45, "flying": false, "armor": 0.0, "heal": 0.0, "split": 0, "cloak": false, "desc": "最基础的敌人，血量较低"},
	Kind.RUNNER: {"name": "疾行者", "hp": 44.0, "speed": 3.70, "reward": 10, "color": Color(0.95, 0.80, 0.35), "size": 1.20, "flying": false, "armor": 0.0, "heal": 0.0, "split": 0, "cloak": false, "desc": "移动迅速，但很脆弱"},
	Kind.TANK: {"name": "重甲", "hp": 280.0, "speed": 1.40, "reward": 24, "color": Color(0.55, 0.45, 0.85), "size": 1.95, "flying": false, "armor": 0.0, "heal": 0.0, "split": 0, "cloak": false, "desc": "高血量，移动缓慢"},
	Kind.BOSS: {"name": "大首领", "hp": 1900.0, "speed": 1.00, "reward": 260, "color": Color(0.95, 0.20, 0.55), "size": 3.05, "flying": false, "armor": 0.15, "heal": 0.0, "split": 0, "cloak": false, "slow_cap": 0.4, "desc": "终焉大首领：血量极高、护甲减免 15%。技能①压制脉冲：每 11 秒让周围 7.5 内所有塔停火 1.5 秒；技能②狂暴：半血后移速 +35%、护甲 +10% 并召唤 3 只小兵"},
	Kind.MINI_BOSS: {"name": "小首领", "hp": 620.0, "speed": 1.35, "reward": 80, "color": Color(0.96, 0.50, 0.20), "size": 2.35, "flying": false, "armor": 0.0, "heal": 0.0, "split": 0, "cloak": false, "slow_cap": 0.55, "desc": "小首领：血量厚实，常带重甲冲锋。技能①战吼：每 8 秒给周围小怪 +30% 移速 3 秒；技能②集结：半血时召唤 2 只小兵"},
	Kind.FLYER: {"name": "飞行怪", "hp": 36.0, "speed": 3.2, "reward": 12, "color": Color(0.65, 0.55, 0.95), "size": 1.15, "flying": true, "armor": 0.0, "heal": 0.0, "split": 0, "cloak": false, "desc": "飞行单位，无视地形直线飞向基地"},
	Kind.SHIELD: {"name": "护盾怪", "hp": 120.0, "speed": 1.8, "reward": 20, "color": Color(0.35, 0.75, 0.90), "size": 1.60, "flying": false, "armor": 0.3, "heal": 0.0, "split": 0, "cloak": false, "desc": "护盾减伤 30%，磨起来很拖时间；奖励比同级怪高"},
	Kind.HEALER: {"name": "治疗怪", "hp": 90.0, "speed": 1.6, "reward": 15, "color": Color(0.40, 0.90, 0.55), "size": 1.45, "flying": false, "armor": 0.0, "heal": 12.0, "split": 0, "cloak": false, "desc": "持续治疗周围友军"},
	Kind.SPLITTER: {"name": "分裂怪", "hp": 100.0, "speed": 1.9, "reward": 14, "color": Color(0.95, 0.60, 0.25), "size": 1.45, "flying": false, "armor": 0.0, "heal": 0.0, "split": 2, "cloak": false, "desc": "死亡后分裂成 2 个小兵"},
	Kind.CLOAK: {"name": "隐身怪", "hp": 40.0, "speed": 2.6, "reward": 13, "color": Color(0.85, 0.85, 0.90), "size": 1.30, "flying": false, "armor": 0.0, "heal": 0.0, "split": 0, "cloak": true, "desc": "隐身，塔无法直接锁定（会被溅射/链式伤害打到）"},
}
