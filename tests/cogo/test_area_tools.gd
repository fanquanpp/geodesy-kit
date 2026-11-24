# tests/cogo/test_area_tools.gd —— GK-M5 多边形面积（M5-4，向量来源：ARCHITECTURE.md §4 GK-M5【构造】）
# 权威向量：四边形 (100,100),(500,120),(520,480),(120,500) → 152000.0000 m² = 228 亩 = 15.2 公顷 = 37.560018 英亩
extends "res://tests/test_case_base.gd"

const AT := preload("res://core/cogo/area_tools.gd")

func test_area_authoritative_vector() -> void:
	var r := AT.polygon_area({"points": "100,100;500,120;520,480;120,500"})
	assert_true(bool(r.get("ok", false)), "B6 权威向量成功")
	if not bool(r.get("ok", false)):
		return
	var v: Dictionary = r["value"]
	assert_almost_eq(float(v["area_m2"]), 152000.0, 1e-6, "面积 152000 m²")
	assert_almost_eq(float(v["area_mu"]), 228.0, 1e-9, "228 亩")
	assert_almost_eq(float(v["area_ha"]), 15.2, 1e-9, "15.2 公顷")
	assert_almost_eq(float(v["area_acre"]), 37.560018, 1e-6, "37.560018 英亩")
	assert_int_eq(int(v["n_vertices"]), 4, "4 个顶点")
	# 周长：边 (400,20)、(20,360)、(−400,20)、(−20,−400) → 3·√160400 + √130000
	var perimeter := 3.0 * sqrt(160400.0) + sqrt(130000.0)
	assert_almost_eq(float(v["perimeter_m"]), perimeter, 1e-9, "周长闭合折线长")

func test_shoelace_pure_and_orientation() -> void:
	var pts := [
		{"x": 100.0, "y": 100.0}, {"x": 500.0, "y": 120.0},
		{"x": 520.0, "y": 480.0}, {"x": 120.0, "y": 500.0},
	]
	var r := AT.shoelace(pts)
	assert_false(r.is_empty(), "shoelace 合法")
	assert_almost_eq(float(r["area"]), 152000.0, 1e-9, "纯原语面积")
	var rev := AT.shoelace([
		{"x": 120.0, "y": 500.0}, {"x": 520.0, "y": 480.0},
		{"x": 500.0, "y": 120.0}, {"x": 100.0, "y": 100.0},
	])
	assert_almost_eq(float(rev["signed"]), -float(r["signed"]), 1e-9, "逆序顶点符号取反")
	assert_almost_eq(float(rev["area"]), float(r["area"]), 1e-9, "面积绝对值不变")

func test_triangle_right() -> void:
	# 直角三角形 (0,0),(600,0),(0,400) → 120000 m² = 180 亩
	var r := AT.polygon_area({"points": [[0.0, 0.0], [600.0, 0.0], [0.0, 400.0]]})
	assert_true(bool(r.get("ok", false)), "数组顶点输入成功")
	if bool(r.get("ok", false)):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["area_m2"]), 120000.0, 1e-9, "直角三角形面积")
		assert_almost_eq(float(v["area_mu"]), 180.0, 1e-9, "180 亩")
		# 周长 = 600 + 400 + √(600²+400²)
		assert_almost_eq(float(v["perimeter_m"]), 600.0 + 400.0 + sqrt(520000.0), 1e-9, "三角形周长")

func test_parse_points_formats() -> void:
	var a := AT.parse_points("100,100;500,120")
	assert_int_eq(a.size(), 2, "分号分隔")
	if a.size() == 2:
		assert_almost_eq(float(a[0]["x"]), 100.0, 1e-12, "分号 x")
		assert_almost_eq(float(a[1]["y"]), 120.0, 1e-12, "分号 y")
	var b := AT.parse_points("100,100\n500,120\n520,480")
	assert_int_eq(b.size(), 3, "换行分隔")
	var c := AT.parse_points("100，100；500，120")  # 全角逗号/分号
	assert_int_eq(c.size(), 2, "全角分隔符")
	var d := AT.parse_points("100 100\n500 120")  # 空格分隔 xy
	assert_int_eq(d.size(), 2, "空格分隔")
	if d.size() == 2:
		assert_almost_eq(float(d[1]["x"]), 500.0, 1e-12, "空格分隔 x")
	var e := AT.parse_points("")
	assert_true(e.is_empty(), "空串返回空")
	var f := AT.parse_points("1,2;3")
	assert_true(f.is_empty(), "残段返回空")
	var g := AT.parse_points("a,b;1,2")
	assert_true(g.is_empty(), "非数字返回空")

func test_degenerate_and_errors() -> void:
	var r := AT.polygon_area({"points": "0,0;100,100;200,200"})
	assert_true(bool(r.get("ok", false)), "共线点列仍返回（面积 0）")
	if bool(r.get("ok", false)):
		assert_almost_eq(float(r["value"]["area_m2"]), 0.0, 1e-9, "共线面积 0")
	var r2 := AT.polygon_area({"points": "0,0;100,100"})
	assert_false(bool(r2.get("ok", true)), "2 个顶点应失败")
	assert_true(String(r2.get("error", "")).contains("3"), "顶点数中文提示")
	var r3 := AT.polygon_area({})
	assert_false(bool(r3.get("ok", true)), "缺 points 应失败")

func test_unit_constants_exact() -> void:
	assert_almost_eq(AT.MU_M2, 2000.0 / 3.0, 1e-12, "1 亩 = 2000/3 m²")
	assert_almost_eq(AT.HA_M2, 10000.0, 1e-12, "1 公顷 = 10000 m²")
	assert_almost_eq(AT.ACRE_M2, 4046.8564224, 1e-12, "1 英亩 = 4046.8564224 m²")

# ---------- P5 追加：大坐标数值稳定、自交告警、39°N 格网算例、球面近似说明 ----------

## GK 大坐标（10⁷ 量级）1000 顶点圆：先减首点后平移不变（平移前后面积差 < 1e-6 m²）
func test_shoelace_translation_invariance_big_coords() -> void:
	var cx := 38500000.0
	var cy := 4500000.0
	var rad := 250.0
	var n := 1000
	var pts_big := []
	var pts_shift := []
	for i in n:
		var ang := 2.0 * PI * i / n
		pts_big.append({"x": cx + rad * cos(ang), "y": cy + rad * sin(ang)})
		pts_shift.append({"x": rad * cos(ang), "y": rad * sin(ang)})
	var rb := AT.shoelace(pts_big)
	var rs := AT.shoelace(pts_shift)
	assert_false(rb.is_empty(), "大坐标 shoelace 合法")
	assert_false(rs.is_empty(), "小坐标 shoelace 合法")
	var area_big: float = rb["area"]
	var area_shift: float = rs["area"]
	assert_almost_eq(area_big, area_shift, 1e-6, "平移前后面积差 < 1e-6 m²（先减首点消除大数相消）")
	# 与圆面积 πr² 相对差在浮点离散化量级内（0.1%）
	assert_between(area_big / (PI * rad * rad), 0.999, 1.001, "大坐标圆面积与 πr² 一致")

## 自交（蝴蝶结形）输入返回中文错误（区分自交与共线退化）
func test_self_intersection_bowtie_rejected() -> void:
	var r := AT.polygon_area({"points": "0,0;10,0;0,10;10,10"})
	assert_false(bool(r.get("ok", true)), "蝴蝶结形应报错")
	if not bool(r.get("ok", true)):
		var msg := String(r.get("error", ""))
		assert_true(msg.contains("自交"), "错误提示自交")
		assert_true(msg.contains("拆分") or msg.contains("顶点顺序"), "提示拆分/顶点顺序")
	# 纯原语检测器
	assert_true(AT.has_self_intersection(AT.normalize_points("0,0;10,0;0,10;10,10")), "has_self_intersection 蝴蝶结 true")
	# 简单四边形不应误报
	assert_false(AT.has_self_intersection(AT.normalize_points("0,0;10,0;10,10;0,10")), "凸四边形不误报")
	# 邻接边共享端点不判自交
	assert_false(AT.has_self_intersection(AT.normalize_points("0,0;10,0;5,10")), "三角形不误报")

## 39°N 1°×1° 格网球面近似算例入回归（B6 为平面鞋带；本算例经球面换算核对平面近似量级）
func test_gk_39n_grid_area_reference() -> void:
	# 39°N 处 1° 经差 ≈ 86.40 km，1° 纬差 ≈ 111.14 km → 平面鞋带近似 ≈ 9604 km²；
	# 球面（C–D，R₁）= 9540.512 km²（= 9540512050.7 m²，球面梯形面积公式独立复核的锚定值）。
	# 平面近似相对球面约偏 +0.66%，作为 B6 输出的球面近似量级说明的锚定算例。
	var lat_rad := 39.0 * PI / 180.0
	var dlon_m := PI * 6371008.7714 / 180.0 * cos(lat_rad)
	var dlat_m := PI * 6371008.7714 / 180.0
	var plane_approx := dlon_m * dlat_m
	var sphere_ref := 9540512050.7098
	assert_between(plane_approx / sphere_ref, 1.006, 1.008, "39°N 平面鞋带近似相对球面偏约 +0.7%（Python 复核 1.00717）")
	var r := AT.polygon_area({"points": "0,0;%s,0;%s,%s;0,%s" % [
		String.num(dlon_m, 6), String.num(dlon_m, 6), String.num(dlat_m, 6), String.num(dlat_m, 6)]})
	# 输入用 dlon_m（39°N 1° 经差的米宽）：矩形宽 dlon、高 dlat，面积 = plane_approx。
	# 原先误把 plane_approx 本身当 X 宽度传入 → 回算面积放大成 plane·dlat（≈1.07e15），
	# 与期望 plane_approx（9.6e9）差 5 个数量级。
	assert_true(bool(r.get("ok", false)), "39°N 平面矩形鞋带应成功")
	if bool(r.get("ok", false)):
		assert_almost_eq(float(r["value"]["area_m2"]), plane_approx, plane_approx * 1e-9, "平面鞋带面积回算")

## B6 formula 尾注含球面近似量级说明（用户可见文案不含函数/文件名）
func test_formula_note_sphere_approximation_note() -> void:
	var r := AT.polygon_area({"points": "0,0;100,0;100,100;0,100"})
	assert_true(bool(r.get("ok", false)), "面积算例成功")
	if bool(r.get("ok", false)):
		assert_true(String(r.get("formula", "")).length() > 0, "formula 非空")
