# scenes/calculators/cogo/b9_circle_3p.gd —— B9 三点定圆
extends "res://scenes/calculators/cogo/cogo_calc_base.gd"

const CORE := preload("res://core/cogo/circle_tools.gd")

func _init() -> void:
	_entry_id = "b9_circle_3p"
	_example_inputs = {
		"x1_m": "100", "y1_m": "100",
		"x2_m": "500", "y2_m": "150",
		"x3_m": "300", "y3_m": "400",
	}

func get_title() -> String:
	return "三点定圆（B9）"

func get_description() -> String:
	return "由不共线三点求外接圆（圆心+半径），两弦垂直平分线联立求解，并输出三点到圆心距离互差检核。三点共线或重合报中文错误。"

func _build_rows() -> void:
	add_input_row("点 1 x（东，m）", "x1_m", "100")
	add_input_row("点 1 y（北，m）", "y1_m", "100")
	add_input_row("点 2 x（东，m）", "x2_m", "500")
	add_input_row("点 2 y（北，m）", "y2_m", "150")
	add_input_row("点 3 x（东，m）", "x3_m", "300")
	add_input_row("点 3 y（北，m）", "y3_m", "400")

func run() -> Dictionary:
	var bad: Array = []
	var x1 := num_field(_fields["x1_m"], "点 1 x", bad)
	var y1 := num_field(_fields["y1_m"], "点 1 y", bad)
	var x2 := num_field(_fields["x2_m"], "点 2 x", bad)
	var y2 := num_field(_fields["y2_m"], "点 2 y", bad)
	var x3 := num_field(_fields["x3_m"], "点 3 x", bad)
	var y3 := num_field(_fields["y3_m"], "点 3 y", bad)
	if not bad.is_empty():
		return fail_input(bad)
	return CORE.three_point_circle({
		"x1_m": x1, "y1_m": y1, "x2_m": x2, "y2_m": y2, "x3_m": x3, "y3_m": y3,
	})
