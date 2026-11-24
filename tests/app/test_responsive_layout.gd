# tests/app/test_responsive_layout.gd —— P9 布局与响应式验收
#
# 覆盖：三档断点判定（600/900）、watch 句柄 + unwatch 不叠加、
# main.gd 顶部导航形态（搜索框常驻/全屏计算器挂载）、触控目标口径
# （触屏 96 / 指针 56）、主题常量收敛、TouchScroll 触控赋能。
extends "res://tests/test_case_base.gd"

func test_breakpoint_tiers() -> void:
	# 窄屏 <600
	assert_int_eq(int(GKResponsive.of_width(599.0)), int(GKResponsive.Breakpoint.COMPACT), "599 为窄屏")
	assert_int_eq(int(GKResponsive.of_width(0.0)), int(GKResponsive.Breakpoint.COMPACT), "0 为窄屏")
	# 中档 600–899
	assert_int_eq(int(GKResponsive.of_width(600.0)), int(GKResponsive.Breakpoint.MEDIUM), "600 为中档下界")
	assert_int_eq(int(GKResponsive.of_width(719.0)), int(GKResponsive.Breakpoint.MEDIUM), "719（设计基准宽）为中档")
	assert_int_eq(int(GKResponsive.of_width(899.0)), int(GKResponsive.Breakpoint.MEDIUM), "899 为中档上界")
	# 宽屏 ≥900
	assert_int_eq(int(GKResponsive.of_width(900.0)), int(GKResponsive.Breakpoint.WIDE), "900 为宽屏下界")
	assert_int_eq(int(GKResponsive.of_width(1280.0)), int(GKResponsive.Breakpoint.WIDE), "1280 为宽屏")
	assert_false(GKResponsive.is_medium(599.0), "599 非中档")
	assert_true(GKResponsive.is_medium(750.0), "750 为中档")
	assert_false(GKResponsive.is_medium(900.0), "900 非中档")
	assert_true(GKResponsive.is_wide(900.0), "宽屏断点保持 ≥900（P6 兼容）")
	assert_false(GKResponsive.is_wide(899.0), "899 非宽屏")

func test_watch_returns_handle_and_unwatch() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	assert_true(tree != null, "SceneTree 可取（headless 下）")
	if tree == null:
		return
	var ctl := Control.new()
	tree.root.add_child(ctl)
	# 计数须用引用类型：GDScript lambda 对外部局部变量按值捕获，int 计数在闭包内不生效
	var box := [0]
	var handle: GKResponsive.WatchHandle = GKResponsive.watch(ctl, func(_w: bool) -> void: box[0] += 1)
	assert_true(handle != null, "watch 返回连接句柄")
	if handle == null:
		ctl.free()
		return
	# 模拟视口尺寸变化信号（断点钩挂在 size_changed 上）
	ctl.get_viewport().emit_signal("size_changed")
	assert_int_eq(box[0], 1, "size_changed 触发断点回调一次")
	handle.unwatch()
	ctl.get_viewport().emit_signal("size_changed")
	assert_int_eq(box[0], 1, "unwatch 后不再触发（无叠加连接/无泄漏）")
	# 重复 unwatch 幂等
	handle.unwatch()
	assert_int_eq(box[0], 1, "重复 unwatch 幂等安全")
	ctl.free()

func test_main_topbar_form_structure() -> void:
	# P9 形态：顶部导航单行（Logo + 返回 + 四导航 + Expand 搜索框 + 主题），
	# 计算器全屏覆盖挂载；无侧栏/rail/抽屉/底部导航。
	var tree := Engine.get_main_loop() as SceneTree
	assert_true(tree != null, "SceneTree 可取")
	if tree == null:
		return
	GKServices.bootstrap()  # 幂等
	var scene := load("res://scenes/main.tscn")
	assert_true(scene != null, "main.tscn 可加载")
	if scene == null:
		return
	var inst: Node = scene.instantiate()
	tree.root.add_child(inst)
	var pages: Dictionary = inst.get("_pages")
	assert_int_eq(pages.size(), 1, "懒加载：启动只实例化首页")
	# 搜索框常驻（顶栏 LineEdit，非独立页面）
	var search_box: LineEdit = inst.get("_search_box")
	assert_true(search_box != null, "常驻搜索框已建")
	assert_true(search_box.is_inside_tree(), "搜索框已入树")
	# 搜索浮层初态隐藏
	var popup: PanelContainer = inst.get("_search_popup")
	assert_true(popup != null and not popup.visible, "搜索浮层初态隐藏")
	# 导航四页切换
	inst.call("_show_page", "settings")
	assert_true((pages["settings"] as Control).visible, "切换到设置页")
	assert_false((pages["home"] as Control).visible, "首页隐藏")
	# 安全区 margin 根容器已建：root 下第一个 MarginContainer
	var found_margin := false
	for child in inst.get_children():
		if child is MarginContainer:
			found_margin = true
	assert_true(found_margin, "根容器存在安全区 MarginContainer")
	tree.root.remove_child(inst)
	inst.free()

func test_fullscreen_calculator_mount() -> void:
	# P9：计算器全屏覆盖挂载（list-detail 已删除）；返回恢复原页面。
	var tree := Engine.get_main_loop() as SceneTree
	assert_true(tree != null, "SceneTree 可取")
	if tree == null:
		return
	GKServices.bootstrap()
	var inst: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(inst)
	var pages: Dictionary = inst.get("_pages")
	# 从历史页打开计算器 → 全屏覆盖；返回 → 回历史页（懒加载先实例化 history）
	inst.call("_show_page", "history")
	var calc: GKCalculatorBase = preload("res://scenes/widgets/calculator_base.gd").new()
	# 直接调全屏挂载路径（_open_entry 需要场景文件；协议结构直接注入）
	calc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inst.set("_calc_holder", calc)
	inst.set("_calc_return_page", "history")
	(inst.get("_page_holder") as Control).add_child(calc)
	for k: String in pages:
		pages[k].visible = false
	assert_true(calc.get_parent() == inst.get("_page_holder"), "计算器全屏挂载入页面区")
	# 关闭恢复原页面
	inst.call("_close_calculator")
	assert_true(inst.get("_calc_holder") == null, "关闭后计算器句柄清空")
	assert_true((pages["history"] as Control).visible, "返回恢复原页面（history）")
	tree.root.remove_child(inst)
	inst.free()

func test_touch_target_tiers() -> void:
	# P9：触控目标按设备能力（触屏 96 / 指针 56），headless 视为非触屏 → 56。
	var tree := Engine.get_main_loop() as SceneTree
	assert_true(tree != null, "SceneTree 可取")
	if tree == null:
		return
	GKServices.bootstrap()
	var inst: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(inst)
	var nav_buttons: Dictionary = inst.get("_nav_buttons")
	var theme_btn: Button = inst.get("_theme_btn")
	var search_box: LineEdit = inst.get("_search_box")
	var expect := float(GKThemeConstants.TOUCH_TARGET if DisplayServer.is_touchscreen_available() \
			else GKThemeConstants.TOUCH_TARGET_POINTER)
	for k: String in nav_buttons:
		assert_eq((nav_buttons[k] as Button).custom_minimum_size.y, expect,
			"导航按钮触控目标 = %d（设备能力口径）" % int(expect))
	assert_eq(theme_btn.custom_minimum_size.y, expect, "主题按钮触控目标同口径")
	assert_eq(search_box.custom_minimum_size.y, expect, "搜索框与导航同行等高")
	tree.root.remove_child(inst)
	inst.free()

func test_theme_constants_and_type_variations() -> void:
	# 布局常量唯一出处：触控目标 96 / 触控间距 16 / 结果值 48 / Caption 22
	assert_int_eq(GKThemeConstants.TOUCH_TARGET, 96, "触控目标常量 96")
	assert_int_eq(GKThemeConstants.MIN_TOUCH_SPACING, 16, "触控间距常量 ≥16")
	assert_int_eq(GKThemeConstants.FONT_RESULT, 48, "结果值字号 48")
	assert_int_eq(GKThemeConstants.FONT_CAPTION, 22, "Caption 字号 22")
	# 指针（宽屏键鼠）触控目标——WCAG 2.5.8 AA 24px 下限之上
	assert_true(GKThemeConstants.TOUCH_TARGET_POINTER >= 24,
		"指针触控目标 ≥24（WCAG 2.5.8 AA）")
	assert_int_eq(GKThemeConstants.TOUCH_TARGET_POINTER, 56, "指针触控目标常量 56")
	# 两套主题 .tres 均带 bg_color meta（P9 主题切换修复：清屏色随主题走）
	for path: String in ["res://themes/main.tres", "res://themes/dark.tres"]:
		var th := load(path) as Theme
		assert_true(th != null, path + " 可加载")
		if th == null:
			continue
		assert_true(th.get_meta("bg_color", null) != null, path + " 带 bg_color meta")
		assert_int_eq(th.get_font_size("font_size", "ResultValue"), 48, path + " ResultValue 48")
		assert_int_eq(th.get_font_size("font_size", "Caption"), 22, path + " Caption 22")
		assert_true(th.get_constant("h_separation", "TabBar") >= 16,
			path + " TabBar h_separation ≥16（触控间距）")

func test_settings_page_contract() -> void:
	# 设置页只调既有 settings.gd API：decimals 步进器 1–12、ui_scale 四档
	var tree := Engine.get_main_loop() as SceneTree
	assert_true(tree != null, "SceneTree 可取")
	if tree == null:
		return
	GKServices.bootstrap()
	var page: GKSettingsPage = preload("res://scenes/nav/settings_page.gd").new()
	tree.root.add_child(page)
	var spin: SpinBox = page.get("_decimals_spin")
	assert_true(spin != null, "decimals 步进器已建")
	if spin != null:
		assert_int_eq(int(spin.min_value), 1, "decimals 下界 1（既有契约）")
		assert_int_eq(int(spin.max_value), 12, "decimals 上界 12（既有契约）")
		assert_int_eq(int(spin.value), GKServices.settings.get_decimals(), "初始值取既有持久值")
		spin.value = 6.0
		assert_int_eq(GKServices.settings.get_decimals(), 6, "步进器变更经 set_value 持久化")
	var group: Array = page.get("_ui_scale_group")
	assert_int_eq(group.size(), 4, "ui_scale 四档按钮")
	if not group.is_empty():
		var std_btn: Button = group[1]
		std_btn.emit_signal("pressed")
		assert_almost_eq(float(GKServices.settings.get_value("ui_scale")), 1.0, 1e-9, "标准档落地")
	tree.root.remove_child(page)
	page.free()

func test_touch_scroll_attached() -> void:
	# P9 触控滚动：GKTouchScroll 工厂产出带拖滚/惯性的 ScrollContainer
	var s := GKTouchScroll.attach(false)
	assert_true(s is ScrollContainer, "attach 产出 ScrollContainer")
	assert_true(s is GKTouchScroll, "产出实例挂 GKTouchScroll 脚本")
	assert_true(s.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
		"默认禁横滚（窄屏口径）")
	var s2 := GKTouchScroll.attach(true)
	assert_false(s2.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
		"显式开启横滚可行")
	s.free()
	s2.free()
