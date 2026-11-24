# core/math/expression_calc.gd —— GK-M1-7 叶子库：科学表达式求值（内置 Expression 包装）
#
# 服务 G7 统计与 I-摄影测量自定义遥感指数；语法为 Godot Expression 子集，三角函数弧度制，
# 度制换算由调用方先行完成。⚠ 整型相除为整除（10/4=2），本层忠实透传不改写。
# 统一返回 §5 协议形状（steps 恒 []，formula 回显原文）；失败 ok=false、value=NAN、error 中文。
# 变量名须合法标识符且不遮蔽 PI/TAU/INF/NAN；值为有限数值；execute(show_error=false) 不污染日志。
# 本类为架构明确许可的引擎核心类型使用点（Expression：非 Node、无 I/O、无网络）。
# 向量：tests/mathk/test_expression_calc.gd。
class_name GKExpressionCalc
extends RefCounted

## 保留常量名：不允许作为变量声明（防止遮蔽 Expression 内置常量）
const RESERVED_NAMES := ["PI", "TAU", "INF", "NAN"]

## 求值主入口。
static func evaluate(expr_text: String, variables: Dictionary = {}) -> Dictionary:
	var text := expr_text.strip_edges()
	if text.is_empty():
		return _result(false, NAN, text, "表达式为空")
	# 变量声明与校验（Dictionary 保持插入顺序，parse 按此顺序登记名册）
	var names := PackedStringArray()
	var inputs := Array()
	for key in variables.keys():
		var k := String(key)
		if not _valid_name(k):
			return _result(false, NAN, text, "变量名「%s」不合法：须以字母或下划线开头，只含字母、数字、下划线，且不得使用保留名 PI/TAU/INF/NAN" % k)
		var val = variables[key]
		if not ((val is float) or (val is int)) or not is_finite(float(val)):
			return _result(false, NAN, text, "变量「%s」的值必须是有限数值" % k)
		names.append(k)
		inputs.append(float(val))
	var e := Expression.new()
	if e.parse(text, names) != OK:
		return _result(false, NAN, text, "表达式语法错误：%s" % e.get_error_text())
	var r = e.execute(inputs, null, false)
	if e.has_execute_failed():
		return _result(false, NAN, text, "表达式计算失败：%s" % e.get_error_text())
	var rt := typeof(r)
	if rt != TYPE_FLOAT and rt != TYPE_INT:
		return _result(false, NAN, text, "表达式的结果不是数值（当前结果类型：%s）" % type_string(rt))
	var value := float(r)
	if not is_finite(value):
		return _result(false, NAN, text, "计算结果非有限值（可能除零或溢出）")
	return _result(true, value, text, "")

## 只解析不执行（输入即时校验用，如按键时实时反馈）。返回 {ok, error}。
static func check(expr_text: String, variables: Dictionary = {}) -> Dictionary:
	var text := expr_text.strip_edges()
	if text.is_empty():
		return {"ok": false, "error": "表达式为空"}
	var names := PackedStringArray()
	for key in variables.keys():
		var k := String(key)
		if not _valid_name(k):
			return {"ok": false, "error": "变量名「%s」不合法：须以字母或下划线开头，只含字母、数字、下划线，且不得使用保留名 PI/TAU/INF/NAN" % k}
		names.append(k)
	var e := Expression.new()
	if e.parse(text, names) != OK:
		return {"ok": false, "error": "表达式语法错误：%s" % e.get_error_text()}
	return {"ok": true, "error": ""}

# ---------- 内部工具 ----------

static func _result(ok: bool, value: float, formula: String, error: String) -> Dictionary:
	return {"ok": ok, "value": value, "steps": [], "formula": formula, "error": error}

## 合法变量名：[A-Za-z_][A-Za-z0-9_]*，且不在保留名清单
static func _valid_name(name: String) -> bool:
	if name.is_empty():
		return false
	if RESERVED_NAMES.has(name):
		return false
	var first := name[0]
	if not ((first >= "a" and first <= "z") or (first >= "A" and first <= "Z") or first == "_"):
		return false
	for i in range(1, name.length()):
		var c := name[i]
		if not ((c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_"):
			return false
	return true
