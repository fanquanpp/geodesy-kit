# platform/touch_scroll.gd —— ScrollContainer 触屏滚动配置（P9.4 重写）
#
# 历史教训：P9 曾用自定义 _gui_input 拦截 InputEventScreenTouch/Drag 手动滚动，
# 真机实测滑动常被判定为点击——自定义拦截与子控件的按压反馈/点击判定互相干扰
# （手指按下即写 _drag_active，但按钮在 press 瞬间已触发 pressed，无法撤回）。
#
# 调研结论（Godot 4 官方文档）：ScrollContainer **原生支持触屏拖滚**
# （Android/iOS 直接可用；桌面需 emulate_touch_from_mouse），且提供：
#   - scroll_deadzone：触屏滚动判定死区（默认 0 = 一碰就滚，误判点击根因）；
#   - NOTIFICATION_SCROLL_BEGIN/END：滚动中通知（可用于抑制误点击）；
#   - scroll_started/scroll_ended 信号。
# 本类只做三件事：①设合理 deadzone（24 设计 px，超过才算拖动）；
# ②隐藏滚动条（触屏拖滚导航，滚动条不占内容宽）；③横滚开关。
# 拖动/点击判定交还引擎原生路径——按钮在滚动开始后自动不触发点击。
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
	return s

## 是否正处于触屏拖滚中（宿主需要抑制误点击时查询）
func is_touch_scrolling() -> bool:
	return _scrolling

var _scrolling := false

func _notification(what: int) -> void:
	if what == NOTIFICATION_SCROLL_BEGIN:
		_scrolling = true
	elif what == NOTIFICATION_SCROLL_END:
		_scrolling = false
