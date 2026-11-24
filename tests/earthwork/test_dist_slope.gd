# tests/earthwork/test_dist_slope.gd —— E4 平距/斜距/坡度
# 权威向量：ARCHITECTURE.md §4 GK-M7【构造·本会话】Δh=30、平距 500 → 空间 500.8992、坡度 6.00%
extends "res://tests/test_case_base.gd"

const Ds := preload("res://core/earthwork/dist_slope.gd")

## 权威向量：高差+平距
func test_vector_authoritative() -> void:
	var res: Dictionary = Ds.forward({"dh_m": 30.0, "d_horiz_m": 500.0})
	assert_true(bool(res.get("ok", false)), "应计算成功：" + String(res.get("error", "")))
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	assert_almost_eq(v["d_slope_m"], 500.8992, 1e-4, "斜距 500.8992")
	assert_almost_eq(v["slope_pct"], 6.00, 1e-9, "坡度 6.00%")
	assert_almost_eq(v["slope_deg"], rad_to_deg(atan(0.06)), 1e-9, "坡度角")
	assert_almost_eq(v["dh_m"], 30.0, 1e-12, "高差回显")

## 六条求解路径互检（同一几何真值）
func test_all_paths_consistent() -> void:
	# 真值：dh=30, horiz=500, slope=√250900, pct=6
	var slope_exact := sqrt(500.0 * 500.0 + 30.0 * 30.0)
	var r1: Dictionary = Ds.forward({"dh_m": 30.0, "d_horiz_m": 500.0})
	var r2: Dictionary = Ds.forward({"dh_m": 30.0, "d_slope_m": slope_exact})
	var r3: Dictionary = Ds.forward({"d_horiz_m": 500.0, "d_slope_m": slope_exact})
	var r4: Dictionary = Ds.forward({"d_horiz_m": 500.0, "slope_pct": 6.0})
	var r5: Dictionary = Ds.forward({"dh_m": 30.0, "slope_pct": 6.0})
	var r6: Dictionary = Ds.forward({"d_slope_m": slope_exact, "slope_pct": 6.0})
	var r7: Dictionary = Ds.forward({"d_horiz_m": 500.0, "slope_deg": rad_to_deg(atan(0.06))})
	var rs := [r1, r2, r3, r4, r5, r6, r7]
	for i in rs.size():
		var r: Dictionary = rs[i]
		assert_true(bool(r.get("ok", false)), "路径 %d 应成功" % (i + 1))
		if not bool(r.get("ok", false)):
			continue
		var v: Dictionary = r["value"]
		assert_almost_eq(v["dh_m"], 30.0, 1e-9, "路径 %d 高差一致" % (i + 1))
		assert_almost_eq(v["d_horiz_m"], 500.0, 1e-9, "路径 %d 平距一致" % (i + 1))
		assert_almost_eq(v["d_slope_m"], 500.8992, 1e-4, "路径 %d 斜距一致" % (i + 1))
		assert_almost_eq(v["slope_pct"], 6.0, 1e-9, "路径 %d 坡度一致" % (i + 1))

## 下坡：坡度为负
func test_downhill_negative_slope() -> void:
	var res: Dictionary = Ds.forward({"dh_m": -30.0, "d_horiz_m": 500.0})
	assert_true(bool(res.get("ok", false)), "下坡成功")
	if bool(res.get("ok", false)):
		assert_almost_eq(res["value"]["slope_pct"], -6.0, 1e-9, "下坡坡度 −6%")
		assert_almost_eq(res["value"]["d_slope_m"], 500.8992, 1e-4, "斜距为正")

## 一致性校验提示（输入矛盾第三量不崩溃，结果以主量为准并提示）
func test_inconsistent_third_value() -> void:
	var res: Dictionary = Ds.forward({"dh_m": 30.0, "d_horiz_m": 500.0, "slope_pct": 7.0})
	assert_true(bool(res.get("ok", false)), "矛盾第三量仍可解算")
	if bool(res.get("ok", false)):
		var steps: Array = res["steps"]
		var joined := ""
		for s: Dictionary in steps:
			joined += String(s.get("result", "")) + String(s.get("substitution", ""))
		assert_true(joined.contains("差异"), "结果步骤中提示差异")

## 错误路径
func test_error_paths() -> void:
	var e1: Dictionary = Ds.forward({"dh_m": 30.0})
	assert_false(bool(e1.get("ok", true)), "仅一个量拒绝")
	var e2: Dictionary = Ds.forward({"dh_m": 50.0, "d_slope_m": 40.0})
	assert_false(bool(e2.get("ok", true)), "斜距<|高差| 拒绝")
	var e3: Dictionary = Ds.forward({"d_horiz_m": 500.0, "d_slope_m": 400.0})
	assert_false(bool(e3.get("ok", true)), "斜距<平距拒绝")
	var e4: Dictionary = Ds.forward({"dh_m": 30.0, "d_horiz_m": 500.0, "slope_pct": 6.0, "slope_deg": 3.0})
	assert_false(bool(e4.get("ok", true)), "slope_pct 与 slope_deg 同时给出拒绝")
	var e5: Dictionary = Ds.forward({"dh_m": 10.0, "slope_pct": 0.0})
	assert_false(bool(e5.get("ok", true)), "坡度 0 但高差非 0 拒绝")

# ---------- P5 追加：三量一致性校验与零解 NaN 防护 ----------

## dh + 平距 + 斜距三量一致 → 不出告警；斜距矛盾（相对超差 > 1e-6）→ warn 提示
func test_three_quantity_consistency_check() -> void:
	var slope_exact := sqrt(500.0 * 500.0 + 30.0 * 30.0)
	var ok_res: Dictionary = Ds.forward({"dh_m": 30.0, "d_horiz_m": 500.0, "d_slope_m": slope_exact})
	assert_true(bool(ok_res.get("ok", false)), "三量一致应成功")
	if bool(ok_res.get("ok", false)):
		var joined := ""
		for s: Dictionary in ok_res["steps"]:
			joined += String(s.get("result", ""))
		assert_false(joined.contains("存在差异"), "三量一致无告警")
	# 斜距矛盾：给 600 m（相对差约 20% ≫ 1e-6）
	var bad_res: Dictionary = Ds.forward({"dh_m": 30.0, "d_horiz_m": 500.0, "d_slope_m": 600.0})
	assert_true(bool(bad_res.get("ok", false)), "矛盾斜距仍按主量解算")
	if bool(bad_res.get("ok", false)):
		var joined2 := ""
		for s: Dictionary in bad_res["steps"]:
			joined2 += String(s.get("result", ""))
		assert_true(joined2.contains("存在差异"), "斜距矛盾写 warn（中文提示）")
		assert_true(joined2.contains("斜距"), "warn 指明斜距量")

## 零解：Δh=0 且坡度 0% → 返回完整零解，slope_pct/slope_deg 均为 0，无 NaN
func test_zero_solution_no_nan() -> void:
	var res: Dictionary = Ds.forward({"dh_m": 0.0, "slope_pct": 0.0})
	assert_true(bool(res.get("ok", false)), "零解应成功（不再产生 NaN）：" + String(res.get("error", "")))
	if bool(res.get("ok", false)):
		var v: Dictionary = res["value"]
		assert_almost_eq(float(v["dh_m"]), 0.0, 1e-12, "高差 0")
		assert_almost_eq(float(v["slope_pct"]), 0.0, 1e-12, "坡度 0")
		assert_almost_eq(float(v["slope_deg"]), 0.0, 1e-12, "坡度角 0")
		assert_almost_eq(float(v["d_slope_m"]), 0.0, 1e-12, "斜距取 0（完整零解）")
		# 所有输出均有限（无 NaN/INF）
		for key: String in ["dh_m", "d_horiz_m", "d_slope_m", "slope_pct", "slope_deg"]:
			assert_true(is_finite(float(v[key])), "输出 %s 为有限值" % key)
		# steps 注明零解含义
		var joined := ""
		for s: Dictionary in res["steps"]:
			joined += String(s.get("result", ""))
		assert_true(joined.contains("零解") or joined.contains("水平"), "steps 说明零解含义")
