# scenes/main.gd —— 导航壳组合根（M0 建成，ARCHITECTURE.md §1.4/§2）
#
# 布局形态（官方原语组合，无内置 Drawer/BottomNavigation）：
#   - 宽屏（≥900 设计 px）：HBox{ 侧边栏 VBox(固定宽 260) + 内容区(Expand) }；
#   - 窄屏（<900）：隐藏侧边栏，底部 TabBar 四类导航（首页/搜索/收藏/历史），
#     抽屉 = DrawerPanel + Tween 滑入 + 半透明 ColorRect 遮罩；
#   - 断点钩 get_viewport().size_changed（themes/responsive.gd 统一实现）。
# 主题热切换：Theme 是普通资源，settings.apply_theme() 整体切换 light/dark。
extends Control

const NAV_ORDER := ["home", "search", "favorites", "history"]
const NAV_TITLES := {"home": "首页", "search": "搜索", "favorites": "收藏", "history": "历史"}
const DRAWER_WIDTH := 320.0

var _wide := true
var _current_page := "home"
var _pages: Dictionary = {}
var _page_holder: Control
var _sidebar: VBoxContainer
var _bottom_nav: TabBar
var _drawer: PanelContainer
var _scrim: ColorRect
var _menu_btn: Button
var _back_btn: Button
var _theme_btn: Button
var _calc_holder: Control  # 当前打开的计算器页面容器（覆盖在页面上）
var _nav_buttons: Dictionary = {}

func _ready() -> void:
	# 服务装配 + 模块目录加载（manifest 缺失静默跳过）
	GKServices.bootstrap()
	GKServices.ensure_catalog()
	_apply_theme_from_settings()
	GKServices.settings.apply_ui_scale(get_window())
	_apply_clear_color()

	_build_ui()
	_wide = GKResponsive.is_wide_now(self)
	_apply_wide(_wide)
	GKResponsive.watch(self, _on_resized)

# ---------- 主题 / 清屏色 ----------

func _apply_theme_from_settings() -> void:
	var dark := GKServices.settings.apply_theme(get_window())
	_apply_clear_color(dark)

func _apply_clear_color(active_theme: Theme = null) -> void:
	var bg := Color(0.949, 0.957, 0.973)  # 与 LIGHT.bg 一致的兜底
	if active_theme != null and active_theme.get_meta("bg_color", null) != null:
		bg = active_theme.get_meta("bg_color")
	elif active_theme == null:
		var project_theme := load("res://themes/main.tres") as Theme
		if project_theme != null:
			bg = project_theme.get_meta("bg_color", bg)
	RenderingServer.set_default_clear_color(bg)

func _on_theme_toggle() -> void:
	var cur := String(GKServices.settings.get_value("theme"))
	var next := "dark" if cur == "light" else "light"
	GKServices.settings.set_value("theme", next)
	_apply_theme_from_settings()  # 已带主题参数应用清屏色；不再二次调用（否则回落浅色覆盖深色）

# ---------- UI 构建 ----------

func _build_ui() -> void:
	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(hbox)

	# —— 宽屏侧边栏 ——
	_sidebar = VBoxContainer.new()
	_sidebar.custom_minimum_size = Vector2(260, 0)
	hbox.add_child(_sidebar)
	var title_row := HBoxContainer.new()
	_sidebar.add_child(title_row)
	var app_logo := TextureRect.new()
	var logo_tex: Texture2D = load("res://assets/icons/app_icon.png")
	if logo_tex != null:
		app_logo.texture = logo_tex
		app_logo.custom_minimum_size = Vector2(56, 56)
		app_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		app_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		title_row.add_child(app_logo)
	var app_title := Label.new()
	app_title.text = "GeodesyKit"
	app_title.theme_type_variation = &"Header"
	app_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	app_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(app_title)
	var app_sub := Label.new()
	app_sub.text = "离线测绘计算器"
	app_sub.theme_type_variation = &"Muted"
	_sidebar.add_child(app_sub)
	_sidebar.add_child(Control.new())  # 弹性占位
	for key: String in NAV_ORDER:
		var b := Button.new()
		b.text = NAV_TITLES[key]
		b.custom_minimum_size = Vector2(0, 96)
		b.toggle_mode = true
		b.pressed.connect(func() -> void: _show_page(key))
		_sidebar.add_child(b)
		_nav_buttons[key] = b
	_sidebar.add_child(Control.new())
	var ver := Label.new()
	ver.text = "Wave 2 集成版 · Godot 4.7"
	ver.theme_type_variation = &"Muted"
	_sidebar.add_child(ver)

	# —— 内容区 ——
	# 外层 MarginContainer 统一页边距（触控边缘留白），内层 VBox 纵向排布：
	# 顶栏 → 页面区(Expand) → 底部导航（窄屏）。底部导航参与容器排布而非
	# 锚点悬浮，页面区自动让位，滚动内容不会被最后 96px 遮挡。
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(content)

	var content_pad := MarginContainer.new()
	content_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_pad.add_theme_constant_override("margin_left", 20)
	content_pad.add_theme_constant_override("margin_right", 20)
	content_pad.add_theme_constant_override("margin_top", 12)
	content_pad.add_theme_constant_override("margin_bottom", 8)
	content.add_child(content_pad)

	var content_v := VBoxContainer.new()
	content_pad.add_child(content_v)

	var top := HBoxContainer.new()
	content_v.add_child(top)
	_menu_btn = Button.new()
	_menu_btn.text = "☰ 菜单"
	_menu_btn.custom_minimum_size = Vector2(0, 96)
	_menu_btn.pressed.connect(_open_drawer)
	top.add_child(_menu_btn)
	_back_btn = Button.new()
	_back_btn.text = "← 返回"
	_back_btn.custom_minimum_size = Vector2(0, 96)
	_back_btn.visible = false
	_back_btn.pressed.connect(_close_calculator)
	top.add_child(_back_btn)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	_theme_btn = Button.new()
	_theme_btn.text = "深色/浅色"
	_theme_btn.custom_minimum_size = Vector2(0, 96)
	_theme_btn.pressed.connect(_on_theme_toggle)
	top.add_child(_theme_btn)

	_page_holder = Control.new()
	_page_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_v.add_child(_page_holder)

	# —— 窄屏底部导航（TabBar）：在容器流内，不遮挡页面内容 ——
	_bottom_nav = TabBar.new()
	_bottom_nav.custom_minimum_size = Vector2(0, 96)
	for key: String in NAV_ORDER:
		_bottom_nav.add_tab(NAV_TITLES[key])
	_bottom_nav.tab_changed.connect(func(idx: int) -> void: _show_page(NAV_ORDER[idx]))
	content_v.add_child(_bottom_nav)

	_pages["home"] = GKHomePage.new()
	_pages["search"] = GKSearchPage.new()
	_pages["favorites"] = GKFavoritesPage.new()
	_pages["history"] = GKHistoryPage.new()
	for key: String in NAV_ORDER:
		var page: Control = _pages[key]
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		page.visible = false
		_page_holder.add_child(page)
		if page.has_signal("open_entry"):
			page.connect("open_entry", _open_entry)
		if page.has_signal("replay_entry"):
			page.connect("replay_entry", _replay_entry)

	# —— 抽屉（窄屏）：遮罩 + DrawerPanel 滑入 ——
	_scrim = ColorRect.new()
	_scrim.color = Color(0, 0, 0, 0.45)
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.visible = false
	_scrim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_close_drawer()
	)
	add_child(_scrim)
	_drawer = PanelContainer.new()
	_drawer.theme_type_variation = &"DrawerPanel"
	_drawer.visible = false
	add_child(_drawer)
	var dv := VBoxContainer.new()
	_drawer.add_child(dv)
	var dt := Label.new()
	dt.text = "导航"
	dt.theme_type_variation = &"Header"
	dv.add_child(dt)
	for key: String in NAV_ORDER:
		var b := Button.new()
		b.text = NAV_TITLES[key]
		b.custom_minimum_size = Vector2(0, 96)
		b.pressed.connect(func() -> void:
			_show_page(key)
			_close_drawer()
		)
		dv.add_child(b)

# ---------- 响应式切换 ----------

func _on_resized(is_wide: bool) -> void:
	if is_wide != _wide:
		_apply_wide(is_wide)

func _apply_wide(is_wide: bool) -> void:
	_wide = is_wide
	_sidebar.visible = is_wide
	_bottom_nav.visible = not is_wide
	_menu_btn.visible = not is_wide
	if is_wide:
		_close_drawer()
	else:
		var idx := NAV_ORDER.find(_current_page)
		if idx >= 0:
			_bottom_nav.current_tab = idx
	_sync_nav_buttons()

# ---------- 页面切换 ----------

func _show_page(key: String) -> void:
	if _calc_holder != null:
		_close_calculator()
	_current_page = key
	for k: String in _pages:
		_pages[k].visible = (k == key)
	var page: Control = _pages[key]
	if page.has_method("refresh"):
		page.call("refresh")
	_sync_nav_buttons()

func _sync_nav_buttons() -> void:
	for k: String in _nav_buttons:
		(_nav_buttons[k] as Button).button_pressed = (k == _current_page)
	var idx := NAV_ORDER.find(_current_page)
	if idx >= 0 and _bottom_nav != null:
		_bottom_nav.current_tab = idx

# ---------- 计算器打开/返回（模块挂载协议：manifest.scene 实例化）----------

func _open_entry(entry: Dictionary) -> void:
	if _calc_holder != null:
		_close_calculator()
	var scene_path := String(entry.get("scene", ""))
	var packed := load(scene_path)
	if packed == null:
		push_warning("计算器场景加载失败：%s" % scene_path)
		return
	var inst: Node = packed.instantiate()
	if not (inst is GKCalculatorBase):
		push_warning("场景根脚本未继承 GKCalculatorBase（契约违反）：%s" % scene_path)
		inst.queue_free()
		return
	var calc := inst as GKCalculatorBase
	if calc.get_entry_id().is_empty():
		calc.set("_entry_id", String(entry.get("id", "")))
	calc.set_example(entry.get("example", {}))
	calc.connect("favorite_changed", func(_id: String, _fav: bool) -> void:
		if _pages.has("favorites"):
			_pages["favorites"].call("refresh")
	)
	_calc_holder = calc
	_calc_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page_holder.add_child(_calc_holder)
	for k: String in _pages:
		_pages[k].visible = false
	_back_btn.visible = true

func _replay_entry(entry_id: String, inputs: Dictionary) -> void:
	var e: Dictionary = GKServices.catalog.entry(entry_id)
	if not e.is_empty():
		_open_entry(e)
		if _calc_holder is GKCalculatorBase:
			(_calc_holder as GKCalculatorBase).set_inputs(inputs)

func _close_calculator() -> void:
	if _calc_holder != null:
		_page_holder.remove_child(_calc_holder)
		_calc_holder.queue_free()
		_calc_holder = null
	_back_btn.visible = false
	_show_page(_current_page)

# ---------- 抽屉 ----------

func _open_drawer() -> void:
	if _wide:
		return
	_scrim.visible = true
	_drawer.visible = true
	var vw := _page_holder.get_viewport_rect().size.x
	_drawer.position = Vector2(-DRAWER_WIDTH - 40.0, 0)
	_drawer.size = Vector2(DRAWER_WIDTH, _page_holder.get_viewport_rect().size.y)
	var tw := create_tween()
	tw.tween_property(_drawer, "position:x", 0.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _close_drawer() -> void:
	_scrim.visible = false
	_drawer.visible = false

# ---------- 退出收尾 ----------

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_on_close_requested()

func _on_close_requested() -> void:
	GKServices.shutdown()
