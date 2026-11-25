class_name Snowball
extends Node3D
## 雪人王的雪球：抛物线飞向一座炮塔，命中后给那座塔挂「攻速下降」。
##
## 为什么不复用 Bullet：Bullet 是打**敌人**的（找 "enemies" 组、结算护甲 / 易伤 / 溅射 / 暴击），
## 而这里的目标是**塔**、结算的是塔身上的攻速倍率 —— 两套目标与规则完全不同，
## 硬塞进 Bullet 只会让命中逻辑到处 `if 目标是塔`。单独一个小节点最省事：
## 飞行 + 到达后调用 `tower.chill()`，释放交给自己。
##
## 数值（间隔 / 射程 / 减速比例 / 持续时间 / 飞行速度 / 抛物线高度）全在 EnemyData 的
## SNOWBALL_* 常量里，这里只负责表现与落点结算。

var slow: float = 0.35          # 攻速下降比例（0.35 = 攻速 ×0.65）
var time: float = 5.0           # 持续秒数
var _target = null              # 目标塔（可能在飞行途中被卖掉）
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _dur: float = 0.4           # 飞行时长（按距离 / 速度算）
var _t: float = 0.0
var _done: bool = false


## 由 Enemy 调用：锁定目标、算出落点与飞行时长
func launch(tower, from: Vector3, slow_ratio: float, dur: float) -> void:
	_target = tower
	slow = slow_ratio
	time = dur
	_from = from
	# 瞄准塔身中段而不是塔顶：塔顶是炮塔 / 水晶，看起来像「没砸中」
	var aim_y := 0.9
	if tower != null and "muzzle_y" in tower:
		aim_y = float(tower.muzzle_y) * 0.55
	_to = tower.global_position + Vector3(0.0, aim_y, 0.0)
	var dist := _from.distance_to(_to)
	_dur = clampf(dist / float(EnemyData.SNOWBALL_SPEED), 0.18, 1.20)
	_t = 0.0
	global_position = _from
	_build_mesh()


func _build_mesh() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Ball"
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	sm.radial_segments = 10
	sm.rings = 6
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.94, 0.98, 1.0)
	m.roughness = 0.9
	m.emission_enabled = true
	m.emission = Color(0.55, 0.82, 1.0)
	m.emission_energy_multiplier = 0.45
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _process(delta: float) -> void:
	if _done or not GameState.running:
		# 暂停 / 波间休整：雪球停在空中，不会趁暂停砸塔
		return
	_t += delta
	var k := clampf(_t / _dur, 0.0, 1.0)
	# 抛物线：水平线性插值 + 竖直方向一个 sin 拱
	global_position = _from.lerp(_to, k) + Vector3(0.0, sin(k * PI) * float(EnemyData.SNOWBALL_ARC), 0.0)
	if k >= 1.0:
		_hit()


func _hit() -> void:
	_done = true
	var parent := get_parent()
	# 塔在飞行途中被卖掉 / 被拆：只放一团雪雾，不结算
	if _target != null and is_instance_valid(_target) and _target.has_method("chill"):
		_target.chill(slow, time)
		if parent != null:
			Fx.flash(parent, _to, Color(0.78, 0.94, 1.0), 0.9, 0.26)
			Fx.ring(parent, _to, Color(0.82, 0.96, 1.0), 1.1, 0.3)
	else:
		if parent != null:
			Fx.flash(parent, global_position, Color(0.85, 0.95, 1.0), 0.6, 0.22)
	queue_free()
