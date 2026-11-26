class_name EnemyData
## 敌人数值配置（外置数据文件）。调整血量/速度/奖励/颜色/描述只改这里。
## 注意：Kind 枚举顺序需与 Enemy.gd 中的 enum 保持完全一致。

enum Kind { GRUNT, RUNNER, TANK, BOSS, FLYER, SHIELD, HEALER, SPLITTER, CLOAK, MINI_BOSS, ICEBREAKER, FROSTWEAVER, FROSTLING, SNOWKING, PINELORD }

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
## 霜松「扎根」召唤的霜崽数量（冰原主题：叫来的不是小兵，是跟着它混的霜崽）
const PINE_SUMMON := 2

## 大首领「终焉之影」· 压制脉冲：每 BOSS_PULSE_INTERVAL 秒，让半径内的塔停火
## BOSS_PULSE_TIME 秒（塔本身不会被摧毁，只是暂时熄火）。
const BOSS_PULSE_INTERVAL := 11.0
const BOSS_PULSE_RADIUS := 7.5
const BOSS_PULSE_TIME := 1.5

## 大首领 · 狂暴（半血时一次性）：移速 +BOSS_ENRAGE_HASTE、护甲 +BOSS_ENRAGE_ARMOR。
const BOSS_ENRAGE_HASTE := 0.35
const BOSS_ENRAGE_ARMOR := 0.10

## 雪人王「雪球」：每隔 SNOWBALL_INTERVAL 秒挑一座射程内的塔丢一颗雪球，
## 命中后那座塔攻速 ×(1 − SNOWBALL_SLOW)、持续 SNOWBALL_TIME 秒（塔不会被摧毁）。
## 半血后间隔 ×SNOWBALL_ENRAGE_COEF —— 雪人王不会狂暴冲锋，它改用「更密的雪球」施压。
const SNOWBALL_INTERVAL := 6.0
const SNOWBALL_RANGE := 8.5
const SNOWBALL_SLOW := 0.35
const SNOWBALL_TIME := 5.0
const SNOWBALL_ENRAGE_COEF := 0.6
const SNOWBALL_SPEED := 9.0
const SNOWBALL_ARC := 1.3
const SNOWBALL_SUMMON := 2

## 雪人王「滚雪球」：把附近的小杂兵卷进球里，滚到一定体量后向前滚一段再炸开。
## 被卷的怪全程**无敌 / 不可锁定 / 不移动**，滚完从球里散出来 —— 等于被雪人王白送了一段路。
## 只卷普通小怪：首领、飞行怪、碎冰者都不卷（碎冰者游泳状态被卷会打断水陆切换）。
const ROLL_FIRST_DELAY := 7.0     # 首次技能延迟（登场先走一小段）
const ROLL_INTERVAL := 16.0        # 冷却（半血后 ×ROLL_ENRAGE_COEF）
const ROLL_RADIUS := 8.0           # 吸附半径（约 4 格，比之前大一圈才好一次卷满）
const ROLL_MAX_GUESTS := 3         # 最多卷几只
const ROLL_GATHER_TIME := 1.2      # 聚球最长时长
const ROLL_ABSORB_TICK := 0.25     # 每隔多久吸一只
const ROLL_POINTS := 5             # 向前滚几个路点后炸开
const ROLL_MAX_PATH_RATIO := 0.5   # 路程过半后技能封存：后半程再送怪等于直接送到基地门口
const ROLL_SPEED := 7.0            # 滚动速度（世界单位 / 秒）
const ROLL_BASE_RADIUS := 0.50     # 空球半径
const ROLL_RADIUS_STEP := 0.18     # 每卷一只球变大多少
const ROLL_ENRAGE_COEF := 0.6      # 半血「暴雪」后冷却缩短

## ---------------------------------------------------------------- 霜语者的冰甲
## 每 ICE_ARMOR_INTERVAL 秒，给 ICE_ARMOR_RADIUS 内的同伴套一层吸收伤害的护盾。
## 护盾量按**挨打那只怪自己的最大生命**算 —— 不这么写的话，后期血量成长起来，
## 冰甲就形同虚设（早期按固定值会过强，后期会过弱）。
## 冰甲唯一的破绽是火：ICE_FIRE_MULT 倍于其它属性的「削甲速度」。
const ICE_ARMOR_INTERVAL := 6.5
const ICE_ARMOR_RADIUS := 6.5
const ICE_ARMOR_RATIO := 0.30
const ICE_ARMOR_TIME := 9.0
const ICE_FIRE_MULT := 2.6

## ---------------------------------------------------------------- 减速规则
## 直接减速（塔造成的减速，走 Enemy.apply_slow 那一层）单层上限：取最强之后最多只减 50%。
## 地形减速（震地雷泥潭这类，走 slow_extra 乘区）不受这个限制，所以总减速可以更高：
## 50% × (1 − 16%) → 速度 0.42，总减速 58%。想调「塔能把敌人冻多狠」只改这一个数。
const MAX_DIRECT_SLOW := 0.5

## 最终速度倍率的全局下限：不管叠了多少层减速，敌人至少还有 25% 速度。
## 兜的是极端叠加（直接减速 50% × 地形减速 90% = 0.05 倍速），避免出现「贴地爬 / 卡住」。
## 注意：加速（战吼 / 狂暴）是在这之前乘的，不会被这个下限吃掉。
const MIN_SPEED_MUL := 0.25

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
	# 冰原专属：不沿雪径走，而是砸开冰面横穿冻湖抄近路 —— 冰面上不能建塔，
	# 所以湖对岸那半圈塔是打不到它的，必须靠湖边的塔补位。
	Kind.ICEBREAKER: {"name": "碎冰者", "hp": 320.0, "speed": 1.25, "reward": 26, "color": Color(0.21, 0.37, 0.56), "size": 2.00, "flying": false, "armor": 0.15, "heal": 0.0, "split": 0, "cloak": false, "icebreak": true, "desc": "砸开冰面横穿冻湖的巨魔：冰面上不能建塔，湖对岸的火力拦不住它，得靠湖边的塔在它上岸时集火"},
	# 冰原专属辅助：自己不打人，只负责给同伴套冰甲。先杀它，或者用喷火塔拆甲。
	Kind.FROSTWEAVER: {"name": "霜语者", "hp": 150.0, "speed": 1.50, "reward": 22, "color": Color(0.46, 0.86, 0.80), "size": 1.55, "flying": false, "armor": 0.0, "heal": 0.0, "split": 0, "cloak": false, "iceshield": true, "desc": "给周围同伴套冰甲的萨满：冰甲按目标最大生命吸收伤害，火属性打上去破得快 2.6 倍 —— 喷火塔拆甲、其余塔补刀"},
	# 冰原小怪：外形是程序化 3D 造型（scripts/FrostlingModel.gd），原画只作设计参考。
	# underwater = 能走水下段，但**自己砸不开冰面** —— 要等碎冰者先把湖凿穿，
	# 它才跟着冰洞游过去；冰面没通时老老实实沿雪径绕湖。
	Kind.FROSTLING: {"name": "霜崽", "hp": 52.0, "speed": 2.90, "reward": 11, "color": Color(1.0, 1.0, 1.0), "size": 1.05, "flying": false, "armor": 0.0, "heal": 0.0, "split": 0, "cloak": false, "underwater": true, "desc": "冰原小怪：体型小、跑得快；碎冰者凿穿冰面后，它会跟着从冰洞底下游过去抄近路"},
	# 第二张图的压轴 Boss（第 10 波）。外观是**程序化 3D 造型**（scripts/SnowkingModel.gd），
	# 不是原画精灵：造型刻意改造过（冰晶王冠 / 六棱冰甲 / 胸口冰核 / 单手蓄力雪球），别再把原画贴上去。
	# 和「大首领」的区别：它不砸塔、不脉冲熄火，而是**往炮塔丢雪球压攻速** ——
	# 塔不会被拆，但被砸中的那几秒输出会明显变慢，逼玩家把塔散开摆、别全挤在湖岸。
	Kind.SNOWKING: {"name": "雪人王", "hp": 1700.0, "speed": 0.95, "reward": 240, "color": Color(0.90, 0.94, 1.0), "size": 2.90, "flying": false, "armor": 0.15, "heal": 0.0, "split": 0, "cloak": false, "slow_cap": 0.4, "snowball": true, "entrance_wait": true, "desc": "霜渊的压轴首领：血量高、护甲减免 15%。它一开波就堵在入口，把这波刚出门的杂兵卷成雪球往前送，等这一波出到一半才动身往里走（不会一直蹲到最后）。技能①雪球：每 6 秒朝射程内的一座塔扔雪球，命中后那座塔攻速 −35%、持续 5 秒（塔不会被摧毁）；技能②暴雪：半血后雪球间隔缩短到 60%，并召唤 2 只霜崽；技能③滚雪球：每 16 秒把半径约 4 格内至多 3 只杂兵卷成雪球，向前滚 5 格后炸开 —— 被卷的怪全程无敌，等于被它白送一段路（它自己走过一半路程后就不再滚了）"},
	# 第二张图的第 5 波小首领（无尽每 5 波）。外观是程序化 3D 造型（scripts/PineBossModel.gd）：
	# 一棵会走路的霜松 —— 三层树冠 + 树枝手臂 + 树根脚 + 树顶冰晶。
	# 技能沿用「小首领」的战吼，但半血「扎根」召唤的是霜崽（冰原杂兵）。
	Kind.PINELORD: {"name": "霜松", "hp": 680.0, "speed": 1.30, "reward": 85, "color": Color(0.20, 0.52, 0.34), "size": 2.35, "flying": false, "armor": 0.10, "heal": 0.0, "split": 0, "cloak": false, "slow_cap": 0.55, "desc": "霜渊的小首领：一棵会走路的霜松，护甲减免 10%。技能①战吼：每 8 秒给周围小怪 +30% 移速 3 秒；技能②扎根：半血时召唤 2 只霜崽"},
}
