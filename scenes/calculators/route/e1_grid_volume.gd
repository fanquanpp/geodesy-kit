# scenes/calculators/route/e1_grid_volume.gd —— E1 方格网法土方计算器
extends "res://scenes/widgets/calculator_base.gd"

const Core := preload("res://core/earthwork/grid_volume.gd")
const Ui := preload("res://scenes/calculators/route/ui_common.gd")

func _ready() -> void:
	super._ready()
	add_input_row("设计高程 (m)", "design_elev_m", "如 0")
	add_input_row("格网边长 a (m)", "cell_size_m", "如 20")
	add_input_row("格网点地面高程（分号分行）", "grid", "行内空格分隔：1 2; 1.5 0.5")
	set_inputs(_example_inputs)

func get_title() -> String:
	return "方格网法土方（E1）"

func get_description() -> String:
	return "V = a²·Σh/4（四角施工高度代数和的 1/4 × 面积）逐格累计填挖；h = 地面 − 设计（正挖负填）"

func get_entry_id() -> String:
	return "e1_grid_volume"

func run() -> Dictionary:
	var grid := Ui.to_grid(_fields["grid"].text)
	if grid.is_empty():
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "请输入格网高程（每行空格分隔，行间分号）"}
	var p := {"grid": grid}
	var zd := Ui.to_f(_fields["design_elev_m"].text)
	if not is_nan(zd):
		p["design_elev_m"] = zd
	var a := Ui.to_f(_fields["cell_size_m"].text)
	if not is_nan(a):
		p["cell_size_m"] = a
	return Core.forward(p)

func set_inputs(inputs: Dictionary) -> void:
	for key: String in _fields:
		if inputs.has(key):
			_fields[key].text = str(inputs[key])
