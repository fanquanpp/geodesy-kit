# tests/earthwork/test_plumb.gd —— E5 垂直度
# 构造向量（自洽检核）：H=50、dx=0.04、dy=0.03 → 总偏移 0.0500、倾斜率 1/1000、θ=0.0573°
extends "res://tests/test_case_base.gd"

const Pl := preload("res://core/earthwork/plumb.gd")

## 构造向量：3-4-5 直角构造
func test_vector_construction() -> void:
	var res: Dictionary = Pl.forward({"h_m": 50.0, "dx_m": 0.04, "dy_m": 0.03})
	assert_true(bool(res.get("ok", false)), "应计算成功：" + String(res.get("error", "")))
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	assert_almost_eq(v["offset_m"], 0.05, 1e-12, "总偏移 0.05（√(0.04²+0.03²)）")
	assert_almost_eq(v["offset_mm"], 50.0, 1e-9, "50 mm")
	assert_almost_eq(v["ratio"], 0.001, 1e-15, "倾斜率 1/1000")
	assert_almost_eq(v["one_over_n"], 1000.0, 1e-9, "1/N 表达 N=1000")
	assert_almost_eq(v["angle_deg"], rad_to_deg(atan(0.001)), 1e-12, "倾角 0.0573°")

## 限差检核：H/1000 边界合格；H/500 超限
func test_limit_checks() -> void:
	var ok: Dictionary = Pl.forward({"h_m": 50.0, "dx_m": 0.04, "dy_m": 0.03, "limit_den": 1000.0})
	assert_almost_eq(ok["value"]["limit_offset_m"], 0.05, 1e-12, "限差偏移 = H/1000 = 0.05")
	assert_true(bool(ok["value"]["ok_limit"]), "δ=限差 → 合格（≤）")
	assert_eq(String(ok["value"]["basis"]), "限差 H/1000（用户输入）", "限差依据回显")
	var bad: Dictionary = Pl.forward({"h_m": 50.0, "dx_m": 0.04, "dy_m": 0.03, "limit_den": 2000.0})
	assert_false(bool(bad["value"]["ok_limit"]), "δ=0.05 > H/2000=0.025 → 超限")
	# 直接给限差偏移（mm）
	var direct: Dictionary = Pl.forward({"h_m": 50.0, "dx_m": 0.04, "dy_m": 0.03, "limit_offset_mm": 60.0})
	assert_almost_eq(direct["value"]["limit_offset_m"], 0.06, 1e-12, "限差 60mm=0.06m")
	assert_true(bool(direct["value"]["ok_limit"]), "0.05 ≤ 0.06 合格")

## 零偏移：1/N 记为 0（N=∞ 口径）
func test_zero_offset() -> void:
	var res: Dictionary = Pl.forward({"h_m": 30.0, "dx_m": 0.0, "dy_m": 0.0})
	assert_true(bool(res.get("ok", false)), "零偏移成功")
	if bool(res.get("ok", false)):
		var v: Dictionary = res["value"]
		assert_almost_eq(v["offset_m"], 0.0, 1e-15, "偏移 0")
		assert_almost_eq(v["one_over_n"], 0.0, 1e-15, "零偏移 N 记 0（∞ 口径）")
		assert_almost_eq(v["angle_deg"], 0.0, 1e-15, "倾角 0")

## 错误路径
func test_error_paths() -> void:
	var e1: Dictionary = Pl.forward({"h_m": 0.0, "dx_m": 0.01, "dy_m": 0.0})
	assert_false(bool(e1.get("ok", true)), "H=0 拒绝")
	var e2: Dictionary = Pl.forward({"h_m": -5.0, "dx_m": 0.01, "dy_m": 0.0})
	assert_false(bool(e2.get("ok", true)), "H<0 拒绝")
	var e3: Dictionary = Pl.forward({"h_m": 50.0, "dx_m": 0.01, "limit_den": 0.0})
	assert_false(bool(e3.get("ok", true)), "limit_den=0 拒绝")
	var e4: Dictionary = Pl.forward({"h_m": 50.0, "dx_m": 0.01, "limit_offset_mm": -10.0})
	assert_false(bool(e4.get("ok", true)), "负限差拒绝")
