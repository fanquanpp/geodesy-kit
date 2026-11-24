# scenes/calculators/cogo/b1_side.gd —— B1 侧方交会（A 点测 β_A，P 点测 γ）
extends "res://scenes/calculators/cogo/cogo_calc_base.gd"

const CORE := preload("res://core/cogo/intersections.gd")

func _init() -> void:
	_entry_id = "b1_side"
	_example_inputs = {
		"x_a_m": "1000", "y_a_m": "1000",
		"x_b_m": "2000", "y_b_m": "1200",
		"beta_a_deg": "48.690068", "gamma_deg": "80.601439", "side": "左",
	}

func get_title() -> String:
	return "侧方交会（B1）"

func get_description() -> String:
	return "在已知点 A 观测 β_A=∠BAP、在待定点 P 观测 γ=∠APB（正值），由内角和推 B 点内角后正弦定理解三角形。交点默认位于 A→B 左侧。"

func _build_rows() -> void:
	add_input_row("已知点 A x（东，m）", "x_a_m", "1000")
	add_input_row("已知点 A y（北，m）", "y_a_m", "1000")
	add_input_row("已知点 B x（东，m）", "x_b_m", "2000")
	add_input_row("已知点 B y（北，m）", "y_b_m", "1200")
	add_input_row("A 点观测角 β_A = ∠BAP", "beta_a_deg", "48.690068（或 48 41 24）")
	add_input_row("P 点观测角 γ = ∠APB", "gamma_deg", "80.601439（或 80 36 05）")
	add_input_row("交点侧别（P 在 AB 的）", "side", "左（默认）/ 右", LineEdit.KEYBOARD_TYPE_DEFAULT)

func run() -> Dictionary:
	var bad: Array = []
	var xa := num_field(_fields["x_a_m"], "已知点 A x", bad)
	var ya := num_field(_fields["y_a_m"], "已知点 A y", bad)
	var xb := num_field(_fields["x_b_m"], "已知点 B x", bad)
	var yb := num_field(_fields["y_b_m"], "已知点 B y", bad)
	var ba := ang_field(_fields["beta_a_deg"], "A 点观测角 β_A", bad)
	var ga := ang_field(_fields["gamma_deg"], "P 点观测角 γ", bad)
	if not bad.is_empty():
		return fail_input(bad)
	var side := side_field(_fields["side"], -1)
	if side == 0:
		bad.append("「交点侧别」只支持 左/右")
		return fail_input(bad)
	return CORE.b1_side({
		"x_a_m": xa, "y_a_m": ya, "x_b_m": xb, "y_b_m": yb,
		"beta_a_deg": ba, "gamma_deg": ga, "side": side,
	})
