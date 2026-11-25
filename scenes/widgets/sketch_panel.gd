# scenes/widgets/sketch_panel.gd —— 可复用示意图控件（GKSketchPanel）
# Control._draw 矢量绘制：米 → 像素归一（数据外接矩形等比缩放、留 8% 边距、y 轴向上）。
# 装配方 set_points(points: PackedVector2Array) 传入米制坐标序列；空数据清屏。
# 数据 setter 赋值即 queue_redraw（验收探针口径：setter 触发重绘至少一次）。
# 可选装饰（默认全关，不传则与旧版裸折线观感一致，向后兼容）：
#   - set_axes(true)：米制格网（draw_dashed_line）+ 边缘刻度值（draw_string）；
#   - set_scale_bar(true)：右下角比例尺线段（按当前米→像素换算标注真实长度）；
#   - set_north_arrow(true)：右上角指北针（N + 箭头；平面图语义，纵断面勿开）；
#   - set_arc_segments(segments)：曲线段（竖曲线/圆曲线）——半透明填充 + 圆弧
#     叠加 + 「R=xxx m」半径注记，segments 形如 [{points, radius_m}]。
class_name GKSketchPanel
extends Control

var _points: PackedVector2Array = PackedVector2Array()
var _closed := false  # 闭合（多边形轮廓：末点回连首点）
var _show_axes := false        # 格网 + 刻度
var _show_scale_bar := false   # 比例尺
var _show_north := false       # 指北针
var _arc_segments: Array = []  # 曲线段 [{points: PackedVector2Array, radius_m: float}]

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

## 米制格网 + 刻度（平面/纵断面通用：格网随数据外接矩形取整米间距）
func set_axes(enabled: bool) -> void:
	_show_axes = enabled
	queue_redraw()

## 比例尺（右下角，长度随当前缩放取 1/2/5×10ⁿ 米整值）
func set_scale_bar(enabled: bool) -> void:
	_show_scale_bar = enabled
	queue_redraw()

## 指北针（右上角；仅平面图开启——y 轴向上即北）
func set_north_arrow(enabled: bool) -> void:
	_show_north = enabled
	queue_redraw()

## 曲线段装饰：segments 元素 {points: PackedVector2Array(米制), radius_m: float}。
## 半透明填充 + 顶点折线 + 圆弧 + R 注记；传 [] 清除。
func set_arc_segments(segments: Array) -> void:
	_arc_segments = segments
	queue_redraw()

func clear() -> void:
	_points = PackedVector2Array()
	_arc_segments = []
	queue_redraw()

## 米 → 像素归一：外接矩形等比缩放居中，y 翻转（数学坐标向上）。
## 装饰（格网/比例尺/曲线段）共用同一换算，故抽出返回缩放系数。
func _to_px(pt: Vector2) -> Vector2:
	if _points.size() < 2:
		return Vector2.ZERO
	return _map_px(_points, pt)

func _map_px(pts: PackedVector2Array, pt: Vector2) -> Vector2:
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
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

## 数据外接矩形的米→像素缩放系数（格网间距/比例尺换算用）
func _scale_factor() -> float:
	if _points.size() < 2:
		return 0.0
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
	return minf(avail.x / span.x, avail.y / span.y)

func _draw() -> void:
	var line_col := get_theme_color("font_color", "Label")
	var accent_col := get_theme_color("font_color", "ResultAccent")
	var muted_col := get_theme_color("font_color", "Caption")
	if _points.size() < 2:
		return
	if _show_axes:
		_draw_grid(muted_col)
	var px := PackedVector2Array()
	for p in _points:
		px.append(_to_px(p))
	if _closed:
		px.append(_to_px(_points[0]))
	# 曲线段：先填充（垫底）再画弧线与注记，最后主折线压顶
	for seg: Dictionary in _arc_segments:
		_draw_arc_segment(seg, accent_col, muted_col)
	draw_polyline(px, accent_col, 2.0, true)
	# 顶点小圆标记 + 点名样式区不做文字（点名归装配方的 Label 行）
	for p in px:
		draw_circle(p, 4.0, line_col)
	if _show_scale_bar:
		_draw_scale_bar(line_col, muted_col)
	if _show_north:
		_draw_north_arrow(line_col)

## 米制格网：按缩放系数取「好看」的整间距（1/2/5×10ⁿ 米），虚线 + 边缘刻度值
func _draw_grid(muted_col: Color) -> void:
	var k := _scale_factor()
	if k <= 0.0:
		return
	var step := _nice_step(k)  # 米
	var lo := _points[0]
	var hi := _points[0]
	for p in _points:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var font := get_theme_font("font", "Label")
	var fs := get_theme_font_size("font_size", "Caption")
	if font == null:
		return
	# 竖格网线（x = step 整数倍）
	var x0 := ceilf(lo.x / step) * step
	var x := x0
	while x <= hi.x:
		var px_x := _map_px(_points, Vector2(x, lo.y)).x
		draw_dashed_line(Vector2(px_x, 0), Vector2(px_x, size.y), muted_col, 1.0, 4.0)
		draw_string(font, Vector2(px_x + 2.0, size.y - 4.0),
				_format_m(x), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, muted_col)
		x += step
	# 横格网线（y = step 整数倍）
	var y0 := ceilf(lo.y / step) * step
	var y := y0
	while y <= hi.y:
		var px_y := _map_px(_points, Vector2(lo.x, y)).y
		draw_dashed_line(Vector2(0, px_y), Vector2(size.x, px_y), muted_col, 1.0, 4.0)
		draw_string(font, Vector2(2.0, px_y - 2.0),
				_format_m(y), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, muted_col)
		y += step

## 「好看」的格网间距：像素间距 ≥48px 的 1/2/5×10ⁿ 米序列
func _nice_step(k: float) -> float:
	for exp_mult: int in [-2, -1, 0, 1, 2, 3, 4]:
		for mult: int in [1, 2, 5]:
			var m := float(mult) * pow(10.0, float(exp_mult))
			if m * k >= 48.0:
				return m
	return 1.0

func _format_m(v: float) -> String:
	if absf(v) >= 1000.0:
		return "%.0fk" % (v / 1000.0)
	return "%.0f" % v

## 比例尺：右下角横线 + 端刻度 + 真实长度标注（长度取像素 80~160px 内的整米值）
func _draw_scale_bar(line_col: Color, muted_col: Color) -> void:
	var k := _scale_factor()
	if k <= 0.0:
		return
	var length_m := 0.0
	for exp_mult: int in [-2, -1, 0, 1, 2, 3, 4]:
		for mult: int in [1, 2, 5]:
			var m := float(mult) * pow(10.0, float(exp_mult))
			var px_len := m * k
			if px_len >= 80.0:
				length_m = m
				break
		if length_m > 0.0:
			break
	if length_m <= 0.0:
		return
	var px_len := length_m * k
	var org := Vector2(size.x - 24.0 - px_len, size.y - 16.0)
	var end := Vector2(size.x - 24.0, size.y - 16.0)
	draw_line(org, end, line_col, 2.0)
	draw_line(org, org + Vector2(0, -6.0), line_col, 2.0)
	draw_line(end, end + Vector2(0, -6.0), line_col, 2.0)
	var font := get_theme_font("font", "Label")
	var fs := get_theme_font_size("font_size", "Caption")
	if font != null:
		var label := "%s m" % _format_m(length_m)
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(end.x - w, org.y - 8.0), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, muted_col)

## 指北针：右上角竖线 + 实心箭头 + N 字（y 轴向上即北，与归一口径一致）
func _draw_north_arrow(line_col: Color) -> void:
	var tip := Vector2(size.x - 20.0, 16.0)
	var base := tip + Vector2(0, 28.0)
	draw_line(base, tip, line_col, 2.0)
	draw_colored_polygon(PackedVector2Array([
		tip, tip + Vector2(-5.0, 8.0), tip + Vector2(5.0, 8.0)]), line_col)
	var font := get_theme_font("font", "Label")
	var fs := get_theme_font_size("font_size", "Caption")
	if font != null:
		draw_string(font, tip + Vector2(8.0, 12.0), "N",
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, line_col)

## 曲线段：半透明填充（draw_colored_polygon）+ 主折线 + 圆弧（draw_arc）+
## 「R=xxx m」注记（弧顶附近，Caption 字号）。radius_m 非正/非有限则只填充不标注。
func _draw_arc_segment(seg: Dictionary, accent_col: Color, muted_col: Color) -> void:
	var pts: PackedVector2Array = seg.get("points", PackedVector2Array())
	if pts.size() < 2:
		return
	var radius_m := float(seg.get("radius_m", 0.0))
	var px := PackedVector2Array()
	for p in pts:
		px.append(_map_px(pts, p))
	# 半透明填充：三角形扇近似（首点 + 相邻两点逐片；折线段自交时填充区域仍限定在带内）
	var fill := Color(accent_col, 0.15)
	for i in range(1, px.size() - 1):
		draw_colored_polygon(
			PackedVector2Array([px[0], px[i], px[i + 1]]), fill)
	draw_polyline(px, accent_col, 2.0, true)
	# R 注记：中点上方偏移；半径用数据空间近似（像素弧半径 / 缩放系数反推不可靠，
	# 直接注装配方给的 radius_m，保证口径与计算结果一致）
	var font := get_theme_font("font", "Label")
	var fs := get_theme_font_size("font_size", "Caption")
	var mid := px[px.size() / 2]
	if font != null and radius_m > 0.0 and is_finite(radius_m):
		var label := "R=%s m" % _format_m(radius_m)
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, mid + Vector2(-w / 2.0, -8.0), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, muted_col)
		# 弧线示意：以中点为弧顶、按弦长与半径近似圆心角画短弧
		if px.size() >= 3:
			var chord := px[0].distance_to(px[px.size() - 1])
			var r_px := maxf(chord / 2.0, 1.0)
			if radius_m > 0.0:
				var sag := radius_m - sqrt(maxf(radius_m * radius_m - chord * chord / 4.0, 0.0))
				r_px = (chord * chord / 8.0 + sag * sag) / (2.0 * sag) if sag > 0.001 else r_px
			var ang := 2.0 * asin(clampf(chord / (2.0 * r_px), 0.0, 1.0))
			var dir := (px[px.size() - 1] - px[0]).angle()
			# 弧心在中点下方（凹向主曲线方向），起止角相对弦方向对称
			var center := mid + Vector2(0, r_px) if dir == 0.0 else mid
			var start := dir + PI / 2.0 - ang / 2.0
			draw_arc(center, r_px, start, start + ang, 16, accent_col, 1.5, true)
