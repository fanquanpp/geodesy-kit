# tests/cogo/test_affine.gd —— GK-M5 仿射变换（M5-5，向量来源：ARCHITECTURE.md §4 GK-M5【构造】）
# 权威向量：枢轴(100,100) 旋转 30° 缩放 2，点(300,150)→(496.4102,−13.3975)（距离比 2.000000、方位偏移 30.0000°）
extends "res://tests/test_case_base.gd"

const AF := preload("res://core/cogo/affine_tools.gd")

func test_affine_authoritative_vector() -> void:
	var r := AF.apply({
		"x_m": 300.0, "y_m": 150.0,
		"x_pivot_m": 100.0, "y_pivot_m": 100.0,
		"rot_deg": 30.0, "scale": 2.0, "dx_m": 0.0, "dy_m": 0.0,
	})
	assert_true(bool(r.get("ok", false)), "B7 权威向量成功")
	if not bool(r.get("ok", false)):
		return
	var v: Dictionary = r["value"]
	assert_almost_eq(float(v["x_m"]), 496.4102, 1e-4, "B7 x_m（向量 496.4102）")
	assert_almost_eq(float(v["y_m"]), -13.3975, 1e-4, "B7 y_m（向量 −13.3975）")
	assert_almost_eq(float(v["dist_ratio"]), 2.0, 1e-9, "距离比 = 2.000000")
	assert_almost_eq(float(v["az_offset_deg"]), 30.0, 1e-9, "方位偏移 = 30.0000°")

func test_rotation_clockwise_convention() -> void:
	# 方位系顺时针：北向量 (0,100) 绕原点转 90° → 东 (100,0)
	var r := AF.apply({
		"x_m": 0.0, "y_m": 100.0,
		"x_pivot_m": 0.0, "y_pivot_m": 0.0,
		"rot_deg": 90.0, "scale": 1.0, "dx_m": 0.0, "dy_m": 0.0,
	})
	assert_true(bool(r.get("ok", false)), "90° 旋转成功")
	if bool(r.get("ok", false)):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["x_m"]), 100.0, 1e-12, "北转 90° 朝东（顺时针约定）")
		assert_almost_eq(float(v["y_m"]), 0.0, 1e-12, "y 分量归零")

func test_translation_only() -> void:
	var r := AF.apply({
		"x_m": 10.0, "y_m": 20.0,
		"x_pivot_m": 0.0, "y_pivot_m": 0.0,
		"rot_deg": 0.0, "scale": 1.0, "dx_m": 100.0, "dy_m": -50.0,
	})
	assert_true(bool(r.get("ok", false)), "纯平移成功")
	if bool(r.get("ok", false)):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["x_m"]), 110.0, 1e-12, "平移 dx")
		assert_almost_eq(float(v["y_m"]), -30.0, 1e-12, "平移 dy")

func test_identity_and_defaults() -> void:
	var r := AF.apply({
		"x_m": 42.0, "y_m": -7.5,
		"x_pivot_m": 3.0, "y_pivot_m": 4.0,
	})
	assert_true(bool(r.get("ok", false)), "缺省旋转/缩放/平移按恒等")
	if bool(r.get("ok", false)):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["x_m"]), 42.0, 1e-12, "恒等 x")
		assert_almost_eq(float(v["y_m"]), -7.5, 1e-12, "恒等 y")

func test_scale_zero_error() -> void:
	var r := AF.apply({
		"x_m": 10.0, "y_m": 10.0,
		"x_pivot_m": 0.0, "y_pivot_m": 0.0,
		"rot_deg": 0.0, "scale": 0.0,
	})
	assert_false(bool(r.get("ok", true)), "缩放 0 应失败")
	assert_true(String(r.get("error", "")).contains("0"), "缩放 0 中文错误")

func test_batch_matches_single() -> void:
	var single := AF.apply({
		"x_m": 300.0, "y_m": 150.0,
		"x_pivot_m": 100.0, "y_pivot_m": 100.0,
		"rot_deg": 30.0, "scale": 2.0, "dx_m": 5.0, "dy_m": -1.0,
	})
	var batch := AF.apply_batch({
		"points": "300,150;100,100;0,0",
		"x_pivot_m": 100.0, "y_pivot_m": 100.0,
		"rot_deg": 30.0, "scale": 2.0, "dx_m": 5.0, "dy_m": -1.0,
	})
	assert_true(bool(batch.get("ok", false)), "批量成功")
	if bool(batch.get("ok", false)):
		var v: Dictionary = batch["value"]
		assert_int_eq(int(v["n_points"]), 3, "批量点数")
		var outs := String(v["points_out"]).split(";", false)
		assert_int_eq(outs.size(), 3, "输出点数一致")
		var sv: Dictionary = single["value"]
		var first := outs[0].split(",", false)
		# 批量输出为 6 位小数格式化文本，与全精度单点结果按 1e-6 对齐
		assert_almost_eq(first[0].to_float(), float(sv["x_m"]), 1e-6, "批量首点 x 与单点一致（6 位小数口径）")
		assert_almost_eq(first[1].to_float(), float(sv["y_m"]), 1e-6, "批量首点 y 与单点一致（6 位小数口径）")
		# 枢轴点不动（只受平移影响）
		var pivot_out := outs[1].split(",", false)
		assert_almost_eq(pivot_out[0].to_float(), 105.0, 1e-9, "枢轴点 x = 枢轴 + dx")
		assert_almost_eq(pivot_out[1].to_float(), 99.0, 1e-9, "枢轴点 y = 枢轴 + dy")

func test_batch_errors() -> void:
	var r := AF.apply_batch({"points": "1,2;bad", "x_pivot_m": 0.0, "y_pivot_m": 0.0})
	assert_false(bool(r.get("ok", true)), "批量非法点应失败")
	assert_true(String(r.get("error", "")).length() > 0, "批量中文错误")
