# tests/adjustment/test_tolerance.gd —— GK-M6-4 限差检核回归（C8）
#
# 向量来源（【构造·判据明确】）：
#   - 用户自输限差模式（当前主用）：data/tolerance.json 为占位空表（GB 50026 等未逐条核读，
#     不伪造标准值）——检核三要素（实际值/限差值/依据）与通过/超限判定为断言重点；
#   - 公式推算 k·√n、k·√L 为纯数学（k=8,n=4 → 16；k=8mm,L=4km → 16mm）；
#   - 查表模式：空表/未收录 → ok=false 中文提示"改用自输限差"；命中条目原样透传。
extends "res://tests/test_case_base.gd"

const TL := preload("res://core/adjustment/tolerance.gd")

func test_c8_check_scalar_pass_and_over() -> void:
	var ok_res := TL.check_scalar({"name": "角度闭合差", "actual": 2.4, "limit": 8.0, "unit": "″",
		"basis": "用户输入限差（图根级自定）"})
	assert_true(bool(ok_res.get("ok", false)), "检核应成功")
	if bool(ok_res.get("ok", false)):
		assert_true(bool(ok_res["value"]["ok_limit"]), "|2.4|≤8 应通过")
		assert_almost_eq(float(ok_res["value"]["limit_value"]), 8.0, 1e-12, "限差值")
		assert_almost_eq(float(ok_res["value"]["f_actual"]), 2.4, 1e-12, "实际值")
		assert_eq(String(ok_res["value"]["basis"]), "用户输入限差（图根级自定）", "依据")
	var over := TL.check_scalar({"name": "角度闭合差", "actual": 2.4, "limit": 2.0, "unit": "″"})
	assert_true(bool(over.get("ok", false)), "超限仍是计算成功")
	if bool(over.get("ok", false)):
		assert_false(bool(over["value"]["ok_limit"]), "|2.4|>2 应超限")
		# 超限提示三要素：实际/限差/依据（步骤文本含三者）
		var found_actual := false
		var found_limit := false
		var found_basis := false
		for st: Dictionary in over["steps"]:
			var s := String(st.get("substitution", "")) + String(st.get("result", ""))
			if "2.4" in s:
				found_actual = true
			if "2.000000" in s or "限差 ±2" in s:
				found_limit = true
			if "依据" in s:
				found_basis = true
		assert_true(found_actual, "超限提示含实际值")
		assert_true(found_limit, "超限提示含限差值")
		assert_true(found_basis, "超限提示含依据")

func test_c8_check_relative() -> void:
	var ok_res := TL.check_relative({"actual_k": 163506.0, "limit_k": 4000.0, "name": "导线相对闭合差"})
	assert_true(bool(ok_res.get("ok", false)), "相对检核应成功")
	if bool(ok_res.get("ok", false)):
		assert_true(bool(ok_res["value"]["ok_limit"]), "1/163506 优于 1/4000 应通过")
	var over := TL.check_relative({"actual_k": 2000.0, "limit_k": 4000.0})
	assert_true(bool(over.get("ok", false)), "相对检核（超限）应成功")
	if bool(over.get("ok", false)):
		assert_false(bool(over["value"]["ok_limit"]), "1/2000 劣于 1/4000 应超限")

func test_c8_limit_formulas() -> void:
	var ang := TL.angle_limit_sqrt_n({"k_coef": 8.0, "n": 4})
	assert_true(bool(ang.get("ok", false)), "√n 公式应成功")
	assert_almost_eq(float(ang["value"]["limit_value"]), 16.0, 1e-12, "k·√n = 8×2 = 16")
	assert_true("非规范值" in String(ang["steps"][0]["formula"]), "公式助手须标注 k 非规范值")
	var lev := TL.level_limit_sqrt_l({"k_coef": 8.0, "L_km": 4.0})
	assert_true(bool(lev.get("ok", false)), "√L 公式应成功")
	assert_almost_eq(float(lev["value"]["limit_value"]), 16.0, 1e-12, "k·√L = 8×2 = 16 mm")

func test_c8_lookup_table() -> void:
	# 占位空表 → 未收录，ok=false 中文提示（诚实行为）
	var empty := TL.lookup_table({"table": [], "kind": "traverse_angle", "level": "三级"})
	assert_false(bool(empty.get("ok", true)), "空表查不到应失败")
	assert_true("未收录" in String(empty.get("error", "")), "提示未收录")
	assert_true("自输限差" in String(empty.get("error", "")), "提示改用自输限差")
	# 用户自建表命中（测试数据，非规范值）
	var table := [
		{"kind": "traverse_angle", "level": "图根", "limit_value": 60.0, "limit_formula": "60√n", "basis": "测试自建表"},
	]
	var hit := TL.lookup_table({"table": table, "kind": "traverse_angle", "level": "图根"})
	assert_true(bool(hit.get("ok", false)), "命中应成功")
	if bool(hit.get("ok", false)):
		assert_almost_eq(float(hit["value"]["limit_value"]), 60.0, 1e-12, "限差值透传")
		assert_eq(String(hit["value"]["basis"]), "测试自建表", "依据透传")

func test_c8_invalid_inputs() -> void:
	var r1 := TL.check_scalar({"name": "x", "actual": "abc", "limit": 1.0})
	assert_false(bool(r1.get("ok", true)), "非数值实际值应失败")
	var r2 := TL.check_scalar({"name": "x", "actual": 1.0, "limit": -2.0})
	assert_false(bool(r2.get("ok", true)), "负限差应失败")
	var r3 := TL.check_relative({"actual_k": 0.0, "limit_k": 4000.0})
	assert_false(bool(r3.get("ok", true)), "非正 k 应失败")
	var r4 := TL.lookup_table({"kind": "a", "level": "b"})
	assert_false(bool(r4.get("ok", true)), "缺表应失败")
