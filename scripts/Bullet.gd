extends Node3D
class_name Bullet
## 子弹：飞向目标，命中后造成伤害（可溅射、可减速、可暴击）。

var target = null
var damage: float = 0.0
var splash: float = 0.0
var slow: float = 0.0
var slow_time: float = 0.0
var is_crit: bool = false
var speed: float = 22.0
var chain: int = 0
var dot: float = 0.0
var src_kind: int = -1          # 发射这发子弹的塔类型（用于元素联动）
var src_level: int = 1          # 发射这发子弹的塔等级（用于命中特效分级）
var src_mutation: String = ""   # 发射这发子弹的塔的变异 id（决定要不要放序列帧特效）
var _hit_targets: Array = []
var _last_pos := Vector3.ZERO
var _mat: StandardMaterial3D

## 毒瓶的抛物线：飞行高度 = 起点到落点的直线插值 + 一个正弦拱起。
## 只改视觉高度，命中判定仍然是「贴到目标 / 飞完全程」，不会因为弧度打偏。
const LOB_HEIGHT := 1.6
var _lob := false
var _lob_travelled := 0.0
var _lob_total := 1.0
var _lob_start_y := 0.0

## 「处决协议」卡的触发阈值：目标生命低于这个比例时吃额外伤害
const EXECUTE_HP_RATIO := 0.35


func configure(t, dmg: float, spl: float, slw: float, st: float, crit: bool, sp: float, chn: int = 0, dot_dps: float = 0.0, kind: int = -1, lvl: int = 1, mut: String = "") -> void:
	target = t
	damage = dmg
	splash = spl
	slow = slw
	slow_time = st
	is_crit = crit
	speed = sp
	chain = chn
	dot = dot_dps
	src_kind = kind
	src_level = lvl
	src_mutation = mut
	if is_instance_valid(t):
		_last_pos = t.global_position + Vector3(0.0, 0.7, 0.0)
	# 毒瓶走抛物线：把起点高度和总距离记下来，_process 里按进度补一个拱
	_lob = src_kind == TowerData.Kind.POISON
	if _lob:
		_lob_start_y = global_position.y
		_lob_total = maxf(global_position.distance_to(_last_pos), 0.5)
	_build()


## 炮塔弹丸的宽度（世界单位）。石块比原来的光球大一圈，才像「一坨石头砸过去」。
const STONE_SIZE := 0.62


func _build() -> void:
	if _build_flask():
		return
	if _build_stone():
		return
	var r := 0.22 if is_crit else 0.16
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 8
	m.rings = 5
	var mi := MeshInstance3D.new()
	mi.mesh = m
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(1.0, 0.85, 0.35) if is_crit else Color(1.0, 0.95, 0.80)
	_mat.emission_enabled = true
	_mat.emission = _mat.albedo_color
	_mat.emission_energy_multiplier = 1.2
	# 可选贴图：res://textures/bullet.png
	if TextureLib.dress(_mat, "bullet"):
		_mat.emission_energy_multiplier = 0.6
	mi.material_override = _mat
	add_child(mi)

	# 简易拖尾
	var trail := MeshInstance3D.new()
	var tm := SphereMesh.new()
	tm.radius = r * 0.7
	tm.height = r * 1.4
	trail.mesh = tm
	var tmat := StandardMaterial3D.new()
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.albedo_color = Color(1.0, 0.7, 0.3, 0.35)
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail.material_override = tmat
	trail.position = Vector3(0.0, 0.0, 0.35)
	add_child(trail)


## 毒瓶塔的弹丸：一只小绿瓶（鼓肚子 + 瓶颈 + 软木塞 + 亮芯）。
## 和炮塔一样用程序化几何而不是贴图 —— 工程里没有「毒瓶」素材，
## 但绿色玻璃瓶的剪影在俯视角下已经足够认出来，别去等美术。
func _build_flask() -> bool:
	if src_kind != TowerData.Kind.POISON:
		return false
	var size := 1.25 if is_crit else 1.0
	var glass := StandardMaterial3D.new()
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.albedo_color = Color(0.30, 0.92, 0.24)
	glass.emission_enabled = true
	glass.emission = Color(0.35, 1.0, 0.28)
	glass.emission_energy_multiplier = 0.85

	var body := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.135 * size
	bm.height = 0.20 * size
	bm.radial_segments = 9
	bm.rings = 5
	body.mesh = bm
	body.material_override = glass
	add_child(body)

	var neck := MeshInstance3D.new()
	var nm := CylinderMesh.new()
	nm.top_radius = 0.035 * size
	nm.bottom_radius = 0.05 * size
	nm.height = 0.10 * size
	nm.radial_segments = 7
	neck.mesh = nm
	neck.material_override = glass
	neck.position.y = 0.12 * size
	add_child(neck)

	var cork := MeshInstance3D.new()
	var km := CylinderMesh.new()
	km.top_radius = 0.042 * size
	km.bottom_radius = 0.042 * size
	km.height = 0.035 * size
	km.radial_segments = 6
	cork.mesh = km
	var kmat := StandardMaterial3D.new()
	kmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	kmat.albedo_color = Color(0.72, 0.55, 0.34)
	cork.material_override = kmat
	cork.position.y = 0.185 * size
	add_child(cork)

	# 拖尾换成一条淡绿色的光带，抛出去的时候能看见轨迹
	var trail := MeshInstance3D.new()
	var tm := SphereMesh.new()
	tm.radius = 0.10 * size
	tm.height = 0.14 * size
	trail.mesh = tm
	var tmat := StandardMaterial3D.new()
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.albedo_color = Color(0.45, 1.0, 0.30, 0.30)
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail.material_override = tmat
	trail.position = Vector3(0.0, 0.02, -0.22)
	add_child(trail)
	return true


## 炮塔专用的石弹：res://textures/bullet_stone.png。
## 用 billboard 方片而不是球 —— 原画是「已经打好光的成品精灵」，贴到球面上会被二次打光、
## 边缘还会糊；方片永远正对镜头，俯视角下最像一颗飞过来的石头。没放图时返回 false，
## 自动回退到原来的发光球（不拖尾，石头不需要拖尾）。
func _build_stone() -> bool:
	if src_kind != TowerData.Kind.CANNON:
		return false
	var tex := TextureLib.get_texture("bullet_stone")
	if tex == null:
		return false
	var aspect := float(tex.get_height()) / maxf(float(tex.get_width()), 1.0)
	var w: float = STONE_SIZE * (1.25 if is_crit else 1.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(w, w * aspect)

	var mi := MeshInstance3D.new()
	mi.mesh = quad
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# 精灵带透明边缘：alpha 混合才能保留原画那圈柔边（scissor 会切成硬边）
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_texture = tex
	_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 一点点自发光：石块原画偏暗，压在深色路面上会糊成一团
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.88, 0.70)
	_mat.emission_energy_multiplier = 0.15
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return true


func _process(delta: float) -> void:
	if not GameState.running:
		return

	var dest := _last_pos
	if is_instance_valid(target):
		dest = target.global_position + Vector3(0.0, 0.7, 0.0)
		_last_pos = dest

	var dir := dest - global_position
	var dist := dir.length()
	var step := speed * delta

	if dist <= step or dist < 0.2:
		_hit(dest)
		return

	global_position += dir.normalized() * step
	# 毒瓶：在直线上叠一个正弦拱起（t=1 时正好落回目标高度，不会悬空炸）
	if _lob:
		_lob_travelled += step
		var t := clampf(_lob_travelled / _lob_total, 0.0, 1.0)
		global_position.y = lerpf(_lob_start_y, dest.y, t) + sin(t * PI) * LOB_HEIGHT
	look_at(global_position + dir, Vector3.UP)


func _hit(pos: Vector3) -> void:
	if chain > 0:
		# 链式闪电：命中当前目标后，跳到附近最近的未命中敌人
		var current = target if is_instance_valid(target) else null
		var jumped := 0
		while current != null and jumped < chain:
			_deal(current)
			_hit_targets.append(current)
			Fx.flash(get_parent(), current.global_position, Color(0.62, 0.52, 1.0), 0.3, 0.12)
			jumped += 1
			# 弹射距离不能用 splash：弹射塔没有任何溅射，splash=0 会导致永远跳不出去
			current = _nearest_enemy_except(current, maxf(splash, 3.2))
		Sound.play("explosion")
		_spawn_flash(pos)
		queue_free()
		return

	if splash > 0.0:
		# 直接命中的目标吃满伤害，半径内的其他敌人只吃衰减后的溅射伤害
		var main_hit = target if is_instance_valid(target) else null
		for e in get_tree().get_nodes_in_group("enemies"):
			if e == null or not is_instance_valid(e):
				continue
			if e.global_position.distance_to(pos) > splash:
				continue
			_deal(e, 1.0 if e == main_hit else float(TowerData.SPLASH_DMG_COEF))
	elif is_instance_valid(target):
		_deal(target)

	Sound.play("explosion" if splash > 0.0 else "hit")
	_spawn_flash(pos)
	queue_free()


## 对单个敌人结算伤害与附带效果。
## 元素联动在这里生效：同一次命中里，每个敌人按它自己的状态分别算加成
## （溅射 / 链式也能正确区分谁被冻住、谁没有）。
## dmg_coef 用于溅射衰减：只有被直接命中的目标吃 1.0，周围敌人按配置打折。
func _deal(e, dmg_coef: float = 1.0) -> void:
	var mult := _synergy_multiplier(e)
	var dmg := damage * (2.0 if is_crit else 1.0) * mult * dmg_coef
	# 「处决协议」：目标血量低于阈值时追加伤害（只看当前血量，所以对首领也生效）
	var exec_bonus := float(GameState.buffs.get("execute", 0.0))
	if exec_bonus > 0.0 and e.hp <= e.max_hp * EXECUTE_HP_RATIO:
		dmg *= 1.0 + exec_bonus
	# 喷火塔射速 3/s，每发都飘字会把屏幕糊满：只有暴击才显示数字
	var show_num := is_crit or src_kind != TowerData.Kind.FLAME
	# 火属性标记：霜语者的冰甲会被火烧得特别快（见 Enemy.take_damage）
	var element := "fire" if src_kind == TowerData.Kind.FLAME else ""
	e.take_damage(dmg, is_crit, show_num, element)
	_apply_effects(e)
	# 火电联动：喷火塔命中「被闪电塔感电」的目标 → 引爆一次小范围爆炸
	if src_kind == TowerData.Kind.FLAME and e.has_method("consume_shock") and e.consume_shock():
		_shock_blast(e)
	if mult > 1.0:
		_synergy_fx(e)


## 冰火两重天：喷火塔打「正被冰塔减速（结霜）」的敌人时伤害提高
func _synergy_multiplier(e) -> float:
	if src_kind != TowerData.Kind.FLAME:
		return 1.0
	if e == null or not is_instance_valid(e):
		return 1.0
	if e.has_method("is_chilled") and e.is_chilled():
		# 融化反应：基础加成 + 强化卡「熔核共鸣 / 元素共鸣」的额外加成
		return 1.0 + float(TowerData.CHILL_DMG_BONUS) + float(GameState.buffs.get("melt_dmg", 0.0))
	return 1.0


## 联动命中的视觉反馈：一小团白蓝色蒸汽（冰遇火升华），不飘字避免刷屏
func _synergy_fx(e) -> void:
	if e == null or not is_instance_valid(e):
		return
	Fx.flash(get_parent(), e.global_position + Vector3(0.0, 0.65, 0.0), Color(0.80, 0.95, 1.0), 0.42, 0.16)


## 火电联动爆炸：以被引爆的敌人为中心，对周围敌人造成一次小范围伤害。
## 这里直接调 take_damage（而不是再造一发子弹），所以不会无限连锁引爆。
func _shock_blast(center) -> void:
	if center == null or not is_instance_valid(center):
		return
	var cpos: Vector3 = center.global_position
	var radius := float(TowerData.SHOCK_BLAST_RADIUS)
	# 超载反应：基础 1.4 倍 + 强化卡「过载增幅 / 元素共鸣」的额外倍率
	var blast_mult := float(TowerData.SHOCK_BLAST_MULT) + float(GameState.buffs.get("overload_dmg", 0.0))
	var blast_dmg := damage * (2.0 if is_crit else 1.0) * blast_mult
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == null or not is_instance_valid(other) or other == center:
			continue
		if other.global_position.distance_to(cpos) <= radius:
			# 火电联动的爆炸同样是火：对冰甲一样是双倍以上削甲
			other.take_damage(blast_dmg, false, false, "fire")
	var parent := get_parent()
	if parent != null:
		# 复用炮塔那套爆炸素材，尺寸跟着爆炸半径走，暴击再大一号
		var sz: float = radius * 1.6 + (0.5 if is_crit else 0.0)
		Fx.burst(parent, cpos + Vector3(0.0, 0.5, 0.0), "fx_explosion", sz, 0.42)
		Fx.flash(parent, cpos + Vector3(0.0, 0.6, 0.0), Color(1.0, 0.55, 0.18), radius * 0.7, 0.22)
		Fx.ring(parent, cpos + Vector3(0.0, 0.3, 0.0), Color(1.0, 0.42, 0.12), radius, 0.34)
	Sound.play("explosion")


## 命中的附带效果：灼烧、感电，加上所有攻击共用的「减速 + 弹药词条」
func _apply_effects(e) -> void:
	if dot > 0.0:
		e.apply_dot(dot, 2.0)
	# 闪电塔：链式闪电的每一跳都会给目标挂感电，等喷火塔来引爆
	if src_kind == TowerData.Kind.TESLA and e.has_method("apply_shock"):
		e.apply_shock(float(TowerData.SHOCK_TIME))
	apply_on_hit_status(e, slow, slow_time)


## 所有攻击路径共用的「减速 + 弹药词条」结算：减速、中毒、流血、破甲、易伤。
## 数值全部存在 GameState.buffs 里（卡牌给的是「所有塔的子弹」），所以箭塔、炮塔、
## 链式闪电的每一跳、以及**冰塔的持续射线**都必须走这里，效果才不会有第二条实现。
static func apply_on_hit_status(e, slw: float, slw_time: float) -> void:
	if e == null or not is_instance_valid(e):
		return
	if slw > 0.0:
		e.apply_slow(slw, slw_time)
	# 「淬毒弹头 / 放血锋刃」：拿过卡之后所有攻击都带毒 / 带流血
	var poison := float(GameState.buffs.get("poison_dps", 0.0))
	if poison > 0.0 and e.has_method("apply_poison"):
		e.apply_poison(poison, float(GameState.buffs.get("poison_time", 3.0)))
	var bleed := float(GameState.buffs.get("bleed_dps", 0.0))
	if bleed > 0.0 and e.has_method("apply_bleed"):
		e.apply_bleed(bleed, float(GameState.buffs.get("bleed_time", 2.5)))
	# 「破甲弹头 / 易伤标记」：削护甲 / 加易伤，从**下一次**命中开始生效
	var brk := float(GameState.buffs.get("armor_break", 0.0))
	if brk > 0.0 and e.has_method("apply_armor_break"):
		e.apply_armor_break(brk, 3.0)
	var vuln := float(GameState.buffs.get("vuln", 0.0))
	if vuln > 0.0 and e.has_method("apply_vuln"):
		e.apply_vuln(vuln, 3.0)


## 找 from 附近、未命中、且在 radius 内最近的敌人
func _nearest_enemy_except(from: Node3D, radius: float):
	var best = null
	var best_d := radius * radius
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e):
			continue
		if _hit_targets.has(e):
			continue
		var d := from.global_position.distance_squared_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _spawn_flash(pos: Vector3) -> void:
	# 炮塔命中：放素材里的那团「烟 + 火花」（res://textures/fx_explosion.png）。
	# 二级及以上换成更炸的「碎石 + 浓烟」版（fx_explosion_l2.png），没放图就沿用一级那张。
	# 变异「攻城巨炮」再换成 9 帧序列（fx_siege_0…8：落石 → 聚拢 → 爆燃）。
	# 尺寸跟着溅射半径走，暴击再大一号；都没图就退回去用纯色光球。
	# 毒瓶：落地砸出一滩毒液（这一下才是毒瓶塔的主要伤害来源）
	if src_kind == TowerData.Kind.POISON:
		_spawn_poison(pos)
		return

	if src_kind == TowerData.Kind.CANNON:
		var sz: float = 2.0 + splash * 0.55 + (0.6 if is_crit else 0.0)
		# 变异「震地雷」：落地炸出一个泥潭，踩进去的敌人才会减速
		if src_mutation == "cannon_quake":
			_spawn_mud(pos)
		if src_mutation == "cannon_heavy":
			# 攻城巨炮是「一炮清场」的重击，爆炸再放大 1.9 倍才压得住
			if Fx.burst_seq(get_parent(), pos, "fx_siege", 9, sz * 1.9, 0.62):
				return
		var slot := "fx_explosion"
		if src_level >= 2 and TextureLib.has("fx_explosion_l2"):
			slot = "fx_explosion_l2"
		if Fx.burst(get_parent(), pos, slot, sz, 0.40):
			return

	var flash := MeshInstance3D.new()
	var r: float = maxf(splash, 0.45) * 0.6
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	flash.mesh = m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.80, 0.40, 0.7) if not is_crit else Color(1.0, 0.35, 0.35, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.material_override = mat
	get_parent().add_child(flash)
	flash.global_position = pos
	var tw := flash.create_tween()
	tw.tween_property(flash, "scale", Vector3(1.6, 1.6, 1.6), 0.16)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.16)
	tw.tween_callback(flash.queue_free)


## 震地雷的泥潭：命中点在地面上铺一块会减速的区域。
## 高度不能用「命中点 - 0.7」反推：敌人恒在 SURFACE_Y 上走，而路面本身抬了 0.06
## （桥上还要再拱 0.08），压在 0.85 的泥潭会被路面整个埋掉 —— 看起来就像「有时候没生成」。
## 统一抬到 SURFACE_Y 之上一点点，和路面流动箭头（FLOW_Y）同一量级。
## 毒瓶落地：在原地铺一滩毒液。
## 高度同样不能从命中点反推（敌人恒在 SURFACE_Y 上，路面还抬了 0.06），
## 和泥潭一样统一压在 SURFACE_Y + 0.16，否则毒池会被路面埋掉，看起来像「有时候没生成」。
func _spawn_poison(pos: Vector3) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var at := Vector3(pos.x, GameGrid.SURFACE_Y + 0.16, pos.z)
	var pool := PoisonPool.new()
	pool.name = "PoisonPool"
	parent.add_child(pool)
	# 毒池半径直接跟这发子弹的溅射走：升级 / 变异 / 卡牌让它变大时会一起变大
	pool.setup(at, maxf(splash, float(TowerData.POISON_POOL_MIN_R)), dot)
	Fx.flash(parent, pos, Color(0.55, 1.0, 0.32), 0.65, 0.20)
	Fx.ring(parent, at, Color(0.42, 0.98, 0.28), maxf(splash, 1.4), 0.34)


func _spawn_mud(pos: Vector3) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var mud := MudPit.new()
	mud.name = "MudPit"
	parent.add_child(mud)
	mud.setup(Vector3(pos.x, GameGrid.SURFACE_Y + 0.16, pos.z))
