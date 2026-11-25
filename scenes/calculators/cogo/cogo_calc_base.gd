# scenes/calculators/cogo/cogo_calc_base.gd —— GK-M5 计算器公共基类
#
# 继承 scenes/widgets/calculator_base.gd（M0 共享契约，不改）：
#   - 基类 _ready 的顺序是 _build_ui() → 标题/描述 → set_inputs(示例)；子类需要在
#     _build_ui 之后、set_inputs 之前建输入行，故本类重排 _ready 并提供 _build_rows() 钩子；
#   - 输入解析辅助（中文错误提示、不崩溃）：
#       num_field  —— 数值（空/非法记入 bad）；
#       ang_field  —— 角度（接受十进制度 30.5 或度分秒 30 30 00 / 30°30′00″，经 M1 parse_dms）；
#       side_field —— 左/右侧别（左/右/left/right/±1，无法识别返回 0）；
#   - fail_input() 把累计的中文错误转为 §5 协议失败结构；bad 元素可携带字段键名
#     （{key, msg}），用于聚焦首个出错字段（widgets 层 focus_field 助手，空值保护）。
class_name GKCogoCalcBase
extends "res://scenes/widgets/calculator_base.gd"

func _ready() -> void:
	_build_ui()
	_build_rows()
	_title_label.text = get_title()
	_desc_label.text = get_description()
	_desc_label.visible = get_description() != ""
	set_inputs(_example_inputs)

## 子类覆写：用 add_input_row(标签, key, placeholder[, keyboard_type]) 建输入行；
## 文本枚举键（模式/侧别/转折角类型等）须显式传 LineEdit.KEYBOARD_TYPE_DEFAULT
func _build_rows() -> void:
	pass

## 历史回放/示例填充：按 key 回填已登记的输入框
func set_inputs(inputs: Dictionary) -> void:
	super.set_inputs(inputs)
	for key: String in inputs:
		if _fields.has(key):
			(_fields[key] as LineEdit).text = String(inputs[key])

# ---------- 输入解析辅助 ----------
# bad 数组元素兼容两种形态：纯字符串（仅文案），或 {key: 字段键名, msg: 中文文案}
# （携带 key 时 fail_input 会尝试聚焦首个出错字段——依赖 widgets 层 focus_field 助手，
#   未合入或不可用时静默跳过，不影响协议返回）。

## 数值输入：空/非法记入 bad（中文提示），返回 NAN；key 为字段键名（可选，用于聚焦）
func num_field(edit: LineEdit, label: String, bad: Array, key := "") -> float:
	var t := edit.text.strip_edges().replace("−", "-")
	if t.is_empty():
		bad.append(_bad_entry(key, "请输入「%s」" % label))
		return NAN
	if not t.is_valid_float():
		bad.append(_bad_entry(key, "「%s」不是有效数字：%s" % [label, t]))
		return NAN
	var v := t.to_float()
	if not is_finite(v):
		bad.append(_bad_entry(key, "「%s」数值超出范围" % label))
		return NAN
	return v

## 角度输入：接受十进制度（30.5）或度分秒（30 30 00 / 30°30′00″）；key 为字段键名（可选）。
## 角度档键盘契约（ask a）：经本函数解析的字段，其 LineEdit 键盘须回落 DEFAULT
## （数字键盘无空格，度分秒输不了）——建行走 add_input_row 的 keyboard_angle=true，
## 本处兜底把漏改的行在获焦时纠正（幂等，行已 DEFAULT 时无副作用）。
func ang_field(edit: LineEdit, label: String, bad: Array, key := "") -> float:
	edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	var t := edit.text.strip_edges()
	if t.is_empty():
		bad.append(_bad_entry(key, "请输入「%s」" % label))
		return NAN
	var v := GKAngles.parse_dms(t)
	if is_nan(v):
		bad.append(_bad_entry(key, "「%s」不是有效角度：%s（可输 30.5 或 30 30 00）" % [label, t]))
		return NAN
	return v

## 可选数值：空返回默认值；有内容则校验；key 为字段键名（可选）
func opt_num_field(edit: LineEdit, default: float, label: String, bad: Array, key := "") -> float:
	if edit.text.strip_edges().is_empty():
		return default
	return num_field(edit, label, bad, key)

## 左/右侧别：空返回 default_side（+1 右 / −1 左）；无法识别返回 0
func side_field(edit: LineEdit, default_side: int) -> int:
	var t := edit.text.strip_edges().to_lower()
	if t.is_empty():
		return default_side
	if t == "右" or t == "r" or t == "right" or t == "1" or t == "+1":
		return 1
	if t == "左" or t == "l" or t == "left" or t == "-1" or t == "−1":
		return -1
	return 0

## 组装 bad 元素：key 非空时携带字段键名（供聚焦），否则退化为纯文案
func _bad_entry(key: String, msg: String) -> Variant:
	if key.is_empty():
		return msg
	return {"key": key, "msg": msg}

## 累计错误 → §5 协议失败结构（中文，多条以分号连接）。
## 若 bad 中携带出错字段键名，尝试聚焦首个出错字段
## （widgets 层 focus_field 助手由 P6 提供；未合入时经 has_method 空值保护跳过）。
func fail_input(bad: Array) -> Dictionary:
	var msg := ""
	var focus_key := ""
	for i in bad.size():
		var entry: Variant = bad[i]
		var text := ""
		if entry is Dictionary:
			text = String(entry.get("msg", ""))
			if focus_key.is_empty():
				focus_key = String(entry.get("key", ""))
		else:
			text = String(entry)
		if i > 0:
			msg += "；"
		msg += text
	if not focus_key.is_empty() and has_method("focus_field"):
		call("focus_field", focus_key)
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": msg}
