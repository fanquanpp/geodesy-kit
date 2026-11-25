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
## horizontal_enabled=false 禁横滚；show_bar=false 隐藏纵向滚动条。
static func attach(horizontal_enabled := false, show_bar := false) -> GKTouchScroll:
	var s := GKTouchScroll.new()
	if not horizontal_enabled:
		s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.scroll_deadzone = int(TOUCH_DEADZONE)
	s.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER if not show_bar \
			else ScrollContainer.SCROLL_MODE_AUTO
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
