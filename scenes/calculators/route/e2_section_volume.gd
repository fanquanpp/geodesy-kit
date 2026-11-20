# scenes/calculators/route/e2_section_volume.gd —— E2 断面法土方计算器
extends "res://scenes/widgets/calculator_base.gd"

const Core := preload("res://core/earthwork/section_volume.gd")
const Ui := preload("res://scenes/calculators/route/ui_common.gd")

func _ready() -> void:
	super._ready()
	add_input_row("断面桩号 (m)", "chains_m", "空格分隔，如 0 50 100")
	add_input_row("填方面积 (m²)", "fill_areas_m2", "与桩号对应，无填填 0")
	add_input_row("挖方面积 (m²)", "cut_areas_m2", "可选，与桩号对应")
	set_inputs(_example_inputs)

func get_title() -> String:
	return "断面法土方（E2）"

func get_description() -> String:
	return "V = Σ(A_i + A_{i+1})/2 × d_i，填挖分列累计，净值 = 填 − 挖"

func get_entry_id() -> String:
	return "e2_section_volume"

func run() -> Dictionary:
	var chains := Ui.to_list(_fields["chains_m"].text)
	if chains.is_empty():
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "请输入断面桩号列表"}
	var fills := Ui.to_list(_fields["fill_areas_m2"].text)
	if fills.is_empty():
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "请输入各断面填方面积"}
	var p := {"chains_m": chains, "fill_areas_m2": fills}
	var cuts := Ui.to_list(_fields["cut_areas_m2"].text)
	if not cuts.is_empty():
		p["cut_areas_m2"] = cuts
	return Core.forward(p)

func set_inputs(inputs: Dictionary) -> void:
	for key: String in _fields:
		if inputs.has(key):
			_fields[key].text = str(inputs[key])
