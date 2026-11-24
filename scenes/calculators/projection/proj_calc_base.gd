# scenes/calculators/projection/proj_calc_base.gd —— M3 计算器公共基类
# 职责：统一输入行登记/标签记录/必填校验/输入回填（GKCalculatorBase 契约之内，不改共享文件）。
extends "res://scenes/widgets/calculator_base.gd"

var _labels: Dictionary = {}   # key -> 中文标签
var _required: Array = []

## 子类覆写：用 _add_row 建输入行（在基类骨架建好之后执行）
func _setup() -> void:
	pass

func _build_ui() -> void:
	super._build_ui()
	_setup()

## 登记一行输入并记录标签；required=true 时为必填；
## 文本枚举键（基准名/半球/图幅号/MGRS 串/名称等）由调用方传 keyboard_type=KEYBOARD_TYPE_DEFAULT；
## suffix：单位（并入标签展示，如 "°"/"m"）
func _add_row(label_text: String, key: String, placeholder: String, required := false,
		keyboard_type: int = LineEdit.KEYBOARD_TYPE_NUMBER, suffix := "") -> void:
	add_input_row(label_text, key, placeholder, keyboard_type, suffix)
	_labels[key] = label_text
	if required:
		_required.append(key)

## 坐标对双列行（P9.4）：左右两个 stacked 字段一行排布（B|L、x|y 等），
## 两键各自登记标签/必填——坐标输入形式（用户要求）。
func _add_coord_pair(label_l: String, key_l: String, label_r: String, key_r: String,
		required := false, suffix_l := "", suffix_r := "") -> void:
	add_coord_pair_row(label_l, key_l, label_r, key_r, suffix_l, suffix_r)
	_labels[key_l] = label_l
	_labels[key_r] = label_r
	if required:
		_required.append(key_l)
		_required.append(key_r)

## 历史回放/示例填充
func set_inputs(inputs: Dictionary) -> void:
	super.set_inputs(inputs)
	for key: String in _fields:
		if inputs.has(key):
			(_fields[key] as LineEdit).text = str(inputs[key])

## 收集非空输入（文本原样传给 core，由 core 解析校验并给出中文错误）
func _params() -> Dictionary:
	var p := {}
	var missing := PackedStringArray()
	for key: String in _fields:
		var t: String = (_fields[key] as LineEdit).text.strip_edges()
		if t.is_empty():
			if _required.has(key):
				missing.append(String(_labels.get(key, key)))
			continue
		p[key] = t
	if missing.size() > 0:
		return {"__fail": true, "error": "请先填写：%s" % "、".join(missing)}
	return p

## _params 的失败结构转 §5 协议
func _fail_or(p: Dictionary) -> Dictionary:
	if not bool(p.get("__fail", false)):
		return p
	return {"ok": false, "value": {}, "steps": [], "formula": "",
			"error": String(p.get("error", "请检查输入"))}
