extends Node3D
## 主控制器：搭建 2.5D 场景、处理鼠标交互（建造 / 选中升级 / 面板出售）、驱动波次与 Roguelike 三选一。

# 相机（可平移 + 缩放）
var cam: Camera3D
var cam_target := Vector3.ZERO     # 视野中心
var cam_height := 24.0
var cam_back := 20.0
var cam_fov := 55.0
var panning := false
var _last_mouse := Vector2.ZERO
var _pan_anchor := Vector3.ZERO
var left_panning := false       # 左键在空白处按住（可能用于平移视角）
var left_dragging := false      # 左键已进入“拖动视角”模式
var _left_anchor := Vector3.ZERO
var _left_press_pos := Vector2.ZERO

## 「复利存款」卡的单波利息上限：不设上限时，后期本金一大，利息会自我滚雪球，
## 金币直接失去意义（也正是「后期不缺钱」的主要来源之一）。
const INTEREST_CAP := 150

const CAM_MIN_H := 9.0
const CAM_MAX_H := 48.0
const CAM_BACK_RATIO := 18.0 / 21.0
const PAN_SPEED := 22.0     # 键盘平移速度（世界单位/秒）
const ZOOM_STEP := 1.15     # 每格滚轮缩放倍率

var grid: GameGrid
var towers_root: Node3D
var enemies_root: Node3D
var ui: GameUI

var hover_cell: Vector2i = Vector2i(-1, -1)
var hover_marker: MeshInstance3D
var hover_mat: StandardMaterial3D

var hover_tower = null                 # 鼠标悬停的塔（临时显示它的射程圈）
var range_preview: Node3D              # 建造模式：悬停格上「将要造的塔」的射程预览
var range_preview_mat: StandardMaterial3D
var range_preview_edge_mat: StandardMaterial3D

var build_kind: int = -1          # -1 表示未选择建造类型
var selected = null               # 当前选中的塔

var wave_active: bool = false
var spawn_queue: Array = []
var spawn_timer: float = 0.0
var spawn_cursor: int = 0
var taken_cards := {}
var game_over: bool = false
var won: bool = false
var endless: bool = false
var _last_lives: int = 9999
var game_speed := 1.0           # 游戏速度倍率（1x / 2x）
var _wave_kills_start: int = 0
var _wave_leaks_start: int = 0
var _preview_wave: int = -1        # 缓存的「下一波预告」对应波次
var _preview_text: String = ""     # 缓存的预告文本（避免每帧重建数组 + 洗牌）
var _info_hold: float = 0.0        # >0 时暂停 _update_info 覆盖，用于显示一次性提示
var _pending_unlock_msg: String = ""  # 波次结束后待提示的「新解锁」信息（等卡牌面板关掉再显示）
var _fullscreen: bool = false

# ---------------------------------------------------------------- 初始化

func _ready() -> void:
	randomize()
	GameState.reset()
	GameState.load_save()
	Fx.reset_counters()
	_last_lives = GameState.lives
	_fullscreen = DisplayServer.window_get_mode(get_window().get_window_id()) == DisplayServer.WINDOW_MODE_FULLSCREEN
	process_mode = Node.PROCESS_MODE_ALWAYS   # 暂停时仍可操作相机 / 切换暂停

	_build_environment()
	_build_camera()
	_build_lights()

	grid = GameGrid.new()
	grid.name = "Grid"
	add_child(grid)

	# 注意：Main 本身是 PROCESS_MODE_ALWAYS（暂停时还要处理相机 / ESC），
	# 所以子节点默认会跟着一直跑。战斗相关的两个子树必须显式改成 PAUSABLE，
	# 否则暂停时塔还在射击、敌人还在走、子弹还在飞。
	towers_root = Node3D.new()
	towers_root.name = "Towers"
	towers_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(towers_root)

	enemies_root = Node3D.new()
	enemies_root.name = "Enemies"
	enemies_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(enemies_root)

	_build_hover_marker()
	_build_range_preview()

	ui = GameUI.new()
	ui.name = "UI"
	add_child(ui)
	ui.setup(self)

	GameState.gold_changed.connect(_on_stat_changed)
	GameState.lives_changed.connect(_on_lives_changed)
	GameState.wave_changed.connect(_on_stat_changed)

	ui.refresh()

	var slots := TextureLib.slot_list()
	if slots.size() > 0:
		print("[TextureLib] 已加载贴图: ", ", ".join(slots))
	else:
		print("[TextureLib] textures/ 为空，使用程序化外观（丢图进 res://textures/ 即可自动替换）")
	var missing := TextureLib.missing_slots()
	if missing.size() > 0:
		print("[TextureLib] 还缺 %d 个槽位: %s（同名图片放进 res://textures/ 即生效）" % [missing.size(), ", ".join(missing)])











func _on_stat_changed(_v: int) -> void:
	if ui != null:
		ui.refresh()


func _build_environment() -> void:
	var env := Environment.new()

	# 可选天空贴图：res://textures/sky.png（等距柱状投影 / Equirectangular 全景图）
	var sky_tex := TextureLib.get_texture("sky")
	if sky_tex != null:
		var sky_mat := PanoramaSkyMaterial.new()
		sky_mat.panorama = sky_tex
		var sky := Sky.new()
		sky.sky_material = sky_mat
		env.background_mode = Environment.BG_SKY
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 1.0
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.045, 0.055, 0.085)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.34, 0.42, 0.60)
		env.ambient_light_energy = 0.65

	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.08
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.4

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)


func _build_camera() -> void:
	cam = Camera3D.new()
	cam.name = "Camera3D"
	add_child(cam)
	cam.fov = cam_fov
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	# 按地图尺寸自适应高度，保证开局能看到全图
	var w := GameGrid.COLS * GameGrid.CELL
	var d := GameGrid.ROWS * GameGrid.CELL
	cam_height = maxf(w, d) * 0.75
	cam_back = cam_height * CAM_BACK_RATIO
	cam_target = Vector3.ZERO
	_apply_camera()


func _apply_camera() -> void:
	cam.position = cam_target + Vector3(0.0, cam_height, cam_back)
	cam.look_at(cam_target, Vector3.UP)


## 滚轮缩放：factor > 1 放大画面（降低高度），factor < 1 缩小（拉高）
func _zoom(factor: float) -> void:
	cam_height = clampf(cam_height * factor, CAM_MIN_H, CAM_MAX_H)
	cam_back = cam_height * CAM_BACK_RATIO
	_apply_camera()


## 中键拖拽平移：把「按下时的地面点」与「当前地面点」的差平移给相机中心
func _on_middle_press(pos: Vector2) -> void:
	panning = true
	_pan_anchor = _mouse_world(pos)


func _on_middle_drag(pos: Vector2) -> void:
	var p := _mouse_world(pos)
	cam_target += _pan_anchor - p
	_pan_anchor = p
	_apply_camera()


## WASD / 方向键平移：相机始终朝 -Z、向右 +X，直接映射到世界轴
func _update_camera_pan(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1.0
	if move == Vector2.ZERO:
		return
	move = move.normalized()
	cam_target.x += move.x * PAN_SPEED * delta
	cam_target.z += move.y * PAN_SPEED * delta
	_apply_camera()


func _build_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	add_child(sun)
	sun.rotation_degrees = Vector3(-58.0, 32.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0

	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	add_child(fill)
	fill.rotation_degrees = Vector3(-35.0, -140.0, 0.0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.6, 0.7, 1.0)


func _build_hover_marker() -> void:
	hover_marker = MeshInstance3D.new()
	hover_marker.name = "HoverMarker"
	var m := PlaneMesh.new()
	m.size = Vector2(GameGrid.CELL * 0.9, GameGrid.CELL * 0.9)
	hover_marker.mesh = m
	# PlaneMesh 在 Godot 4 里已经是水平的，不需要再旋转
	hover_mat = StandardMaterial3D.new()
	hover_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hover_mat.albedo_color = Color(0.35, 1.0, 0.55, 0.35)
	hover_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hover_marker.material_override = hover_mat
	hover_marker.visible = false
	add_child(hover_marker)


## 选好塔类型后，在鼠标格上画一个「射程预览圈」，建之前就能看清能打到哪
func _build_range_preview() -> void:
	range_preview = Node3D.new()
	range_preview.name = "RangePreview"
	range_preview.visible = false
	add_child(range_preview)

	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.02
	cm.radial_segments = 48
	disc.mesh = cm
	range_preview_mat = StandardMaterial3D.new()
	range_preview_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	range_preview_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	range_preview_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	range_preview_mat.albedo_color = Color(0.35, 1.0, 0.55, 0.14)
	disc.material_override = range_preview_mat
	disc.position.y = 0.12
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	range_preview.add_child(disc)

	var edge := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.98
	tm.outer_radius = 1.0
	tm.rings = 56
	tm.ring_segments = 6
	edge.mesh = tm
	range_preview_edge_mat = StandardMaterial3D.new()
	range_preview_edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	range_preview_edge_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	range_preview_edge_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	range_preview_edge_mat.albedo_color = Color(0.45, 1.0, 0.65, 0.65)
	edge.material_override = range_preview_edge_mat
	edge.position.y = 0.13
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	range_preview.add_child(edge)

# ---------------------------------------------------------------- 输入

## F11 / Alt+Enter 切换全屏
func _toggle_fullscreen() -> void:
	_fullscreen = not _fullscreen
	var wid := get_window().get_window_id()
	if _fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN, wid)
	else:
		# 切回窗口：恢复成 1600×900 并居中，和全屏有明显区别
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED, wid)
		var target := Vector2i(1600, 900)
		var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen(wid))
		DisplayServer.window_set_size(target, wid)
		DisplayServer.window_set_position(Vector2i((screen.x - target.x) / 2, (screen.y - target.y) / 2), wid)
	print("[Main] 全屏切换 -> ", "全屏" if _fullscreen else "窗口")


## 切换暂停
func toggle_pause() -> void:
	if game_over:
		return
	var p := not get_tree().paused
	get_tree().paused = p
	if ui != null:
		ui.show_pause(p)


## 切换 1x / 2x 游戏速度
func toggle_speed() -> void:
	game_speed = 2.0 if game_speed < 1.5 else 1.0
	Engine.time_scale = game_speed
	if ui != null:
		ui.update_speed(game_speed)


func _unhandled_input(event: InputEvent) -> void:
	# 图鉴 / 卡牌 / 结算 / 暂停 / 变异这些全屏面板打开时，鼠标事件一律不再带动地图：
	# 否则在图鉴里滚列表的同时镜头也会缩放（滚轮事件没被某个 Control accept 时
	# 会一路漏到 _unhandled_input）。键盘仍然照常处理，ESC 才能关面板。
	if ui != null and ui.is_modal_open() and event is InputEventMouse:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# 相机控制：中键拖拽 + 滚轮缩放（任何时候都可用）
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_on_middle_press(mb.position)
			else:
				panning = false
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom(1.0 / ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom(ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			# 左键：空白处按住拖动平移视角；点击=建造/选塔/取消（内部区分 game_over）
			if mb.pressed:
				_on_left_press()
			else:
				_on_left_release()
		elif not game_over:
			# 右键：只用来取消建造（出售已改为塔面板上的按钮，防止误点拆塔）
			if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
				_on_right_press()
	elif event is InputEventMouseMotion:
		if panning:
			_on_middle_drag(event.position)
		elif left_panning:
			_on_left_drag(event.position)
		elif not game_over:
			_update_hover(event.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11 or event.physical_keycode == KEY_F11:
			_toggle_fullscreen()
		elif event.keycode == KEY_ENTER and event.alt_pressed:
			_toggle_fullscreen()
		elif event.keycode == KEY_ESCAPE:
			if ui != null and ui.mutation_visible():
				ui.hide_mutations()
			elif ui != null and ui.codex_visible():
				ui.hide_codex()
			elif build_kind >= 0:
				set_build_kind(-1)
			else:
				toggle_pause()
		elif event.keycode == KEY_Q:
			if selected != null and is_instance_valid(selected):
				selected.cycle_priority()
				if ui != null:
					ui.set_info(selected.info_text())
				Sound.play("click")
		elif event.keycode == KEY_U:
			upgrade_selected()
		elif event.keycode == KEY_P:
			# 变异三选一自己会暂停游戏，此时再按 P 会在弹窗背后把战场放开，直接忽略
			if ui == null or not ui.mutation_visible():
				toggle_pause()
		elif event.keycode == KEY_F:
			toggle_speed()


func _mouse_world(screen_pos: Vector2) -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.ZERO
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var hit = Plane(Vector3.UP, GameGrid.SURFACE_Y).intersects_ray(from, dir)
	if hit == null:
		return Vector3.ZERO
	return Vector3(hit)


func _update_hover(screen_pos: Vector2) -> void:
	var p := _mouse_world(screen_pos)
	var c := grid.world_to_cell(p)
	# 鼠标压在某座塔上时，临时显示它的射程圈
	_set_hover_tower(_tower_at_world(p) if grid.in_bounds(c) else null)
	if grid.in_bounds(c):
		hover_cell = c
		hover_marker.visible = true
		# 抬起 0.10：高于路面（路面顶在 SURFACE_Y + 0.09），否则悬停在路格上会被路面盖住
		hover_marker.global_position = grid.cell_to_world(c) + Vector3(0.0, 0.10, 0.0)
		var ok: bool = build_kind >= 0 and grid.can_place(c) and GameState.gold >= int(Tower.DATA[build_kind]["cost"])
		if build_kind >= 0:
			hover_mat.albedo_color = Color(0.35, 1.0, 0.55, 0.35) if ok else Color(1.0, 0.35, 0.35, 0.28)
		else:
			# 没在建造时：布防台高亮成蓝色，普通格子只给一层很淡的白，避免满地红灯
			hover_mat.albedo_color = Color(0.45, 0.85, 1.0, 0.22) if grid.is_build_slot(c) else Color(1.0, 1.0, 1.0, 0.08)
		_update_range_preview(c, ok)
	else:
		hover_cell = Vector2i(-1, -1)
		hover_marker.visible = false
		_update_range_preview(c, false)


## 切换「当前悬停的塔」，把上一座的射程圈关掉
func _set_hover_tower(t) -> void:
	if hover_tower == t:
		return
	if hover_tower != null and is_instance_valid(hover_tower):
		hover_tower.set_hovered(false)
	hover_tower = t
	if hover_tower != null and is_instance_valid(hover_tower):
		hover_tower.set_hovered(true)


## 建造模式下：在鼠标格上预览所选塔的射程（绿色可建 / 红色不可建）
func _update_range_preview(c: Vector2i, ok: bool) -> void:
	if range_preview == null:
		return
	if build_kind < 0 or not grid.in_bounds(c):
		range_preview.visible = false
		return
	var r: float = float(Tower.DATA[build_kind]["range"]) * float(GameState.buffs["range"])
	range_preview.visible = true
	range_preview.global_position = grid.cell_to_world(c)
	range_preview.scale = Vector3(r, 1.0, r)
	var col := Color(0.35, 1.0, 0.55) if ok else Color(1.0, 0.35, 0.35)
	range_preview_mat.albedo_color = Color(col.r, col.g, col.b, 0.14)
	range_preview_edge_mat.albedo_color = Color(col.r, col.g, col.b, 0.65)


func _tower_at_world(p: Vector3):
	var c := grid.world_to_cell(p)
	return grid.tower_at(c)


func _on_left_press() -> void:
	var mp := get_viewport().get_mouse_position()
	var p := _mouse_world(mp)
	var c := grid.world_to_cell(p)

	if game_over:
		# 游戏结束：左键只用于平移视角
		left_panning = true
		left_dragging = false
		_left_press_pos = mp
		_left_anchor = p
		return

	if build_kind >= 0:
		var existing = grid.tower_at(c) if grid.in_bounds(c) else null
		if existing != null and is_instance_valid(existing):
			# 建造模式下点到已有的塔：退出建造，改为选中它（弹出升级 / 出售）
			set_build_kind(-1)
		elif grid.in_bounds(c) and grid.can_place(c):
			# 左键点蓝色布防台就是建造（保持建造模式，可以连续放置）
			_try_build(c)
			return
		else:
			# 不合法位置：按住可以拖动平移，单击（没拖动）= 取消建造
			left_panning = true
			left_dragging = false
			_left_press_pos = mp
			_left_anchor = p
			return

	var t = _tower_at_world(p)
	if t != null:
		# 塔上按下：选中 + 弹出升级 / 出售面板
		_clear_selection()
		selected = t
		t.set_selected(true)
		if ui != null:
			ui.show_tower_popup(t)
			ui.set_info(t.info_text())
	else:
		# 空白处按下：可平移视角
		_clear_selection()
		left_panning = true
		left_dragging = false
		_left_press_pos = mp
		_left_anchor = p


## 左键在空白处拖动：超过阈值后进入平移视角模式
func _on_left_drag(pos: Vector2) -> void:
	if not left_panning:
		return
	if not left_dragging:
		if _left_press_pos.distance_to(pos) < 5.0:
			return
		left_dragging = true
	var p := _mouse_world(pos)
	cam_target += _left_anchor - p
	_left_anchor = p
	_apply_camera()


func _on_left_release() -> void:
	if left_panning:
		left_panning = false
		var was_drag := left_dragging
		left_dragging = false
		if not was_drag and build_kind >= 0:
			# 建造模式下左键点击（没拖动）= 取消建造
			set_build_kind(-1)


func _on_right_press() -> void:
	# 右键只用于取消建造（出售已收归塔面板里的「出售」按钮，避免误点拆塔）
	if build_kind >= 0:
		set_build_kind(-1)


## 左键建造入口：金币够就放塔，不够就提示，不改变当前建造类型（可连续放置）
func _try_build(c: Vector2i) -> void:
	if build_kind < 0:
		return
	# 兜底：跳波等操作后可能残留一个「已重新上锁」的建造类型
	if not Tower.is_unlocked(build_kind):
		set_build_kind(-1)
		Sound.play("click")
		return
	var d: Dictionary = Tower.DATA[build_kind]
	var cost := int(d["cost"])
	if not GameState.spend(cost):
		Sound.play("click")
		_flash_info("金币不足：建造 %s 需要 %d 金（还差 %d）" % [d["name"], cost, cost - GameState.gold])
		return
	_place_tower(build_kind, c)
	_update_hover(get_viewport().get_mouse_position())


func _clear_selection() -> void:
	if selected != null and is_instance_valid(selected):
		selected.set_selected(false)
	selected = null
	if hover_tower != null and is_instance_valid(hover_tower):
		hover_tower.set_hovered(false)
	hover_tower = null
	if range_preview != null:
		range_preview.visible = false
	if ui != null:
		ui.hide_tower_popup()

# ---------------------------------------------------------------- 建造 / 出售

func _place_tower(k: int, c: Vector2i) -> void:
	var t := Tower.new()
	towers_root.add_child(t)
	t.setup(k, c)
	grid.set_blocked(c, true)
	grid.towers[grid.idx(c)] = t
	grid.refresh()
	_repath_all()
	Sound.play("place")
	Fx.flash(towers_root, t.global_position, Color(0.5, 1.0, 0.7), 0.5, 0.22)


func _sell(t) -> void:
	if t == null or not is_instance_valid(t):
		return
	var pos: Vector3 = t.global_position
	# 返还比例基础 50%，「废料回收」卡会往上加（封顶 90%，免得卖塔变成套利）
	var refund := clampf(float(GameState.buffs.get("refund", 0.5)), 0.0, 0.9)
	GameState.add_gold(int(float(t.value) * refund))
	grid.towers.erase(grid.idx(t.cell))
	grid.set_blocked(t.cell, false)
	t.queue_free()
	grid.refresh()
	_repath_all()
	Sound.play("sell")
	Fx.flash(towers_root, pos, Color(0.5, 0.6, 1.0), 0.4, 0.2)


func _repath_all() -> void:
	# 固定路线：建塔 / 出售不会改变敌人行进路线，无需重新寻路
	pass


func refresh_towers() -> void:
	for t in grid.towers.values():
		if t != null and is_instance_valid(t):
			t.recalc_and_rebuild()


## 花金币给当前选中的塔升一级（U 键 / 信息面板「升级」按钮）
func upgrade_selected() -> void:
	var t = selected
	if t == null or not is_instance_valid(t):
		return
	var cost: int = t.upgrade_cost()
	if cost < 0:
		# 满级了：还没变异就弹出三选一，已变异则只是提示
		if t.can_mutate():
			open_mutation_panel()
		else:
			_flash_info("已达最高等级 Lv.%d（已变异）" % Tower.MAX_LEVEL)
		return
	if not GameState.spend(cost):
		Sound.play("click")
		_flash_info("金币不足：升级需要 %d 金（还差 %d）" % [cost, cost - GameState.gold])
		return
	t.value += cost
	t.level_up()
	Sound.play("levelup")
	Fx.flash(towers_root, t.global_position, Color(0.55, 0.90, 1.0), 0.6, 0.25)
	Fx.ring(towers_root, t.global_position, Color(0.55, 0.90, 1.0), 0.5, 0.30)
	if ui != null:
		ui.set_info(t.info_text())
	if t.can_mutate():
		# 刚升到满级：直接把玩家的注意力引到「变异」上，别让他们以为没得升了
		_flash_info("已升到 Lv.%d 满级 —— 点浮窗「变异」选择最终形态" % Tower.MAX_LEVEL)


## 满级塔的「变异」入口：打开三选一面板。
## 面板打开时会暂停游戏（见 GameUI.show_mutations），关掉 / 选完由 UI 恢复暂停状态。
func open_mutation_panel() -> void:
	var t = selected
	if t == null or not is_instance_valid(t):
		return
	if not t.can_mutate():
		_flash_info("这座塔已经变异过了")
		return
	var mc: int = t.mutation_cost()
	if mc > 0 and GameState.gold < mc:
		Sound.play("click")
		_flash_info("变异需要 %d 金（还差 %d）" % [mc, mc - GameState.gold])
		return
	if ui != null:
		ui.show_mutations(t, Tower.mutations_for(t.kind))


## 玩家在变异面板里选定了方向 —— 一次性生效，之后不能再改
func apply_mutation(id: String) -> void:
	var t = selected
	if t == null or not is_instance_valid(t):
		return
	if not t.can_mutate():
		return
	var mc: int = t.mutation_cost()
	if mc < 0:
		return
	if not GameState.spend(mc):
		Sound.play("click")
		_flash_info("金币不足：变异需要 %d 金" % mc)
		return
	t.apply_mutation(id)
	t.value += mc          # 计入投入，出售时按比例返还
	var md: Dictionary = t.mutation_def()
	if md.is_empty():
		return
	var tint: Color = md["tint"]
	Sound.play("levelup")
	Fx.flash(towers_root, t.global_position, tint, 0.9, 0.4)
	Fx.ring(towers_root, t.global_position, tint, 0.7, 0.45)
	if ui != null:
		ui.show_tower_popup(t)
	_flash_info("%s 变异为「%s」" % [str(Tower.DATA[t.kind]["name"]), str(md["name"])])


## 出售当前选中的塔（信息面板「出售」按钮）
func sell_selected() -> void:
	var t = selected
	if t == null or not is_instance_valid(t):
		return
	_clear_selection()
	_sell(t)


## 在信息面板上短暂显示一条提示（避免被每帧刷新的 _update_info 立刻覆盖）
func _flash_info(text: String) -> void:
	_info_hold = 1.4
	if ui != null:
		ui.set_info(text)


func upgrade_random_tower() -> void:
	var pool: Array = []
	for t in grid.towers.values():
		if t != null and is_instance_valid(t) and int(t.level) < Tower.MAX_LEVEL:
			pool.append(t)
	if pool.size() == 0:
		return
	pool.pick_random().level_up()


func set_build_kind(k: int) -> void:
	# 未解锁的塔不能选（商店按钮本身已禁用，这里再兜一层）
	if k >= 0 and not Tower.is_unlocked(k):
		var d: Dictionary = Tower.DATA[k]
		_flash_info("%s 尚未解锁：第 %d 波开放" % [d["name"], Tower.unlock_wave(k)])
		return
	if build_kind == k:
		build_kind = -1
	else:
		build_kind = k
	if ui != null:
		ui.update_shop_highlight(build_kind)
		_update_hover(get_viewport().get_mouse_position())

# ---------------------------------------------------------------- 波次

func start_wave() -> void:
	if wave_active or game_over:
		return
	# 先标记「战斗中」再改波次：set_wave 会触发 UI 刷新，
	# 这样商店按「当前波」而不是「下一波」判断解锁，避免按钮提前亮起。
	wave_active = true
	GameState.wave_active = true
	GameState.set_wave(GameState.wave + 1)
	_wave_kills_start = GameState.total_kills
	_wave_leaks_start = GameState.total_leaks
	spawn_queue = Waves.plan(GameState.wave)
	spawn_timer = 0.7
	spawn_cursor = randi()
	_clear_selection()
	ui.set_wave_busy(true)
	Sound.play("wave")


func _spawn_next() -> void:
	if spawn_queue.is_empty():
		return
	# 固定路线：两条 lane 各有一个入口（右上 / 右下），出怪时交替走两条线，
	# 保证每一波都能同时压两边，玩家必须分兵防守。
	var spawns := grid.reachable_spawns()
	if spawns.is_empty():
		return
	var k: int = spawn_queue.pop_front()
	# 大部分时候两条线交替出怪（保证两边都有人压），偶尔连发同一侧，制造「一边倒」的冲锋
	if spawns.size() > 1 and randf() > 0.25:
		spawn_cursor += 1
	var c: Vector2i = spawns[spawn_cursor % spawns.size()]
	var e := Enemy.new()
	enemies_root.add_child(e)
	e.spawn(k, grid.spawn_world_for(c), grid.path_home_world_from(c), Waves.hp_scale(GameState.wave), GameState.wave)
	# 首领登场：信息面板闪现提示，玩家不会漏看
	if k == Enemy.Kind.BOSS:
		_flash_info("大首领出现了！会放压制脉冲让周围塔熄火，半血后狂暴并召唤援军 —— 别把防线堆在它身边")
		Sound.play("wave")
	elif k == Enemy.Kind.MINI_BOSS:
		_flash_info("小首领出现了！战吼会给周围小怪加速，半血召唤援军 —— 先集火它")
		Sound.play("wave")


func _end_wave() -> void:
	wave_active = false
	GameState.wave_active = false
	# 波间休整时刷新一次商店：这一波结束后新解锁的塔要立刻可点
	if ui != null:
		ui.refresh()

	# 波间收入 = 固定金币卡 + 利息（利息部分要封顶，否则本金越大利息越多，越到后期越不缺钱）
	var interest := mini(int(float(GameState.gold) * float(GameState.buffs["interest"])), INTEREST_CAP)
	var bonus := int(GameState.buffs["gold_wave"]) + interest
	if bonus > 0:
		GameState.add_gold(bonus)

	# 「守夜人」：每波结束回复生命（最多不超过开局上限，避免无限叠甲）
	var regen := int(GameState.buffs.get("life_regen", 0))
	if regen > 0 and GameState.lives < GameState.START_LIVES:
		GameState.lives = mini(GameState.lives + regen, maxi(GameState.START_LIVES, GameState.lives))
		GameState.lives_changed.emit(GameState.lives)

	var kills := GameState.total_kills - _wave_kills_start
	var leaks := GameState.total_leaks - _wave_leaks_start

	if GameState.wave == Waves.TOTAL and not endless:
		won = true
		game_over = true
		GameState.running = false
		GameState.best_wave = maxi(GameState.best_wave, GameState.wave)
		GameState.save_best()
		ui.set_wave_busy(false)
		ui.show_end(true)
		return

	# 下一波解锁的新塔：等卡牌面板关掉后再提示，避免被面板挡住
	var next_wave := GameState.wave + 1
	var fresh := Tower.unlocked_at(next_wave)
	if not fresh.is_empty():
		var names: Array[String] = []
		for k in fresh:
			names.append(str(Tower.DATA[k]["name"]))
		_pending_unlock_msg = "新解锁：%s（下波可建造）" % "、".join(names)

	var cards := Cards.offer(3, taken_cards)
	ui.set_wave_busy(false)
	if cards.size() > 0:
		ui.show_wave_result(kills, leaks, cards)
	else:
		_show_pending_unlock()


## 显示波次结束后暂存的「新解锁」提示（卡牌面板关闭后调用）
func _show_pending_unlock() -> void:
	if _pending_unlock_msg == "":
		return
	_flash_info(_pending_unlock_msg)
	_pending_unlock_msg = ""


func continue_endless() -> void:
	endless = true
	game_over = false
	won = false
	GameState.running = true
	if ui != null:
		ui.hide_end()
		ui.refresh()


func choose_card(id: String) -> void:
	taken_cards[id] = int(taken_cards.get(id, 0)) + 1
	Cards.apply(id, self)
	refresh_towers()
	ui.hide_cards()
	ui.refresh()
	_show_pending_unlock()
	Sound.play("levelup")

# ---------------------------------------------------------------- 测试工具

## 测试用：跳到指定波次并立即开战（直接测某一波的首领 / 阵容）
func debug_jump_wave(target: int) -> void:
	_debug_prepare(target)
	start_wave()


## 测试用：只把波次指针挪到目标波（下一波就是该波），不立刻开战
func debug_set_wave(target: int) -> void:
	_debug_prepare(target)
	if ui != null:
		ui.refresh()


## 清场 + 复位结算状态，再把波次设成 target - 1（开战后正好是 target）
func _debug_prepare(target: int) -> void:
	var wave := clampi(target, 1, 999)
	# 超过总波数按无尽模式处理，避免 UI 显示「波次 11 / 10」这种怪状态
	endless = wave > Waves.TOTAL
	wave_active = false
	GameState.wave_active = false
	_pending_unlock_msg = ""
	spawn_queue.clear()
	spawn_timer = 0.0
	game_over = false
	won = false
	GameState.running = true
	_clear_selection()
	_debug_clear_units()
	# 关掉暂停 / 结算 / 卡牌 / 波次结算 / 变异这些会挡住操作的弹窗
	get_tree().paused = false
	if ui != null:
		ui.close_mutation_panel()
		ui.show_pause(false)
		ui.hide_end()
		ui.hide_cards()
		ui.hide_wave_result()
	GameState.set_wave(wave - 1)
	_last_lives = GameState.lives
	if ui != null:
		ui.refresh()


## 测试用：一键清怪。清空场上敌人 + 本波还没刷出来的队列；
## 如果正在战斗中，这一波会直接结算并弹出三选一卡。
func debug_clear_enemies() -> void:
	_debug_clear_units()
	spawn_queue.clear()
	spawn_timer = 0.0
	_flash_info("测试：已清空场上敌人")


## 直接移除场上所有敌人与飞行中的子弹（不走伤害结算，不给金币 / 击杀数）
func _debug_clear_units() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != null and is_instance_valid(e):
			e.queue_free()
	if towers_root != null:
		for c in towers_root.get_children():
			if c is Bullet:
				c.queue_free()


func _on_lives_changed(v: int) -> void:
	if ui != null:
		ui.refresh()
	if v < _last_lives and grid != null:
		grid.on_base_hit()
	_last_lives = v
	if v <= 0 and not game_over:
		game_over = true
		wave_active = false
		GameState.wave_active = false
		GameState.running = false
		GameState.best_wave = maxi(GameState.best_wave, GameState.wave)
		GameState.save_best()
		ui.show_end(false)

# ---------------------------------------------------------------- 主循环

## 路线箭头只是「准备阶段」的行进方向提示：开波后敌人自己会走，箭头留在路上反而挡视线。
## 每帧同步一次（GameGrid 内部有变化才真的赋值），所以开波 / 收波 / 跳波 / 重开 / 结算
## 都不需要额外的显隐调用，状态永远跟着 wave_active 走。
func _refresh_flow_hint() -> void:
	if grid != null:
		grid.set_flow_visible(not wave_active and not game_over)


func _process(delta: float) -> void:
	_refresh_flow_hint()
	_update_camera_pan(delta / game_speed)
	if _info_hold > 0.0:
		_info_hold = maxf(_info_hold - delta, 0.0)

	if get_tree().paused:
		return

	if wave_active and not game_over:
		if spawn_queue.size() > 0:
			spawn_timer -= delta
			if spawn_timer <= 0.0:
				_spawn_next()
				spawn_timer = Waves.interval(GameState.wave)
		else:
			if get_tree().get_nodes_in_group("enemies").size() == 0:
				_end_wave()

	_update_info()


func _update_info() -> void:
	if ui == null:
		return
	if _info_hold > 0.0:
		return
	ui.set_selected_tower(selected if (selected != null and is_instance_valid(selected)) else null)
	if selected != null and is_instance_valid(selected):
		ui.set_info(selected.info_text())
		return
	if hover_cell.x >= 0:
		var t = grid.tower_at(hover_cell)
		if t != null and is_instance_valid(t):
			ui.set_info(t.info_text())
			return
		if build_kind >= 0:
			var d: Dictionary = Tower.DATA[build_kind]
			ui.set_info("建造 %s（%d 金）\n%s\n左键点击蓝色布防台放置（可连续放置），右键 / ESC 取消" % [d["name"], d["cost"], d["desc"]])
			return
	# 预告只在波次变化时重算一次：Waves.preview() 会新建数组 + 洗牌 + 拼字符串，
	# 放在每帧的 _update_info() 里会造成大量无谓分配
	if _preview_wave != GameState.wave:
		_preview_wave = GameState.wave
		_preview_text = Waves.preview(GameState.wave + 1)
	ui.set_info("守住左侧水晶！敌人从右侧两条土路分头压上，中途汇成一路。\n下一波：%s\n塔只能建在土路旁的蓝色布防台上（数量有限），路径格不可建塔" % _preview_text)
