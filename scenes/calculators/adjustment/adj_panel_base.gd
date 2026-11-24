# scenes/calculators/adjustment/adj_panel_base.gd —— M6 计算器域内公共基类
# 继承 scenes/widgets/calculator_base.gd（契约不变），补充：
#   - set_inputs 统一实现（历史回放/示例填充按已登记字段写 text）；
#   - _build_fields() 钩子：子类在此用 add_input_row/_add_text_area 建输入行；
#   - 文本块解析（逐行、空白/逗号分隔、# 注释、中文报错）与数值校验工具。
# 触控目标：LineEdit 96px 高（calculator_base 保证），TextEdit ≥200px。
extends "res://scenes/widgets/calculator_base.gd"

## 子类覆写：在 super._ready() 之后建立本计算器的输入字段
func _build_fields() -> void:
	pass

func _ready() -> void:
	super._ready()
	_build_fields()
	set_inputs(_example_inputs)

## 多行文本域登记表（基类 register_field 只收 LineEdit，共享文件不可改，故域内自管）
var _areas: Dictionary = {}

## 统一输入快照（LineEdit 字段 + TextEdit 字段）
func get_inputs() -> Dictionary:
	var out := {}
	for key: String in _fields:
		out[key] = _fields[key].text
	for key: String in _areas:
		out[key] = _areas[key].text
	return out

## 统一输入填充（历史回放/示例填充）
func set_inputs(inputs: Dictionary) -> void:
	super.set_inputs(inputs)
	for key: String in _fields:
		if inputs.has(key):
			_fields[key].text = str(inputs[key])
	for key: String in _areas:
		if inputs.has(key):
			_areas[key].text = str(inputs[key])

# ---------- 构件 ----------

## 按键取字段文本（LineEdit 与 TextEdit 通吃）
func _field_text(key: String) -> String:
	if _areas.has(key):
		return String(_areas[key].text)
	if _fields.has(key):
		return String(_fields[key].text)
	return ""

## 多行文本域（网形/观测数据用），登记进 _areas
func _add_text_area(label_text: String, key: String, placeholder := "") -> TextEdit:
	var row := VBoxContainer.new()
	var lab := Label.new()
	lab.text = label_text
	row.add_child(lab)
	var edit := TextEdit.new()
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(0, 200)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	row.add_child(edit)
	_inputs_root.add_child(row)
	_areas[key] = edit
	return edit

func _add_section(text: String) -> void:
	var lab := Label.new()
	lab.text = text
	lab.theme_type_variation = &"Header"
	_inputs_root.add_child(lab)

# ---------- 解析工具 ----------

## 文本块 → 行 token 数组（空白/逗号分隔；# 与 // 注释、空行跳过）
func _parse_lines(text: String) -> Array:
	var out := []
	var lines := text.split("\n")
	for line: String in lines:
		var t := line.strip_edges()
		if t.is_empty() or t.begins_with("#") or t.begins_with("//"):
			continue
		var cleaned := t.replace("，", " ").replace(",", " ").replace("\t", " ")
		while "  " in cleaned:
			cleaned = cleaned.replace("  ", " ")
		var tokens := cleaned.split(" ", false)
		if tokens.size() > 0:
			out.append(tokens)
	return out

## token → float；非法返回 NAN（调用方用 _need_num 报中文错）
func _num(s) -> float:
	if s is float or s is int:
		return float(s)
	var t := String(s).strip_edges().replace("−", "-")
	if t.is_empty() or not t.is_valid_float():
		return NAN
	return t.to_float()

## 取必填数值：非法/缺失返回 NAN 并累计错误信息到 errors
func _need_num(tokens: Array, idx: int, what: String, errors: PackedStringArray) -> float:
	if tokens.size() <= idx:
		errors.append("%s 缺少 %s" % [what, _idx_name(idx)])
		return NAN
	var v := _num(tokens[idx])
	if is_nan(v):
		errors.append("%s 的 %s 不是有效数字：%s" % [what, _idx_name(idx), String(tokens[idx])])
	return v

func _idx_name(idx: int) -> String:
	return "第%d列" % (idx + 1)

## 解析失败的统一 §5 失败壳（value 空、error 中文）
func _parse_fail(errors: PackedStringArray) -> Dictionary:
	var msg := "输入格式有误：" + "；".join(errors) + "。请按提示格式逐行填写。"
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": msg}
