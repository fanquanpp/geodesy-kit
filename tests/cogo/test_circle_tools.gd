# tests/cogo/test_circle_tools.gd —— GK-M5 三点定圆与圆弧要素（M5-7，向量来源：ARCHITECTURE.md §4 GK-M5【构造】）
# 权威向量：三点 (100,100),(500,150),(300,400) → 圆心 (292.0455,188.6364)、R=211.5133（三半径一致）
extends "res://tests/test_case_base.gd"

const CT := preload("res://core/cogo/circle_tools.gd")

func test_three_point_circle_authoritative_vector() -> void:
	var r := CT.three_point_circle({
		"x1_m": 100.0, "y1_m": 100.0, "x2_m": 500.0, "y2_m": 150.0, "x3_m": 300.0, "y3_m": 400.0,
	})
	assert_true(bool(r.get("ok", false)), "B9 三点定圆成功")
	if not bool(r.get("ok", false)):
		return
	var v: Dictionary = r["value"]
	assert_almost_eq(float(v["cx_m"]), 292.0455, 5e-4, "圆心 x（向量 292.0455）")
	assert_almost_eq(float(v["cy_m"]), 188.6364, 5e-4, "圆心 y（向量 188.6364）")
	assert_almost_eq(float(v["r_m"]), 211.5133, 5e-4, "半径（向量 211.5133）")
	assert_true(float(v["r_diff_m"]) < 1e-9, "三点到圆心距离互差 ≈ 0")

func test_three_point_circle_exact() -> void:
	# 精确构造：圆心 (500,500) R=200，三点取方位 0°/90°/180° 处
	var r := CT.circumcircle(500.0, 700.0, 700.0, 500.0, 500.0, 300.0)
	assert_false(r.is_empty(), "精确外接圆")
	assert_almost_eq(float(r["cx"]), 500.0, 1e-9, "精确圆心 x")
	assert_almost_eq(float(r["cy"]), 500.0, 1e-9, "精确圆心 y")
	assert_almost_eq(float(r["r"]), 200.0, 1e-9, "精确半径")

func test_collinear_error() -> void:
	var r := CT.three_point_circle({
		"x1_m": 0.0, "y1_m": 0.0, "x2_m": 100.0, "y2_m": 100.0, "x3_m": 200.0, "y3_m": 200.0,
	})
	assert_false(bool(r.get("ok", true)), "共线应失败")
	assert_true(String(r.get("error", "")).contains("共线"), "共线中文错误")

func test_arc_elements_exact_quarter() -> void:
	# R=100、Δ=90°：弧长 50π、弦长 100√2、弓高 100(1−√2/2)、扇形 1250π、弓形 1250π−5000
	var e := CT.arc_elements(100.0, 90.0)
	assert_almost_eq(float(e["arc"]), 100.0 * PI / 2.0, 1e-9, "弧长 L = R·Δrad")
	assert_almost_eq(float(e["chord"]), 141.42135623730951, 1e-9, "弦长 C = 2R·sin(Δ/2)")
	assert_almost_eq(float(e["sagitta"]), 29.289321881345245, 1e-9, "弓高 f = R(1−cos(Δ/2))")
	assert_almost_eq(float(e["sector"]), 7853.981633974483, 1e-9, "扇形面积 = R²Δrad/2")
	assert_almost_eq(float(e["segment"]), 2853.9816339744832, 1e-9, "弓形面积 = R²(Δrad−sinΔrad)/2")

func test_arc_by_azimuth_cw() -> void:
	var r := CT.arc_by_azimuth({
		"cx_m": 0.0, "cy_m": 0.0, "r_m": 100.0,
		"az1_deg": 0.0, "az2_deg": 90.0, "dir": "cw",
	})
	assert_true(bool(r.get("ok", false)), "顺时针 90° 弧成功")
	if not bool(r.get("ok", false)):
		return
	var v: Dictionary = r["value"]
	assert_almost_eq(float(v["delta_deg"]), 90.0, 1e-9, "圆心角 90°")
	assert_almost_eq(float(v["arc_m"]), 100.0 * PI / 2.0, 1e-9, "弧长")
	assert_almost_eq(float(v["chord_m"]), 141.42135623730951, 1e-9, "弦长")
	assert_almost_eq(float(v["segment_area_m2"]), 2853.9816339744832, 1e-9, "弓形面积")
	assert_false(bool(v["full_circle"]), "非全圆")

func test_arc_by_azimuth_ccw_and_major() -> void:
	# 逆时针 0°→90° 的反向：az1=90、az2=0、ccw → Δ=90°，要素与顺时针相同
	var r := CT.arc_by_azimuth({
		"cx_m": 0.0, "cy_m": 0.0, "r_m": 100.0,
		"az1_deg": 90.0, "az2_deg": 0.0, "dir": "ccw",
	})
	assert_true(bool(r.get("ok", false)), "逆时针 90° 弧成功")
	if bool(r.get("ok", false)):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["delta_deg"]), 90.0, 1e-9, "逆时针圆心角 90°")
	# 优弧：az1=0、az2=90、ccw → Δ=270°，弦长与 90° 弧相同（同一条弦）
	var major := CT.arc_by_azimuth({
		"cx_m": 0.0, "cy_m": 0.0, "r_m": 100.0,
		"az1_deg": 0.0, "az2_deg": 90.0, "dir": "ccw",
	})
	assert_true(bool(major.get("ok", false)), "优弧 270° 成功")
	if bool(major.get("ok", false)):
		var mv: Dictionary = major["value"]
		assert_almost_eq(float(mv["delta_deg"]), 270.0, 1e-9, "优弧圆心角 270°")
		assert_almost_eq(float(mv["arc_m"]), 100.0 * 3.0 * PI / 2.0, 1e-9, "优弧弧长")
		assert_almost_eq(float(mv["chord_m"]), 141.42135623730951, 1e-9, "优弧弦长 = 同弦 90° 弧")
		assert_almost_eq(float(mv["segment_area_m2"]), 5000.0 * (3.0 * PI / 2.0 + 1.0), 1e-9, "优弧弓形面积（Δrad−sinΔrad，sin270°=−1）")

func test_arc_full_circle() -> void:
	var r := CT.arc_by_azimuth({
		"cx_m": 0.0, "cy_m": 0.0, "r_m": 100.0,
		"az1_deg": 45.0, "az2_deg": 45.0, "dir": "cw",
	})
	assert_true(bool(r.get("ok", false)), "全圆成功")
	if bool(r.get("ok", false)):
		var v: Dictionary = r["value"]
		assert_true(bool(v["full_circle"]), "全圆标记")
		assert_almost_eq(float(v["delta_deg"]), 360.0, 1e-9, "圆心角 360°")
		assert_almost_eq(float(v["arc_m"]), 2.0 * PI * 100.0, 1e-9, "周长 = 2πR")
		assert_almost_eq(float(v["sector_area_m2"]), PI * 10000.0, 1e-9, "扇形 = 圆面积 πR²")

func test_arc_by_points_cw_ccw_major() -> void:
	# 圆心 (500,500) R=200：P₁(方位0°)、P₂(45°)、P₃(90°) → 顺时针 90°
	var p1x := 500.0
	var p1y := 700.0
	var p2x := 500.0 + 200.0 * sin(deg_to_rad(45.0))
	var p2y := 500.0 + 200.0 * cos(deg_to_rad(45.0))
	var p3x := 700.0
	var p3y := 500.0
	var r := CT.arc_by_points({"x1_m": p1x, "y1_m": p1y, "x2_m": p2x, "y2_m": p2y, "x3_m": p3x, "y3_m": p3y})
	assert_true(bool(r.get("ok", false)), "三点弧成功")
	if bool(r.get("ok", false)):
		var v: Dictionary = r["value"]
		assert_eq(String(v["dir"]), "顺时针", "方向由 P₂ 判定（顺时针）")
		assert_almost_eq(float(v["delta_deg"]), 90.0, 1e-9, "圆心角 90°")
		assert_almost_eq(float(v["r_m"]), 200.0, 1e-9, "半径 200")
		assert_almost_eq(float(v["arc_m"]), 200.0 * PI / 2.0, 1e-9, "弧长")
	# 逆序三点 → 逆时针，圆心角仍 90°
	var rev := CT.arc_by_points({"x1_m": p3x, "y1_m": p3y, "x2_m": p2x, "y2_m": p2y, "x3_m": p1x, "y3_m": p1y})
	assert_true(bool(rev.get("ok", false)), "逆序三点弧成功")
	if bool(rev.get("ok", false)):
		var rv: Dictionary = rev["value"]
		assert_eq(String(rv["dir"]), "逆时针", "逆序方向")
		assert_almost_eq(float(rv["delta_deg"]), 90.0, 1e-9, "逆序圆心角 90°")
	# 优弧：P₂ 在方位 270° 处（不在 0°→90° 顺时针展开弧内）→ 逆时针 270°
	var mx := 500.0 + 200.0 * sin(deg_to_rad(270.0))
	var my := 500.0 + 200.0 * cos(deg_to_rad(270.0))
	var major := CT.arc_by_points({"x1_m": p1x, "y1_m": p1y, "x2_m": mx, "y2_m": my, "x3_m": p3x, "y3_m": p3y})
	assert_true(bool(major.get("ok", false)), "三点优弧成功")
	if bool(major.get("ok", false)):
		var mv: Dictionary = major["value"]
		assert_eq(String(mv["dir"]), "逆时针", "优弧方向")
		assert_almost_eq(float(mv["delta_deg"]), 270.0, 1e-9, "优弧圆心角 270°")

func test_arc_errors() -> void:
	var r := CT.arc_by_azimuth({
		"cx_m": 0.0, "cy_m": 0.0, "r_m": 0.0,
		"az1_deg": 0.0, "az2_deg": 90.0, "dir": "cw",
	})
	assert_false(bool(r.get("ok", true)), "半径 0 应失败")
	var r2 := CT.arc_by_azimuth({
		"cx_m": 0.0, "cy_m": 0.0, "r_m": 100.0,
		"az1_deg": 0.0, "az2_deg": 90.0, "dir": "弧线",
	})
	assert_false(bool(r2.get("ok", true)), "非法方向应失败")
	var r3 := CT.arc_by_points({"x1_m": 0.0, "y1_m": 0.0, "x2_m": 1.0, "y2_m": 1.0, "x3_m": 2.0, "y3_m": 2.0})
	assert_false(bool(r3.get("ok", true)), "三点共线弧应失败")
