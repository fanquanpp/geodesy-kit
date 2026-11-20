# tests/mathk/test_expression_calc.gd —— GK-M1-7 Expression 包装回归（构造向量，解析可验证）
#
# 构造向量（手算）：1+2*3=7、sqrt(16)=4、sin(PI/6)=0.5、max(3,5)*2=10、pow(2,10)=1024、
# 2.5*4+1=11（变量 a=2.5,x=4,b=1）、(5+3)/(5-3)=4、h·cos(0)=h。
# 拒绝路径：空表达式 / 语法错误 / 未声明变量 / 除零 / 非有限结果 / 非数值结果 /
# 非法与保留变量名 / 非数值变量值 —— 全部 ok=false + 中文 error + value=NAN。
# 说明：check() 只解析不执行，用于输入即时校验。
extends "res://tests/test_case_base.gd"

const EC := preload("res://core/math/expression_calc.gd")

# 防御性取值助手：字典键缺失/类型意外时给默认值，避免空引用触发 runner 已知盲点
func _ok(r) -> bool:
	return bool(r.get("ok", false))

func _val(r) -> float:
	return float(r.get("value", NAN))

func _err(r) -> String:
	return String(r.get("error", ""))

func test_basic_arithmetic_and_functions() -> void:
	var r: Dictionary = EC.evaluate("1+2*3")
	assert_true(_ok(r), "四则运算应成功")
	assert_almost_eq(_val(r), 7.0, 1e-12, "1+2*3=7")
	assert_almost_eq(_val(EC.evaluate("sqrt(16)")), 4.0, 1e-12, "sqrt(16)=4")
	assert_almost_eq(_val(EC.evaluate("sin(PI/6)")), 0.5, 1e-12, "sin(PI/6)=0.5（弧度制）")
	assert_almost_eq(_val(EC.evaluate("PI")), 3.141592653589793, 1e-12, "常量 PI")
	assert_almost_eq(_val(EC.evaluate("max(3,5)*2")), 10.0, 1e-12, "max(3,5)*2=10")
	assert_almost_eq(_val(EC.evaluate("min(3,5)")), 3.0, 1e-12, "min(3,5)=3")
	assert_almost_eq(_val(EC.evaluate("pow(2,10)")), 1024.0, 1e-9, "pow(2,10)=1024")
	assert_almost_eq(_val(EC.evaluate("abs(-3)")), 3.0, 1e-12, "abs(-3)=3")
	assert_almost_eq(_val(EC.evaluate("(2+3)*4-10.0/4")), 17.5, 1e-12, "括号与浮点除法优先级")
	# 引擎语义固定（G7 需知）：整型字面量相除为整除（GDScript 语义），10/4=2；
	# 浮点除必须写 10.0/4。本层不做语法改写，UI 提示文案由 G7 自行携带。
	assert_almost_eq(_val(EC.evaluate("10/4")), 2.0, 1e-12, "整型相除=整除（引擎语义）")
	# 协议形状：成功时 steps 为空数组、formula 回显原文、error 为空
	assert_true((r.get("steps", null) is Array) and (r["steps"] as Array).is_empty(), "steps 恒为 []")
	assert_eq(String(r.get("formula", "")), "1+2*3", "formula 回显")
	assert_eq(_err(r), "", "成功时 error 为空")

func test_variables() -> void:
	var r: Dictionary = EC.evaluate("a*x + b", {"a": 2.5, "x": 4, "b": 1.0})
	assert_true(_ok(r), "带变量求值应成功")
	assert_almost_eq(_val(r), 11.0, 1e-12, "2.5*4+1=11")
	var r2: Dictionary = EC.evaluate("h*cos(zen)", {"h": 10.0, "zen": 0.0})
	assert_almost_eq(_val(r2), 10.0, 1e-12, "h·cos(0)=h")
	var r3: Dictionary = EC.evaluate("(x+y)/(x-y)", {"x": 5.0, "y": 3.0})
	assert_almost_eq(_val(r3), 4.0, 1e-12, "(5+3)/(5-3)=4")
	# 整型变量值也接受
	var r4: Dictionary = EC.evaluate("n*2", {"n": 21})
	assert_almost_eq(_val(r4), 42.0, 1e-12, "整型变量值")

func test_rejects_with_chinese_error() -> void:
	# 空表达式
	var r0: Dictionary = EC.evaluate("  ")
	assert_false(_ok(r0), "空表达式应拒绝")
	assert_true(is_nan(_val(r0)), "拒绝时 value=NAN")
	assert_true(_err(r0).contains("空"), "空表达式中文提示")
	# 语法错误
	var r1: Dictionary = EC.evaluate("1+")
	assert_false(_ok(r1), "语法错误应拒绝")
	assert_true(_err(r1).contains("语法"), "语法错误中文提示")
	# 未声明变量
	assert_false(_ok(EC.evaluate("x+1")), "未声明变量应拒绝")
	# 除零（整型执行失败 / 浮点非有限，两条路径都必须 ok=false）
	assert_false(_ok(EC.evaluate("1/0")), "整型除零应拒绝")
	assert_false(_ok(EC.evaluate("1.0/0.0")), "浮点除零（非有限结果）应拒绝")
	# 未知函数（解析期或执行期失败均计为拒绝）
	assert_false(_ok(EC.evaluate("no_such_fn(1)")), "未知函数应拒绝")
	# 非数值结果
	assert_false(_ok(EC.evaluate("1<2")), "布尔结果不是数值")
	assert_false(_ok(EC.evaluate("'abc'")), "字符串结果不是数值")
	# 变量名不合法 / 保留名 / 值非数值
	assert_false(_ok(EC.evaluate("x", {"1x": 1.0})), "数字开头变量名应拒绝")
	assert_false(_ok(EC.evaluate("x", {"x y": 1.0})), "含空格变量名应拒绝")
	assert_false(_ok(EC.evaluate("x", {"PI": 1.0})), "保留名 PI 应拒绝")
	assert_false(_ok(EC.evaluate("x", {"x": "abc"})), "字符串变量值应拒绝")
	assert_false(_ok(EC.evaluate("x", {"x": NAN})), "NaN 变量值应拒绝")
	# 拒绝时 error 非空
	var rx: Dictionary = EC.evaluate("x", {"PI": 1.0})
	assert_true(_err(rx) != "", "拒绝时必须给出中文 error")

func test_check_parse_only() -> void:
	var good: Dictionary = EC.check("a*x+b", {"a": 0.0, "x": 0.0, "b": 0.0})
	assert_true(bool(good.get("ok", false)), "check 合法表达式")
	assert_eq(String(good.get("error", "")), "", "check 通过时 error 为空")
	assert_false(bool(EC.check("1+").get("ok", true)), "check 语法错误")
	assert_false(bool(EC.check("").get("ok", true)), "check 空表达式")
	assert_false(bool(EC.check("q+1", {"PI": 0.0}).get("ok", true)), "check 保留名同样拒绝")
	var bad: Dictionary = EC.check("1+")
	assert_true(String(bad.get("error", "")) != "", "check 失败给出提示")
