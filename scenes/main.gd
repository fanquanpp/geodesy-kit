# scenes/main.gd —— 导航壳组合根（P9 重构：顶部导航单行 + 常驻搜索框）
#
# 布局形态（用户硬性要求）：
#   - 顶部导航行（与搜索框同行、等高）：Logo + 返回 + [首页/收藏/历史/设置]
#     横排按钮 + Expand 搜索框 + 主题切换。搜索不再独立页面——搜索框常驻
#     顶栏，输入即下方出结果浮层（防抖 0.25s）。
#   - 无左侧栏/导航栏/抽屉/底部 TabBar：全断点统一顶部导航；窄屏（COMPACT
#     <600）不换行塌两条——搜索框折叠为图标钮，点按展开搜索浮层（LineEdit
#     移入浮层顶部），导航钮保持顶部单行。
#   - 计算器全屏展开（删除 list-detail 三栏）：打开计算器覆盖页面区，返回
#     按钮回到原页面。
#   - 断点钩控制触控目标高度（96 触屏 / 56 指针）、窄屏搜索折叠形态；页面级
#     网格列数/计算器左右布局由各页面自行挂视口 size_changed 重算。
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
var _go_back_last_ms := 0  # Android 返回键防抖（防御双派发：两次事件只算一次）
var _kb_timer: Timer  # 软键盘高度轮询器（main 持有；计算器字段获焦时启动）
var _kb_prev_inset := -1  # 上次写入的键盘 inset（未变不重写，防布局抖动）
var _top_bar: HBoxContainer  # 顶部导航行直接持引用（搜索浮层定位用）——
# 此前按节点路径 "MarginContainer/TopBar" 查找永不命中（TopBar 实际挂在
# safe MarginContainer → root_v 下两层），全靠 _find_top_bar 遍历兜底
var _search_toggle_btn: Button  # 窄屏搜索图标钮（折叠态顶栏占位，点按展开浮层）
var _search_box_parent: Control  # 搜索框原父容器（展开态归还用；折叠/展开不重建控件）
var _search_in_popup_box: VBoxContainer  # 浮层顶部行（展开态搜索框临时宿主）
var _search_scroll: ScrollContainer  # 浮层结果滚动区（视口 resize 时重算高度上限）

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
	# Android 返回键：不退出应用，按栈回退（quit_on_go_back=false，project.godot）
	get_window().go_back_requested.connect(_on_go_back_requested)
	# 软键盘高度轮询器（生命周期归属 main：单 Timer，字段获焦时启动）
	_kb_timer = Timer.new()
	_kb_timer.wait_time = 0.1
	_kb_timer.one_shot = false
	_kb_timer.timeout.connect(_poll_keyboard_inset)
	add_child(_kb_timer)
	# 焦点变化统一入口：LineEdit 获焦（计算器字段）启动轮询、失焦停止——
	# 用 Viewport.gui_focus_changed 而非逐字段连线，懒加载页/新实例化的计算器
	# 无需各自挂接。仅 Android 开启（iOS/桌面键盘高度恒 0，轮询无意义）。
	if DisplayServer.get_name() == "android":
		get_window().gui_focus_changed.connect(_on_viewport_focus_changed)
	else:
		# 非 Android：搜索浮层「点击外部/失焦关闭」的兑现路径——LineEdit 失焦
		# （点浮层外任意处、点导航钮）即收起浮层（Android 走返回键/图标钮收起）
		get_window().gui_focus_changed.connect(_on_focus_changed_desktop)
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
	# 上缘再与挖孔/刘海 cutout 取 max：部分 ROM 的 safe area 不含摄像头挖孔
	# （get_display_cutouts 为 Android 专有 API），取并集防状态栏压住顶栏。
	var cut_top := 0.0
	for cut: Rect2 in DisplayServer.get_display_cutouts():
		if cut.size.y > 0.0:
			cut_top = maxf(cut_top, float(cut.position.y + cut.size.y))
	var win_pos := DisplayServer.window_get_position()
	var top := float(safe.position.y - win_pos.y)
	var left := float(safe.position.x - win_pos.x)
	var bottom := float((safe.position.y + safe.size.y) - (win_pos.y + win_size.y))
	var right := float((safe.position.x + safe.size.x) - (win_pos.x + win_size.x))
	_safe_inset_design = Vector4(
		maxf(maxf(top, 0.0), cut_top) * sy, maxf(right, 0.0) * sx,
		maxf(bottom, 0.0) * sy, maxf(left, 0.0) * sx)
	# 最小保护值：safe area 与 cutout 都拿不到时仍给状态栏基本让位（~1/16 设计高）
	if _safe_inset_design.x <= 0.0:
		_safe_inset_design.x = 48.0 * sy

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

# ---------- Android 返回键（quit_on_go_back=false，main 接管栈回退） ----------

## 栈回退次序：搜索浮层 → 计算器 → 非首页回首页；首页无栈可退（不退出应用，
## 由系统决定）。≥150ms 防抖：go_back_requested 双派发未在 4.7 文档核验
## （godot#123454 无从查证），防御性过滤同一物理按键的重复事件。
func _on_go_back_requested() -> void:
	var now := Time.get_ticks_msec()
	if now - _go_back_last_ms < 150:
		return
	_go_back_last_ms = now
	if _search_popup != null and _search_popup.visible:
		_close_search()
		return
	if _calc_holder != null:
		_close_calculator()
		return
	if _current_page != "home":
		_show_page("home")

## 非 Android（桌面/iOS/Web）：浮层「点击外部/失焦关闭」——
## 焦点仍在搜索框（null → 框）不收；焦点移到别处（点外部/其他控件）即收起。
## 折叠态下点图标钮：按钮 pressed 前焦点已离开框，先收起再被 _open_search_overlay
## 重新展开，时序上同帧无闪烁（visible 最终为 true）。
func _on_focus_changed_desktop(control: Control) -> void:
	if _search_popup == null or not _search_popup.visible:
		return
	if control == _search_box:
		return
	# 焦点落到浮层内结果条目（Button）时不收——pressed 回调自己会 _close_search
	if control != null and _search_popup.is_ancestor_of(control):
		return
	_close_search()

# ---------- 桌面快捷键（DisplayServer 守卫，移动端不注册） ----------

## 桌面键鼠：Esc 关搜索浮层/计算器、Ctrl+F 聚焦搜索框。
## 仅 feature == "keyboard" 平台生效（Android/iOS 无物理键盘不拦截 Esc）。
func _unhandled_key_input(event: InputEvent) -> void:
	if DisplayServer.get_name() != "windows" and DisplayServer.get_name() != "macos" \
			and DisplayServer.get_name() != "linux" and DisplayServer.get_name() != "web":
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		if _search_popup != null and _search_popup.visible:
			_close_search()
			get_viewport().set_input_as_handled()
			return
		if _calc_holder != null:
			_close_calculator()
			get_viewport().set_input_as_handled()
	elif key.ctrl_pressed and key.keycode == KEY_F:
		# 折叠态先展开浮层再聚焦（_open_search_overlay 内含 grab_focus）
		if _search_toggle_btn.visible:
			_open_search_overlay()
		else:
			_search_box.grab_focus()
		get_viewport().set_input_as_handled()

# ---------- 软键盘避让（唯一依据：DisplayServer.virtual_keyboard_get_height） ----------

## 焦点变化统一入口（gui_focus_changed，探针确认存在）：Line 系控件获焦视为
## 可能弹软键盘——轮询器启动；焦点移走或清空则停止（键盘自然收起，高度归 0
## 由下一 tick 撤回 inset）。
func _on_viewport_focus_changed(control: Control) -> void:
	if control is LineEdit:
		_start_keyboard_poll()
	else:
		_stop_keyboard_poll()

## 字段获焦 → 启动轮询。轮询而非单次延迟读取：Android 键盘弹出动画期间高度
## 渐变，逐帧追平；iOS 窗口不 resize，高度读取是唯一线索（真机是否返回非 0
## 待实测——高度归 0 时 inset 同步撤回，API 无效平台退化为无避让而非错乱）。
func _start_keyboard_poll() -> void:
	_kb_prev_inset = -1
	if not _kb_timer.is_stopped():
		return
	_poll_keyboard_inset()  # 先同步读一次（键盘已弹出时首个 tick 即生效）
	_kb_timer.start()

func _stop_keyboard_poll() -> void:
	_kb_timer.stop()
	_kb_prev_inset = -1
	_write_keyboard_inset(0)

## 轮询 tick：键盘高度换算为设计像素 inset，经唯一写者写入根 MarginContainer
## margin_bottom（与安全区 bottom inset 取 max——单写者，消除两处写互踩抖动）。
func _poll_keyboard_inset() -> void:
	var h := float(DisplayServer.virtual_keyboard_get_height())
	var inset := 0
	if h > 0.0 and get_window() != null:
		var win_size := Vector2(DisplayServer.window_get_size())
		if win_size.y > 0.0:
			inset = int(h * (1280.0 / win_size.y))
	_write_keyboard_inset(inset)

## 键盘 inset 写入（唯一写者）：maxf(安全区 bottom, 键盘) 后写同一 MarginContainer；
## 值未变不重写。焦点离开键盘自然收起、高度归 0，inset 同帧撤回。
func _write_keyboard_inset(keyboard_inset: int) -> void:
	if keyboard_inset == _kb_prev_inset:
		return
	_kb_prev_inset = keyboard_inset
	for child: Node in get_children():
		if child is MarginContainer:
			var bottom := maxf(_safe_inset_design.z, float(keyboard_inset))
			child.add_theme_constant_override(
				"margin_bottom", 12 + int(bottom))

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
	_sync_theme_button()

## 主题按钮选中态：深色主题时按下（toggle_mode + button_pressed 反映当前主题，
## 与导航按钮的选中语言一致；亮色为未选中默认态）
func _sync_theme_button() -> void:
	_theme_btn.button_pressed = String(GKServices.settings.get_value("theme")) == "dark"

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
	_top_bar = top  # 直接持引用：_update_search_popup_pos 不再走节点路径/遍历兜底

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
	# 窄屏（COMPACT <600）折叠为图标钮——720 基准减导航四钮后顶栏溢出，
	# 点按图标把搜索框移入浮层展开输入（形态切换见 _apply_search_fold）
	_search_box = LineEdit.new()
	_search_box.name = "SearchBox"
	_search_box.placeholder_text = "搜索计算器…"
	_search_box.custom_minimum_size = Vector2(200, GKThemeConstants.TOUCH_TARGET)
	_search_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_box.size_flags_stretch_ratio = 1.0
	_search_box.text_changed.connect(_on_search_changed)
	_search_box.text_submitted.connect(_on_search_submitted)
	top.add_child(_search_box)
	_search_box_parent = top  # 展开态归还位置（折叠/展开只挪动不重建）

	_search_toggle_btn = Button.new()
	_search_toggle_btn.text = "🔍"
	_search_toggle_btn.custom_minimum_size = Vector2(0, GKThemeConstants.TOUCH_TARGET)
	_search_toggle_btn.visible = false  # 默认中/宽屏常驻搜索框，窄屏才折叠
	_search_toggle_btn.pressed.connect(_open_search_overlay)
	top.add_child(_search_toggle_btn)

	_theme_btn = Button.new()
	_theme_btn.text = "深/浅"
	_theme_btn.toggle_mode = true  # 选中态 = 当前为深色主题（见 _sync_theme_button）
	_theme_btn.custom_minimum_size = Vector2(0, GKThemeConstants.TOUCH_TARGET)
	_theme_btn.pressed.connect(_on_theme_toggle)
	top.add_child(_theme_btn)
	_sync_theme_button()

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
	# 窄屏折叠态时浮层顶部多一行搜索框宿主（图标钮点开后 LineEdit 挪入此处）
	_search_popup = PanelContainer.new()
	_search_popup.name = "SearchPopup"
	_search_popup.theme_type_variation = &"Card"
	_search_popup.visible = false
	_search_popup.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	add_child(_search_popup)
	var sv := VBoxContainer.new()
	_search_popup.add_child(sv)
	_search_in_popup_box = VBoxContainer.new()
	_search_in_popup_box.visible = false  # 展开态才显示（_apply_search_fold 控制）
	sv.add_child(_search_in_popup_box)
	_search_hint = Label.new()
	_search_hint.theme_type_variation = &"Caption"
	_search_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 文本不拦点击（同 result_card）
	sv.add_child(_search_hint)
	var scroll := ScrollContainer.new()
	# 裸 ScrollContainer 不走 GKTouchScroll（浮层需默认滚动条），但 deadzone
	# 口径与 GKTouchScroll.TOUCH_DEADZONE 一致：一碰就滚会误判点击
	scroll.scroll_deadzone = 24
	# 高度随视口收缩：固定 480 在矮窗口（如桌面 720×960 覆盖半屏）会顶出视口，
	# 上限 480、下限 0.4×视口高，max 后仍不超过视口可用高。
	var vp_h := get_viewport_rect().size.y
	scroll.custom_minimum_size = Vector2(0, maxf(240.0, minf(480.0, vp_h * 0.4)))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sv.add_child(scroll)
	_search_scroll = scroll  # resize 后 _apply_search_fold 重算高度上限
	_search_results = VBoxContainer.new()
	_search_results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_search_results)
	# 浮层自身不吞全屏点击：click 外部关闭靠 gui_focus_changed 的焦点丢失判定
	# （LineEdit 失焦即收起），无需全屏透明遮罩（遮罩会拦住浮层内滚动）。
	# 启动按当前断点定搜索形态（窄屏折叠 / 中宽常驻）+ 挂视口 resize 重算
	_apply_search_fold()
	get_viewport().size_changed.connect(_apply_search_fold)

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
	var y := 64.0
	if _top_bar != null:
		y = _top_bar.position.y + _top_bar.size.y + 4.0
	_search_popup.position = Vector2(12 + _safe_inset_design.w, y)
	_search_popup.size = Vector2(size.x - 24.0 - _safe_inset_design.w - _safe_inset_design.y, 0)

# ---------- 搜索（常驻顶栏 + 窄屏折叠浮层） ----------

## 搜索形态（断点驱动，视口 resize 重算）：
##   COMPACT（<600）：顶栏搜索框折叠为图标钮，LineEdit 挪入浮层顶部行；
##   MEDIUM/WIDE：搜索框回顶栏 Expand 位，浮层只放结果（图标钮隐藏）。
## 只挪动 _search_box 一个控件（不重建），焦点态/文本随控件保留。
func _apply_search_fold() -> void:
	if _search_box == null or _search_toggle_btn == null:
		return
	var folded := GKResponsive.breakpoint_now(self) == GKResponsive.Breakpoint.COMPACT
	_search_toggle_btn.visible = folded
	# 浮层高度随视口收缩：上限 480、下限 0.4×视口高、兜底 240（矮窗不顶出视口）
	if _search_scroll != null:
		var vp_h := get_viewport_rect().size.y
		_search_scroll.custom_minimum_size = Vector2(0, maxf(240.0, minf(480.0, vp_h * 0.4)))
	if folded:
		if _search_box.get_parent() != _search_in_popup_box:
			# 折叠：顶栏 → 浮层顶部宿主行；同时把浮层内搜索框行显示出来
			_search_box.get_parent().remove_child(_search_box)
			_search_in_popup_box.add_child(_search_box)
			_search_in_popup_box.visible = true
	else:
		if _search_box.get_parent() != _search_box_parent:
			# 展开：浮层 → 顶栏 Expand 位（加回末尾，主题钮之前顺序无碍——
			# _search_box 本在主题钮前，重挂后仍在原位附近，导航钮不重建）
			_search_box.get_parent().remove_child(_search_box)
			var theme_idx := _search_box_parent.get_children().find(_theme_btn)
			_search_box_parent.add_child(_search_box)
			if theme_idx >= 0:
				_search_box_parent.move_child(_search_box, theme_idx)
			_search_in_popup_box.visible = false
			_close_search()

## 窄屏图标钮点按：展开浮层并聚焦搜索框（浮层此时兼作输入面板）
func _open_search_overlay() -> void:
	_update_search_popup_pos()
	_search_popup.visible = true
	_search_box.grab_focus()

## 搜索浮层点击外部关闭：LineEdit 焦点丢失且浮层可见 → 收起。
## 窄屏折叠态搜索框在浮层内；中/宽屏在顶栏——点结果条目先走 pressed（内部
## 先 _close_search），失焦收起不会误伤点按。展开态下顶栏搜索框失焦即收
## （main.gd:201 旧注释「失焦收起」的实际兑现）。
func _on_viewport_gui_focus_lost() -> void:
	if _search_popup != null and _search_popup.visible and _search_box != null:
		_close_search()

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
		# 图标与首页分类同源：条目 → 展示组 → GROUPS.icon（GKDisplayGroups 头注释的赋值规则）
		var gkey := GKDisplayGroups.entry_group(String(e.get("id", "")), e)
		var icon_path := GKDisplayGroups.group_icon(gkey)
		if icon_path != "" and ResourceLoader.exists(icon_path):
			b.icon = load(icon_path)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		# 触控目标按设备降档：触屏 96 / 指针 56（resize 后由 _apply_touch_targets 补齐）
		b.custom_minimum_size = Vector2(0, float(GKThemeConstants.TOUCH_TARGET
			if DisplayServer.is_touchscreen_available()
			else GKThemeConstants.TOUCH_TARGET_POINTER))
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
		none.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 文本不拦点击（同 result_card）
		_search_results.add_child(none)
	_update_search_popup_pos()
	_search_popup.visible = true

func _close_search() -> void:
	if _search_popup == null:
		return
	_search_popup.visible = false
	_search_box.text = ""
	# 窄屏折叠态下浮层即输入面板：一并收回图标态（焦点撤出防键盘残留）
	if _search_toggle_btn.visible:
		_search_box.release_focus()

# ---------- 响应式切换（触控目标高度单一职责） ----------

func _on_resized(_is_wide: bool) -> void:
	_apply_touch_targets()

## 触屏设备 96 触控目标 / 指针设备（宽屏键鼠）56——按设备能力而非断点：
## 触屏判定用 DisplayServer.is_touchscreen_available（真机/平板 true）。
## 搜索结果条目同口径降档：触屏 96 / 指针 56（main.gd:282 触控目标承诺）。
func _apply_touch_targets() -> void:
	var touch := DisplayServer.is_touchscreen_available()
	var h := float(GKThemeConstants.TOUCH_TARGET if touch else GKThemeConstants.TOUCH_TARGET_POINTER)
	for key: String in _nav_buttons:
		(_nav_buttons[key] as Button).custom_minimum_size = Vector2(0, h)
	_back_btn.custom_minimum_size = Vector2(0, h)
	_theme_btn.custom_minimum_size = Vector2(0, h)
	_search_toggle_btn.custom_minimum_size = Vector2(0, h)
	_search_box.custom_minimum_size = Vector2(200, h)
	# 浮层内已存在的结果条目同步（_do_search 建行时按当时口径，resize 后补齐）
	if _search_results != null:
		for c: Control in _search_results.get_children():
			if c is Button:
				c.custom_minimum_size = Vector2(0, h)
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
		_alert_open_fail(String(entry.get("name", scene_path)), "计算器场景加载失败，请检查模块是否完整安装。")
		return
	var inst: Node = packed.instantiate()
	if not (inst is GKCalculatorBase):
		push_warning("场景根脚本未继承 GKCalculatorBase（契约违反）：%s" % scene_path)
		inst.queue_free()
		_alert_open_fail(String(entry.get("name", scene_path)), "计算器场景契约违反（根脚本未继承 GKCalculatorBase）。")
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

## 打开计算器失败的用户可见反馈：仅 push_warning 用户看不到（桌面控制台/移动端
## adb），点方块无任何反应像坏了——弹 AcceptDialog 给中文原因（局部变量即用即释）
func _alert_open_fail(name_text: String, reason: String) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "无法打开"
	dlg.dialog_text = "「%s」打开失败：%s" % [name_text, reason]
	get_tree().root.add_child(dlg)
	dlg.popup_centered()
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)

func _close_calculator(restore_page := true) -> void:
	if _calc_holder != null:
		_page_holder.remove_child(_calc_holder)
		_calc_holder.queue_free()
		_calc_holder = null
	_stop_keyboard_poll()  # 计算器关闭 → 字段焦点不复存在，键盘避让撤回
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
		if is_inside_tree() and get_window() != null:
			if get_window().size_changed.is_connected(_on_window_geometry_changed):
				get_window().size_changed.disconnect(_on_window_geometry_changed)
			if get_window().go_back_requested.is_connected(_on_go_back_requested):
				get_window().go_back_requested.disconnect(_on_go_back_requested)
			if get_window().gui_focus_changed.is_connected(_on_viewport_focus_changed):
				get_window().gui_focus_changed.disconnect(_on_viewport_focus_changed)

func _on_close_requested() -> void:
	if _bp_handle != null:
		_bp_handle.unwatch()
		_bp_handle = null
	if get_window() != null and get_window().size_changed.is_connected(_on_window_geometry_changed):
		get_window().size_changed.disconnect(_on_window_geometry_changed)
	GKServices.shutdown()
