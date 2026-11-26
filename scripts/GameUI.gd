extends CanvasLayer
class_name GameUI
## 全部 UI 用代码构建：HUD、塔商店、悬停信息、Roguelike 三选一卡牌、结算界面。

var main = null           # Main.gd 实例
var ui_root: Control

var lbl_wave: Label
var lbl_lives: Label
var lbl_gold: Label
var lbl_buff: Label
var lbl_info: Label
var info_panel: Panel
var info_show_btn: Button
var lbl_hint: Label
var hint_panel: Panel
var hint_show_btn: Button
var _hint_fit_pending: bool = false
var btn_wave: Button
var btn_fullscreen: Button
var btn_speed: Button
var btn_pause: Button
var pause_root: Control
var shop_btns: Array = []

var _was_paused_before_mutation: bool = false

var card_root: Control
var card_box: HBoxContainer

var mutation_root: Control
var mutation_box: HBoxContainer
var mutation_title: Label
var end_root: Control
var end_title: Label
var end_sub: Label

var btn_codex: Button
var codex_root: Control
var _was_paused_before_codex: bool = false
var _codex_viewports: Array = []      # 图鉴里每个敌人一个 SubViewport（3D 模型预览）

# 测试工具：跳到指定波次（方便直接测某个波次 / 首领）
var btn_debug: Button
var debug_root: Panel
var debug_spin: SpinBox

# 测试工具：上帝模式（F2）—— 左键点地图任意格直接刷怪
## 面板开着的时候左键就是「出怪」，这样不需要额外的「已启用」状态，
## 面板本身就是提示：看得见它，就知道左键在放怪。
var btn_god: Button
var god_root: Panel
var god_kinds: Array = []              # Enemy.DATA 的键，顺序 = Kind 枚举顺序
var god_idx: int = 0                   # 当前选中的敌人类型（god_kinds 的下标）
var god_count: int = 1                 # 一次放几只
var god_hp: float = 1.0                # 血量倍率（叠在波次成长上）
var god_type_list: GridContainer       # 怪列表（每个按钮一种怪）
var god_type_btns: Array = []          # 和 god_kinds 同下标
var god_count_btns: Array = []
var god_hp_btns: Array = []
var god_crystal_btn: Button            # 水晶无敌开关（不扣生命）
var _god_count_idx: int = 0
var _god_hp_idx: int = 0

# 开发用地图切换器（右上角按钮 / F1）
var btn_map: Button
var map_root: Control
var map_list: VBoxContainer
var _was_paused_before_map: bool = false

var lbl_best: Label

var wave_result_root: Control
var wave_result_stats: Label
var _pending_cards: Array = []

var end_btn2: Button
var end_btn_next: Button             # 「前往下一张地图」（只有存在下一张图时才显示）
var _end_next_id: String = ""

var _preview_cache: Dictionary = {}   # 波次 -> 预告文本（避免每次刷新都重新洗牌）

var info_actions: HBoxContainer
var btn_upgrade: Button
var btn_sell_tower: Button
var _sel_tower = null                 # 信息面板当前对应的塔（按钮用）
var _sel_key: String = ""             # 按钮状态签名，避免每帧重设 Button 文本

# 点击塔后浮在塔顶的「升级 / 出售」小面板
var tower_popup: Panel
var popup_title: Label
var popup_upgrade: Button
var popup_sell: Button
var _popup_tower = null
var _popup_key: String = ""

const POPUP_SIZE := Vector2(226, 98)
const POPUP_HEIGHT := 2.7             # 面板锚在塔顶上方多少世界单位

# --- 上帝模式面板：怪列表的列数 / 数量与血量档位 ---
const GOD_COLUMNS := 4
const GOD_COUNTS := [1, 3, 5, 10]
const GOD_HPS := [1.0, 3.0, 10.0]
const GOD_PICK_COLOR := Color(1.0, 0.86, 0.45)     # 当前选中项的文字色
const GOD_IDLE_COLOR := Color(0.88, 0.92, 1.0)

# --- 布局常量：集中管理，改一处即可联动（避免魔法数字散落各处） ---
const HUD_LEFT := 16
const HUD_TOP := 14
const HUD_WIDTH := 324
const HUD_HEIGHT := 186
const HUD_BOTTOM := HUD_TOP + HUD_HEIGHT
const SCREEN_MARGIN := 16

const HINT_GAP := 12                  # 提示面板与 HUD 面板的间距
const HINT_WIDTH := 484
const HINT_MAX_HEIGHT := 480        # 上限放宽：让内容真正决定高度，不再卡死在 330
const HINT_MIN_HEIGHT := 150
const HINT_BOTTOM_RESERVE := 130      # 底部给商店按钮预留的空间

const RIGHT_COL_TOP := 262            # 右上角按钮列起始 Y
const RIGHT_COL_WIDTH := 134
const RIGHT_BTN_HEIGHT := 44
const RIGHT_BTN_GAP := 8

const CODEX_PREVIEW_SIZE := 76        # 图鉴里 3D 预览的像素尺寸
const CODEX_PREVIEW_HEIGHT := 1.7     # 预览里模型归一化后的世界高度

# 操作提示：一行一条，每条控制在 22 字以内（17px 字号 / 面板内宽约 452px ≈ 一行 26 字），
# 这样 10 条 + 标题刚好放进 HINT_MAX_HEIGHT，不会自动换行把文字顶到面板外面。
# 想加内容就加一条，同时确认总行数仍能装下（或调大 HINT_MAX_HEIGHT）。
const HINT_LINES := [
	"左键点发光的布防台建塔，可连续放置",
	"左键点塔：升级 / 出售 · 悬停看射程",
	"出售走塔浮窗按钮，返还 50% 投入",
	"拖动空白处平移视角 · 滚轮缩放",
	"右键：取消建造（不会误拆塔）",
	"Q 切目标优先级 · U 升级选中塔",
	"ESC：取消建造 / 关闭当前面板",
	"塔随波次解锁，商店标注解锁波次",
	"蓝光地砖可建塔 · 棕色土路是敌线",
	"目标：守住水晶，别让敌人冲到跟前",
]


func setup(m) -> void:
	main = m
	process_mode = Node.PROCESS_MODE_ALWAYS   # 暂停时 UI 仍可交互
	_build()
	refresh()


func _build() -> void:
	var theme := Theme.new()
	if ClassDB.class_exists("SystemFont"):
		var sf = ClassDB.instantiate("SystemFont")
		sf.font_names = PackedStringArray(["Microsoft YaHei", "SimHei", "Noto Sans CJK SC", "Arial"])
		theme.default_font = sf
	theme.default_font_size = 17

	ui_root = Control.new()
	ui_root.name = "UIRoot"
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 空白处让 3D 接收点击
	ui_root.theme = theme
	add_child(ui_root)

	_build_hud()
	_build_info()
	_build_shop()
	_build_tower_popup()
	_build_fullscreen_btn()
	_build_speed_pause_btns()
	_build_hint()
	_build_debug()
	_build_god()
	_build_codex()
	_build_cards()
	_build_mutations()
	_build_wave_result()
	_build_end()
	_build_pause()
	_build_map_switch()      # 放最后：切换器面板要盖在其他面板之上


func _style_panel(p: Panel) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.12, 0.88)
	sb.border_color = Color(0.32, 0.48, 0.72, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	p.add_theme_stylebox_override("panel", sb)


func _fill(ctl: Control, l: float, t: float, r: float, b: float) -> void:
	ctl.set_anchors_preset(Control.PRESET_FULL_RECT)
	ctl.offset_left = l
	ctl.offset_top = t
	ctl.offset_right = r
	ctl.offset_bottom = b


## 右上角按钮列：按槽位自动堆叠。新增按钮只要给一个 slot，
## 不用再去手工平移后面所有按钮的 offset。
func _place_right_col(ctl: Control, slot: int) -> float:
	var top := RIGHT_COL_TOP + slot * (RIGHT_BTN_HEIGHT + RIGHT_BTN_GAP)
	ctl.anchor_left = 1.0
	ctl.anchor_right = 1.0
	ctl.anchor_top = 0.0
	ctl.anchor_bottom = 0.0
	ctl.offset_left = -(RIGHT_COL_WIDTH + SCREEN_MARGIN)
	ctl.offset_right = -SCREEN_MARGIN
	ctl.offset_top = top
	ctl.offset_bottom = top + RIGHT_BTN_HEIGHT
	return top + RIGHT_BTN_HEIGHT


func _build_hud() -> void:
	var p := Panel.new()
	p.anchor_left = 0.0
	p.anchor_top = 0.0
	p.anchor_right = 0.0
	p.anchor_bottom = 0.0
	p.offset_left = HUD_LEFT
	p.offset_top = HUD_TOP
	p.offset_right = HUD_LEFT + HUD_WIDTH
	p.offset_bottom = HUD_BOTTOM
	_style_panel(p)
	ui_root.add_child(p)

	var vb := VBoxContainer.new()
	_fill(vb, 16, 12, -16, -12)
	vb.add_theme_constant_override("separation", 6)
	p.add_child(vb)

	lbl_wave = Label.new(); vb.add_child(lbl_wave)
	lbl_lives = Label.new(); vb.add_child(lbl_lives)
	lbl_gold = Label.new(); vb.add_child(lbl_gold)
	lbl_best = Label.new()
	lbl_best.add_theme_color_override("font_color", Color(0.95, 0.80, 0.45))
	vb.add_child(lbl_best)
	lbl_buff = Label.new()
	lbl_buff.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_buff.add_theme_color_override("font_color", Color(0.65, 0.90, 1.0))
	vb.add_child(lbl_buff)

	for l in [lbl_wave, lbl_lives, lbl_gold, lbl_best, lbl_buff]:
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _build_info() -> void:
	info_panel = Panel.new()
	info_panel.anchor_left = 1.0
	info_panel.anchor_top = 0.0
	info_panel.anchor_right = 1.0
	info_panel.anchor_bottom = 0.0
	info_panel.offset_left = -380
	info_panel.offset_top = 14
	info_panel.offset_right = -16
	# 选中塔时信息有 7~9 行（伤害 / 描述 / 优先级 / 升级提示 / 联动），这里留足高度
	info_panel.offset_bottom = 250
	info_panel.clip_contents = true
	_style_panel(info_panel)
	ui_root.add_child(info_panel)

	var vb := VBoxContainer.new()
	_fill(vb, 16, 10, -16, -10)
	vb.add_theme_constant_override("separation", 6)
	info_panel.add_child(vb)

	# 标题行：和左上角「操作提示」保持同一套收放逻辑
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	vb.add_child(head)

	var title := Label.new()
	title.text = "情报"
	title.add_theme_color_override("font_color", Color(0.72, 0.85, 1.0))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(title)

	var hide_btn := Button.new()
	hide_btn.text = "收起"
	hide_btn.custom_minimum_size = Vector2(64, 28)
	hide_btn.pressed.connect(_toggle_info_panel)
	head.add_child(hide_btn)

	lbl_info = Label.new()
	lbl_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(lbl_info)

	# 选中塔时才出现的两个操作按钮：花金币升级 / 出售
	info_actions = HBoxContainer.new()
	info_actions.add_theme_constant_override("separation", 8)
	info_actions.visible = false
	vb.add_child(info_actions)

	btn_upgrade = Button.new()
	btn_upgrade.custom_minimum_size = Vector2(0, 34)
	btn_upgrade.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_upgrade.pressed.connect(_on_upgrade_pressed)
	info_actions.add_child(btn_upgrade)

	btn_sell_tower = Button.new()
	btn_sell_tower.custom_minimum_size = Vector2(0, 34)
	btn_sell_tower.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_sell_tower.pressed.connect(_on_sell_pressed)
	info_actions.add_child(btn_sell_tower)

	# 收起后右上角留一个小按钮，点开恢复
	info_show_btn = Button.new()
	info_show_btn.text = "情报"
	info_show_btn.anchor_left = 1.0
	info_show_btn.anchor_top = 0.0
	info_show_btn.anchor_right = 1.0
	info_show_btn.anchor_bottom = 0.0
	info_show_btn.offset_left = -80
	info_show_btn.offset_top = 14
	info_show_btn.offset_right = -16
	info_show_btn.offset_bottom = 48
	info_show_btn.visible = false
	info_show_btn.pressed.connect(_show_info_panel)
	ui_root.add_child(info_show_btn)


func _toggle_info_panel() -> void:
	Sound.play("click")
	info_panel.visible = false
	info_show_btn.visible = true


func _show_info_panel() -> void:
	Sound.play("click")
	info_panel.visible = true
	info_show_btn.visible = false


func _build_shop() -> void:
	var p := Panel.new()
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 1.0
	p.anchor_bottom = 1.0
	# 8 种塔 + 波次按钮：面板要比 7 种塔时再宽一点，否则最后两个按钮会被挤出屏幕
	p.offset_left = -588
	p.offset_top = -104
	p.offset_right = 588
	p.offset_bottom = -16
	_style_panel(p)
	ui_root.add_child(p)

	var hb := HBoxContainer.new()
	_fill(hb, 16, 14, -16, -14)
	hb.add_theme_constant_override("separation", 10)
	p.add_child(hb)

	for k in [Tower.Kind.ARROW, Tower.Kind.CANNON, Tower.Kind.FROST, Tower.Kind.SNIPER, Tower.Kind.TESLA, Tower.Kind.FLAME, Tower.Kind.BOUNCE, Tower.Kind.POISON]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(96, 60)
		b.pressed.connect(_on_shop_pressed.bind(k))
		hb.add_child(b)
		shop_btns.append(b)

	btn_wave = Button.new()
	# 比普通商店按钮宽一点：首领波时第一行要放得下「⚠ 首领波 · 大首领」
	btn_wave.custom_minimum_size = Vector2(200, 60)
	btn_wave.pressed.connect(_on_start_wave)
	hb.add_child(btn_wave)


## 点击塔时浮在塔顶的小面板：升级 / 出售，两个按钮直接操作当前选中的塔
func _build_tower_popup() -> void:
	tower_popup = Panel.new()
	tower_popup.name = "TowerPopup"
	tower_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	tower_popup.custom_minimum_size = POPUP_SIZE
	tower_popup.size = POPUP_SIZE
	tower_popup.visible = false
	_style_panel(tower_popup)
	ui_root.add_child(tower_popup)

	var vb := VBoxContainer.new()
	_fill(vb, 10, 8, -10, -8)
	vb.add_theme_constant_override("separation", 6)
	tower_popup.add_child(vb)

	popup_title = Label.new()
	popup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup_title.add_theme_font_size_override("font_size", 16)
	popup_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(popup_title)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	vb.add_child(hb)

	popup_upgrade = Button.new()
	popup_upgrade.custom_minimum_size = Vector2(0, 34)
	popup_upgrade.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	popup_upgrade.pressed.connect(_on_popup_upgrade)
	hb.add_child(popup_upgrade)

	popup_sell = Button.new()
	popup_sell.custom_minimum_size = Vector2(0, 34)
	popup_sell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	popup_sell.pressed.connect(_on_popup_sell)
	hb.add_child(popup_sell)


func _build_fullscreen_btn() -> void:
	btn_fullscreen = Button.new()
	btn_fullscreen.text = "全屏 F11"
	_place_right_col(btn_fullscreen, 0)
	btn_fullscreen.pressed.connect(_on_fullscreen_pressed)
	ui_root.add_child(btn_fullscreen)


func _build_speed_pause_btns() -> void:
	# 暂停按钮（右上角，全屏按钮下方）
	btn_pause = Button.new()
	btn_pause.text = "暂停 P"
	_place_right_col(btn_pause, 1)
	btn_pause.pressed.connect(_on_pause_pressed)
	ui_root.add_child(btn_pause)

	# 倍速按钮
	btn_speed = Button.new()
	btn_speed.text = "速度 1x (F)"
	_place_right_col(btn_speed, 2)
	btn_speed.pressed.connect(_on_speed_pressed)
	ui_root.add_child(btn_speed)


func _build_hint() -> void:
	# 放在左上角 HUD 面板下方。具体位置和高度由 _layout_hint() 按当前视口算出，
	# 窗口变小 / 全屏切换时会自动收缩，不会压到 HUD 或底部中央的商店按钮。
	hint_panel = Panel.new()
	hint_panel.clip_contents = true    # 极端小窗口下宁可按框裁掉，也不让文字爬到框外
	_style_panel(hint_panel)
	ui_root.add_child(hint_panel)

	var vb := VBoxContainer.new()
	_fill(vb, 16, 10, -16, -10)
	vb.add_theme_constant_override("separation", 8)
	hint_panel.add_child(vb)

	var hb := HBoxContainer.new()
	vb.add_child(hb)
	var title := Label.new()
	title.text = "操作提示"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(title)
	var hide_btn := Button.new()
	hide_btn.text = "收起"
	hide_btn.custom_minimum_size = Vector2(64, 30)
	hide_btn.pressed.connect(_toggle_hint)
	hb.add_child(hide_btn)

	lbl_hint = Label.new()
	lbl_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_hint.add_theme_color_override("font_color", Color(0.72, 0.78, 0.90))
	lbl_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var txt := ""
	for line in HINT_LINES:
		txt += str(line) + "\n"
	lbl_hint.text = txt.strip_edges()
	vb.add_child(lbl_hint)

	# 收起后左上角留一个小的「提示」按钮，点击可重新展开
	hint_show_btn = Button.new()
	hint_show_btn.text = "提示"
	hint_show_btn.size = Vector2(64, 34)
	hint_show_btn.visible = false
	hint_show_btn.pressed.connect(_show_hint)
	ui_root.add_child(hint_show_btn)

	_layout_hint()
	if not get_viewport().size_changed.is_connected(_layout_hint):
		get_viewport().size_changed.connect(_layout_hint)


func _toggle_hint() -> void:
	hint_panel.visible = false
	hint_show_btn.visible = true


func _show_hint() -> void:
	hint_panel.visible = true
	hint_show_btn.visible = false


## 按当前视口高度重新摆放提示面板：上沿紧贴 HUD 下方，高度按提示条数算出，
## 底部给商店按钮留出空间。窗口太矮时自动降一级字号，尽量让 10 条提示完整显示。
func _layout_hint() -> void:
	var vh: float = get_viewport().get_visible_rect().size.y
	var top: float = float(HUD_BOTTOM + HINT_GAP)
	var avail: float = vh - top - HINT_BOTTOM_RESERVE

	var fs: int = 17
	var need: float = _hint_need_height(fs)
	# 装不下（窗口太矮）或超过面板上限时，降一级字号再算
	if (need > avail or need > float(HINT_MAX_HEIGHT)) and avail > 0.0:
		fs = 15
		need = _hint_need_height(fs)
	if lbl_hint != null:
		lbl_hint.add_theme_font_size_override("font_size", fs)

	var h: float = clampf(minf(need * 1.04, maxf(avail, float(HINT_MIN_HEIGHT))), float(HINT_MIN_HEIGHT), float(HINT_MAX_HEIGHT))

	hint_panel.anchor_left = 0.0
	hint_panel.anchor_top = 0.0
	hint_panel.anchor_right = 0.0
	hint_panel.anchor_bottom = 0.0
	hint_panel.offset_left = HUD_LEFT
	hint_panel.offset_top = top
	hint_panel.offset_right = HUD_LEFT + HINT_WIDTH
	hint_panel.offset_bottom = top + h

	hint_show_btn.position = Vector2(HUD_LEFT, top)

	# 兜底校正：等布局跑完一帧后，用 Label 的真实最小高度再量一次。
	# 字体度量算出来的值偶有偏差，量错了就是「文字被裁一半」，这里保证以实际渲染为准。
	if not _hint_fit_pending:
		_hint_fit_pending = true
		_fit_hint_after_layout(top)


func _fit_hint_after_layout(top: float):
	await get_tree().process_frame
	await get_tree().process_frame
	_hint_fit_pending = false
	if lbl_hint == null or not is_instance_valid(lbl_hint):
		return
	if hint_panel == null or not hint_panel.visible:
		return
	# 只增不减：万一 Label 还没算出宽度、实测值偏小，也不会把面板压扁去裁字。
	var cur: float = hint_panel.offset_bottom - hint_panel.offset_top
	var need: float = 58.0 + lbl_hint.get_combined_minimum_size().y + 8.0
	if need > cur + 0.5:
		hint_panel.offset_bottom = top + clampf(need, float(HINT_MIN_HEIGHT), float(HINT_MAX_HEIGHT))


## 提示面板需要的高度：按「每行能放几个全角字」估算，并且**宁可偏高**。
## 真实高度会在 _fit_hint_after_layout() 里用 Label 的实测值再校正一次，
## 所以这里只要求「别算小」，算大了不会裁字。
func _hint_need_height(fs: int) -> float:
	var pad := 58.0                                              # 标题行 30 + 间距 8 + 上下内边距 20
	var inner_w := float(HINT_WIDTH - 32)
	var per_line: int = maxi(1, int(inner_w / (float(fs) * 1.05)))   # 保守：全角字宽 ≈ 1.05 倍字号
	var rows := 1                                                # 额外留一行余量
	for line in HINT_LINES:
		var n := str(line).length()
		rows += maxi(1, ceili(float(n) / float(per_line)))
	return pad + float(rows) * float(fs) * 1.5


## 测试工具：右上角「跳波测试」按钮 + 指定波次面板。
## 开发期验证某一波（比如直接跳到第 5 / 10 波看小首领 / 大首领）用，不影响正常流程。
func _build_debug() -> void:
	btn_debug = Button.new()
	btn_debug.text = "跳波测试"
	var dbg_bottom := _place_right_col(btn_debug, 4)
	btn_debug.pressed.connect(_on_debug_pressed)
	ui_root.add_child(btn_debug)

	debug_root = Panel.new()
	debug_root.anchor_left = 1.0
	debug_root.anchor_right = 1.0
	debug_root.anchor_top = 0.0
	debug_root.anchor_bottom = 0.0
	# 下方还给「地图切换」按钮（slot 5）留一行，面板整体再往下挪一格
	var panel_top := dbg_bottom + RIGHT_BTN_GAP + RIGHT_BTN_HEIGHT + RIGHT_BTN_GAP
	debug_root.offset_left = -320
	debug_root.offset_top = panel_top
	debug_root.offset_right = -SCREEN_MARGIN
	debug_root.offset_bottom = panel_top + 304
	debug_root.visible = false
	_style_panel(debug_root)
	ui_root.add_child(debug_root)

	var vb := VBoxContainer.new()
	_fill(vb, 14, 10, -14, -10)
	vb.add_theme_constant_override("separation", 8)
	debug_root.add_child(vb)

	var title := Label.new()
	title.text = "测试工具 · 跳波"
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)

	var lbl := Label.new()
	lbl.text = "目标波次"
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)

	debug_spin = SpinBox.new()
	debug_spin.min_value = 1
	debug_spin.max_value = 30      # 再往上敌人数量会爆炸，测试没必要
	debug_spin.step = 1
	debug_spin.value = 5
	debug_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(debug_spin)

	var jump := Button.new()
	jump.text = "跳到该波并开战"
	jump.custom_minimum_size = Vector2(0, 36)
	jump.pressed.connect(_on_debug_jump)
	vb.add_child(jump)

	var only := Button.new()
	only.text = "仅设置波次（不开战）"
	only.custom_minimum_size = Vector2(0, 30)
	only.pressed.connect(_on_debug_set_wave)
	vb.add_child(only)

	var gold := Button.new()
	gold.text = "测试金币 +1000"
	gold.custom_minimum_size = Vector2(0, 30)
	gold.pressed.connect(_on_debug_gold)
	vb.add_child(gold)

	var clear := Button.new()
	clear.text = "一键清怪（结束本波）"
	clear.custom_minimum_size = Vector2(0, 30)
	clear.pressed.connect(_on_debug_clear)
	vb.add_child(clear)

	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(0, 28)
	close.pressed.connect(func(): debug_root.visible = false)
	vb.add_child(close)


## 测试工具：上帝模式（右上角按钮 / F2）。
## 面板挂在**顶部正中**而不是右上角按钮列下方 —— 按钮列已经顶到屏幕底，放不下第二块；
## 中间顶部这块一直空着，也正好不挡左右两侧的信息栏。
## 怪的选项做成**列表**（而不是「点一下换一种」的循环按钮）：十几种怪循环一轮既费劲，
## 也看不出到底有哪些。列表直接由 Enemy.DATA 生成，加新怪不用回来改这里。
func _build_god() -> void:
	btn_god = Button.new()
	btn_god.text = "上帝模式 F2"
	_place_right_col(btn_god, 6)
	btn_god.pressed.connect(_on_god_pressed)
	ui_root.add_child(btn_god)

	god_root = Panel.new()
	god_root.anchor_left = 0.5
	god_root.anchor_right = 0.5
	god_root.anchor_top = 0.0
	god_root.anchor_bottom = 0.0
	god_root.offset_left = -262
	god_root.offset_right = 262
	god_root.offset_top = 12
	god_root.offset_bottom = 400        # 占位值，真实高度由 _fit_god_panel() 按内容算
	god_root.visible = false
	_style_panel(god_root)
	ui_root.add_child(god_root)

	var vb := VBoxContainer.new()
	_fill(vb, 12, 8, -12, -8)
	vb.add_theme_constant_override("separation", 6)
	god_root.add_child(vb)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	vb.add_child(head)

	var title := Label.new()
	title.text = "上帝模式 · 左键点地图放怪"
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(title)

	# 水晶无敌：开着的时候漏怪只记数、不扣生命 —— 压测后期波次时不用一直重开
	god_crystal_btn = Button.new()
	god_crystal_btn.text = "水晶无敌"
	god_crystal_btn.toggle_mode = true
	god_crystal_btn.custom_minimum_size = Vector2(96, 28)
	god_crystal_btn.tooltip_text = "开着时：敌人漏进基地照常消失、照常记漏怪数，但不扣生命（换图 / 重开会自动关闭）"
	god_crystal_btn.toggled.connect(_on_god_crystal_toggled)
	head.add_child(god_crystal_btn)

	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(64, 28)
	close.pressed.connect(_on_god_pressed)
	head.add_child(close)

	# 怪列表：点哪个就是哪个，选中的那个高亮
	god_type_list = GridContainer.new()
	god_type_list.columns = GOD_COLUMNS
	god_type_list.add_theme_constant_override("h_separation", 6)
	god_type_list.add_theme_constant_override("v_separation", 4)
	vb.add_child(god_type_list)

	god_kinds.clear()
	god_type_btns.clear()
	for k in Enemy.DATA.keys():
		var d: Dictionary = Enemy.DATA[k]
		var i := god_kinds.size()
		god_kinds.append(int(k))
		var b := Button.new()
		# 首领前面加星：列表里一眼能认出是哪几档强度
		b.text = "%s%s" % ["★" if _god_is_boss(int(k)) else "", str(d.get("name", "?"))]
		b.tooltip_text = "HP %.0f · 速度 %.2f\n%s" % [
			float(d.get("hp", 0.0)), float(d.get("speed", 0.0)), str(d.get("desc", ""))]
		b.custom_minimum_size = Vector2(0, 28)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		b.pressed.connect(_on_god_type_pick.bind(i))
		god_type_list.add_child(b)
		god_type_btns.append(b)

	god_count_btns.clear()
	vb.add_child(_god_option_row("数量", GOD_COUNTS, _god_count_idx, god_count_btns, _on_god_count_pick))
	god_hp_btns.clear()
	vb.add_child(_god_option_row("血量", GOD_HPS, _god_hp_idx, god_hp_btns, _on_god_hp_pick))

	var tip := Label.new()
	# 这里**不能**用 AUTOWRAP：自动换行的 Label 在宽度还没确定时报出的最小高度
	# 是「每个字一行」，会把面板撑到 1000+ 像素。手动分行，两行都短到放得下。
	tip.text = "左键点地图放怪（水面 / 岩石 / 路线外都行）\n波间休整时刷的怪要等开波才会走"
	tip.add_theme_color_override("font_color", Color(0.72, 0.78, 0.90))
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(tip)

	_fit_god_panel()
	_refresh_god_ui()


## 面板高度按内容撑开：怪的种类一变行数就变，写死高度迟早对不上
func _fit_god_panel() -> void:
	if god_root == null or god_root.get_child_count() == 0:
		return
	var vb := god_root.get_child(0) as Control
	if vb == null:
		return
	god_root.offset_bottom = god_root.offset_top + vb.get_combined_minimum_size().y + 16.0


func _god_is_boss(k: int) -> bool:
	return k == Enemy.Kind.BOSS or k == Enemy.Kind.MINI_BOSS \
		or k == Enemy.Kind.SNOWKING or k == Enemy.Kind.PINELORD


## 一行档位按钮（数量 / 血量）：每个按钮对应一个固定值，选中的高亮。
## 和怪列表同一个理由 —— 轮换按钮看不出有哪几档、也看不出现在在第几档。
func _god_option_row(label_text: String, opts: Array, cur: int, btns: Array, cb: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(44, 0)
	l.add_theme_color_override("font_color", Color(0.72, 0.78, 0.90))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	for i in range(opts.size()):
		var b := Button.new()
		b.text = "×%d" % int(opts[i])
		b.custom_minimum_size = Vector2(58, 26)
		b.toggle_mode = true
		b.button_pressed = (i == cur)
		b.pressed.connect(cb.bind(i))
		row.add_child(b)
		btns.append(b)
	return row


func _on_god_pressed() -> void:
	toggle_god()


func toggle_god() -> void:
	if god_root == null:
		return
	god_root.visible = not god_root.visible
	# 每次打开都重算一次高度：字体 / 行数变化时不用重启就对齐
	if god_root.visible:
		_fit_god_panel()
	Sound.play("click")
	if god_root.visible and main != null:
		# 进上帝模式先把建造模式退掉：否则一次左键既要放怪又要建塔
		main.call("set_build_kind", -1)


func god_visible() -> bool:
	return god_root != null and god_root.visible


## 当前面板选中的敌人类型（Enemy.Kind）
func god_kind() -> int:
	if god_kinds.is_empty():
		return Enemy.Kind.GRUNT
	return int(god_kinds[clampi(god_idx, 0, god_kinds.size() - 1)])


func _on_god_type_pick(i: int) -> void:
	Sound.play("click")
	god_idx = clampi(i, 0, maxi(god_kinds.size() - 1, 0))
	_refresh_god_ui()


func _on_god_count_pick(i: int) -> void:
	Sound.play("click")
	_god_count_idx = clampi(i, 0, GOD_COUNTS.size() - 1)
	god_count = int(GOD_COUNTS[_god_count_idx])
	_refresh_god_ui()


func _on_god_hp_pick(i: int) -> void:
	Sound.play("click")
	_god_hp_idx = clampi(i, 0, GOD_HPS.size() - 1)
	god_hp = float(GOD_HPS[_god_hp_idx])
	_refresh_god_ui()


func _on_god_crystal_toggled(on: bool) -> void:
	Sound.play("click")
	GameState.crystal_invincible = on
	_god_select(god_crystal_btn, on)
	refresh()


## 选中项高亮：按下底纹 + 文字色一起用 —— 默认主题的 pressed 底纹太淡，
## 只看底纹几乎分辨不出当前选的是哪一种怪。
func _refresh_god_ui() -> void:
	for i in range(god_type_btns.size()):
		_god_select(god_type_btns[i], i == god_idx)
	if god_crystal_btn != null:
		_god_select(god_crystal_btn, GameState.crystal_invincible)
	for i in range(god_count_btns.size()):
		_god_select(god_count_btns[i], i == _god_count_idx)
	for i in range(god_hp_btns.size()):
		_god_select(god_hp_btns[i], i == _god_hp_idx)


func _god_select(b: Button, on: bool) -> void:
	b.button_pressed = on
	var col := GOD_PICK_COLOR if on else GOD_IDLE_COLOR
	b.add_theme_color_override("font_color", col)
	b.add_theme_color_override("font_pressed_color", col)
	b.add_theme_color_override("font_hover_pressed_color", col)
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.80))


## 开发用地图切换器（右上角按钮 / F1）：列出 MapDefs 里的所有地图，点一下重载场景过去。
## 纯开发工具，不做解锁限制 —— 任何一张图随时能进。
func _build_map_switch() -> void:
	btn_map = Button.new()
	btn_map.text = "地图切换 F1"
	_place_right_col(btn_map, 5)
	btn_map.pressed.connect(_on_map_pressed)
	ui_root.add_child(btn_map)

	map_root = Control.new()
	map_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_root.mouse_filter = Control.MOUSE_FILTER_STOP
	map_root.visible = false
	ui_root.add_child(map_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	map_root.add_child(dim)

	var wrap := Panel.new()
	wrap.anchor_left = 0.5
	wrap.anchor_right = 0.5
	wrap.anchor_top = 0.5
	wrap.anchor_bottom = 0.5
	wrap.offset_left = -330
	wrap.offset_right = 330
	wrap.offset_top = -220
	wrap.offset_bottom = 220
	_style_panel(wrap)
	map_root.add_child(wrap)

	var vb := VBoxContainer.new()
	_fill(vb, 22, 20, -22, -20)
	vb.add_theme_constant_override("separation", 10)
	wrap.add_child(vb)

	var title := Label.new()
	title.text = "地图切换 · 开发用"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.55, 0.92, 1.0))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(title)

	var sub := Label.new()
	sub.text = "点一下立即切换（重载场景）。金币 / 生命按新开一局算，不继承。"
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.72, 0.80, 0.90))
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(sub)

	map_list = VBoxContainer.new()
	map_list.add_theme_constant_override("separation", 8)
	map_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(map_list)

	var close := Button.new()
	close.text = "关闭 (F1)"
	close.custom_minimum_size = Vector2(0, 40)
	close.pressed.connect(func(): map_root.visible = false)
	vb.add_child(close)


## 重建地图列表：当前地图标「当前」（仍然可点 = 重新载入），其余直接切过去
func _refresh_map_list() -> void:
	if map_list == null:
		return
	for c in map_list.get_children():
		map_list.remove_child(c)
		c.queue_free()
	var cur := ""
	if main != null:
		cur = str(main.get("map_id"))
	if cur == "":
		cur = MapDefs.DEFAULT_ID
	for id in MapDefs.ids():
		var d: Dictionary = MapDefs.get_map(id)
		var b := Button.new()
		var tag: String = "（当前 · 点击重载）" if id == cur else ""
		b.text = "%s%s\n%s" % [str(d.get("name", id)), tag, str(d.get("desc", ""))]
		b.custom_minimum_size = Vector2(0, 62)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = "地图 id: %s" % id
		b.pressed.connect(_on_map_pick.bind(id))
		map_list.add_child(b)


func toggle_map_switch() -> void:
	if map_root == null:
		return
	if map_root.visible:
		_close_map_switch()
		return
	_refresh_map_list()
	map_root.visible = true
	# 面板打开时暂停战场（和暂停 / 图鉴一致），免得在挑地图的时候家被拆了
	_was_paused_before_map = get_tree().paused
	get_tree().paused = true
	Sound.play("click")


func _close_map_switch() -> void:
	if map_root == null or not map_root.visible:
		return
	map_root.visible = false
	get_tree().paused = _was_paused_before_map


func map_switch_visible() -> bool:
	return map_root != null and map_root.visible


func _on_map_pressed() -> void:
	toggle_map_switch()


func _on_map_pick(id: String) -> void:
	Sound.play("click")
	_close_map_switch()
	if main != null:
		main.call("go_to_map", id)


func _build_codex() -> void:
	# 图鉴按钮（右上角按钮列最下方）
	btn_codex = Button.new()
	btn_codex.text = "图鉴"
	_place_right_col(btn_codex, 3)
	btn_codex.pressed.connect(_on_codex_pressed)
	ui_root.add_child(btn_codex)

	# 图鉴面板（全屏遮罩，点关闭或 ESC 退出）
	codex_root = Control.new()
	codex_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	codex_root.mouse_filter = Control.MOUSE_FILTER_STOP
	codex_root.visible = false
	ui_root.add_child(codex_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.62)
	codex_root.add_child(dim)

	var wrap := Panel.new()
	wrap.anchor_left = 0.5
	wrap.anchor_right = 0.5
	wrap.anchor_top = 0.5
	wrap.anchor_bottom = 0.5
	wrap.offset_left = -500
	wrap.offset_right = 500
	wrap.offset_top = -340
	wrap.offset_bottom = 340
	_style_panel(wrap)
	codex_root.add_child(wrap)

	var vb := VBoxContainer.new()
	_fill(vb, 24, 20, -24, -20)
	vb.add_theme_constant_override("separation", 14)
	wrap.add_child(vb)

	var head := HBoxContainer.new()
	vb.add_child(head)

	var title := Label.new()
	title.text = "敌人图鉴"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.custom_minimum_size = Vector2(90, 40)
	close_btn.pressed.connect(_on_codex_close)
	head.add_child(close_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)

	# 飞行怪（FLYER）暂时停用，先不进图鉴
	var kinds := [
		Enemy.Kind.GRUNT, Enemy.Kind.RUNNER, Enemy.Kind.TANK,
		Enemy.Kind.SHIELD, Enemy.Kind.HEALER, Enemy.Kind.SPLITTER, Enemy.Kind.CLOAK,
		Enemy.Kind.FROSTLING, Enemy.Kind.ICEBREAKER, Enemy.Kind.FROSTWEAVER,
		Enemy.Kind.MINI_BOSS, Enemy.Kind.PINELORD, Enemy.Kind.SNOWKING, Enemy.Kind.BOSS,
	]
	_codex_viewports.clear()
	for k in kinds:
		list.add_child(_codex_row(int(k)))


## 图鉴里的小 3D 预览：一个独立 SubViewport 里放归一化后的敌方模型。
## 没有对应 GLB 时：有原画精灵（enemy_<后缀>.png）就显示精灵，否则回退成色块。
func _codex_preview(k: int, d: Dictionary) -> Control:
	var model := ModelLib.instance_path("res://models/enemies/enemy_%s.glb" % _codex_suffix(k))
	# 霜崽 / 雪人王没有 GLB：图鉴里直接用场上的程序化 3D 造型，而不是贴一张立绘
	if model == null:
		if k == Enemy.Kind.SNOWKING:
			model = SnowkingModel.build(1.0)
		elif k == Enemy.Kind.FROSTLING:
			model = FrostlingModel.build(1.0)
		elif k == Enemy.Kind.PINELORD:
			model = PineBossModel.build(1.0)
	if model == null:
		var tex := TextureLib.get_texture("enemy_%s" % _codex_suffix(k))
		if tex != null:
			var pic := TextureRect.new()
			pic.texture = tex
			pic.custom_minimum_size = Vector2(CODEX_PREVIEW_SIZE, CODEX_PREVIEW_SIZE)
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			return pic
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(30, 30)
		swatch.color = d["color"]
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return swatch

	# 归一化：按包围盒缩放到固定世界高度，水平居中、底部贴 y=0
	var box := ModelLib.aabb_of(model)
	var s: float = CODEX_PREVIEW_HEIGHT / maxf(box.size.y, 0.001)
	var c := box.get_center()
	model.scale = Vector3(s, s, s)
	model.position = Vector3(-c.x * s, -box.position.y * s, -c.z * s)
	model.rotation_degrees.y = 24.0
	# 隐身怪整体半透明，和图鉴里的「隐身」标签对应
	if bool(d.get("cloak", false)):
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			(mi as GeometryInstance3D).transparency = 0.55

	var vpc := SubViewportContainer.new()
	vpc.custom_minimum_size = Vector2(CODEX_PREVIEW_SIZE, CODEX_PREVIEW_SIZE)
	vpc.stretch = true
	vpc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vpc.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 别抢 ScrollContainer 的滚轮

	var vp := SubViewport.new()
	vp.size = Vector2i(CODEX_PREVIEW_SIZE, CODEX_PREVIEW_SIZE)
	vp.transparent_bg = true
	vp.own_world_3d = true          # 必须独立世界，否则相机会拍到主战场
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vpc.add_child(vp)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.70, 0.85)
	env.ambient_light_energy = 0.85
	we.environment = env
	vp.add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, 38, 0)
	key.light_energy = 1.35
	vp.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, -135, 0)
	fill.light_energy = 0.55
	vp.add_child(fill)

	vp.add_child(model)

	var cam := Camera3D.new()
	cam.fov = 32.0
	cam.position = Vector3(0.0, 1.05, 3.3)
	cam.look_at_from_position(cam.position, Vector3(0.0, CODEX_PREVIEW_HEIGHT * 0.48, 0.0), Vector3.UP)
	vp.add_child(cam)

	_codex_viewports.append(vp)
	return vpc


## 敌人类型 → 模型文件名后缀（与 Enemy.slot_suffix 保持一致）
func _codex_suffix(k: int) -> String:
	match k:
		Enemy.Kind.RUNNER:
			return "runner"
		Enemy.Kind.TANK:
			return "tank"
		Enemy.Kind.BOSS:
			return "boss"
		Enemy.Kind.MINI_BOSS:
			return "miniboss"
		Enemy.Kind.FLYER:
			return "flyer"
		Enemy.Kind.SHIELD:
			return "shield"
		Enemy.Kind.HEALER:
			return "healer"
		Enemy.Kind.SPLITTER:
			return "splitter"
		Enemy.Kind.ICEBREAKER:
			return "icebreaker"
		Enemy.Kind.FROSTWEAVER:
			return "frostweaver"
		Enemy.Kind.FROSTLING:
			return "frostling"
		Enemy.Kind.SNOWKING:
			return "snowking"
		Enemy.Kind.PINELORD:
			return "pinelord"
		_:
			return "grunt"


func _codex_row(k: int) -> Control:
	var d: Dictionary = Enemy.DATA[k]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	row.add_child(_codex_preview(k, d))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	row.add_child(info)

	var name_lbl := Label.new()
	name_lbl.text = str(d["name"])
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(name_lbl)

	var tags: Array[String] = []
	if bool(d.get("flying", false)): tags.append("飞行")
	if float(d.get("armor", 0.0)) > 0.0: tags.append("护盾减伤")
	if float(d.get("heal", 0.0)) > 0.0: tags.append("治疗友军")
	if int(d.get("split", 0)) > 0: tags.append("死亡分裂")
	if bool(d.get("cloak", false)): tags.append("隐身")
	if float(d.get("slow_cap", 1.0)) < 1.0: tags.append("减速抗性")
	var stats := "生命 %.0f · 速度 %.2f · 奖励 %d" % [d["hp"], d["speed"], d["reward"]]
	if tags.size() > 0:
		stats += " · [%s]" % " / ".join(tags)

	var stats_lbl := Label.new()
	stats_lbl.text = stats
	stats_lbl.add_theme_color_override("font_color", Color(0.72, 0.85, 1.0))
	stats_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(stats_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = str(d.get("desc", ""))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_color_override("font_color", Color(0.72, 0.78, 0.90))
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(desc_lbl)

	return row


func _on_codex_pressed() -> void:
	Sound.play("click")
	if codex_root != null:
		_was_paused_before_codex = get_tree().paused
		get_tree().paused = true
		codex_root.visible = true
		# 预览是一次性渲染的，每次打开重绘一遍（模型/材质可能刚被换过）
		for vp in _codex_viewports:
			if is_instance_valid(vp):
				vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _on_codex_close() -> void:
	Sound.play("click")
	_close_codex()


# ---------------------------------------------------------------- 测试工具回调

func _on_debug_pressed() -> void:
	Sound.play("click")
	debug_root.visible = not debug_root.visible
	if debug_root.visible:
		debug_spin.value = clampi(GameState.wave + 1, 1, 999)


func _on_debug_jump() -> void:
	Sound.play("click")
	debug_root.visible = false
	if main != null:
		main.call("debug_jump_wave", int(debug_spin.value))


func _on_debug_set_wave() -> void:
	Sound.play("click")
	debug_root.visible = false
	if main != null:
		main.call("debug_set_wave", int(debug_spin.value))


func _on_debug_gold() -> void:
	Sound.play("click")
	GameState.add_gold(1000)


func _on_debug_clear() -> void:
	Sound.play("click")
	if main != null:
		main.call("debug_clear_enemies")


func codex_visible() -> bool:
	return codex_root != null and codex_root.visible


func hide_codex() -> void:
	_close_codex()


func _close_codex() -> void:
	if codex_root != null:
		codex_root.visible = false
	if not _was_paused_before_codex:
		get_tree().paused = false


func _build_cards() -> void:
	card_root = Control.new()
	card_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	card_root.mouse_filter = Control.MOUSE_FILTER_STOP
	card_root.visible = false
	ui_root.add_child(card_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	card_root.add_child(dim)

	var wrap := Panel.new()
	wrap.anchor_left = 0.5
	wrap.anchor_right = 0.5
	wrap.anchor_top = 0.5
	wrap.anchor_bottom = 0.5
	wrap.offset_left = -470
	wrap.offset_right = 470
	wrap.offset_top = -230
	wrap.offset_bottom = 200
	_style_panel(wrap)
	card_root.add_child(wrap)

	var vb := VBoxContainer.new()
	_fill(vb, 24, 20, -24, -20)
	vb.add_theme_constant_override("separation", 16)
	wrap.add_child(vb)

	var title := Label.new()
	title.text = "第 %d 波结束 —— 选择一张强化卡"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(title)
	title.name = "Title"
	card_root.set_meta("title", title)

	card_box = HBoxContainer.new()
	card_box.alignment = BoxContainer.ALIGNMENT_CENTER
	card_box.add_theme_constant_override("separation", 20)
	vb.add_child(card_box)


## 满级塔的变异三选一面板：和卡牌面板同一套视觉，但选择结果不可更改。
## 打开时**暂停游戏**（和卡牌三选一一致），玩家可以慢慢读三个方向的说明，
## 不会因为读字的时间被敌人白推一段路；关闭 / 选完自动恢复原来的暂停状态。
func _build_mutations() -> void:
	mutation_root = Control.new()
	mutation_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	mutation_root.mouse_filter = Control.MOUSE_FILTER_STOP
	mutation_root.visible = false
	ui_root.add_child(mutation_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 面板已经暂停游戏，遮罩用卡牌面板同一档（0.55），把战场压暗、视线集中到选项上
	dim.color = Color(0.02, 0.03, 0.07, 0.55)
	mutation_root.add_child(dim)

	var wrap := Panel.new()
	wrap.anchor_left = 0.5
	wrap.anchor_right = 0.5
	wrap.anchor_top = 0.5
	wrap.anchor_bottom = 0.5
	wrap.offset_left = -470
	wrap.offset_right = 470
	wrap.offset_top = -215
	wrap.offset_bottom = 195
	_style_panel(wrap)
	mutation_root.add_child(wrap)

	var vb := VBoxContainer.new()
	_fill(vb, 24, 20, -24, -20)
	vb.add_theme_constant_override("separation", 12)
	wrap.add_child(vb)

	mutation_title = Label.new()
	mutation_title.text = "选择变异方向"
	mutation_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mutation_title.add_theme_font_size_override("font_size", 24)
	mutation_title.add_theme_color_override("font_color", Color(0.86, 0.72, 1.0))
	mutation_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(mutation_title)

	var tip := Label.new()
	tip.text = "游戏已暂停 —— 变异一次定终身，选定后这座塔的最终形态就固定了"
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.add_theme_color_override("font_color", Color(0.66, 0.72, 0.85))
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(tip)

	mutation_box = HBoxContainer.new()
	mutation_box.alignment = BoxContainer.ALIGNMENT_CENTER
	mutation_box.add_theme_constant_override("separation", 18)
	mutation_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(mutation_box)

	var cancel := Button.new()
	cancel.text = "再想想（关闭）"
	cancel.custom_minimum_size = Vector2(180, 36)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(hide_mutations)
	vb.add_child(cancel)


func _build_end() -> void:
	end_root = Control.new()
	end_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_root.mouse_filter = Control.MOUSE_FILTER_STOP
	end_root.visible = false
	ui_root.add_child(end_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	end_root.add_child(dim)

	var wrap := Panel.new()
	wrap.anchor_left = 0.5
	wrap.anchor_right = 0.5
	wrap.anchor_top = 0.5
	wrap.anchor_bottom = 0.5
	wrap.offset_left = -350
	wrap.offset_right = 350
	wrap.offset_top = -200
	wrap.offset_bottom = 200
	_style_panel(wrap)
	end_root.add_child(wrap)

	var vb := VBoxContainer.new()
	_fill(vb, 24, 24, -24, -24)
	vb.add_theme_constant_override("separation", 18)
	wrap.add_child(vb)

	end_title = Label.new()
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_title.add_theme_font_size_override("font_size", 30)
	end_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(end_title)

	end_sub = Label.new()
	end_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	end_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(end_sub)

	# 胜利后「前往下一张地图」和「重新开始」并排；失败时前者隐藏、后者铺满
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)

	end_btn_next = Button.new()
	end_btn_next.text = "前往下一张地图"
	end_btn_next.custom_minimum_size = Vector2(0, 52)
	end_btn_next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	end_btn_next.visible = false
	end_btn_next.pressed.connect(_on_end_next)
	row.add_child(end_btn_next)

	var b := Button.new()
	b.text = "重新开始"
	b.custom_minimum_size = Vector2(0, 52)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(_on_restart)
	row.add_child(b)

	end_btn2 = Button.new()
	end_btn2.text = "继续无尽模式"
	end_btn2.custom_minimum_size = Vector2(0, 52)
	end_btn2.visible = false
	end_btn2.pressed.connect(_on_endless)
	vb.add_child(end_btn2)


func _build_wave_result() -> void:
	wave_result_root = Control.new()
	wave_result_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	wave_result_root.mouse_filter = Control.MOUSE_FILTER_STOP
	wave_result_root.visible = false
	ui_root.add_child(wave_result_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	wave_result_root.add_child(dim)

	var wrap := Panel.new()
	wrap.anchor_left = 0.5
	wrap.anchor_right = 0.5
	wrap.anchor_top = 0.5
	wrap.anchor_bottom = 0.5
	wrap.offset_left = -220
	wrap.offset_right = 220
	wrap.offset_top = -140
	wrap.offset_bottom = 140
	_style_panel(wrap)
	wave_result_root.add_child(wrap)

	var vb := VBoxContainer.new()
	_fill(vb, 24, 22, -24, -22)
	vb.add_theme_constant_override("separation", 16)
	wrap.add_child(vb)

	var title := Label.new()
	title.text = "第 %d 波结束" % GameState.wave
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.name = "Title"
	vb.add_child(title)
	wave_result_root.set_meta("title", title)

	wave_result_stats = Label.new()
	wave_result_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wave_result_stats.add_theme_font_size_override("font_size", 20)
	wave_result_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(wave_result_stats)

	var continue_btn := Button.new()
	continue_btn.text = "继续"
	continue_btn.custom_minimum_size = Vector2(0, 52)
	continue_btn.pressed.connect(_on_wave_result_continue)
	vb.add_child(continue_btn)


func _build_pause() -> void:
	pause_root = Control.new()
	pause_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_root.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_root.visible = false
	ui_root.add_child(pause_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	pause_root.add_child(dim)

	var wrap := Panel.new()
	wrap.anchor_left = 0.5
	wrap.anchor_right = 0.5
	wrap.anchor_top = 0.5
	wrap.anchor_bottom = 0.5
	wrap.offset_left = -220
	wrap.offset_right = 220
	wrap.offset_top = -150
	wrap.offset_bottom = 150
	_style_panel(wrap)
	pause_root.add_child(wrap)

	var vb := VBoxContainer.new()
	_fill(vb, 24, 24, -24, -24)
	vb.add_theme_constant_override("separation", 18)
	wrap.add_child(vb)

	var title := Label.new()
	title.text = "游戏已暂停"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(title)

	var resume := Button.new()
	resume.text = "继续 (ESC/P)"
	resume.custom_minimum_size = Vector2(0, 56)
	resume.pressed.connect(_on_resume_pressed)
	vb.add_child(resume)

	var restart := Button.new()
	restart.text = "重新开始"
	restart.custom_minimum_size = Vector2(0, 56)
	restart.pressed.connect(_on_restart)
	vb.add_child(restart)

# ---------------------------------------------------------------- 刷新

func refresh() -> void:
	# HUD 第一行带上当前地图短名，切图后一眼能看出在哪（"裂谷 · 波次 3 / 10"）
	var map_short := ""
	if main != null:
		map_short = MapDefs.short_of(str(main.get("map_id")))
	if map_short != "":
		map_short += " · "
	if main != null and bool(main.get("endless")):
		lbl_wave.text = "%s无尽  波次 %d" % [map_short, GameState.wave]
	else:
		lbl_wave.text = "%s波次  %d / %d" % [map_short, GameState.wave, Waves.TOTAL]
	# 水晶无敌时给个常驻标记：面板关掉以后也要一眼看出现在扣不扣血
	lbl_lives.text = "生命  %d%s" % [
		GameState.lives, "  ∞ 无敌" if GameState.crystal_invincible else ""]
	lbl_gold.text = "金币  %d" % GameState.gold
	lbl_best.text = "最高  %d 波" % GameState.best_wave

	var parts: Array[String] = []
	var b := GameState.buffs
	if b["damage"] > 1.001: parts.append("伤害×%.2f" % b["damage"])
	if b["rate"] > 1.001: parts.append("攻速×%.2f" % b["rate"])
	if b["range"] > 1.001: parts.append("射程×%.2f" % b["range"])
	if b["slow"] > 1.001: parts.append("减速×%.2f" % b["slow"])
	if b["splash"] > 1.001: parts.append("溅射×%.2f" % b["splash"])
	if b["crit"] > 0.001: parts.append("暴击%d%%" % int(b["crit"] * 100.0))
	if b["gold_wave"] > 0: parts.append("波次金币+%d" % int(b["gold_wave"]))
	if b["interest"] > 0.001: parts.append("利息%d%%" % int(b["interest"] * 100.0))
	# 新增的「状态 / 反应 / 触发」类遗物也要在状态栏里有名字，否则玩家不知道自己在吃什么加成
	if float(b.get("melt_dmg", 0.0)) > 0.001: parts.append("融化+%d%%" % int(float(b["melt_dmg"]) * 100.0))
	if float(b.get("overload_dmg", 0.0)) > 0.001: parts.append("超载+%d%%" % int(float(b["overload_dmg"]) * 100.0))
	if float(b.get("poison_dps", 0.0)) > 0.001: parts.append("中毒%d/s" % int(float(b["poison_dps"])))
	if float(b.get("bleed_dps", 0.0)) > 0.001: parts.append("流血%d/s" % int(float(b["bleed_dps"])))
	if float(b.get("armor_break", 0.0)) > 0.001: parts.append("破甲%d%%" % int(minf(float(b["armor_break"]), 1.0) * 100.0))
	if float(b.get("vuln", 0.0)) > 0.001: parts.append("易伤%d%%" % int(float(b["vuln"]) * 100.0))
	if float(b.get("execute", 0.0)) > 0.001: parts.append("处决+%d%%" % int(float(b["execute"]) * 100.0))
	if float(b.get("death_blast", 0.0)) > 0.001: parts.append("尸爆%d%%" % int(float(b["death_blast"]) * 100.0))
	if int(b.get("life_regen", 0)) > 0: parts.append("每波+%d命" % int(b["life_regen"]))
	if float(b.get("refund", 0.5)) > 0.501: parts.append("回收%d%%" % int(float(b["refund"]) * 100.0))
	lbl_buff.text = " ".join(parts) if parts.size() > 0 else "暂无强化"

	var kinds := [Tower.Kind.ARROW, Tower.Kind.CANNON, Tower.Kind.FROST, Tower.Kind.SNIPER, Tower.Kind.TESLA, Tower.Kind.FLAME, Tower.Kind.BOUNCE, Tower.Kind.POISON]
	var picked: int = int(main.get("build_kind")) if main != null else -1
	for i in range(shop_btns.size()):
		var k: int = kinds[i]
		var d: Dictionary = Tower.DATA[k]
		var sb: Button = shop_btns[i]
		if Tower.is_unlocked(k):
			sb.disabled = false
			sb.text = "%s\n%d金" % [d["name"], d["cost"]]
			sb.tooltip_text = "%s：%s" % [d["name"], d["desc"]]
			sb.modulate = Color(0.60, 1.0, 0.70) if k == picked else Color(1, 1, 1)
		else:
			# 未解锁：灰掉并写明解锁波次，玩家能提前规划金币
			sb.disabled = true
			sb.text = "未解锁\n第 %d 波" % Tower.unlock_wave(k)
			sb.tooltip_text = "%s 将在第 %d 波解锁" % [d["name"], Tower.unlock_wave(k)]
			sb.modulate = Color(0.55, 0.55, 0.55)

	_refresh_wave_button()

	# 金币变化会让「升级」按钮的可点状态变化，顺手刷新一次
	if info_actions != null:
		if _sel_tower != null and is_instance_valid(_sel_tower):
			set_selected_tower(_sel_tower)
		else:
			set_selected_tower(null)


func _refresh_wave_button() -> void:
	if btn_wave == null or main == null:
		return
	# 每次重刷先恢复默认样式，首领波再单独覆盖成红色
	btn_wave.remove_theme_color_override("font_color")
	btn_wave.modulate = Color(1.0, 1.0, 1.0)

	if GameState.wave >= Waves.TOTAL and not bool(main.get("endless")):
		btn_wave.text = "已通关"
		btn_wave.disabled = true
		btn_wave.tooltip_text = ""
		return
	var busy: bool = bool(main.get("wave_active"))
	btn_wave.disabled = busy
	if busy:
		btn_wave.text = "战斗进行中…"
		btn_wave.tooltip_text = ""
		return

	var next := GameState.wave + 1
	# 首领名要跟着地图走（霜渊第 10 波是雪人王，不是通用大首领）
	var wave_opts := {}
	if main != null:
		wave_opts = main._wave_opts()
	var boss := Waves.boss_name(next, wave_opts)
	var full := _preview(next)
	btn_wave.tooltip_text = "下一波：" + full
	if boss != "":
		# 首领波：按钮本身直接预警，玩家在开战前就能调整阵型
		btn_wave.text = "⚠ 首领波 · %s\n开始第 %d 波" % [boss, next]
		btn_wave.add_theme_color_override("font_color", Color(1.0, 0.40, 0.40))
		btn_wave.modulate = Color(1.0, 0.88, 0.88)
	else:
		btn_wave.text = "开始第 %d 波\n%s" % [next, _preview_short(full)]


## 波次预告缓存：refresh() 每次金币变化都会调用，不能每次都重建数组再洗牌
func _preview(wave: int) -> String:
	if not _preview_cache.has(wave):
		# 地图专属怪（碎冰者 / 霜语者）的预告必须和实际出怪用同一套规则，
		# 所以直接问 Main 要那份「本图开关」，不要在这里重算一遍。
		var opts := {}
		if main != null:
			opts = main._wave_opts()
		_preview_cache[wave] = Waves.preview(wave, opts)
	return str(_preview_cache[wave])


## 按钮只有两行、宽度有限：只取前两种敌人，完整列表放在 tooltip 里
func _preview_short(full: String) -> String:
	var parts := full.split("、")
	if parts.size() <= 2:
		return full
	return "%s、%s 等" % [parts[0], parts[1]]


func set_info(text: String) -> void:
	if lbl_info != null and lbl_info.text != text:
		lbl_info.text = text


## 选中塔时刷新信息面板下方的「升级 / 出售」按钮；没选中就隐藏
func set_selected_tower(t) -> void:
	if info_actions == null:
		return
	if t == null or not is_instance_valid(t):
		_sel_tower = null
		_sel_key = ""
		info_actions.visible = false
		return
	_sel_tower = t
	info_actions.visible = true
	# 每帧都会调到这里，只在「塔 / 等级 / 金币」变化时才重设按钮文本
	var mut_id := str(t.get("mutation"))
	var key := "%d|%d|%d|%d|%s" % [t.get_instance_id(), int(t.level), GameState.gold, int(t.value), mut_id]
	if key == _sel_key:
		return
	_sel_key = key
	var cost: int = t.upgrade_cost()
	if cost < 0:
		if mut_id == "":
			var mc: int = int(t.mutation_cost())
			btn_upgrade.text = "变异（%d 金）" % mc
			btn_upgrade.disabled = GameState.gold < mc
		else:
			btn_upgrade.text = "已变异"
			btn_upgrade.disabled = true
	else:
		btn_upgrade.text = "升级 Lv.%d（%d 金）" % [int(t.level) + 1, cost]
		btn_upgrade.disabled = GameState.gold < cost
	btn_sell_tower.text = "出售（+%d 金）" % int(int(t.value) * 0.5)


func set_wave_busy(busy: bool) -> void:
	_refresh_wave_button()

# ---------------------------------------------------------------- 塔操作浮窗

func _process(_delta: float) -> void:
	_update_tower_popup()


## 点击某座塔时调用：面板锚在塔顶上方，跟着相机移动实时刷新位置
func show_tower_popup(t) -> void:
	if tower_popup == null:
		return
	_popup_tower = t
	_popup_key = ""
	tower_popup.visible = t != null and is_instance_valid(t)
	_update_tower_popup()


func hide_tower_popup() -> void:
	_popup_tower = null
	_popup_key = ""
	if tower_popup != null:
		tower_popup.visible = false


func _update_tower_popup() -> void:
	if tower_popup == null or _popup_tower == null:
		return
	var t = _popup_tower
	if not is_instance_valid(t):
		hide_tower_popup()
		return
	if main != null and bool(main.get("game_over")):
		hide_tower_popup()
		return
	# 暂停 / 卡牌 / 结算 / 图鉴这些全屏遮罩打开时先收起来，关掉后自动恢复
	if _popup_blocked():
		tower_popup.visible = false
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# 塔等级越高塔身越高，用枪口高度当锚点，面板始终浮在塔顶
	var top_y := POPUP_HEIGHT
	var my = t.get("muzzle_y")
	if my != null:
		top_y = maxf(POPUP_HEIGHT, float(my) + 0.4)
	var wp: Vector3 = t.global_position + Vector3(0.0, top_y, 0.0)
	if cam.is_position_behind(wp):
		tower_popup.visible = false
		return
	tower_popup.visible = true
	_refresh_tower_popup(t)
	var vp := get_viewport().get_visible_rect().size
	var sp := cam.unproject_position(wp)
	var sz := tower_popup.size
	var pos := Vector2(sp.x - sz.x * 0.5, sp.y - sz.y - 8.0)
	pos.x = clampf(pos.x, 8.0, maxf(vp.x - sz.x - 8.0, 8.0))
	pos.y = clampf(pos.y, 8.0, maxf(vp.y - sz.y - 8.0, 8.0))
	tower_popup.position = pos


## 是否有全屏面板正开着（图鉴 / 卡牌 / 结算 / 波次结算 / 暂停 / 变异）。
## Main 用它拦住鼠标事件，避免面板里的滚轮同时缩放地图。
func is_modal_open() -> bool:
	return _popup_blocked()


func _popup_blocked() -> bool:
	return (codex_root != null and codex_root.visible) \
		or (card_root != null and card_root.visible) \
		or (mutation_root != null and mutation_root.visible) \
		or (end_root != null and end_root.visible) \
		or (wave_result_root != null and wave_result_root.visible) \
		or (map_root != null and map_root.visible) \
		or (pause_root != null and pause_root.visible)


## 只在塔 / 等级 / 金币 / 投入金额变化时重设按钮文本（每帧都会被调用）
func _refresh_tower_popup(t) -> void:
	var mut_id := str(t.get("mutation"))
	var key := "%d|%d|%d|%d|%s" % [t.get_instance_id(), int(t.level), GameState.gold, int(t.value), mut_id]
	if key == _popup_key:
		return
	_popup_key = key
	var d: Dictionary = Tower.DATA[int(t.kind)]
	var md: Dictionary = t.mutation_def()
	var tname := str(d["name"])
	if not md.is_empty():
		tname += "·" + str(md["name"])
	popup_title.text = "%s  Lv.%d" % [tname, int(t.level)]
	var cost: int = t.upgrade_cost()
	if cost < 0:
		if mut_id == "":
			# 满级且还没变异：这里就是变异入口（浮窗按钮窄，文案压到「变异 + 价格」）
			var mc: int = int(t.mutation_cost())
			popup_upgrade.text = "变异 %d" % mc
			popup_upgrade.tooltip_text = "花 %d 金从 3 个方向里选一个，永久生效" % mc
			popup_upgrade.disabled = GameState.gold < mc
		else:
			popup_upgrade.text = "已变异"
			popup_upgrade.disabled = true
	else:
		popup_upgrade.text = "升级 %d 金" % cost
		popup_upgrade.disabled = GameState.gold < cost
	popup_sell.text = "出售 +%d 金" % int(int(t.value) * 0.5)


func _on_popup_upgrade() -> void:
	if main == null:
		return
	main.call("upgrade_selected")
	_popup_key = ""


func _on_popup_sell() -> void:
	if main == null:
		return
	main.call("sell_selected")
	hide_tower_popup()

# ---------------------------------------------------------------- 卡牌 / 结算

func show_cards(cards: Array) -> void:
	# 变异面板可能正开着（它也暂停游戏）：先正常收掉，避免两层遮罩叠在一起。
	# 用 close_mutation_panel 而不是直接改 visible，否则它留下的暂停状态没人恢复。
	close_mutation_panel()
	for c in card_box.get_children():
		c.free()
	for c in cards:
		var b := Button.new()
		b.custom_minimum_size = Vector2(270, 210)
		b.text = "%s\n\n%s" % [c["name"], c["desc"]]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.pressed.connect(_on_card_picked.bind(c["id"]))
		card_box.add_child(b)
	var t = card_root.get_meta("title", null)
	if t != null:
		t.text = "第 %d 波结束 —— 选择一张强化卡" % GameState.wave
	card_root.visible = true


func hide_cards() -> void:
	card_root.visible = false


# ---------------------------------------------------------------- 变异

## 打开变异三选一。
## 打开期间**暂停游戏** —— 三个方向的说明要读完，不该用「敌人白推一段路」来收税。
## 记下打开前的暂停状态，关闭时还原，避免把玩家自己按的暂停也一起解掉。
func show_mutations(t, list: Array) -> void:
	if mutation_root == null or t == null or not is_instance_valid(t):
		return
	for c in mutation_box.get_children():
		c.free()
	var d: Dictionary = Tower.DATA[int(t.kind)]
	var mc: int = int(t.mutation_cost())
	mutation_title.text = "%s Lv.%d —— 选择变异方向（%d 金）" % [str(d["name"]), int(t.level), mc]
	for m in list:
		var b := Button.new()
		b.custom_minimum_size = Vector2(272, 226)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.text = "【%s】\n\n%s" % [str(m["name"]), str(m["desc"])]
		var tint: Color = m["tint"]
		b.add_theme_color_override("font_color", tint)
		b.pressed.connect(_on_mutation_picked.bind(str(m["id"])))
		mutation_box.add_child(b)
	# 已经开着（例如连按 U 又触发一次）：只刷新选项，不要重复记录暂停状态 ——
	# 否则第二次会把「已暂停」当成打开前的状态记下来，关掉后就再也解不开暂停。
	if not mutation_root.visible:
		_was_paused_before_mutation = get_tree().paused
		get_tree().paused = true
	mutation_root.visible = true
	Sound.play("click")


## 关闭面板并还原暂停状态；面板本来就没开时什么都不做（不会误解除别的暂停）
func close_mutation_panel() -> void:
	if mutation_root == null or not mutation_root.visible:
		return
	mutation_root.visible = false
	if not _was_paused_before_mutation:
		get_tree().paused = false
	_was_paused_before_mutation = false


func hide_mutations() -> void:
	close_mutation_panel()
	Sound.play("click")


func mutation_visible() -> bool:
	return mutation_root != null and mutation_root.visible


## ESC 关闭变异面板（Main 也会处理 ESC，这里先兜一层）
func _unhandled_input(event: InputEvent) -> void:
	if not mutation_visible():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		hide_mutations()
		get_viewport().set_input_as_handled()


func _on_mutation_picked(id: String) -> void:
	if mutation_root == null:
		return
	# 先恢复暂停再让 Main 结算：变异成功的闪光 / 光环是挂在地图节点上的补间动画，
	# 树还停在 paused 状态的话补间不会推进，特效会「卡住不动」。
	close_mutation_panel()
	Sound.play("click")
	if main != null:
		main.call("apply_mutation", id)


## next_map_id 非空时，结算面板会多出「前往下一张地图」按钮（第十波守住后才有）。
func show_end(win: bool, next_map_id: String = "") -> void:
	close_mutation_panel()
	_end_next_id = next_map_id
	if win:
		end_title.text = "黎明降临"
		end_title.add_theme_color_override("font_color", Color(0.45, 1.0, 0.60))
		var extra := ""
		if next_map_id != "":
			extra = "\n东侧的裂口后面是「%s」，潮水还没退干净。" % MapDefs.name_of(next_map_id)
		end_sub.text = "终焉水晶仍在呼吸。\n你守住了全部 %d 波蚀潮，剩余焰心（生命）：%d%s\n可继续挑战「余潮」无尽模式！" % [Waves.TOTAL, GameState.lives, extra]
		end_btn2.visible = true
		end_btn_next.visible = next_map_id != ""
		if next_map_id != "":
			end_btn_next.text = "前往「%s」" % MapDefs.name_of(next_map_id)
	else:
		end_title.text = "水晶熄灭"
		end_title.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
		end_sub.text = "在第 %d 波倒下 —— 永夜吞没了%s。\n再试一次吧。" % [GameState.wave, MapDefs.short_of(str(main.get("map_id")) if main != null else "")]
		end_btn2.visible = false
		end_btn_next.visible = false
	end_root.visible = true


func hide_end() -> void:
	if end_root != null:
		end_root.visible = false


func hide_wave_result() -> void:
	if wave_result_root != null:
		wave_result_root.visible = false


func show_wave_result(kills: int, leaks: int, cards: Array) -> void:
	close_mutation_panel()
	_pending_cards = cards
	var t = wave_result_root.get_meta("title", null)
	if t != null:
		t.text = "第 %d 波结束" % GameState.wave
	wave_result_stats.text = "击杀 %d · 漏怪 %d" % [kills, leaks]
	wave_result_root.visible = true


func _on_wave_result_continue() -> void:
	Sound.play("click")
	wave_result_root.visible = false
	show_cards(_pending_cards)

# ---------------------------------------------------------------- 回调

func _on_shop_pressed(k: int) -> void:
	if main == null:
		return
	if not Tower.is_unlocked(k):
		Sound.play("click")
		return
	main.call("set_build_kind", k)
	Sound.play("click")


func _on_upgrade_pressed() -> void:
	if main == null:
		return
	main.call("upgrade_selected")


func _on_sell_pressed() -> void:
	if main == null:
		return
	main.call("sell_selected")


func _on_start_wave() -> void:
	if main == null:
		return
	main.call("start_wave")


func _on_fullscreen_pressed() -> void:
	if main == null:
		return
	main.call("_toggle_fullscreen")
	Sound.play("click")
	var wid := get_window().get_window_id()
	var m := DisplayServer.window_get_mode(wid)
	var full := (m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	btn_fullscreen.text = "窗口模式" if full else "全屏 F11"


func _on_card_picked(id: String) -> void:
	if main == null:
		return
	main.call("choose_card", id)
	Sound.play("click")


func _on_restart() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	GameState.reset()
	# 重开当前地图：场景文件里不存地图 id，必须把当前图写回 pending_id，
	# 否则 reload 后会掉回默认地图（第二张图重开会莫名其妙回到裂谷）
	if main != null:
		MapDefs.pending_id = str(main.get("map_id"))
	get_tree().reload_current_scene()


func _on_pause_pressed() -> void:
	Sound.play("click")
	if main != null:
		main.call("toggle_pause")


func _on_speed_pressed() -> void:
	Sound.play("click")
	if main != null:
		main.call("toggle_speed")


func _on_resume_pressed() -> void:
	Sound.play("click")
	if main != null:
		main.call("toggle_pause")


func _on_endless() -> void:
	Sound.play("click")
	if main != null:
		main.call("continue_endless")


## 结算面板「前往下一张地图」：金币 / 生命继承，塔和卡牌不继承
func _on_end_next() -> void:
	Sound.play("click")
	if main == null or _end_next_id == "":
		return
	get_tree().paused = false
	Engine.time_scale = 1.0
	main.call("go_to_next_map")


func show_pause(p: bool) -> void:
	if pause_root != null:
		pause_root.visible = p


func update_speed(s: float) -> void:
	if btn_speed != null:
		btn_speed.text = "速度 %.0fx (F)" % s


func update_shop_highlight(build_kind: int) -> void:
	var kinds := [Tower.Kind.ARROW, Tower.Kind.CANNON, Tower.Kind.FROST, Tower.Kind.SNIPER, Tower.Kind.TESLA, Tower.Kind.FLAME, Tower.Kind.BOUNCE, Tower.Kind.POISON]
	for i in range(shop_btns.size()):
		var k: int = kinds[i]
		var b: Button = shop_btns[i]
		if not Tower.is_unlocked(k):
			b.modulate = Color(0.55, 0.55, 0.55)
		elif k == build_kind:
			b.modulate = Color(0.60, 1.0, 0.70)
		else:
			b.modulate = Color(1, 1, 1)
