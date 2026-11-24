# scenes/calculators/route/d3_vertical_curve.gd —— D3 竖曲线计算器
extends "res://scenes/widgets/calculator_base.gd"

const Core := preload("res://core/route/vertical_curve.gd")
const Ui := preload("res://scenes/calculators/route/ui_common.gd")

func _ready() -> void:
	super._ready()
	add_input_row("坡度 g1（%）", "g1_pct", "如 3（下坡用负号）")
	add_input_row("坡度 g2（%）", "g2_pct", "如 -2")
	add_input_row("竖曲线长 L（m）", "l_m", "如 400")
	add_input_row("变坡点桩号 PVI（m）", "pvi_chain_m", "如 1000")
	add_input_row("变坡点高程（m）", "pvi_elev_m", "如 100")
	add_input_row("查询桩号（m）", "stakes_m", "多个用空格/逗号分隔，如 900 1000", LineEdit.KEYBOARD_TYPE_DEFAULT)
	set_inputs(_example_inputs)

func get_title() -> String:
	return "竖曲线高程（D3）"

func get_description() -> String:
	return "对称二次抛物线竖曲线：BVC/EVC 桩号高程、中点、外距 E（凸负凹正）、任意桩号设计高程"

func get_entry_id() -> String:
	return "d3_vertical_curve"

func run() -> Dictionary:
	var p := {}
	var g1 := Ui.to_f(_fields["g1_pct"].text)
	var g2 := Ui.to_f(_fields["g2_pct"].text)
	var l := Ui.to_f(_fields["l_m"].text)
	var pc := Ui.to_f(_fields["pvi_chain_m"].text)
	var pe := Ui.to_f(_fields["pvi_elev_m"].text)
	if not is_nan(g1):
		p["g1_pct"] = g1
	if not is_nan(g2):
		p["g2_pct"] = g2
	if not is_nan(l):
		p["l_m"] = l
	if not is_nan(pc):
		p["pvi_chain_m"] = pc
	if not is_nan(pe):
		p["pvi_elev_m"] = pe
	var stakes := Ui.to_list(_fields["stakes_m"].text)
	if not stakes.is_empty():
		p["stakes_m"] = stakes
	return Core.forward(p)

func set_inputs(inputs: Dictionary) -> void:
	super.set_inputs(inputs)
	for key: String in _fields:
		if inputs.has(key):
			_fields[key].text = str(inputs[key])
