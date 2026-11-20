# scenes/calculators/route/d2_alignment_el.gd —— D2 线元法计算器
extends "res://scenes/widgets/calculator_base.gd"

const Core := preload("res://core/route/alignment_el.gd")
const Ui := preload("res://scenes/calculators/route/ui_common.gd")

var _mode_opt: OptionButton

func _ready() -> void:
	super._ready()
	add_input_row("起点 X 东 (m)", "x_m", "如 1000")
	add_input_row("起点 Y 北 (m)", "y_m", "如 2000")
	add_input_row("起点切线方位 (°)", "bearing_deg", "如 30")
	add_input_row("起点里程 (m)", "chain_m", "默认 0")
	add_input_row("线元表 类型,长,k0,k1（分号分行）", "elements", "如 line,100; spiral,60,0,0.002; arc,130.9,0.002,0.002")
	var row := HBoxContainer.new()
	var lab := Label.new()
	lab.text = "计算模式"
	lab.custom_minimum_size = Vector2(180, 0)
	row.add_child(lab)
	_mode_opt = OptionButton.new()
	_mode_opt.add_item("正算：里程 → 坐标")
	_mode_opt.add_item("反算：坐标 → 里程+偏距")
	_mode_opt.add_item("采样：等间距坐标表")
	_mode_opt.add_item("装配：分段表")
	_mode_opt.custom_minimum_size = Vector2(0, 96)
	row.add_child(_mode_opt)
	_inputs_root.add_child(row)
	add_input_row("查询里程 (m)", "chain_m_q", "正算用")
	add_input_row("查询 X 东 (m)", "x_m_q", "反算用")
	add_input_row("查询 Y 北 (m)", "y_m_q", "反算用")
	add_input_row("采样步距 (m)", "step_m", "采样用，如 20")
	set_inputs(_example_inputs)

func get_title() -> String:
	return "线元法（D2）"

func get_description() -> String:
	return "直线/圆曲线/缓和曲线线元统一模型（曲率线性过渡），装配与正反算、等间距采样；D 组定位地基"

func get_entry_id() -> String:
	return "d2_alignment_el"

func run() -> Dictionary:
	var p := _collect_common()
	if p is Dictionary and p.has("error"):
		return p
	match _mode_opt.selected:
		0:
			p["chain_m"] = Ui.to_f(_fields["chain_m_q"].text)
			return Core.point_at(p)
		1:
			p["x_m"] = Ui.to_f(_fields["x_m_q"].text)
			p["y_m"] = Ui.to_f(_fields["y_m_q"].text)
			return Core.inverse(p)
		2:
			p["step_m"] = Ui.to_f(_fields["step_m"].text)
			return Core.sample(p)
		_:
			return Core.build(p)

func _collect_common() -> Dictionary:
	var sx := Ui.to_f(_fields["x_m"].text)
	var sy := Ui.to_f(_fields["y_m"].text)
	var az := Ui.to_f(_fields["bearing_deg"].text)
	if is_nan(sx) or is_nan(sy) or is_nan(az):
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "请填写起点坐标 X/Y 与切线方位（数字）"}
	var rows := Ui.to_list_multi(_fields["elements"].text, ";")
	if rows.is_empty():
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "请输入至少一个线元（每行：类型,长度,k0,k1，line 可省略 k0/k1）"}
	var els := []
	var errs := PackedStringArray()
	for i in rows.size():
		var parts := Ui.to_list(rows[i])
		if parts.is_empty():
			continue
		var typ := String(parts[0]).to_lower()
		if typ == "line" and parts.size() >= 2:
			els.append({"type": "line", "len": parts[1], "k0": 0.0, "k1": 0.0})
			continue
		if parts.size() < 4:
			errs.append("第 %d 行应为：类型,长度,k0,k1" % (i + 1))
			continue
		if typ != "arc" and typ != "spiral":
			errs.append("第 %d 行类型须为 line/arc/spiral" % (i + 1))
			continue
		els.append({"type": typ, "len": parts[1], "k0": parts[2], "k1": parts[3]})
	if not errs.is_empty():
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "线元表格式有误：" + "；".join(errs)}
	if els.is_empty():
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "未解析到有效线元"}
	var p := {"elements": els, "start": {"x_m": sx, "y_m": sy, "bearing_deg": az}}
	var ch0 := Ui.to_f(_fields["chain_m"].text)
	if not is_nan(ch0):
		p["start"]["chain_m"] = ch0
	return p

func get_inputs() -> Dictionary:
	var out := super.get_inputs()
	out["mode"] = str(_mode_opt.selected)
	return out

func set_inputs(inputs: Dictionary) -> void:
	for key: String in _fields:
		if inputs.has(key):
			_fields[key].text = str(inputs[key])
	if inputs.has("mode"):
		var idx := int(Ui.to_f(str(inputs["mode"])))
		if idx >= 0 and idx < _mode_opt.item_count:
			_mode_opt.select(idx)
