# scenes/calculators/route/b3_curve_elements.gd —— B3 圆曲线要素计算器
extends "res://scenes/widgets/calculator_base.gd"

const Core := preload("res://core/route/curve_elements.gd")
const Ui := preload("res://scenes/calculators/route/ui_common.gd")

func _ready() -> void:
	super._ready()
	add_input_row("半径 R（m）", "r_m", "如 500")
	add_input_row("缓和曲线长 l0（m）", "l0_m", "纯圆曲线填 0")
	add_input_row("转角 α（°）", "alpha_deg", "如 30 或 25-30-00 度分秒")
	add_input_row("交点里程 JD（m）", "jd_chain_m", "可选，如 1234.5")
	set_inputs(_example_inputs)

func get_title() -> String:
	return "圆曲线要素（B3）"

func get_description() -> String:
	return "对称基本型（直—缓—圆—缓—直）曲线要素：β0/p/m/T/L/E/q 与主点里程；l0=0 时为纯圆曲线"

func get_entry_id() -> String:
	return "b3_curve_elements"

func run() -> Dictionary:
	var p := {}
	var r := Ui.to_f(_fields["r_m"].text)
	if not is_nan(r):
		p["r_m"] = r
	var l0 := Ui.to_f(_fields["l0_m"].text)
	if not is_nan(l0):
		p["l0_m"] = l0
	var a := Ui.to_f(_fields["alpha_deg"].text)
	if is_nan(a) and String(_fields["alpha_deg"].text).strip_edges() != "":
		a = GKAngles.parse_dms(_fields["alpha_deg"].text)  # 支持 25-30-00 度分秒
	if not is_nan(a):
		p["alpha_deg"] = a
	var jd := Ui.to_f(_fields["jd_chain_m"].text)
	if not is_nan(jd):
		p["jd_chain_m"] = jd
	return Core.forward(p)

func set_inputs(inputs: Dictionary) -> void:
	super.set_inputs(inputs)
	for key: String in _fields:
		if inputs.has(key):
			_fields[key].text = str(inputs[key])
