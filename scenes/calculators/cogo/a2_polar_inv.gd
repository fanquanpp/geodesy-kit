# scenes/calculators/cogo/a2_polar_inv.gd —— A2 坐标反算
extends "res://scenes/calculators/cogo/cogo_calc_base.gd"

const CORE := preload("res://core/cogo/cogo.gd")

func _init() -> void:
	_entry_id = "a2_polar_inv"
	_example_inputs = {"x0_m": "1000", "y0_m": "1000", "x_m": "1353.553390593", "y_m": "1353.553390593"}

func get_title() -> String:
	return "坐标反算（A2）"

func get_description() -> String:
	return "由两点坐标反算边长与坐标方位角（含反方位角）。约定：x=东、y=北，方位角北起顺时针；两点重合无解。"

func _build_rows() -> void:
	# P9.4 坐标输入形式：起点/待定点 xy 各成坐标对双列
	add_coord_pair_row("起点 x（东）", "x0_m", "起点 y（北）", "y0_m", "m", "m")
	add_coord_pair_row("待定点 x（东）", "x_m", "待定点 y（北）", "y_m", "m", "m")

func run() -> Dictionary:
	var bad: Array = []
	var x0 := num_field(_fields["x0_m"], "起点 x", bad)
	var y0 := num_field(_fields["y0_m"], "起点 y", bad)
	var x := num_field(_fields["x_m"], "待定点 x", bad)
	var y := num_field(_fields["y_m"], "待定点 y", bad)
	if not bad.is_empty():
		return fail_input(bad)
	return CORE.inverse({"x0_m": x0, "y0_m": y0, "x_m": x, "y_m": y})
