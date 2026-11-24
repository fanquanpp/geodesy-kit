# themes/responsive.gd —— 响应式断点（ARCHITECTURE.md §1.4，P7 扩展为三档）
#
# 口径（调研 multiple_resolutions/gui_containers + Material 3 window size classes）：
#   - 单一设计基准 720×1280 + stretch canvas_items/expand（project.godot）；
#   - COMPACT（有效宽 <600 设计 px）：底部 TabBar 四类导航 + 抽屉（原窄屏形态）；
#   - MEDIUM（600–899 设计 px）：底部导航保留，内容区按 M3 medium 形态处理
#     （导航条目横向排布 / 输入两列，不再全屏单列）；
#   - WIDE（≥900 设计 px）：HBox 侧边栏 + 内容区，计算器页 list-detail 双栏；
#   - 断点切换钩 get_viewport().size_changed 信号，由本类统一实现。
#   watch() 返回连接句柄（GKResponsive.WatchHandle），调用方须在页面销毁/退出时
#   调 handle.unwatch() 断开（同一线程内重复 watch 同一回调不叠加——每个 handle
#   独立持有一条连接，unwatch 精确断开自己的那条）。
class_name GKResponsive
extends RefCounted

const MEDIUM_MIN_WIDTH := 600.0
const WIDE_MIN_WIDTH := 900.0

enum Breakpoint { COMPACT, MEDIUM, WIDE }

## 断点连接句柄：watch() 的返回值，unwatch() 精确断开本句柄持有的一条连接。
class WatchHandle:
	extends RefCounted
	var _vp: Viewport
	var _conn: Callable
	var _connected := false

	## 断开本句柄的断点回调（幂等：未连接/视口已释放时安全返回）。
	func unwatch() -> void:
		if _connected and _vp != null and is_instance_valid(_vp):
			_vp.size_changed.disconnect(_conn)
		_connected = false
		_vp = null
		_conn = Callable()

## 注意：函数名不能用保留字 `breakpoint`（GDScript 断点语句），故为 of_width。
static func of_width(width: float) -> Breakpoint:
	if width >= WIDE_MIN_WIDTH:
		return Breakpoint.WIDE
	if width >= MEDIUM_MIN_WIDTH:
		return Breakpoint.MEDIUM
	return Breakpoint.COMPACT

static func is_wide(width: float) -> bool:
	return width >= WIDE_MIN_WIDTH

## 中档（600–899 设计 px）：M3 medium 形态——导航保留、内容双列，不再全屏单列。
static func is_medium(width: float) -> bool:
	return width >= MEDIUM_MIN_WIDTH and width < WIDE_MIN_WIDTH

## 当前视口断点（stretch 后的设计像素）
static func breakpoint_now(control: Control) -> Breakpoint:
	if control == null or control.get_viewport() == null:
		return Breakpoint.WIDE
	return of_width(control.get_viewport().get_visible_rect().size.x)

## 当前视口是否宽屏（stretch 后的设计像素）
static func is_wide_now(control: Control) -> bool:
	return breakpoint_now(control) == Breakpoint.WIDE

## 挂接断点回调：视口尺寸变化时 callback(is_wide) 被调用（is_wide = ≥900 设计 px，
## 与既有 P6 用法兼容；中档区分请配合 breakpoint_now / is_medium 使用）。
## 返回连接句柄（调用方退出/销毁时须 handle.unwatch()）；视口不可用时返回未连接句柄。
static func watch(control: Control, callback: Callable) -> WatchHandle:
	var handle := WatchHandle.new()
	if control == null:
		return handle
	var vp := control.get_viewport()
	if vp == null:
		return handle
	var cb := func() -> void:
		callback.call(is_wide_now(control))
	vp.size_changed.connect(cb)
	handle._vp = vp
	handle._conn = cb
	handle._connected = true
	return handle
