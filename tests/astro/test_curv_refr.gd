# tests/astro/test_curv_refr.gd —— GK-M8-5（F1）球气差
# 向量来源：教材速算式自洽（k=0.14 → f = 0.43·D²_km/R_km），本会话 Python 复核：
#   D=1000 m, k=0.14 → c1=0.078481 m，r=0.010987 m，f=0.067493 m；
#   D=500 m, k=0.13 → f=0.017067 m。R 取平均半径 6371008.7714 m（与 I-GIS 同口径）。
extends "res://tests/test_case_base.gd"

const C := preload("res://core/astro/curvature_refraction.gd")

const R1 := 6371008.7714

func test_correction_d1000_k014() -> void:
	var r := C.correction({"D_m": 1000.0, "k": 0.14})
	assert_true(r["ok"], "D=1000/k=0.14 应成功")
	if bool(r["ok"]):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["curv_m"]), 1000000.0 / (2.0 * R1), 1e-12, "地球曲率差 c₁ = D²/(2R)（双路径）")
		assert_almost_eq(float(v["curv_m"]), 0.078481, 1e-5, "曲率差（权威速算值）")
		assert_almost_eq(float(v["refr_m"]), 0.010987, 1e-5, "折光差")
		assert_almost_eq(float(v["f_m"]), 0.067493, 1e-5, "球气差综合改正")
		assert_almost_eq(float(v["f_m"]), 0.43 * 1.0 / 6371.0087714 * 1000.0, 1e-5, "教材速算式 0.43·D²km/R")
		assert_almost_eq(float(v["f_m"]), float(v["curv_m"]) - float(v["refr_m"]), 1e-12, "f = c₁ − r 自洽")

func test_correction_d500_k013() -> void:
	var r := C.correction({"D_m": 500.0, "k": 0.13})
	assert_true(r["ok"], "D=500/k=0.13 应成功")
	if bool(r["ok"]):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["f_m"]), (1.0 - 0.13) * 250000.0 / (2.0 * R1), 1e-12, "f 定义式（双路径）")
		assert_almost_eq(float(v["f_m"]), 0.017067, 1e-5, "f 数值")

func test_correction_k_default_and_range() -> void:
	var r := C.correction({"D_m": 1000.0})
	assert_true(r["ok"], "默认 k 应可用")
	if bool(r["ok"]):
		assert_almost_eq(float(r["value"]["k"]), 0.14, 1e-12, "默认折光系数 0.14")
	var r2 := C.correction({"D_m": 1000.0, "k": 0.0})
	assert_true(r2["ok"], "k=0（无折光）应可用")
	if bool(r2["ok"]):
		assert_almost_eq(float(r2["value"]["f_m"]), float(r2["value"]["curv_m"]), 1e-12, "k=0 时 f=c₁")

func test_trig_height() -> void:
	# h = D·tanα + (1−k)D²/(2R) + i − v
	var r := C.trig_height({"D_m": 1000.0, "alpha_deg": 3.0, "i_m": 1.5, "v_m": 0.0, "k": 0.14})
	assert_true(r["ok"], "三角高程算例应成功")
	if bool(r["ok"]):
		var v: Dictionary = r["value"]
		var geo := 1000.0 * tan(deg_to_rad(3.0))
		var f := (1.0 - 0.14) * 1000000.0 / (2.0 * R1)
		assert_almost_eq(float(v["geometric_m"]), geo, 1e-12, "几何高差双路径")
		assert_almost_eq(float(v["f_m"]), f, 1e-12, "球气差双路径")
		assert_almost_eq(float(v["dh_m"]), geo + f + 1.5 - 0.0, 1e-12, "总高差自洽")
		assert_almost_eq(float(v["dh_m"]), 53.9753, 1e-4, "总高差数值")
	# 仰角为负（俯角）
	var r2 := C.trig_height({"D_m": 2000.0, "alpha_deg": -1.5, "i_m": 1.4, "v_m": 2.0, "k": 0.13})
	assert_true(r2["ok"], "俯角算例应成功")
	if bool(r2["ok"]):
		var geo2 := 2000.0 * tan(deg_to_rad(-1.5))
		var f2 := (1.0 - 0.13) * 4000000.0 / (2.0 * R1)
		assert_almost_eq(float(r2["value"]["dh_m"]), geo2 + f2 + 1.4 - 2.0, 1e-12, "俯角高差自洽")
		assert_true(float(r2["value"]["dh_m"]) < 0.0, "俯角高差为负")

func test_chord_arc_diff() -> void:
	var d := C.chord_arc_diff_m(1000.0, R1)
	assert_almost_eq(d, 1000000000.0 / (24.0 * R1 * R1), 1e-18, "弦弧差定义式")
	assert_almost_eq(d, 1.0265e-6, 1e-8, "弦弧差量级（D=1 km 约 1 μm）")
	assert_true(is_nan(C.chord_arc_diff_m(-1.0, R1)), "非法输入返回 NAN")

func test_invalid_inputs() -> void:
	var r1 := C.correction({"D_m": -5.0})
	assert_false(bool(r1["ok"]), "负距离应拒绝")
	var r2 := C.correction({"D_m": 1000.0, "k": 1.5})
	assert_false(bool(r2["ok"]), "k>1 应拒绝")
	var r3 := C.trig_height({"D_m": 1000.0, "alpha_deg": 95.0})
	assert_false(bool(r3["ok"]), "|竖直角|≥90 应拒绝")
	var r4 := C.trig_height({"D_m": 1000.0, "alpha_deg": 3.0, "i_m": -1.0})
	assert_false(bool(r4["ok"]), "负仪器高应拒绝")
	for r: Dictionary in [r1, r2, r3, r4]:
		assert_true(String(r["error"]).length() > 0, "失败必带中文错误")
		assert_true((r["value"] as Dictionary).is_empty(), "失败时 value 为空")
