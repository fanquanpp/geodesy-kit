# tests/cogo/test_line_tools.gd —— GK-M5 点线关系（M5-6，向量来源：ARCHITECTURE.md §4 GK-M5【构造】）
# 权威向量：线起点(1000,1000) az30°，点(2150,1950)→桩号 1397.7241、偏距 +520.9292（右正）
extends "res://tests/test_case_base.gd"

const LT := preload("res://core/cogo/line_tools.gd")

func test_point_line_authoritative_vector() -> void:
	var r := LT.point_line_rel({
		"x0_m": 1000.0, "y0_m": 1000.0, "az_deg": 30.0,
		"x_m": 2150.0, "y_m": 1950.0,
	})
	assert_true(bool(r.get("ok", false)), "B8 权威向量成功")
	if not bool(r.get("ok", false)):
		return
	var v: Dictionary = r["value"]
	assert_almost_eq(float(v["station_m"]), 1397.7241, 1e-4, "桩号 1397.7241（向量 4 位舍入）")
	assert_almost_eq(float(v["offset_m"]), 520.9292, 1e-4, "偏距 +520.9292（右正）")
	assert_eq(String(v["side"]), "右侧", "右侧判定")
	assert_false(bool(v["on_line"]), "不在线上")
	assert_almost_eq(float(v["x_foot_m"]) , 1000.0 + float(v["station_m"]) * sin(deg_to_rad(30.0)), 1e-9, "垂足 x = x0 + st·sinα")
	assert_almost_eq(float(v["y_foot_m"]), 1000.0 + float(v["station_m"]) * cos(deg_to_rad(30.0)), 1e-9, "垂足 y = y0 + st·cosα")

func test_on_line_point() -> void:
	# 线上点：起点(1000,1000) az30° d=400 → (1200, 1346.41016)，偏距 0、桩号 400
	var r := LT.point_line_rel({
		"x0_m": 1000.0, "y0_m": 1000.0, "az_deg": 30.0,
		"x_m": 1000.0 + 400.0 * sin(deg_to_rad(30.0)),
		"y_m": 1000.0 + 400.0 * cos(deg_to_rad(30.0)),
	})
	assert_true(bool(r.get("ok", false)), "线上点成功")
	if bool(r.get("ok", false)):
		var v: Dictionary = r["value"]
		assert_true(bool(v["on_line"]), "on_line = true")
		assert_almost_eq(float(v["offset_m"]), 0.0, 1e-9, "偏距为 0")
		assert_almost_eq(float(v["station_m"]), 400.0, 1e-9, "桩号 = 400")
		assert_eq(String(v["side"]), "线上", "side = 线上")

func test_left_side_negative_offset() -> void:
	# 点位于线左侧：起点(1000,1000) az30°，点取 az20° 方向 400 m 处
	# st = 400·cos(10°)、off = −400·sin(10°)（右正左负）
	var r := LT.point_line_rel({
		"x0_m": 1000.0, "y0_m": 1000.0, "az_deg": 30.0,
		"x_m": 1000.0 + 400.0 * sin(deg_to_rad(20.0)),
		"y_m": 1000.0 + 400.0 * cos(deg_to_rad(20.0)),
	})
	assert_true(bool(r.get("ok", false)), "左侧点成功")
	if bool(r.get("ok", false)):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["station_m"]), 400.0 * cos(deg_to_rad(10.0)), 1e-9, "桩号 = d·cos(夹角)")
		assert_almost_eq(float(v["offset_m"]), -400.0 * sin(deg_to_rad(10.0)), 1e-9, "偏距 = −d·sin(夹角)（左负）")
		assert_eq(String(v["side"]), "左侧", "左侧判定")

func test_foot_geometry() -> void:
	var r := LT.point_line_rel({
		"x0_m": 1000.0, "y0_m": 1000.0, "az_deg": 30.0,
		"x_m": 2150.0, "y_m": 1950.0,
	})
	var v: Dictionary = r["value"]
	var fx := float(v["x_foot_m"])
	var fy := float(v["y_foot_m"])
	# 垂足在线上：重算其偏距应为 0
	var foot_rel := LT.point_line(1000.0, 1000.0, 30.0, fx, fy)
	assert_almost_eq(float(foot_rel["offset"]), 0.0, 1e-9, "垂足偏距 = 0")
	assert_almost_eq(float(foot_rel["station"]), float(v["station_m"]), 1e-9, "垂足桩号 = 点桩号")
	# 点到垂足距离 = |偏距|
	assert_almost_eq(float(v["point_line_dist_m"]), absf(float(v["offset_m"])), 1e-12, "点线距 = |偏距|")
	var dpf := sqrt((2150.0 - fx) * (2150.0 - fx) + (1950.0 - fy) * (1950.0 - fy))
	assert_almost_eq(dpf, absf(float(v["offset_m"])), 1e-9, "|P−垂足| = |偏距|")

func test_station_range_check() -> void:
	var base := {
		"x0_m": 1000.0, "y0_m": 1000.0, "az_deg": 30.0,
		"x_m": 2150.0, "y_m": 1950.0,
	}
	var in_len := base.duplicate()
	in_len["len_m"] = 2000.0
	var r1 := LT.point_line_rel(in_len)
	assert_true(bool(r1.get("ok", false)), "范围内成功")
	assert_int_eq(r1["steps"].size(), 4, "范围内 4 步")
	assert_true(String(r1["steps"][3]["result"]).contains("在范围内"), "范围内提示文本")
	var out_len := base.duplicate()
	out_len["len_m"] = 1000.0
	var r2 := LT.point_line_rel(out_len)
	assert_true(bool(r2.get("ok", false)), "超线长仍返回结果")
	assert_int_eq(r2["steps"].size(), 4, "超线长仍 4 步（检核步骤文本变化）")
	assert_true(String(r2["steps"][3]["result"]).contains("超出"), "超限提示文本")
	var no_len := base.duplicate()
	var r3 := LT.point_line_rel(no_len)
	assert_true(String(r3["steps"][3]["result"]).contains("线长"), "未提供线长提示")

func test_foot_envelope() -> void:
	var r := LT.foot({
		"x0_m": 0.0, "y0_m": 0.0, "az_deg": 0.0,
		"x_m": 30.0, "y_m": 40.0,
	})
	assert_true(bool(r.get("ok", false)), "垂足入口成功")
	if bool(r.get("ok", false)):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["x_foot_m"]), 0.0, 1e-12, "az=0 垂足 x = 0")
		assert_almost_eq(float(v["y_foot_m"]), 40.0, 1e-12, "az=0 垂足 y = 点 y")
		assert_almost_eq(float(v["station_m"]), 40.0, 1e-12, "桩号 = 40")
		assert_almost_eq(float(v["point_line_dist_m"]), 30.0, 1e-12, "点线距 = 30")

func test_errors() -> void:
	var r := LT.point_line_rel({"x0_m": 0.0, "y0_m": 0.0, "az_deg": "xx", "x_m": 1.0, "y_m": 1.0})
	assert_false(bool(r.get("ok", true)), "非法方位角失败")
	assert_true(String(r.get("error", "")).contains("角度"), "非法角度中文错误")
	var r2 := LT.point_line_rel({"x0_m": 0.0, "y0_m": 0.0, "az_deg": 0.0, "x_m": 1.0, "y_m": 1.0, "len_m": -5.0})
	assert_false(bool(r2.get("ok", true)), "负线长失败")
