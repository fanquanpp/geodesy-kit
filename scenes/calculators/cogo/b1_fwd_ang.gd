# scenes/calculators/cogo/b1_fwd_ang.gd —— B1 前方交会（角度式：在 A、B 上测水平角）
extends "res://scenes/calculators/cogo/cogo_calc_base.gd"

const CORE := preload("res://core/cogo/intersections.gd")

func _init() -> void:
	_entry_id = "b1_fwd_ang"
	_example_inputs = {
		"x_a_m": "1000", "y_a_m": "1000",
		"x_b_m": "2000", "y_b_m": "1200",
		"beta1_deg": "48.690068", "beta2_deg": "50.708494", "side": "左",
	}

func get_title() -> String:
	return "前方交会（角度式）（B1）"

func get_description() -> String:
	return "在两已知点 A、B 上观测水平角 β₁=∠BAP、β₂=∠ABP（三角形内角正值），求交定点 P。交点默认位于 A→B 左侧；角度可输 48.69 或 48 41 24。"

func _build_rows() -> void:
	add_input_row("已知点 A x（东，m）", "x_a_m", "1000")
	add_input_row("已知点 A y（北，m）", "y_a_m", "1000")
	add_input_row("已知点 B x（东，m）", "x_b_m", "2000")
	add_input_row("已知点 B y（北，m）", "y_b_m", "1200")
	add_input_row("A 点角 β₁ = ∠BAP", "beta1_deg", "48.690068（或 48 41 24）")
	add_input_row("B 点角 β₂ = ∠ABP", "beta2_deg", "50.708494（或 50 42 31）")
	add_input_row("交点侧别（P 在 AB 的）", "side", "左（默认）/ 右", LineEdit.KEYBOARD_TYPE_DEFAULT)

func run() -> Dictionary:
	var bad: Array = []
	var xa := num_field(_fields["x_a_m"], "已知点 A x", bad)
	var ya := num_field(_fields["y_a_m"], "已知点 A y", bad)
	var xb := num_field(_fields["x_b_m"], "已知点 B x", bad)
	var yb := num_field(_fields["y_b_m"], "已知点 B y", bad)
	var b1 := ang_field(_fields["beta1_deg"], "A 点角 β₁", bad)
	var b2 := ang_field(_fields["beta2_deg"], "B 点角 β₂", bad)
	if not bad.is_empty():
		return fail_input(bad)
	var side := side_field(_fields["side"], -1)
	if side == 0:
		bad.append("「交点侧别」只支持 左/右")
		return fail_input(bad)
	return CORE.b1_angles({
		"x_a_m": xa, "y_a_m": ya, "x_b_m": xb, "y_b_m": yb,
		"beta1_deg": b1, "beta2_deg": b2, "side": side,
	})
