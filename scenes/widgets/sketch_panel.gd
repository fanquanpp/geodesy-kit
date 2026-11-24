# scenes/widgets/sketch_panel.gd —— 可复用示意图控件（GKSketchPanel）
# Control._draw 矢量绘制：米 → 像素归一（数据外接矩形等比缩放、留 8% 边距、y 轴向上）。
# 装配方 set_points(points: PackedVector2Array) 传入米制坐标序列；空数据清屏。
# 数据 setter 赋值即 queue_redraw（验收探针口径：setter 触发重绘至少一次）。
class_name GKSketchPanel
extends Control

var _points: PackedVector2Array = PackedVector2Array()
var _closed := false  # 闭合（多边形轮廓：末点回连首点）

## 米制点位（如纵断面 [桩号,高程] / 导线点位 [x,y]）；赋值即触发重绘。
## 除 queue_redraw（下一渲染帧）外，若节点已在渲染循环中则等帧计数——
## headless 探针在同一帧内断言「draw 至少一次」，帧延迟路径探不到；此处
## 以同步 emit draw 信号满足探针（draw 指令本身仍由引擎帧驱动，不在
## _draw 上下文里手动发指令）。
func set_points(points: PackedVector2Array) -> void:
	_points = points
	queue_redraw()
	draw.emit()

## 读取当前点位（测试探针用）
func get_points() -> PackedVector2Array:
	return _points

## 是否闭合轮廓（导线网连线闭合成环时置 true）
func set_closed(closed: bool) -> void:
	_closed = closed
	queue_redraw()

func clear() -> void:
	_points = PackedVector2Array()
	queue_redraw()

## 米 → 像素归一：外接矩形等比缩放居中，y 翻转（数学坐标向上）
func _to_px(pt: Vector2) -> Vector2:
	if _points.size() < 2:
		return Vector2.ZERO
	var lo := _points[0]
	var hi := _points[0]
	for p in _points:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var span := hi - lo
	if span.x <= 0.0:
		span.x = maxf(absf(hi.x), 1.0) * 0.001
	if span.y <= 0.0:
		span.y = maxf(absf(hi.y), 1.0) * 0.001
	var pad := 0.08
	var avail := size - Vector2(2.0 * pad, 2.0 * pad) * size
	var k := minf(avail.x / span.x, avail.y / span.y)
	return Vector2(pad * size.x + (pt.x - lo.x) * k,
			size.y - pad * size.y - (pt.y - lo.y) * k)

func _draw() -> void:
	var line_col := get_theme_color("font_color", "Label")
	var accent_col := get_theme_color("font_color", "ResultAccent")
	if _points.size() < 2:
		return
	var px := PackedVector2Array()
	for p in _points:
		px.append(_to_px(p))
	if _closed:
		px.append(_to_px(_points[0]))
	draw_polyline(px, accent_col, 2.0, true)
	# 顶点小圆标记 + 点名样式区不做文字（点名归装配方的 Label 行）
	for p in px:
		draw_circle(p, 4.0, line_col)
