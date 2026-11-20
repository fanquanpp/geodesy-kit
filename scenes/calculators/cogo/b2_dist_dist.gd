# scenes/calculators/cogo/b2_dist_dist.gd —— B2 距离-距离交会（两圆求交，双解判别+指定侧）
extends "res://scenes/calculators/cogo/cogo_calc_base.gd"

const CORE := preload("res://core/cogo/intersections.gd")

func _init() -> void:
	_entry_id = "b2_dist_dist"
	_example_inputs = {
		"x_a_m": "1000", "y_a_m": "1000", "d_a_m": "700",
		"x_b_m": "1800", "y_b_m": "1050", "d_b_m": "600", "side": "右",
	}

func get_title() -> String:
	return "距离-距离交会（B2）"

func get_description() -> String:
	return "以两已知点为圆心、观测距离为半径作圆求交。恒有双解（相切退化为一解），按侧别参数取 A→B 右侧（+，默认）或左侧（−）；另一解输出在 alt_x/alt_y。无实交点报中文错误。"

func _build_rows() -> void:
	add_input_row("已知点 A x（东，m）", "x_a_m", "1000")
	add_input_row("已知点 A y（北，m）", "y_a_m", "1000")
	add_input_row("A 点距离 D_A（m）", "d_a_m", "700")
	add_input_row("已知点 B x（东，m）", "x_b_m", "1800")
	add_input_row("已知点 B y（北，m）", "y_b_m", "1050")
	add_input_row("B 点距离 D_B（m）", "d_b_m", "600")
	add_input_row("交点侧别（P 在 A→B 的）", "side", "右（默认）/ 左")

func run() -> Dictionary:
	var bad: Array = []
	var xa := num_field(_fields["x_a_m"], "已知点 A x", bad)
	var ya := num_field(_fields["y_a_m"], "已知点 A y", bad)
	var da := num_field(_fields["d_a_m"], "A 点距离", bad)
	var xb := num_field(_fields["x_b_m"], "已知点 B x", bad)
	var yb := num_field(_fields["y_b_m"], "已知点 B y", bad)
	var db := num_field(_fields["d_b_m"], "B 点距离", bad)
	if not bad.is_empty():
		return fail_input(bad)
	var side := side_field(_fields["side"], 1)
	if side == 0:
		bad.append("「交点侧别」只支持 左/右")
		return fail_input(bad)
	return CORE.b2_dist_dist({
		"x_a_m": xa, "y_a_m": ya, "d_a_m": da,
		"x_b_m": xb, "y_b_m": yb, "d_b_m": db,
		"side": side,
	})
