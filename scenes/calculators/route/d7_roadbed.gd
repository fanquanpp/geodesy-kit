# scenes/calculators/route/d7_roadbed.gd —— D7 路基开挖口/坡脚计算器
extends "res://scenes/widgets/calculator_base.gd"

const Core := preload("res://core/route/roadbed.gd")
const Ui := preload("res://scenes/calculators/route/ui_common.gd")

func _ready() -> void:
	super._ready()
	add_input_row("设计中心高程（m）", "design_elev_m", "如 55")
	add_input_row("路基半宽 b（m）", "half_width_m", "如 10")
	add_input_row("路拱横坡 i（%）", "cross_slope_pct", "默认 0，如 2")
	add_input_row("填方坡率 1:m 的 m", "fill_slope_ratio", "如 1.5 表示 1:1.5")
	add_input_row("挖方坡率 1:n 的 n", "cut_slope_ratio", "如 0.75 表示 1:0.75")
	add_input_row("地面线 偏距,高程（分号分行）", "ground", "如 -40,50; 0,50; 40,52（偏距右正左负）", LineEdit.KEYBOARD_TYPE_DEFAULT)
	set_inputs(_example_inputs)

func get_title() -> String:
	return "路基开挖口/坡脚放样（D7）"

func get_description() -> String:
	return "横断面模板（路槽边缘+路拱）与地面折线精确求交：两侧填/挖判定、坡脚/开挖口距中桩距离与地面高程"

func get_entry_id() -> String:
	return "d7_roadbed"

func run() -> Dictionary:
	var kv := Ui.to_kv_rows(_fields["ground"].text, ["offset_m", "elev_m"])
	if not kv["errors"].is_empty():
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "地面线格式有误：" + "；".join(kv["errors"])}
	var rows: Array = kv["rows"]
	if rows.size() < 2:
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "地面线至少 2 点（每行 偏距,高程）"}
	var p := {"ground": rows}
	for key in ["design_elev_m", "half_width_m", "cross_slope_pct", "fill_slope_ratio", "cut_slope_ratio"]:
		var f := Ui.to_f(_fields[key].text)
		if not is_nan(f):
			p[key] = f
	return Core.forward(p)

func set_inputs(inputs: Dictionary) -> void:
	super.set_inputs(inputs)
	for key: String in _fields:
		if inputs.has(key):
			_fields[key].text = str(inputs[key])
