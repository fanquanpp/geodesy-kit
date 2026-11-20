# scenes/calculators/route/b4_spiral.gd —— B4 缓和曲线（回旋线）坐标计算器
extends "res://scenes/widgets/calculator_base.gd"

const Core := preload("res://core/route/spiral.gd")
const Ui := preload("res://scenes/calculators/route/ui_common.gd")

func _ready() -> void:
	super._ready()
	add_input_row("圆半径 R (m)", "r_m", "如 500")
	add_input_row("缓和曲线全长 l0 (m)", "l0_m", "如 60")
	add_input_row("查询弧长 l (m)", "l_m", "0 ≤ l ≤ l0，如 60")
	add_input_row("转向 dir (+1右/-1左)", "dir", "默认 +1")
	add_input_row("起点 X 东 (m)", "x_m", "可选，全局坐标归化")
	add_input_row("起点 Y 北 (m)", "y_m", "可选")
	add_input_row("起点切线方位 (°)", "bearing_deg", "可选，如 30")
	set_inputs(_example_inputs)

func get_title() -> String:
	return "缓和曲线坐标（B4）"

func get_description() -> String:
	return "回旋线任意弧长切线坐标（布告式级数公式链 + Fresnel 数值积分双路径互检）与切线角，可选全局归化"

func get_entry_id() -> String:
	return "b4_spiral"

func run() -> Dictionary:
	var p := {}
	var r := Ui.to_f(_fields["r_m"].text)
	if not is_nan(r):
		p["r_m"] = r
	var l0 := Ui.to_f(_fields["l0_m"].text)
	if not is_nan(l0):
		p["l0_m"] = l0
	var l := Ui.to_f(_fields["l_m"].text)
	if not is_nan(l):
		p["l_m"] = l
	var d := Ui.to_f(_fields["dir"].text)
	if not is_nan(d):
		p["dir"] = int(d) if absf(d) >= 1.0 else (1 if d >= 0.0 else -1)
	var x := Ui.to_f(_fields["x_m"].text)
	var y := Ui.to_f(_fields["y_m"].text)
	var az := Ui.to_f(_fields["bearing_deg"].text)
	if not is_nan(x) and not is_nan(y) and not is_nan(az):
		p["start"] = {"x_m": x, "y_m": y, "bearing_deg": az}
	return Core.coords(p)

func set_inputs(inputs: Dictionary) -> void:
	for key: String in _fields:
		if inputs.has(key):
			_fields[key].text = str(inputs[key])
