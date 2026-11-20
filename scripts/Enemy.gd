extends Node3D
class_name Enemy
## 敌人：沿 GameGrid 生成的固定路线行进，支持减速、血条、漏怪扣血。
## 固定路线下建塔不会改变行进路径，所以战斗中不再重算；repath() 仅作兜底保留。

enum Kind { GRUNT, RUNNER, TANK, BOSS, FLYER, SHIELD, HEALER, SPLITTER, CLOAK, MINI_BOSS }

const DATA := EnemyData.DATA

const BAR_WIDTH := 1.15

const HEAL_RADIUS := 2.8
const HEAL_INTERVAL := 0.6

## 「连锁爆破」卡的爆炸半径（伤害 = 死亡敌人最大生命 × buffs["death_blast"]）
const DEATH_BLAST_RADIUS := 2.4

const CLOAK_HIDDEN := 2.6
const CLOAK_VISIBLE := 1.0

## 血条着色器。
## 为什么不直接用 scale.x 表示血量：
##   StandardMaterial3D 的 billboard 是在顶点着色器里用相机基向量替换掉模型旋转的
##   （MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0..2], MODEL_MATRIX[3])），
##   只保留位移、丢掉缩放，所以 scale.x 对这个材质是无效的——血条会一直满格。
## 这里改成用 uniform ratio 在片元阶段裁剪填充宽度。
## 注意：Godot 4 的自定义着色器没有 billboard 这个 render_mode（写了会直接编译失败），
##      所以「正对镜头」改成在 GDScript 里手动对齐相机朝向，见 _face_bar_to_camera()。
const BAR_SHADER := [
	"shader_type spatial;",
	"render_mode unshaded, cull_disabled;",
	"uniform float ratio : hint_range(0.0, 1.0) = 1.0;",
	"uniform vec3 full_color : source_color = vec3(0.36, 0.92, 0.44);",
	"uniform vec3 low_color : source_color = vec3(0.95, 0.32, 0.28);",
	"uniform vec3 back_color : source_color = vec3(0.10, 0.11, 0.16);",
	"uniform vec3 frame_color : source_color = vec3(0.04, 0.05, 0.08);",
	"void fragment() {",
	"	float pad = 0.035;",
	"	vec3 col = frame_color;",
	"	if (UV.x > pad && UV.x < 1.0 - pad && UV.y > 0.20 && UV.y < 0.80) {",
	"		float inner = (UV.x - pad) / (1.0 - pad * 2.0);",
	"		if (inner <= ratio) {",
	"			col = mix(low_color, full_color, smoothstep(0.0, 0.75, ratio));",
	"		} else {",
	"			col = back_color;",
	"		}",
	"	}",
	"	ALBEDO = col;",
	"}",
]

var kind: int = Kind.GRUNT
var max_hp: float = 1.0
var hp: float = 1.0
var base_speed: float = 2.0
var reward: int = 0
var progress: float = 0.0       # 已行进距离，用于塔选择「最靠前」的目标
var flying: bool = false        # 飞行怪：无视地形，直线飞向基地
var armor: float = 0.0          # 护甲：减伤比例（0~1）
var heal: float = 0.0           # 治疗怪：每次治疗量
var split: int = 0              # 分裂怪：死亡后分裂数量
var cloak: bool = false         # 隐身怪：塔无法直接锁定
var slow_cap: float = 1.0       # 减速抗性：一次减速最多只能削到该比例（首领 < 1.0）
var direct_target: Vector3 = Vector3.ZERO
var regen: float = 0.0           # 精英词条：每秒回血
var elites: Array = []           # 精英词条列表
var wave_no: int = 1             # 生成时的波次（召唤援军要沿用同一套血量成长）
var hp_scale_v: float = 1.0      # 生成时的血量成长系数

var _haste: float = 0.0          # 战吼：移速加成（0.3 = +30%）
var _haste_timer: float = 0.0
var _skill_timer: float = 0.0    # 首领技能的冷却计时
var _enraged: bool = false       # 大首领是否已进入狂暴阶段
var _summoned: bool = false      # 半血召唤是否已触发

var _heal_timer: float = 0.0
var _cloaked: bool = false       # 隐身怪：当前是否处于隐身阶段
var _cloak_timer: float = 0.0
var _dot_dps: float = 0.0        # 燃烧：每秒伤害
var _dot_timer: float = 0.0
var _dot_tick: float = 0.0
var _shock_timer: float = 0.0    # 感电：闪电塔挂的标记，喷火塔命中会引爆
var _poison_dps: float = 0.0     # 中毒（强化卡给所有塔子弹附带的持续伤害，无视护甲）
var _poison_timer: float = 0.0
var _poison_tick: float = 0.0
var _bleed_dps: float = 0.0      # 流血（同上，但吃护甲减免）
var _bleed_timer: float = 0.0
var _bleed_tick: float = 0.0
var _armor_break: float = 0.0    # 破甲：被「破甲弹头」削掉的护甲值
var _armor_break_timer: float = 0.0
var _vuln: float = 0.0           # 易伤：受到伤害提高的比例
var _vuln_timer: float = 0.0

var path_world: Array[Vector3] = []
var path_idx: int = 0

var slow_factor: float = 1.0
var slow_timer: float = 0.0
## 额外减速乘区（震地雷泥潭这类「地面减速」）：和 slow_factor **乘算**，
## 1.0 = 没踩到泥潭。冰塔 -22% 与泥潭 -16% 同时在场时，实际速度 = 0.78 × 0.84。
var slow_extra: float = 1.0
var _slow_extra_timer: float = 0.0
var _dying: bool = false

var _body: Node3D
var _bar_root: Node3D
var _bar_mat: ShaderMaterial
var _mat: StandardMaterial3D
var _cam: Camera3D

var _marker_root: Node3D        # 首领头顶的悬浮标记
var _marker_gem: MeshInstance3D # 标记里旋转的宝石
var _marker_base_y: float = 0.0
var _marker_t: float = 0.0

# ---------------------------------------------------------------- 生成

func spawn(k: int, start_pos: Vector3, world_path: Array[Vector3], hp_scale: float, wave: int) -> void:
	_init_enemy(k, start_pos, world_path, hp_scale, wave, -1)


func _init_enemy(k: int, start_pos: Vector3, world_path: Array[Vector3], hp_scale: float, wave: int, reward_override: int) -> void:
	kind = k
	var d: Dictionary = DATA[k]
	max_hp = float(d["hp"]) * hp_scale
	hp = max_hp
	base_speed = float(d["speed"])
	if reward_override >= 0:
		reward = reward_override
	else:
		reward = int(round(float(d["reward"]) * Waves.reward_scale(wave)))
	flying = bool(d.get("flying", false))
	armor = float(d.get("armor", 0.0))
	heal = float(d.get("heal", 0.0))
	split = int(d.get("split", 0))
	cloak = bool(d.get("cloak", false))
	slow_cap = float(d.get("slow_cap", 1.0))
	regen = 0.0
	elites = []
	wave_no = wave
	hp_scale_v = hp_scale
	_haste = 0.0
	_haste_timer = 0.0
	_enraged = false
	_summoned = false
	_skill_timer = _first_skill_delay()
	_cloaked = false
	_cloak_timer = 0.0
	_dot_dps = 0.0
	_dot_timer = 0.0
	_dot_tick = 0.0
	_shock_timer = 0.0
	_poison_dps = 0.0
	_poison_timer = 0.0
	_poison_tick = 0.0
	_bleed_dps = 0.0
	_bleed_timer = 0.0
	_bleed_tick = 0.0
	_armor_break = 0.0
	_armor_break_timer = 0.0
	_vuln = 0.0
	_vuln_timer = 0.0
	slow_factor = 1.0
	slow_timer = 0.0
	slow_extra = 1.0
	_slow_extra_timer = 0.0
	global_position = start_pos
	var wp: Array[Vector3] = [start_pos]
	# 路面加宽到 3.2 之后，每只怪在路面内随机偏一点：
	# 一群怪会自然铺成两三列往前走，而不是全部踩在同一条细线上。
	# 体型越大偏心越小（平方衰减）：大首领几乎踩中线，不会半个身子压在路肩 / 桥栏上。
	var body_s: float = maxf(float(d["size"]), 1.0)
	var spread: float = 0.42 * clampf(pow(1.4 / body_s, 2.0), 0.05, 1.0)
	var lat := Vector3(randf_range(-spread, spread), 0.0, randf_range(-spread, spread))
	for p in world_path:
		wp.append(p + lat)
	path_world = wp
	path_idx = 0
	progress = 0.0
	if flying and world_path.size() > 0:
		direct_target = world_path[world_path.size() - 1]
	name = "%s" % d["name"]
	add_to_group("enemies")
	_roll_elites(wave)
	_build(d)
	if cloak:
		_cloaked = true
		_apply_cloak_visual()


## 精英词条：随波次概率给非首领敌人挂随机强化
func _roll_elites(wave: int) -> void:
	# 首领不吃随机精英词条：它们本身就是被设计好的强度节点
	if kind == Kind.BOSS or kind == Kind.MINI_BOSS:
		return
	var chance := clampf(0.06 + 0.035 * float(wave - 1), 0.0, 0.45)
	if randf() > chance:
		return
	var pool: Array = ["fast", "regen", "armored", "giant"]
	var count := 1
	if wave >= 6 and randf() < 0.4:
		count = 2
	for i in range(count):
		if pool.is_empty():
			break
		var idx := randi() % pool.size()
		elites.append(pool[idx])
		pool.remove_at(idx)
	_apply_elites()


func _apply_elites() -> void:
	if elites.is_empty():
		return
	for e in elites:
		match e:
			"fast":
				base_speed *= 1.35
			"regen":
				regen = max_hp * 0.03
			"armored":
				# 上限压到 0.6：护盾怪本身带护甲，再叠「坚甲」词条时不能叠加成
				# 「打不动」的怪物（0.85 减伤 = 有效血量 6.7 倍，玩家会觉得卡关）
				armor = minf(armor + 0.25, 0.6)
			"giant":
				max_hp *= 1.6
				hp = max_hp
				reward = int(reward * 1.5)
				scale = Vector3(1.3, 1.3, 1.3)

# ---------------------------------------------------------------- 首领技能
## 首领不再是「血更厚的木桩」：小首领靠战吼 / 集结带动整波冲锋，
## 大首领靠压制脉冲打断防线、半血狂暴决定战斗的后半段节奏。
## 数值全在 EnemyData 里，这里只负责表现与结算。

## 首领是「有技能的那两只」
func is_boss() -> bool:
	return kind == Kind.BOSS or kind == Kind.MINI_BOSS


## 第一次放技能的延迟：首领登场先走一小段，给玩家一点反应时间
func _first_skill_delay() -> float:
	if kind == Kind.MINI_BOSS:
		return float(EnemyData.WARCRY_INTERVAL) * 0.6
	if kind == Kind.BOSS:
		return float(EnemyData.BOSS_PULSE_INTERVAL) * 0.5
	return 0.0


## 战吼加速：可被更长的 / 更强的战吼覆盖（取最大值，不叠乘）
func apply_haste(amount: float, time: float) -> void:
	_haste = maxf(_haste, amount)
	_haste_timer = maxf(_haste_timer, time)


func _tick_haste(delta: float) -> void:
	if _haste_timer <= 0.0:
		return
	_haste_timer -= delta
	if _haste_timer <= 0.0:
		_haste = 0.0


func _tick_boss_skill(delta: float) -> void:
	# 半血事件（一次性）：大小首领都会召唤援军，大首领额外进入狂暴
	if not _summoned and hp <= max_hp * float(EnemyData.SUMMON_HP_RATIO):
		_summoned = true
		_on_half_hp()

	_skill_timer -= delta
	if _skill_timer > 0.0:
		return
	if kind == Kind.MINI_BOSS:
		_skill_timer = float(EnemyData.WARCRY_INTERVAL)
		_warcry()
	else:
		_skill_timer = float(EnemyData.BOSS_PULSE_INTERVAL)
		_pulse()


## 小首领「潮主」· 战吼：半径内的小怪集体加速，逼玩家先处理首领
func _warcry() -> void:
	var radius := float(EnemyData.WARCRY_RADIUS)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e) or e == self:
			continue
		if e.is_boss():
			continue
		if e.global_position.distance_to(global_position) > radius:
			continue
		e.apply_haste(float(EnemyData.WARCRY_HASTE), float(EnemyData.WARCRY_TIME))
	var parent := get_parent()
	Fx.ring(parent, global_position, Color(1.0, 0.62, 0.22), radius * 0.8, 0.45)
	Fx.flash(parent, global_position + Vector3(0.0, 1.4, 0.0), Color(1.0, 0.72, 0.30), 1.0, 0.32)
	Sound.play("wave", -6.0)


## 大首领「终焉之影」· 压制脉冲：范围内所有塔暂时熄火（不摧毁，只是停火）
func _pulse() -> void:
	var radius := float(EnemyData.BOSS_PULSE_RADIUS)
	for t in get_tree().get_nodes_in_group("towers"):
		if t == null or not is_instance_valid(t):
			continue
		if t.global_position.distance_to(global_position) > radius:
			continue
		t.suppress(float(EnemyData.BOSS_PULSE_TIME))
	var parent := get_parent()
	Fx.ring(parent, global_position, Color(0.62, 0.35, 1.0), radius, 0.55)
	Fx.flash(parent, global_position + Vector3(0.0, 1.6, 0.0), Color(0.72, 0.42, 1.0), 1.8, 0.42)
	Sound.play("explosion", -8.0)


## 半血：召唤援军；大首领额外狂暴
func _on_half_hp() -> void:
	var parent := get_parent()
	if kind == Kind.BOSS:
		_enraged = true
		base_speed *= 1.0 + float(EnemyData.BOSS_ENRAGE_HASTE)
		armor = minf(armor + float(EnemyData.BOSS_ENRAGE_ARMOR), 0.9)
		_update_tint()
		Fx.flash(parent, global_position + Vector3(0.0, 1.6, 0.0), Color(1.0, 0.25, 0.32), 2.2, 0.5)
		Fx.ring(parent, global_position, Color(1.0, 0.25, 0.35), 3.6, 0.65)
		Fx.damage_number(parent, global_position + Vector3(0.0, 2.9, 0.0), "狂暴", Color(1.0, 0.35, 0.35), true)
		Sound.play("wave")
		_summon_guards(int(EnemyData.BOSS_SUMMON))
	else:
		Fx.ring(parent, global_position, Color(1.0, 0.55, 0.25), 2.6, 0.5)
		Fx.damage_number(parent, global_position + Vector3(0.0, 1.8, 0.0), "集结", Color(1.0, 0.72, 0.35), false)
		_summon_guards(int(EnemyData.MINI_BOSS_SUMMON))


## 召唤援军：复用「剩余路径」逻辑（和分裂怪同一套），保证召唤物顺着原路线走
func _summon_guards(count: int) -> void:
	var parent_node := get_parent()
	if parent_node == null or count <= 0:
		return
	var remaining: Array[Vector3] = []
	for j in range(path_idx, path_world.size()):
		remaining.append(path_world[j])
	if remaining.is_empty():
		return
	for i in range(count):
		var e := Enemy.new()
		parent_node.add_child(e)
		var ang := TAU * float(i) / float(count)
		var off := Vector3(cos(ang) * 1.1, 0.0, sin(ang) * 1.1)
		e._init_enemy(Kind.GRUNT, global_position + off, remaining, hp_scale_v * float(EnemyData.SUMMON_HP_COEF), wave_no, -1)
	Fx.ring(parent_node, global_position, Color(1.0, 0.55, 0.75), 2.2, 0.45)


func _build(d: Dictionary) -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)

	var col: Color = d["color"]
	var s: float = float(d["size"])

	# 优先用 res://models/enemies/enemy_<类型>.glb（放了模型就不再用程序化几何）
	if not _build_custom_body(s):
		var mesh: Mesh
		if kind == Kind.RUNNER:
			var cm := CylinderMesh.new()
			cm.top_radius = 0.16 * s
			cm.bottom_radius = 0.30 * s
			cm.height = 1.15 * s
			mesh = cm
		elif kind == Kind.BOSS:
			var bm := BoxMesh.new()
			bm.size = Vector3(1.05 * s, 1.15 * s, 1.05 * s)
			mesh = bm
		elif kind == Kind.MINI_BOSS:
			var mm := BoxMesh.new()
			mm.size = Vector3(0.85 * s, 0.95 * s, 0.85 * s)
			mesh = mm
		elif kind == Kind.FLYER:
			var bm := BoxMesh.new()
			bm.size = Vector3(0.7 * s, 0.5 * s, 0.7 * s)
			mesh = bm
		else:
			var sm := SphereMesh.new()
			sm.radius = 0.35 * s
			sm.height = 0.80 * s
			sm.radial_segments = 12
			mesh = sm

		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = col
		_mat.roughness = 0.55
		_mat.emission_enabled = true
		_mat.emission = col
		_mat.emission_energy_multiplier = 0.12
		# 可选贴图：res://textures/enemy_grunt.png / enemy_runner / enemy_tank / enemy_boss
		if TextureLib.dress(_mat, "enemy_%s" % slot_suffix()):
			_mat.emission = Color.WHITE
			_mat.emission_energy_multiplier = 0.05
		if cloak:
			_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = _mat
		mi.position.y = 0.45 * s
		_body.add_child(mi)

	# 首领体型更大，血条同步加宽，远看也能盯住它的血线
	var bar_w := BAR_WIDTH
	if kind == Kind.BOSS:
		bar_w = BAR_WIDTH * 2.0
	elif kind == Kind.MINI_BOSS:
		bar_w = BAR_WIDTH * 1.5
	# 血条离地高度跟着体型走：身体顶面大约在 0.85~1.03 倍体型处，
	# 1.05*s+0.25 让大小怪的血条都贴着脑袋，不会因为放大而飘到半空。
	_build_bar(1.05 * s + 0.25, bar_w)

	if kind == Kind.SHIELD:
		_build_shield_ring(s)
	if kind == Kind.HEALER:
		_build_heal_ring(s)
	if kind == Kind.BOSS:
		_build_boss_ring(s, Color(1.0, 0.22, 0.48))
		_build_boss_marker(s, Color(1.0, 0.28, 0.52), "BOSS")
	elif kind == Kind.MINI_BOSS:
		_build_boss_ring(s, Color(1.0, 0.62, 0.22))
		_build_boss_marker(s, Color(1.0, 0.64, 0.24), "MINI BOSS")
	if not elites.is_empty():
		_build_elite_ring(s)


## 当前敌人类型对应的贴图槽位后缀
## 用外部模型替换敌人外形：把任意 GLB 命名为
## `res://models/enemies/enemy_grunt.glb`（runner / tank / boss / flyer / shield 同理）即可，
## 这里会自动按身高缩放到和原程序化敌人一致、底部贴地、水平居中。
## 找不到文件返回 false —— 回退到程序化几何，工程永远能跑。
func _build_custom_body(s: float) -> bool:
	# 隐身怪要靠材质透明度做隐身效果，用外部模型会失效，所以直接走程序化外观
	if cloak:
		return false
	var path := "res://models/enemies/enemy_%s.glb" % slot_suffix()
	var model := ModelLib.instance_path(path)
	if model == null:
		return false
	var box := ModelLib.aabb_of(model)
	var base := model.scale
	var cur_h: float = box.size.y * absf(base.y)
	if cur_h <= 0.0001:
		model.queue_free()
		return false
	var target_h: float = 0.80 * s
	if kind == Kind.BOSS:
		target_h = 1.15 * s
	elif kind == Kind.MINI_BOSS:
		target_h = 0.95 * s
	var k := target_h / cur_h
	model.scale = base * Vector3(k, k, k)
	# 让模型底部贴地（y=0）、水平居中到格子中心
	var c := box.get_center()
	model.position = Vector3(-c.x * base.x * k, -box.position.y * base.y * k, -c.z * base.z * k)
	_body.add_child(model)
	return true


func slot_suffix() -> String:
	match kind:
		Kind.RUNNER:
			return "runner"
		Kind.TANK:
			return "tank"
		Kind.BOSS:
			return "boss"
		Kind.MINI_BOSS:
			return "miniboss"
		Kind.FLYER:
			return "flyer"
		Kind.SHIELD:
			return "shield"
		Kind.HEALER:
			return "healer"
		Kind.SPLITTER:
			return "splitter"
		_:
			return "grunt"


func _build_bar(y: float, width: float = BAR_WIDTH) -> void:
	_bar_root = Node3D.new()
	_bar_root.name = "HealthBar"
	_bar_root.position.y = y
	add_child(_bar_root)

	var sh := Shader.new()
	sh.code = "\n".join(BAR_SHADER)
	_bar_mat = ShaderMaterial.new()
	_bar_mat.shader = sh

	# 外框 + 底槽 + 填充全部由着色器一次画完，所以只要一个 quad
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(width + 0.06, 0.20)
	quad.mesh = qm
	quad.material_override = _bar_mat
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar_root.add_child(quad)

	_update_bar()
	_face_bar_to_camera()


## 护盾怪：加一个半透明护盾环
func _build_shield_ring(s: float) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42 * s
	tm.outer_radius = 0.55 * s
	ring.mesh = tm
	ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.35, 0.75, 0.95, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = mat
	ring.position.y = 0.55 * s
	_body.add_child(ring)


## 治疗怪：绿色光环，示意治疗范围
func _build_heal_ring(s: float) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = HEAL_RADIUS * 0.94
	tm.outer_radius = HEAL_RADIUS
	ring.mesh = tm
	ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.40, 0.90, 0.55, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = mat
	ring.position.y = 0.25
	_body.add_child(ring)


## 首领光环：脚下常亮一圈专属色环，一眼能从怪堆里认出来
func _build_boss_ring(s: float, col: Color) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	# 光环按体型放大，但跟着身体走而不是按 s 死乘：
	# 旧写法 0.82~1.0*s 在 s=3 时会变成直径 6 的地面大圆圈，直接铺满整条路。
	tm.inner_radius = 0.58 * s
	tm.outer_radius = 0.72 * s
	tm.rings = 48
	tm.ring_segments = 6
	ring.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(col.r, col.g, col.b, 0.55)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 0.9
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = mat
	ring.position.y = 0.08
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(ring)


## 首领头顶的悬浮标记：文字 + 旋转宝石，血条上方一直悬浮，怪再多也能一眼锁定
func _build_boss_marker(s: float, col: Color, text: String) -> void:
	_marker_root = Node3D.new()
	_marker_root.name = "BossMarker"
	# 悬在血条上方（血条高度见 _build_bar 的 1.05*s + 0.25）
	_marker_base_y = 1.05 * s + 0.25 + 0.60
	_marker_root.position.y = _marker_base_y
	add_child(_marker_root)

	var label := Label3D.new()
	label.text = text
	label.font_size = 96
	label.pixel_size = 0.0032
	label.outline_size = 18
	label.outline_modulate = Color(0.05, 0.02, 0.06, 0.85)
	label.modulate = col.lightened(0.30)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	_marker_root.add_child(label)

	_marker_gem = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.11 * s
	sm.height = 0.11 * s * 2.4
	sm.radial_segments = 4       # 4 段 2 环 = 八面体，看起来像一颗悬浮宝石
	sm.rings = 2
	_marker_gem.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 1.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_marker_gem.material_override = mat
	_marker_gem.position.y = 0.62
	_marker_gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker_root.add_child(_marker_gem)


## 标记上下轻微浮动 + 宝石自转，静止的图标容易被怪堆淹没
func _animate_boss_marker(delta: float) -> void:
	if _marker_root == null or not is_instance_valid(_marker_root):
		return
	_marker_t += delta
	_marker_root.position.y = _marker_base_y + sin(_marker_t * 2.6) * 0.10
	if _marker_gem != null and is_instance_valid(_marker_gem):
		_marker_gem.rotation.y += delta * 2.4


## 精英怪：金色光环标识（词条不同仅属性差异，视觉统一）
func _build_elite_ring(s: float) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.55 * s
	tm.outer_radius = 0.68 * s
	ring.mesh = tm
	ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.75, 0.25, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = mat
	ring.position.y = 0.12
	_body.add_child(ring)

# ---------------------------------------------------------------- 移动

func _process(delta: float) -> void:
	if not _dying:
		_face_bar_to_camera()
		_animate_boss_marker(delta)
	if not GameState.running or _dying:
		return

	if slow_timer > 0.0:
		slow_timer -= delta
		if slow_timer <= 0.0:
			slow_factor = 1.0
			_update_tint()

	# 泥潭的额外减速：单独计时，走出泥潭后自己恢复，不影响冰塔那一层
	if _slow_extra_timer > 0.0:
		_slow_extra_timer -= delta
		if _slow_extra_timer <= 0.0:
			slow_extra = 1.0

	if _shock_timer > 0.0:
		_shock_timer -= delta
		if _shock_timer <= 0.0:
			_update_tint()

	# 战吼加速与首领技能：都跟着普通 _process 走，暂停 / 波间休整时不会空转
	_tick_haste(delta)
	if is_boss():
		_tick_boss_skill(delta)

	if heal > 0.0:
		_heal_timer -= delta
		if _heal_timer <= 0.0:
			_heal_timer = HEAL_INTERVAL
			_heal_aura()

	if cloak:
		_cloak_timer += delta
		var was := _cloaked
		if _cloaked:
			if _cloak_timer >= CLOAK_HIDDEN:
				_cloaked = false
				_cloak_timer = 0.0
		elif _cloak_timer >= CLOAK_VISIBLE:
			_cloaked = true
			_cloak_timer = 0.0
		if was != _cloaked:
			_apply_cloak_visual()

	if regen > 0.0 and hp < max_hp:
		hp = minf(hp + regen * delta, max_hp)
		_update_bar()

	if _dot_timer > 0.0:
		_dot_timer -= delta
		_dot_tick -= delta
		if _dot_tick <= 0.0:
			_dot_tick = 0.5
			take_damage(_dot_dps * 0.5, false, false)
		if _dot_timer <= 0.0:
			# 烧完了：清掉状态并还原外观（可能还带着冰塔的减速蓝色）
			_dot_dps = 0.0
			_update_tint()

	# 中毒 / 流血：塔的附加状态，和燃烧一样每 0.5 秒结算一次
	if _poison_timer > 0.0:
		_poison_timer -= delta
		_poison_tick -= delta
		if _poison_tick <= 0.0:
			_poison_tick = 0.5
			_take_raw(_poison_dps * 0.5)   # 毒无视护甲
		if _poison_timer <= 0.0:
			_poison_dps = 0.0
			_update_tint()

	if _bleed_timer > 0.0:
		_bleed_timer -= delta
		_bleed_tick -= delta
		if _bleed_tick <= 0.0:
			_bleed_tick = 0.5
			take_damage(_bleed_dps * 0.5, false, false)   # 流血吃护甲
		if _bleed_timer <= 0.0:
			_bleed_dps = 0.0
			_update_tint()

	# 破甲 / 易伤：只影响后续命中，到期自动复原
	if _armor_break_timer > 0.0:
		_armor_break_timer -= delta
		if _armor_break_timer <= 0.0:
			_armor_break = 0.0
	if _vuln_timer > 0.0:
		_vuln_timer -= delta
		if _vuln_timer <= 0.0:
			_vuln = 0.0

	if flying:
		# 飞行怪：直线飞向基地，无视地形阻挡
		var fdir := direct_target - global_position
		fdir.y = 0.0
		var fdist := fdir.length()
		var fstep := base_speed * slow_factor * slow_extra * (1.0 + _haste) * delta
		if fdist <= fstep:
			progress += fdist
			_leak()
			return
		global_position += fdir.normalized() * fstep
		progress += fstep
		if fdist > 0.0001:
			_body.rotation.y = atan2(fdir.x, fdir.z)
		_body.position.y = sin(progress * 3.0) * 0.08 + 0.3
		return

	if path_idx >= path_world.size():
		return

	var dest: Vector3 = path_world[path_idx]
	var dir := dest - global_position
	dir.y = 0.0
	var dist := dir.length()
	var step := base_speed * slow_factor * slow_extra * (1.0 + _haste) * delta

	if dist <= step:
		progress += dist
		if dist > 0.0001:
			global_position += dir.normalized() * dist
		path_idx += 1
		if path_idx >= path_world.size():
			_leak()
			return
	else:
		progress += step
		global_position += dir.normalized() * step

	if dist > 0.0001:
		_body.rotation.y = atan2(dir.x, dir.z)
	# 轻微上下浮动
	_body.position.y = sin(progress * 3.0) * 0.06

# ---------------------------------------------------------------- 受击

func take_damage(amount: float, crit: bool = false, show_number: bool = true) -> void:
	if _dying:
		return
	# 破甲先扣护甲，易伤再放大伤害：两个都只影响「这一次命中之后」的攻击
	var eff_armor := maxf(armor - _armor_break, 0.0)
	if eff_armor > 0.0:
		amount *= (1.0 - eff_armor)
	if _vuln > 0.0:
		amount *= 1.0 + _vuln
	hp -= amount
	_update_bar()
	if crit and _mat != null:
		_mat.emission_energy_multiplier = 1.0
	# 小额伤害不飘字：喷火/箭塔每发都飘会把屏幕糊满，也省掉大量 Label3D
	if show_number and (crit or amount >= 8.0):
		Fx.damage_number(get_parent(), global_position + Vector3(0.0, 0.7, 0.0), str(int(round(amount))), Color(1.0, 0.35, 0.35) if crit else Color(1.0, 0.9, 0.7), crit)
	if hp <= 0.0:
		_die()


## 无视护甲的真实伤害（中毒的结算入口）：护甲只挡「被打」的部分，挡不住毒性
func _take_raw(amount: float) -> void:
	if _dying:
		return
	hp -= amount
	_update_bar()
	if hp <= 0.0:
		_die()


func apply_slow(factor: float, time: float) -> void:
	# 首领的减速抗性：一次减速最多只能削到 slow_cap，冰塔不能把它冻成不动靶子
	factor = minf(factor, slow_cap)
	slow_factor = maxf(minf(slow_factor, 1.0 - factor), 0.25)
	slow_timer = maxf(slow_timer, time)
	_update_tint()


## 地形减速（震地雷的泥潭）：**乘算**叠在冰塔减速之上，互不覆盖。
## 例：冰塔 -22%（slow_factor 0.78）+ 泥潭 -16%（slow_extra 0.84）→ 实际 0.655 倍速。
## 走的是独立乘区，所以不会被 apply_slow 的「取更强」逻辑吞掉。
func apply_extra_slow(factor: float, time: float) -> void:
	if _dying:
		return
	var f := clampf(factor, 0.0, 0.9)
	slow_extra = minf(slow_extra, 1.0 - f)
	_slow_extra_timer = maxf(_slow_extra_timer, time)


## 是否处于「冰塔减速」状态。喷火塔的联动加成按这个状态判定
## 注意：只看冰塔那一层，踩泥潭不算「被冻住」，不会触发融化反应
func is_chilled() -> bool:
	return slow_timer > 0.0


## 是否正在燃烧（喷火塔的持续伤害）
func is_burning() -> bool:
	return _dot_timer > 0.0


## 是否感电（被闪电塔命中，喷火塔可以引爆）
func is_shocked() -> bool:
	return _shock_timer > 0.0


## 闪电塔命中时挂上感电标记
func apply_shock(duration: float) -> void:
	if _dying:
		return
	_shock_timer = maxf(_shock_timer, duration)
	_update_tint()


## 引爆感电：引爆成功后清除标记，避免喷火塔每一发都触发爆炸
func consume_shock() -> bool:
	if _shock_timer <= 0.0:
		return false
	_shock_timer = 0.0
	_update_tint()
	return true


## 治疗：由治疗怪的光环调用，回满为止
func heal_hp(amount: float) -> void:
	if _dying:
		return
	hp = minf(hp + amount, max_hp)
	_update_bar()
	Fx.damage_number(get_parent(), global_position + Vector3(0.0, 0.9, 0.0), "+%d" % int(round(amount)), Color(0.40, 0.95, 0.55), false)


## 治疗光环：每跳治疗周围友军（不含自己）
func _heal_aura() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e) or e == self:
			continue
		if e.global_position.distance_to(global_position) <= HEAL_RADIUS:
			e.heal_hp(heal)


## 燃烧：喷火塔施加的持续伤害
func apply_dot(dps: float, duration: float) -> void:
	if _dying:
		return
	_dot_dps = maxf(_dot_dps, dps)
	_dot_timer = maxf(_dot_timer, duration)
	_dot_tick = 0.0
	_update_tint()


## 中毒（强化卡「淬毒弹头」）：每秒伤害，**无视护甲**
func apply_poison(dps: float, duration: float) -> void:
	if _dying:
		return
	_poison_dps = maxf(_poison_dps, dps)
	_poison_timer = maxf(_poison_timer, duration)
	_poison_tick = 0.0
	_update_tint()


## 流血（强化卡「放血锋刃」）：每秒伤害，吃护甲减免，但基础值更高
func apply_bleed(dps: float, duration: float) -> void:
	if _dying:
		return
	_bleed_dps = maxf(_bleed_dps, dps)
	_bleed_timer = maxf(_bleed_timer, duration)
	_bleed_tick = 0.0
	_update_tint()


func is_poisoned() -> bool:
	return _poison_timer > 0.0


func is_bleeding() -> bool:
	return _bleed_timer > 0.0


## 破甲（强化卡「破甲弹头」）：临时削掉一部分护甲，对护盾怪 / 重甲收益最大。
## 用 maxf 而不是累加 —— 同一批塔互相刷新，不该因为射速高就无限叠。
func apply_armor_break(amount: float, duration: float) -> void:
	if _dying:
		return
	_armor_break = maxf(_armor_break, amount)
	_armor_break_timer = maxf(_armor_break_timer, duration)


## 易伤（强化卡「易伤标记」）：受到的所有伤害提高，同样取最大值不叠加
func apply_vuln(amount: float, duration: float) -> void:
	if _dying:
		return
	_vuln = maxf(_vuln, amount)
	_vuln_timer = maxf(_vuln_timer, duration)


## 塔锁定目标时判断：隐身怪在隐身阶段不可被直接锁定
func is_hidden() -> bool:
	return cloak and _cloaked


func _update_tint() -> void:
	if _mat == null:
		return
	if slow_timer > 0.0:
		if _dot_timer > 0.0:
			# 冰火两重天：又冻又烧 → 泛白，提示喷火塔正在吃联动加成
			_mat.albedo_color = Color(0.90, 0.96, 1.0)
			_mat.emission = Color(0.70, 0.88, 1.0)
			_mat.emission_energy_multiplier = 1.0
		else:
			_mat.albedo_color = Color(0.55, 0.80, 1.0)
			_mat.emission = Color(0.30, 0.60, 1.0)
			_mat.emission_energy_multiplier = 0.5
	elif _shock_timer > 0.0:
		# 感电：淡紫色，提示「喷火塔打它会引爆」
		_mat.albedo_color = Color(0.80, 0.72, 1.0)
		_mat.emission = Color(0.60, 0.42, 1.0)
		_mat.emission_energy_multiplier = 0.75
	elif _bleed_timer > 0.0:
		# 流血：暗红，和中毒用颜色区分开
		_mat.albedo_color = Color(0.98, 0.42, 0.38)
		_mat.emission = Color(0.95, 0.20, 0.18)
		_mat.emission_energy_multiplier = 0.70
	elif _poison_timer > 0.0:
		# 中毒：墨绿
		_mat.albedo_color = Color(0.62, 0.92, 0.42)
		_mat.emission = Color(0.40, 0.95, 0.30)
		_mat.emission_energy_multiplier = 0.60
	else:
		var d: Dictionary = DATA[kind]
		_mat.albedo_color = d["color"]
		_mat.emission = d["color"]
		_mat.emission_energy_multiplier = 0.12
		if _enraged:
			# 狂暴：底色压向暗红并常亮，一眼看出大首领进入了第二阶段
			var base_col: Color = d["color"]
			_mat.albedo_color = base_col.lerp(Color(1.0, 0.18, 0.22), 0.55)
			_mat.emission = Color(1.0, 0.25, 0.30)
			_mat.emission_energy_multiplier = 0.95
		if cloak:
			_apply_cloak_visual()


## 隐身怪：根据当前隐身状态调整身体透明度与血条可见性
func _apply_cloak_visual() -> void:
	if _mat != null:
		_mat.albedo_color.a = 0.16 if _cloaked else 1.0
		_mat.emission.a = 0.16 if _cloaked else 1.0
	if _bar_root != null:
		_bar_root.visible = not _cloaked


func _update_bar() -> void:
	if _bar_mat == null:
		return
	# 受击瞬间立即生效：改的是 shader 参数，不依赖节点缩放
	_bar_mat.set_shader_parameter("ratio", clampf(hp / max_hp, 0.0, 1.0))


## 让血条正对镜头。
## 不用 StandardMaterial3D 的 billboard：它会在顶点阶段用相机基向量替换模型旋转，
## 顺带把节点缩放丢掉（血条就永远满格了）。这里改成手动把血条的方向对齐相机。
func _face_bar_to_camera() -> void:
	if _bar_root == null or not is_inside_tree():
		return
	if _cam == null or not is_instance_valid(_cam):
		_cam = get_viewport().get_camera_3d()
	if _cam == null:
		return
	var t := _bar_root.global_transform
	# orthonormalized 去掉相机可能带的缩放，免得血条被一起拉大
	t.basis = _cam.global_transform.basis.orthonormalized()
	_bar_root.global_transform = t


func _die() -> void:
	_dying = true
	GameState.add_gold(reward)
	GameState.on_kill()
	remove_from_group("enemies")
	if _bar_root != null:
		_bar_root.visible = false
	if _marker_root != null:
		_marker_root.visible = false
	Sound.play("death")
	if kind == Kind.BOSS or kind == Kind.MINI_BOSS:
		# 首领倒下：更大的爆闪 + 冲击环，给足击杀反馈
		Fx.flash(get_parent(), global_position, Color(1.0, 0.45, 0.55), 1.4, 0.45)
		Fx.ring(get_parent(), global_position, Color(1.0, 0.45, 0.55), 2.4, 0.7)
		Fx.ring(get_parent(), global_position, Color(1.0, 0.85, 0.45), 1.6, 0.5)
	else:
		Fx.flash(get_parent(), global_position, Color(1.0, 0.6, 0.3), 0.4, 0.2)
		Fx.ring(get_parent(), global_position, Color(1.0, 0.6, 0.3), 0.4, 0.25)
	if split > 0:
		_spawn_split_children()
	# 「连锁爆破」：死亡炸开一圈（伤害按自身最大生命的比例算，天然跟着波次成长）
	var blast := float(GameState.buffs.get("death_blast", 0.0))
	if blast > 0.0:
		_death_blast(blast)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(0.02, 0.02, 0.02), 0.18)
	tw.parallel().tween_property(self, "position:y", position.y + 0.5, 0.18)
	tw.tween_callback(queue_free)


## 「连锁爆破」的爆炸结算。用 take_damage 结算（会吃护甲/易伤），
## 每个敌人只会在自己死亡时炸一次，所以不会无限连锁。
func _death_blast(ratio: float) -> void:
	var dmg := max_hp * ratio
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e):
			continue
		if e.global_position.distance_to(global_position) > DEATH_BLAST_RADIUS:
			continue
		e.take_damage(dmg, false, false)
	Fx.ring(get_parent(), global_position, Color(1.0, 0.55, 0.20), DEATH_BLAST_RADIUS, 0.3)
	Fx.flash(get_parent(), global_position + Vector3(0.0, 0.5, 0.0), Color(1.0, 0.60, 0.25), DEATH_BLAST_RADIUS * 0.7, 0.2)


## 分裂怪：死亡后沿剩余路径分裂成若干小兵（不额外给奖励，避免刷金）。
## 小兵血量按「当前波血量成长 × 0.55」结算 —— 否则后期分裂出来的小兵还是开局强度，
## 血量成长就只对原生怪物生效，线性曲线会断掉。
func _spawn_split_children() -> void:
	var parent_node := get_parent()
	if parent_node == null or split <= 0:
		return
	var remaining: Array[Vector3] = []
	for j in range(path_idx, path_world.size()):
		remaining.append(path_world[j])
	for i in range(split):
		var e := Enemy.new()
		parent_node.add_child(e)
		var off := Vector3((randf() - 0.5) * 0.6, 0.0, (randf() - 0.5) * 0.6)
		e._init_enemy(Kind.GRUNT, global_position + off, remaining, hp_scale_v * 0.55, wave_no, 0)


func _leak() -> void:
	if _dying:
		return
	_dying = true
	remove_from_group("enemies")
	GameState.on_leak()
	GameState.lose_life(1)
	Sound.play("leak")
	queue_free()

# ---------------------------------------------------------------- 重新寻路

func repath(grid: GameGrid) -> void:
	if _dying:
		return
	var c := grid.world_to_cell(global_position)
	if not grid.in_bounds(c):
		c = Vector2i(clampi(c.x, 0, GameGrid.COLS - 1), clampi(c.y, 0, GameGrid.ROWS - 1))
	if grid.is_blocked(c):
		c = grid.nearest_reachable(c)
	var cells := grid.path_home_cells_from(c)
	if cells.is_empty():
		return
	var wp: Array[Vector3] = [global_position]
	for cc in cells:
		wp.append(grid.cell_to_world(cc))
	path_world = wp
	path_idx = 0
