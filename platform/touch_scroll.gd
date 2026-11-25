# platform/touch_scroll.gd —— ScrollContainer 触屏滚动配置（v0.4 官方拖滚修复）
#
# 历史教训：
#   - P9：自定义 _gui_input 拦截触控手动滚动——与子控件点击判定互相干扰，废弃；
#   - P9.4：改用引擎原生触屏拖滚 + deadzone=24 区分点击/拖动；
#   - v0.4 深挖：原生拖滚在 MIUI 上「卡片上滑动不滚，只有裸背景能滚」——
#     根因（godot#16318/#95532，六年老 bug）：ScrollContainer 的触屏拖滚只认
#     落入它 gui_input 的 ScreenTouch/ScreenDrag，而 PanelContainer/
#     FoldableContainer/Button 默认 mouse_filter=STOP，把事件吞掉不冒泡。
#
# 官方解法（两件事缺一不可，godot#16318 → #95532 演化结论）：
#   1. 子控件 mouse_filter STOP→PASS：不处理时向上冒泡到 ScrollContainer；
#   2. scroll_deadzone=24：deadzone 内 = 点击（Button RELEASE 模式正常触发），
#      超出 = NOTIFICATION_SCROLL_BEGIN，base_button 原生取消按钮按压——
#      「滑动不误触、点击不失效」两全。
# 本类自动做第 1 件事：attach() 的 child_entered_tree hook 把入树子树统一
# STOP→PASS；NOTIFICATION_CHILD_ORDER_CHANGED 兜底重扫动态 add 的子树。
class_name GKTouchScroll
extends ScrollContainer

## 触屏拖动判定死区（设计 px）：低于此位移视为点击（按钮/输入框可正常点），
## 高于此才进入滚动——真机反馈「滑动总被判定点击」的修复项。
const TOUCH_DEADZONE := 24.0

## 工厂：创建触屏友好的 ScrollContainer。
## horizontal_enabled=false 禁横滚；show_bar 默认 true（v0.4：触屏拖滚判定在
## 部分 ROM 上仍不可靠，加回可见滚动条——拖动滚动条是确定的滚动路径）。
static func attach(horizontal_enabled := false, show_bar := true) -> GKTouchScroll:
	var s := GKTouchScroll.new()
	if not horizontal_enabled:
		s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.scroll_deadzone = int(TOUCH_DEADZONE)
	# SHOW_ALWAYS：滚动条常显（含灰色轨道）——用户要求可见滚动条作为可靠的
	# 滚动路径（AUTO 在内容不超屏时隐藏，横屏首页看不到会以为没生效）
	s.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS if show_bar \
			else ScrollContainer.SCROLL_MODE_SHOW_NEVER
	# 滚动条加粗（v0.4 用户反馈"太细"）：grabber 主体 16dp 宽、热区 32dp——
	# StyleBoxFlat content_margin 撑出热区，中央画粗 grabber；
	# custom_minimum_size 32dp 保证手指能点中/拖住。
	var vbar := s.get_v_scroll_bar()
	vbar.custom_minimum_size = Vector2(32, 0)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(0.42, 0.47, 0.56, 0.9)  # 中性灰蓝，深浅主题都可辨
	grabber.set_corner_radius_all(8)
	grabber.set_content_margin_all(0)
	grabber.content_margin_left = 8.0   # grabber 视觉宽 16dp：左右 margin 各 8
	grabber.content_margin_right = 8.0
	grabber.expand_margin_left = 6.0    # 热区外扩：手指命中更容易
	grabber.expand_margin_right = 6.0
	vbar.add_theme_stylebox_override("grabber", grabber)
	var grabber_hl := grabber.duplicate()
	grabber_hl.bg_color = Color(0.52, 0.58, 0.68, 1.0)  # hover/按下更亮
	vbar.add_theme_stylebox_override("grabber_highlight", grabber_hl)
	vbar.add_theme_stylebox_override("grabber_pressed", grabber_hl)
	# 直接子节点入树即展开整棵子树转 PASS
	s.child_entered_tree.connect(func(node: Node) -> void:
		if node is Control:
			_apply_pass_recursive(node as Control))
	return s

## 递归把控件树里的 STOP mouse_filter 转 PASS（Label 的 IGNORE 不动）。
static func _apply_pass_recursive(c: Control) -> void:
	if c.mouse_filter == Control.MOUSE_FILTER_STOP:
		c.mouse_filter = Control.MOUSE_FILTER_PASS
	for child in c.get_children():
		if child is Control:
			_apply_pass_recursive(child as Control)

## 是否正处于触屏拖滚中（宿主需要抑制误点击时查询）
func is_touch_scrolling() -> bool:
	return _scrolling

var _scrolling := false

func _notification(what: int) -> void:
	if what == NOTIFICATION_SCROLL_BEGIN:
		_scrolling = true
	elif what == NOTIFICATION_SCROLL_END:
		_scrolling = false
	elif what == NOTIFICATION_CHILD_ORDER_CHANGED:
		# 动态 add 的子树（先挂 v 后挂卡片等）重扫一遍 STOP→PASS
		for child in get_children():
			if child is Control:
				_apply_pass_recursive(child as Control)
