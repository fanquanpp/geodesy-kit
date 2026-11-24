# scenes/calculators/route/d1_alignment_jd.gd —— D1 交点法正反算计算器
extends "res://scenes/widgets/calculator_base.gd"

const Core := preload("res://core/route/alignment_jd.gd")
const Ui := preload("res://scenes/calculators/route/ui_common.gd")

var _mode_opt: OptionButton

func _ready() -> void:
	super._ready()
	add_input_row("起点 X 东（m）", "x_m", "如 1000")
	add_input_row("起点 Y 北（m）", "y_m", "如 2000")
	add_input_row("起点里程（m）", "chain_m", "默认 0")
	add_input_row("起始切线方位（°）", "bearing_deg", "留空则取 起点→JD1 方向")
	add_input_row("交点表 x,y,R,l0（分号分行）", "jds", "如 1200,2346.41,300,60; 1691.49,2690.56,300,60", LineEdit.KEYBOARD_TYPE_DEFAULT)
	add_input_row("末交点切线方位（°）", "end_bearing_deg", "可选；留空则末交点不设曲线")
	var row := HBoxContainer.new()
	var lab := Label.new()
	lab.text = "计算模式"
	lab.custom_minimum_size = Vector2(180, 0)
	row.add_child(lab)
	_mode_opt = OptionButton.new()
	_mode_opt.add_item("正算：里程 → 坐标")
	_mode_opt.add_item("反算：坐标 → 里程+偏距")
	_mode_opt.add_item("装配：要素与主点")
	_mode_opt.custom_minimum_size = Vector2(0, 96)
	row.add_child(_mode_opt)
	_inputs_root.add_child(row)
	add_input_row("查询里程桩号（m）", "chain_m_q", "正算用，如 450")
	add_input_row("查询 X 东（m）", "x_m_q", "反算用")
	add_input_row("查询 Y 北（m）", "y_m_q", "反算用")
	set_inputs(_example_inputs)

func get_title() -> String:
	return "交点法中线正反算（D1）"

func get_description() -> String:
	return "由交点序列推转角→曲线要素→主点里程/坐标；支持里程→坐标（正算）、坐标→里程+偏距（反算，右正左负）"

func get_entry_id() -> String:
	return "d1_alignment_jd"

func run() -> Dictionary:
	var kv := Ui.to_kv_rows(_fields["jds"].text, ["x_m", "y_m", "r_m", "l0_m"])
	if not kv["errors"].is_empty():
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "交点表格式有误：" + "；".join(kv["errors"])}
	var rows: Array = kv["rows"]
	if rows.is_empty():
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "请输入至少一个交点（每行 x,y,R,l0）"}
	var p := {"jds": rows}
	var sx := Ui.to_f(_fields["x_m"].text)
	var sy := Ui.to_f(_fields["y_m"].text)
	if is_nan(sx) or is_nan(sy):
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "请填写起点坐标 X 东 / Y 北"}
	p["start"] = {"x_m": sx, "y_m": sy}
	var ch0 := Ui.to_f(_fields["chain_m"].text)
	if not is_nan(ch0):
		p["start"]["chain_m"] = ch0
	var az0 := Ui.to_f(_fields["bearing_deg"].text)
	if not is_nan(az0):
		p["start"]["bearing_deg"] = az0
	var aze := Ui.to_f(_fields["end_bearing_deg"].text)
	if not is_nan(aze):
		p["end_bearing_deg"] = aze
	match _mode_opt.selected:
		0:
			p["chain_m"] = Ui.to_f(_fields["chain_m_q"].text)
			return Core.point_at(p)
		1:
			p["x_m"] = Ui.to_f(_fields["x_m_q"].text)
			p["y_m"] = Ui.to_f(_fields["y_m_q"].text)
			return Core.inverse(p)
		_:
			return Core.forward(p)

func get_inputs() -> Dictionary:
	var out := super.get_inputs()
	out["mode"] = str(_mode_opt.selected)
	return out

func set_inputs(inputs: Dictionary) -> void:
	super.set_inputs(inputs)
	for key: String in _fields:
		if inputs.has(key):
			_fields[key].text = str(inputs[key])
	if inputs.has("mode"):
		var idx := int(Ui.to_f(str(inputs["mode"])))
		if idx >= 0 and idx < _mode_opt.item_count:
			_mode_opt.select(idx)
