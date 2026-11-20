# GeodesyKit 测试断言基类
# 所有测试脚本必须：extends "res://tests/test_case_base.gd"
# 断言为"软失败"：单条断言失败不会中断测试方法，失败消息累计到 failures，
# 由 run_tests.gd 统计。不使用 push_error/push_warning（避免污染退出码判断）。
# 注意：失败消息组装一律用显式 if/else，不用内嵌三元运算符（避免 GDScript
# 三元与 % 运算符优先级纠缠导致的运行期 variant 错误）。
extends RefCounted

# 当前正在执行的测试方法名，由 run_tests.gd 在调用前设置
var current_method := ""
# 本次测试累计失败消息（每条 = "方法名: 描述"）
var failures: PackedStringArray = PackedStringArray()

func _fail(msg: String) -> void:
	failures.append("%s: %s" % [current_method, msg])

func assert_true(cond: bool, msg := "条件应为真") -> void:
	if not cond:
		_fail(msg)

func assert_false(cond: bool, msg := "条件应为假") -> void:
	if cond:
		_fail(msg)

func assert_eq(actual, expected, msg := "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		if msg == "":
			msg = "实际=%s 期望=%s" % [str(actual), str(expected)]
		else:
			msg = "%s 实际=%s 期望=%s" % [msg, str(actual), str(expected)]
		_fail(msg)

func assert_ne(actual, expected, msg := "") -> void:
	if typeof(actual) == typeof(expected) and actual == expected:
		if msg == "":
			msg = "两者不应相等：%s" % str(actual)
		else:
			msg = "%s 两者不应相等：%s" % [msg, str(actual)]
		_fail(msg)

## 浮点容差断言：核心验收入口。显式拒绝 NaN/INF，防止 "NaN != NaN" 漏判。
func assert_almost_eq(actual: float, expected: float, tol := 1e-6, msg := "") -> void:
	if not is_finite(actual) or not is_finite(expected):
		if msg == "":
			msg = "出现非有限值 actual=%f expected=%f" % [actual, expected]
		else:
			msg = "%s 出现非有限值 actual=%f expected=%f" % [msg, actual, expected]
		_fail(msg)
		return
	if absf(actual - expected) > tol:
		if msg == "":
			msg = "实际=%.12f 期望=%.12f 容差=%s" % [actual, expected, str(tol)]
		else:
			msg = "%s 实际=%.12f 期望=%.12f 容差=%s" % [msg, actual, expected, str(tol)]
		_fail(msg)

## 逐分量浮点断言（Vector2/Vector3/Array 均可）
func assert_vector_almost_eq(actual, expected, tol := 1e-6, msg := "") -> void:
	if actual is Vector2 and expected is Vector2:
		assert_almost_eq(actual.x, expected.x, tol, msg + " x")
		assert_almost_eq(actual.y, expected.y, tol, msg + " y")
	elif actual is Vector3 and expected is Vector3:
		assert_almost_eq(actual.x, expected.x, tol, msg + " x")
		assert_almost_eq(actual.y, expected.y, tol, msg + " y")
		assert_almost_eq(actual.z, expected.z, tol, msg + " z")
	elif actual is Array and expected is Array:
		assert_eq(actual.size(), expected.size(), msg + " 数组长度不一致")
		for i in mini(actual.size(), expected.size()):
			assert_almost_eq(float(actual[i]), float(expected[i]), tol, "%s 元素[%d]" % [msg, i])
	else:
		_fail("类型不支持逐分量比较：%s vs %s" % [type_string(typeof(actual)), type_string(typeof(expected))])

## 区间断言（闭区间）
func assert_between(v: float, lo: float, hi: float, msg := "应落在区间内") -> void:
	if not (v >= lo and v <= hi):
		_fail("%s：v=%f 不在 [%f, %f]" % [msg, v, lo, hi])

## 整型相等（用于带号、EPSG 码等整型量）
func assert_int_eq(actual: int, expected: int, msg := "") -> void:
	if actual != expected:
		if msg == "":
			msg = "实际=%d 期望=%d" % [actual, expected]
		else:
			msg = "%s 实际=%d 期望=%d" % [msg, actual, expected]
		_fail(msg)
