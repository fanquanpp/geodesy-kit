# scenes/calculators/cogo/b1_fwd_az.gd —— B1 前方交会（方位式：两已知点各测一条方位线）
extends "res://scenes/calculators/cogo/cogo_calc_base.gd"

const CORE := preload("res://core/cogo/intersections.gd")

func _init() -> void:
	_entry_id = "b1_fwd_az"
	_example_inputs = {
		"x_a_m": "1000", "y_a_m": "1000", "az1_deg": "30",
		"x_b_m": "2000", "y_b_m": "1200", "az2_deg": "309.3986",
	}

func get_title() -> String:
	return "前方交会（方位式）（B1）"

func get_description() -> String:
	return "由两个已知点分别向待定点观测坐标方位角，两方位线求交定 P。方位角北起顺时针（可输 309.3986 或 309 23 55）；交会角 <15° 时提示精度弱。"

func _build_rows() -> void:
	add_input_row("已知点 A x（东，m）", "x_a_m", "1000")
	add_input_row("已知点 A y（北，m）", "y_a_m", "1000")
	add_input_row("A 点方位角 α₁（A→P）", "az1_deg", "30（或 30 00 00）")
	add_input_row("已知点 B x（东，m）", "x_b_m", "2000")
	add_input_row("已知点 B y（北，m）", "y_b_m", "1200")
	add_input_row("B 点方位角 α₂（B→P）", "az2_deg", "309.3986（或 309 23 55）")

func run() -> Dictionary:
	var bad: Array = []
	var xa := num_field(_fields["x_a_m"], "已知点 A x", bad)
	var ya := num_field(_fields["y_a_m"], "已知点 A y", bad)
	var az1 := ang_field(_fields["az1_deg"], "A 点方位角", bad)
	var xb := num_field(_fields["x_b_m"], "已知点 B x", bad)
	var yb := num_field(_fields["y_b_m"], "已知点 B y", bad)
	var az2 := ang_field(_fields["az2_deg"], "B 点方位角", bad)
	if not bad.is_empty():
		return fail_input(bad)
	return CORE.b1_azimuth({
		"x_a_m": xa, "y_a_m": ya, "az1_deg": az1,
		"x_b_m": xb, "y_b_m": yb, "az2_deg": az2,
	})
