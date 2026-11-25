# scenes/calculators/cogo/b2_az_dist.gd —— B2 方位-距离交会（方位线与圆求交，双解取近/远端）
extends "res://scenes/calculators/cogo/cogo_calc_base.gd"

const CORE := preload("res://core/cogo/intersections.gd")

func _init() -> void:
	_entry_id = "b2_az_dist"
	_example_inputs = {
		"x_a_m": "0", "y_a_m": "0", "az1_deg": "90",
		"x_b_m": "500", "y_b_m": "400", "d_b_m": "500", "branch": "近端",
	}

func get_title() -> String:
	return "方位-距离交会（B2）"

func get_description() -> String:
	return "由 A 点沿方位角的射线与以 B 为圆心、D_B 为半径的圆求交（一元二次，双解取近端/远端）。解在射线反方向（t<0）判为无解。"

func _build_rows() -> void:
	add_input_row("A 点 x（东，m）", "x_a_m", "0")
	add_input_row("A 点 y（北，m）", "y_a_m", "0")
	add_input_row("A 线方位角 α₁（A→P）", "az1_deg", "90（或 90 00 00）")
	add_input_row("B 点 x（东，m）", "x_b_m", "500")
	add_input_row("B 点 y（北，m）", "y_b_m", "400")
	add_input_row("B 点距离 D_B（m）", "d_b_m", "500")
	add_input_row("解的分支", "branch", "近端（默认）/ 远端", LineEdit.KEYBOARD_TYPE_DEFAULT)

func run() -> Dictionary:
	var bad: Array = []
	var xa := num_field(_fields["x_a_m"], "A 点 x", bad, "x_a_m")
	var ya := num_field(_fields["y_a_m"], "A 点 y", bad, "y_a_m")
	var az1 := ang_field(_fields["az1_deg"], "A 线方位角", bad, "az1_deg")
	var xb := num_field(_fields["x_b_m"], "B 点 x", bad, "x_b_m")
	var yb := num_field(_fields["y_b_m"], "B 点 y", bad, "y_b_m")
	var db := num_field(_fields["d_b_m"], "B 点距离", bad, "d_b_m")
	if not bad.is_empty():
		return fail_input(bad)
	return CORE.b2_az_dist({
		"x_a_m": xa, "y_a_m": ya, "az1_deg": az1,
		"x_b_m": xb, "y_b_m": yb, "d_b_m": db,
		"branch": String(_fields["branch"].text).strip_edges(),
	})
