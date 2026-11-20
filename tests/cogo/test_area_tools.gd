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
