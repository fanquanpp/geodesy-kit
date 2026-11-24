# platform/touch_scroll.gd —— ScrollContainer 触屏拖滚赋能（P9 触控优化）
#
# 问题（用户真机反馈「只能拖动滚动条才能动」）：Godot ScrollContainer 在触屏上
# 默认只响应滚轮/滚动条拖拽，手指拖动内容不滚动（无惯性 pan）。
# 修法：给滚动容器挂本脚本扩展，_gui_input 拦截 InputEventScreenDrag/Touch
# 手动滚动 + 惯性衰减（每帧 scroll_vertical += velocity，速度 ×0.92 衰减）。
# 用法：GKTouchScroll.attach(scroll) 替换直接 new ScrollContainer——
# 返回挂了脚本的实例；桌面端行为不变（无 touch 事件走到默认处理）。
class_name GKTouchScroll
extends ScrollContainer

var _drag_active := false
var _last_pos := Vector2.ZERO
var _velocity := Vector2.ZERO
var _inertia := false

## 工厂：创建并返回触控赋能的 ScrollContainer（等价 ScrollContainer.new() + 挂脚本）
static func attach(horizontal_enabled := false) -> GKTouchScroll:
	var s := GKTouchScroll.new()
	if not horizontal_enabled:
		s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return s

func _ready() -> void:
	# 触屏设备才需要拖滚；桌面端保持原生滚轮行为
	set_process(_drag_active or _inertia)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_drag_active = true
			_inertia = false
			_last_pos = event.position
			_velocity = Vector2.ZERO
			accept_event()
		else:
			_drag_active = false
			# 松手时保留速度做惯性滚动（阈值以下直接停）
			_inertia = _velocity.length() > 2.0
			set_process(_drag_active or _inertia)
			accept_event()
	elif event is InputEventScreenDrag and _drag_active:
		var drag := event as InputEventScreenDrag
		var move := drag.position - _last_pos
		_last_pos = drag.position
		_velocity = drag.velocity
		# 手指移动即滚动（拖内容 = 滚动条反向，符合自然触控映射）
		scroll_vertical -= int(move.y)
		if horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			scroll_horizontal -= int(move.x)
		accept_event()

func _process(delta: float) -> void:
	if _inertia:
		var d := float(delta)
		scroll_vertical -= int(_velocity.y * d)
		if horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			scroll_horizontal -= int(_velocity.x * d)
		_velocity *= pow(0.92, d * 60.0)  # 帧率无关的指数衰减
		if _velocity.length() < 2.0:
			_inertia = false
			set_process(false)