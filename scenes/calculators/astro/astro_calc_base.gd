# scenes/calculators/astro/astro_calc_base.gd —— GK-M8 astro 域计算器公共基类
#
# 继承 scenes/widgets/calculator_base.gd（M0 共享契约，不改）：
#   - 重排 _ready：_build_ui → _build_rows → 标题/描述 → set_inputs(示例)
#     （与 scenes/calculators/cogo/cogo_calc_base.gd 同手法，见其头注）；
#   - 输入解析辅助（中文错误提示、不崩溃）：
#       num_field  —— 数值（空/非法记入 bad）；
#       ang_field  —— 角度（十进制度或度分秒，经 M1 GKAngles.parse_dms）；
#       opt_num_field —— 可选数值（空返回默认）；
#   - fail_input() 把累计的中文错误转为 §5 协议失败结构。
class_name GKAstroCalcBase
extends "res://scenes/widgets/calculator_base.gd"

func _ready() -> void:
	_build_ui()
	_build_rows()
	_title_label.text = get_title()
	_desc_label.text = get_description()
	_desc_label.visible = get_description() != ""
	set_inputs(_example_inputs)

## 子类覆写：用 add_input_row(标签, key, placeholder) 建输入行
func _build_rows() -> void:
	pass

## 历史回放/示例填充：按 key 回填已登记的输入框
func set_inputs(inputs: Dictionary) -> void:
	for key: String in inputs:
		if _fields.has(key):
			(_fields[key] as LineEdit).text = String(inputs[key])

# ---------- 输入解析辅助 ----------

## 数值输入：空/非法记入 bad（中文提示），返回 NAN
func num_field(edit: LineEdit, label: String, bad: Array) -> float:
	var t := edit.text.strip_edges().replace("−", "-")
	if t.is_empty():
		bad.append("请输入「%s」" % label)
		return NAN
	if not t.is_valid_float():
		bad.append("「%s」不是有效数字：%s" % [label, t])
		return NAN
	var v := t.to_float()
	if not is_finite(v):
		bad.append("「%s」数值超出范围" % label)
		return NAN
	return v

## 角度输入：接受十进制度（30.5）或度分秒（30 30 00 / 30°30′00″）
func ang_field(edit: LineEdit, label: String, bad: Array) -> float:
	var t := edit.text.strip_edges()
	if t.is_empty():
		bad.append("请输入「%s」" % label)
		return NAN
	var v := GKAngles.parse_dms(t)
	if is_nan(v):
		bad.append("「%s」不是有效角度：%s（可输 30.5 或 30 30 00）" % [label, t])
		return NAN
	return v

## 可选数值：空返回默认值；有内容则校验
func opt_num_field(edit: LineEdit, default: float, label: String, bad: Array) -> float:
	if edit.text.strip_edges().is_empty():
		return default
	return num_field(edit, label, bad)

## 累计错误 → §5 协议失败结构（中文，多条以分号连接）
func fail_input(bad: Array) -> Dictionary:
	var msg := ""
	for i in bad.size():
		if i > 0:
			msg += "；"
		msg += String(bad[i])
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": msg}
