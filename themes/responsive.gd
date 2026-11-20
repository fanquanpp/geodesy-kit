# themes/responsive.gd —— 响应式断点（ARCHITECTURE.md §1.4）
#
# 口径（调研 multiple_resolutions/gui_containers）：
#   - 单一设计基准 720×1280 + stretch canvas_items/expand（project.godot）；
#   - 宽屏（有效宽 ≥900 设计 px）：HBox 侧边栏 + 内容区；
#   - 窄屏（<900）：隐藏侧边栏，底部 TabBar 四类导航 + 抽屉；
#   - 断点切换钩 get_viewport().size_changed 信号，由本类统一实现。
class_name GKResponsive
extends RefCounted

const WIDE_MIN_WIDTH := 900.0

static func is_wide(width: float) -> bool:
	return width >= WIDE_MIN_WIDTH

## 当前视口是否宽屏（stretch 后的设计像素）
static func is_wide_now(control: Control) -> bool:
	if control == null or control.get_viewport() == null:
		return true
	return is_wide(control.get_viewport().get_visible_rect().size.x)

## 挂接断点回调：视口尺寸变化时 callback(is_wide) 被调用。
## 返回 Signal 连接对象（调用方可自行断开）。
static func watch(control: Control, callback: Callable) -> void:
	var vp := control.get_viewport()
	if vp == null:
		return
	vp.size_changed.connect(func() -> void:
		callback.call(is_wide_now(control))
	)
