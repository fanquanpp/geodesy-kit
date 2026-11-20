# scenes/calculators/cogo/b2_az_az.gd —— B2 方位-方位交会（与 B1 方位式前方交会同源算法）
extends "res://scenes/calculators/cogo/cogo_calc_base.gd"

const CORE := preload("res://core/cogo/intersections.gd")

func _init() -> void:
	_entry_id = "b2_az_az"
	_example_inputs = {
		"x_a_m": "1000", "y_a_m": "1000", "az1_deg": "30",
		"x_b_m": "2000", "y_b_m": "1200", "az2_deg": "309.3986",
	}

func get_title() -> String:
	return "方位-方位交会（B2）"

func get_description() -> String:
	return "两条已知方位角的直线求交（B2 编号入口；与前方交会·方位式同一算法）。方位角北起顺时针；两线平行/重合报错，交会角越界提示精度弱。"

func _build_rows() -> void:
	add_input_row("射线 A 起点 x（东，m）", "x_a_m", "1000")
	add_input_row("射线 A 起点 y（北，m）", "y_a_m", "1000")
	add_input_row("A 线方位角 α₁", "az1_deg", "30（或 30 00 00）")
	add_input_row("射线 B 起点 x（东，m）", "x_b_m", "2000")
	add_input_row("射线 B 起点 y（北，m）", "y_b_m", "1200")
	add_input_row("B 线方位角 α₂", "az2_deg", "309.3986（或 309 23 55）")

func run() -> Dictionary:
	var bad: Array = []
	var xa := num_field(_fields["x_a_m"], "A 起点 x", bad)
	var ya := num_field(_fields["y_a_m"], "A 起点 y", bad)
	var az1 := ang_field(_fields["az1_deg"], "A 线方位角", bad)
	var xb := num_field(_fields["x_b_m"], "B 起点 x", bad)
	var yb := num_field(_fields["y_b_m"], "B 起点 y", bad)
	var az2 := ang_field(_fields["az2_deg"], "B 线方位角", bad)
	if not bad.is_empty():
		return fail_input(bad)
	return CORE.b2_az_az({
		"x_a_m": xa, "y_a_m": ya, "az1_deg": az1,
		"x_b_m": xb, "y_b_m": yb, "az2_deg": az2,
	})
