# scenes/main.gd —— 导航壳组合根（P9 重构：顶部导航单行 + 常驻搜索框）
#
# 布局形态（用户硬性要求）：
#   - 顶部导航行（与搜索框同行、等高）：Logo + 返回 + [首页/收藏/历史/设置]
#     横排按钮 + Expand 搜索框 + 主题切换。搜索不再独立页面——搜索框常驻
#     顶栏，输入即下方出结果浮层（防抖 0.25s）。
#   - 无左侧栏/导航栏/抽屉/底部 TabBar：全断点统一顶部导航，窄屏自动换行。
#   - 计算器全屏展开（删除 list-detail 三栏）：打开计算器覆盖页面区，返回
#     按钮回到原页面。
#   - 断点钩仅控制触控目标高度（96 触屏 / 56 指针）与条目网格列数。
# 主题热切换：settings.apply_theme() 显式赋 light/dark 两套主题（不再依赖
#   null 回落——真机实测该机制控件与清屏色切换不同步）。
# 安全区：启动时 DisplayServer.get_display_safe_area() 计算四边 inset 并映射
#   到设计像素，根容器外层 MarginContainer 加 margin；窗口 size_changed 重算。
extends Control

const NAV_ORDER := ["home", "favorites", "history", "settings"]
const NAV_TITLES := {
	"home": "首页", "favorites": "收藏", "history": "历史", "settings": "设置",
}

var _current_page := "home"
var _pages: Dictionary = {}
var _page_scripts: Dictionary = {}  # key → 脚本（懒加载：首次切到才实例化）
var _page_holder: Control
var _nav_buttons: Dictionary = {}
var _back_btn: Button
var _theme_btn: Button
var _search_box: LineEdit
var _search_popup: PanelContainer  # 搜索结果浮层（顶栏下挂，输入时显示）
var _search_results: VBoxContainer
var _search_hint: Label
var _search_debounce: SceneTreeTimer
var _calc_holder: Control  # 当前打开的计算器（全屏覆盖在页面上）
var _calc_return_page := ""  # 打开计算器前的页面（返回时恢复）
var _safe_inset_design := Vector4(0, 0, 0, 0)  # 上/右/下/左 设计像素 inset
var _bp_handle: GKResponsive.WatchHandle  # 断点连接句柄（退出/PREDELETE 时 unwatch）

func _ready() -> void:
	# 服务装配 + 模块目录加载（manifest 缺失静默跳过）
	GKServices.bootstrap()
	GKServices.ensure_catalog()
	_apply_theme_from_settings()
	GKServices.settings.apply_ui_scale(get_window())
	_apply_safe_area()

	_build_ui()
	_apply_touch_targets()
	# watch 返回连接句柄；本壳只在 _ready 连一次，退出/PREDELETE 时 unwatch。
	_bp_handle = GKResponsive.watch(self, _on_resized)
	# 安全区随窗口变化重算（跨屏拖动/旋转后刘海 inset 改变）
	get_window().size_changed.connect(_on_window_geometry_changed)
	# 首启显式定位首页：_build_ui 把页面全部 visible=false（真机首启实测复现）
	_show_page("home")

# ---------- 安全区（刘海/圆角/手势条 → 设计像素 inset） ----------

## 启动时读取显示安全区，换算为 720×1280 设计基准的像素 inset。
## 口径：DisplayServer 返回屏幕像素坐标，与窗口真实尺寸（同坐标系）相除得
## 缩放比再乘设计尺寸——不能与视口可见区域（设计像素）混用两套坐标系。
## 平台约束：安全区只在移动端有意义（窗口铺满屏幕）；桌面窗口自由摆放，
## get_display_safe_area 返回整屏可用区，窗口居屏一角时 inset 全为正——
## 直接应用会把根容器 margins 撑成几百上千 px（真 bug：PC 布局塌缩元凶）。
## 故桌面（非 Android/iOS/Web）一律 inset 归零。
func _apply_safe_area() -> void:
	var feature := DisplayServer.get_name()
	if feature != "android" and feature != "ios" and feature != "web":
		_safe_inset_design = Vector4(0, 0, 0, 0)
		return
	var win := get_window()
	if win == null:
		return
	var win_size := Vector2(DisplayServer.window_get_size())
	if win_size.x <= 0.0 or win_size.y <= 0.0:
		return
	var sx := 720.0 / win_size.x
	var sy := 1280.0 / win_size.y
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0:
		return
	var win_pos := DisplayServer.window_get_position()
	var top := float(safe.position.y - win_pos.y)
	var left := float(safe.position.x - win_pos.x)
	var bottom := float((safe.position.y + safe.size.y) - (win_pos.y + win_size.y))
	var right := float((safe.position.x + safe.size.x) - (win_pos.x + win_size.x))
	_safe_inset_design = Vector4(
		maxf(top, 0.0) * sy, maxf(right, 0.0) * sx,
		maxf(bottom, 0.0) * sy, maxf(left, 0.0) * sx)

## 窗口尺寸/位置变化：重算安全区 inset 并刷新根 MarginContainer。
func _on_window_geometry_changed() -> void:
	if not is_inside_tree():
		return
	var old := _safe_inset_design
	_apply_safe_area()
	if _safe_inset_design == old:
		return
	for child: Node in get_children():
		if child is MarginContainer:
			_apply_safe_margins(child)

# ---------- 主题 / 清屏色 ----------

func _apply_theme_from_settings() -> void:
	var th := GKServices.settings.apply_theme(get_window())
	_apply_clear_color(th)

## 清屏色统一从已应用主题的 bg_color meta 读取（主题常量唯一出处）；
## 主题未就位时按 settings 当前值选对应 .tres 兜底，不再默认浅色。
func _apply_clear_color(active_theme: Theme = null) -> void:
	var th := active_theme
	if th == null:
		var is_dark := String(GKServices.settings.get_value("theme")) == "dark"
		th = load("res://themes/dark.tres") if is_dark else load("res://themes/main.tres")
	var bg := Color(0.949, 0.957, 0.973)
	if th != null:
		bg = th.get_meta("bg_color", bg)
	RenderingServer.set_default_clear_color(bg)

func _on_theme_toggle() -> void:
	var cur := String(GKServices.settings.get_value("theme"))
	var next := "dark" if cur == "light" else "light"
	GKServices.settings.set_value("theme", next)
	_apply_theme_from_settings()  # apply_theme 内已显式赋主题 + 返回值同步清屏色

# ---------- UI 构建 ----------

func _build_ui() -> void:
	# 外层安全区让位 MarginContainer：四边 inset 由 _apply_safe_area 计算
	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(safe)
	_apply_safe_margins(safe)

	var root_v := VBoxContainer.new()
	safe.add_child(root_v)

	# —— 顶部导航行：Logo + 返回 + 四导航 + Expand 搜索框 + 主题（单行等高）——
	var top := HBoxContainer.new()
	top.name = "TopBar"
	top.add_theme_constant_override("separation", GKThemeConstants.MIN_TOUCH_SPACING)
	root_v.add_child(top)

	var app_logo := TextureRect.new()
	var logo_tex: Texture2D = load("res://assets/icons/app_icon.png")
	if logo_tex != null:
		app_logo.texture = logo_tex
		app_logo.custom_minimum_size = Vector2(40, 40)
		app_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		app_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		app_logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(app_logo)

	_back_btn = Button.new()
	_back_btn.text = "◀ 返回"
	_back_btn.custom_minimum_size = Vector2(0, GKThemeConstants.TOUCH_TARGET)
	_back_btn.visible = false
	_back_btn.pressed.connect(_close_calculator)
	top.add_child(_back_btn)

	for key: String in NAV_ORDER:
		var b := Button.new()
		b.text = NAV_TITLES[key]
		b.custom_minimum_size = Vector2(0, GKThemeConstants.TOUCH_TARGET)
		b.toggle_mode = true
		b.pressed.connect(func() -> void: _show_page(key))
		top.add_child(b)
		_nav_buttons[key] = b

	# 常驻搜索框：与导航同行等高（替代独立搜索页；输入即出结果浮层）
	_search_box = LineEdit.new()
	_search_box.name = "SearchBox"
	_search_box.placeholder_text = "搜索计算器…"
	_search_box.custom_minimum_size = Vector2(200, GKThemeConstants.TOUCH_TARGET)
	_search_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_box.size_flags_stretch_ratio = 1.0
	_search_box.text_changed.connect(_on_search_changed)
	_search_box.text_submitted.connect(_on_search_submitted)
	top.add_child(_search_box)

	_theme_btn = Button.new()
	_theme_btn.text = "深/浅"
	_theme_btn.custom_minimum_size = Vector2(0, GKThemeConstants.TOUCH_TARGET)
	_theme_btn.pressed.connect(_on_theme_toggle)
	top.add_child(_theme_btn)

	# —— 页面懒加载（P9 内存优化）：只有首页在启动时实例化，其余页首次切到才建
	# （四个导航页各自带 ScrollContainer/控件树，全量预建白占内存）。
	_page_holder = Control.new()
	_page_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_v.add_child(_page_holder)
	_page_scripts = {
		"home": GKHomePage,
		"favorites": GKFavoritesPage,
		"history": GKHistoryPage,
		"settings": GKSettingsPage,
	}
	_ensure_page("home")

	# —— 搜索结果浮层：锚在顶栏下方横跨全宽，输入时显示、失焦/选条目后收起 ——
	_search_popup = PanelContainer.new()
	_search_popup.name = "SearchPopup"
	_search_popup.theme_type_variation = &"Card"
	_search_popup.visible = false
	_search_popup.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	add_child(_search_popup)
	var sv := VBoxContainer.new()
	_search_popup.add_child(sv)
	_search_hint = Label.new()
	_search_hint.theme_type_variation = &"Caption"
	sv.add_child(_search_hint)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 480)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sv.add_child(scroll)
	_search_results = VBoxContainer.new()
	_search_results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_search_results)

## 安全区 inset 写入根 MarginContainer
func _apply_safe_margins(margin_container: MarginContainer) -> void:
	margin_container.add_theme_constant_override(
		"margin_top", 8 + int(_safe_inset_design.x))
	margin_container.add_theme_constant_override(
		"margin_right", 12 + int(_safe_inset_design.y))
	margin_container.add_theme_constant_override(
		"margin_bottom", 12 + int(_safe_inset_design.z))
	margin_container.add_theme_constant_override(
		"margin_left", 12 + int(_safe_inset_design.w))

## 搜索浮层定位：顶栏正下方（顶栏高度随触控目标档位变化，动态取值）。
func _update_search_popup_pos() -> void:
	if _search_popup == null:
		return
	var top_bar := get_node_or_null("MarginContainer/TopBar") as Control
	if top_bar == null:
		top_bar = _find_top_bar()
	var y := 64.0
	if top_bar != null:
		y = top_bar.position.y + top_bar.size.y + 4.0
	_search_popup.position = Vector2(12 + _safe_inset_design.w, y)
	_search_popup.size = Vector2(size.x - 24.0 - _safe_inset_design.w - _safe_inset_design.y, 0)

func _find_top_bar() -> Control:
	for child: Node in get_children():
		if child is MarginContainer and child.get_child_count() > 0:
			var v := child.get_child(0) as Control
			if v != null and v.get_child_count() > 0:
				return v.get_child(0) as Control
	return null

# ---------- 搜索（常驻顶栏版） ----------

func _on_search_changed(_q: String) -> void:
	# 防抖：每次按键重置计时器，停顿后统一走 _do_search（避免逐键重建闪烁）
	_search_debounce = get_tree().create_timer(0.25)
	_search_debounce.timeout.connect(_do_search, CONNECT_ONE_SHOT)

func _on_search_submitted(t: String) -> void:
	var results: Array = GKServices.ensure_catalog().search(t.strip_edges())
	if not results.is_empty():
		_close_search()
		_open_entry(results[0])

func _do_search() -> void:
	var q := _search_box.text.strip_edges()
	if q.is_empty():
		_close_search()
		return
	# 同步移除旧结果再重建（queue_free 延迟释放会让本帧出现双份卡片）
	for c in _search_results.get_children():
		_search_results.remove_child(c)
		c.free()
	var results: Array = GKServices.ensure_catalog().search(q)
	_search_hint.text = "「%s」命中 %d 项" % [q, results.size()]
	for e: Dictionary in results:
		var b := Button.new()
		b.text = "%s · %s" % [String(e["name"]),
			GKModuleIndex.DOMAIN_TITLES.get(e.get("domain", ""), e.get("domain", ""))]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, GKThemeConstants.TOUCH_TARGET)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var e_ref := e
		b.pressed.connect(func() -> void:
			_close_search()
			_open_entry(e_ref)
		)
		_search_results.add_child(b)
	if results.is_empty():
		var none := Label.new()
		none.theme_type_variation = &"Muted"
		none.text = "无匹配项：换个关键词试试"
		_search_results.add_child(none)
	_update_search_popup_pos()
	_search_popup.visible = true

func _close_search() -> void:
	_search_popup.visible = false
	_search_box.text = ""

# ---------- 响应式切换（触控目标高度单一职责） ----------

func _on_resized(_is_wide: bool) -> void:
	_apply_touch_targets()

## 触屏设备 96 触控目标 / 指针设备（宽屏键鼠）56——按设备能力而非断点：
## 触屏判定用 DisplayServer.is_touchscreen_available（真机/平板 true）。
func _apply_touch_targets() -> void:
	var touch := DisplayServer.is_touchscreen_available()
	var h := float(GKThemeConstants.TOUCH_TARGET if touch else GKThemeConstants.TOUCH_TARGET_POINTER)
	for key: String in _nav_buttons:
		(_nav_buttons[key] as Button).custom_minimum_size = Vector2(0, h)
	_back_btn.custom_minimum_size = Vector2(0, h)
	_theme_btn.custom_minimum_size = Vector2(0, h)
	_search_box.custom_minimum_size = Vector2(200, h)
	# 已实例化页面中的输入行同步（懒加载页在创建时按当前口径建行）
	for page: Control in _pages.values():
		for row: Node in page.find_children("*", "GKInputRow", true, false):
			var edit: LineEdit = row.get_node_or_null("Edit")
			if edit != null:
				edit.custom_minimum_size = Vector2(0, h)

# ---------- 页面切换 ----------

## 页面懒加载：未实例化的页面在首次切换时创建（内存优化——非首访页面不占内存）。
func _ensure_page(key: String) -> Control:
	if _pages.has(key):
		return _pages[key]
	var script: GDScript = _page_scripts[key]
	var page: Control = script.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.visible = false
	_page_holder.add_child(page)
	if page.has_signal("open_entry"):
		page.connect("open_entry", _open_entry)
	if page.has_signal("replay_entry"):
		page.connect("replay_entry", _replay_entry)
	_pages[key] = page
	return page

func _show_page(key: String) -> void:
	if _calc_holder != null:
		_close_calculator()
	_close_search()
	_current_page = key
	var page := _ensure_page(key)
	for k: String in _pages:
		_pages[k].visible = (k == key)
	if page.has_method("refresh"):
		page.call("refresh")
	_sync_nav_buttons()

func _sync_nav_buttons() -> void:
	for k: String in _nav_buttons:
		(_nav_buttons[k] as Button).button_pressed = (k == _current_page)

# ---------- 计算器打开/返回（全屏覆盖；模块挂载协议：manifest.scene 实例化）----------

func _open_entry(entry: Dictionary) -> void:
	if _calc_holder != null:
		_close_calculator(false)
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
	calc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_calc_holder = calc
	_calc_return_page = _current_page
	_page_holder.add_child(calc)
	for k: String in _pages:
		_pages[k].visible = false
	_back_btn.visible = true
	_sync_nav_buttons()
	_apply_touch_targets()

func _replay_entry(entry_id: String, inputs: Dictionary) -> void:
	var e: Dictionary = GKServices.catalog.entry(entry_id)
	if not e.is_empty():
		_open_entry(e)
		if _calc_holder is GKCalculatorBase:
			(_calc_holder as GKCalculatorBase).set_inputs(inputs)

func _close_calculator(restore_page := true) -> void:
	if _calc_holder != null:
		_page_holder.remove_child(_calc_holder)
		_calc_holder.queue_free()
		_calc_holder = null
	_back_btn.visible = false
	if restore_page:
		_show_page(_calc_return_page if _calc_return_page != "" else "home")

# ---------- 退出收尾 ----------

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_on_close_requested()
	elif what == NOTIFICATION_PREDELETE:
		# 断点句柄解绑（防窗口销毁后 size_changed 悬挂连接）
		if _bp_handle != null:
			_bp_handle.unwatch()
			_bp_handle = null
		if is_inside_tree() and get_window() != null \
				and get_window().size_changed.is_connected(_on_window_geometry_changed):
			get_window().size_changed.disconnect(_on_window_geometry_changed)

func _on_close_requested() -> void:
	if _bp_handle != null:
		_bp_handle.unwatch()
		_bp_handle = null
	if get_window() != null and get_window().size_changed.is_connected(_on_window_geometry_changed):
		get_window().size_changed.disconnect(_on_window_geometry_changed)
	GKServices.shutdown()
