# scenes/calculators/route/e4_dist_slope.gd —— E4 平距/空间距离/坡度计算器
extends "res://scenes/widgets/calculator_base.gd"

const Core := preload("res://core/earthwork/dist_slope.gd")
const Ui := preload("res://scenes/calculators/route/ui_common.gd")

func _ready() -> void:
	super._ready()
	add_input_row("高差 Δh (m)", "dh_m", "四量给二，如 30（下坡负号）")
	add_input_row("平距 (m)", "d_horiz_m", "如 500")
	add_input_row("空间距离/斜距 (m)", "d_slope_m", "可选")
	add_input_row("坡度 (%)", "slope_pct", "可选，如 6")
	add_input_row("坡度角 (°)", "slope_deg", "可选，与坡度%二选一")
	set_inputs(_example_inputs)

func get_title() -> String:
	return "平距/空间距离/坡度（E4）"

func get_description() -> String:
	return "斜距²=平距²+高差²；i=Δh/平距；四量（高差/平距/斜距/坡度）给两个独立量即可互算"

func get_entry_id() -> String:
	return "e4_dist_slope"

func run() -> Dictionary:
	var p := {}
	for key in ["dh_m", "d_horiz_m", "d_slope_m", "slope_pct", "slope_deg"]:
		var f := Ui.to_f(_fields[key].text)
		if not is_nan(f):
			p[key] = f
	return Core.forward(p)

func set_inputs(inputs: Dictionary) -> void:
	for key: String in _fields:
		if inputs.has(key):
			_fields[key].text = str(inputs[key])
