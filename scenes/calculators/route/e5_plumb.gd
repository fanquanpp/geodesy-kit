# scenes/calculators/route/e5_plumb.gd —— E5 垂直度计算器
extends "res://scenes/widgets/calculator_base.gd"

const Core := preload("res://core/earthwork/plumb.gd")
const Ui := preload("res://scenes/calculators/route/ui_common.gd")

func _ready() -> void:
	super._ready()
	add_input_row("高度 H (m)", "h_m", "如 50")
	add_input_row("顶部偏移 dx 东 (m)", "dx_m", "如 0.04")
	add_input_row("顶部偏移 dy 北 (m)", "dy_m", "如 0.03")
	add_input_row("限差 1/N 的 N", "limit_den", "如 1000 表示 H/1000（可选）")
	add_input_row("限差偏移 (mm)", "limit_offset_mm", "直接给限差时填（可选）")
	set_inputs(_example_inputs)

func get_title() -> String:
	return "垂直度（E5）"

func get_description() -> String:
	return "总偏移 δ=√(dx²+dy²)、倾斜率 δ/H（1/N 表达）、倾角；限差由用户输入（规范限值因构件而异）"

func get_entry_id() -> String:
	return "e5_plumb"

func run() -> Dictionary:
	var p := {}
	for key in ["h_m", "dx_m", "dy_m", "limit_den", "limit_offset_mm"]:
		var f := Ui.to_f(_fields[key].text)
		if not is_nan(f):
			p[key] = f
	return Core.forward(p)

func set_inputs(inputs: Dictionary) -> void:
	for key: String in _fields:
		if inputs.has(key):
			_fields[key].text = str(inputs[key])
