# scenes/calculators/cogo/b8_point_line.gd —— B8 桩号与偏距（点线关系：投影/垂足/点线距）
extends "res://scenes/calculators/cogo/cogo_calc_base.gd"

const CORE := preload("res://core/cogo/line_tools.gd")

func _init() -> void:
	_entry_id = "b8_point_line"
	_example_inputs = {
		"x0_m": "1000", "y0_m": "1000", "az_deg": "30",
		"x_m": "2150", "y_m": "1950", "len_m": "2000",
	}

func get_title() -> String:
	return "桩号与偏距（点线关系）（B8）"

func get_description() -> String:
	return "由起点+方位角定义的射线：计算待查点的桩号（沿线投影，沿线方向为正）、偏距（右正左负）、垂足坐标与点线距。线长可选，桩号超出 [0, 线长] 时给出检核提示。"

func _build_rows() -> void:
	add_input_row("线起点 x（东，m）", "x0_m", "1000")
	add_input_row("线起点 y（北，m）", "y0_m", "1000")
	add_input_row("线方位角 α", "az_deg", "30（或 30 00 00）")
	add_input_row("待查点 x（东，m）", "x_m", "2150")
	add_input_row("待查点 y（北，m）", "y_m", "1950")
	add_input_row("线长（m，可空）", "len_m", "2000")

func run() -> Dictionary:
	var bad: Array = []
	var x0 := num_field(_fields["x0_m"], "线起点 x", bad, "x0_m")
	var y0 := num_field(_fields["y0_m"], "线起点 y", bad, "y0_m")
	var az := ang_field(_fields["az_deg"], "线方位角", bad, "az_deg")
	var x := num_field(_fields["x_m"], "待查点 x", bad, "x_m")
	var y := num_field(_fields["y_m"], "待查点 y", bad, "y_m")
	if not bad.is_empty():
		return fail_input(bad)
	var len_v := opt_num_field(_fields["len_m"], NAN, "线长", bad, "len_m")
	if not bad.is_empty():
		return fail_input(bad)
	var p := {
		"x0_m": x0, "y0_m": y0, "az_deg": az,
		"x_m": x, "y_m": y,
	}
	if not is_nan(len_v):
		p["len_m"] = len_v
	return CORE.point_line_rel(p)
