# 冒烟测试：验证测试框架本身（数值取自已验证向量：A1 坐标正算 45°/500m）
extends "res://tests/test_case_base.gd"

func test_harness_float_tolerance() -> void:
	assert_almost_eq(1.0 + 1e-9, 1.0, 1e-6, "远小于容差应通过")
	assert_almost_eq(1.0 + 2e-6, 1.0, 1e-5, "容差边界内应通过")
	assert_between(30.5, 30.0, 31.0, "区间断言")
	assert_int_eq(int(4527), 4527, "整型断言")

func test_known_vector_forward() -> void:
	# A1 坐标正算：P(1000,1000), az=45°, d=500 -> (1353.5534, 1353.5534)
	var dx: float = 500.0 * sin(deg_to_rad(45.0))
	var dy: float = 500.0 * cos(deg_to_rad(45.0))
	assert_almost_eq(1000.0 + dx, 1353.553390593, 1e-6, "x")
	assert_almost_eq(1000.0 + dy, 1353.553390593, 1e-6, "y")
