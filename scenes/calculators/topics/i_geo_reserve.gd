# scenes/calculators/topics/i_geo_reserve.gd —— I-地质 线储量/块段储量
extends "res://scenes/calculators/topics/topics_calc_base.gd"

const CORE := preload("res://core/topics/geology.gd")

func _init() -> void:
	_entry_id = "i_geo_reserve"
	_example_inputs = {
		"S1_m2": "500", "S2_m2": "400", "L_m": "100",
		"density_t_m3": "2.8", "grade_percent": "1.5",
	}

func get_title() -> String:
	return "线储量/块段储量（I）"

func get_description() -> String:
	return "只给断面面积 S₁ 与矿石体重 γ → 线储量 q = S₁·γ（t/m）与线金属量；再给相邻断面面积 S₂ 与断面间距 L → 块段储量（断面平均法）：V=(S₁+S₂)L/2，Q=V·γ，P=Q·品位。品位为百分比（%，可空默认 0）。"

func _build_rows() -> void:
	add_input_row("断面面积 S₁（m²）", "S1_m2", "500")
	add_input_row("相邻断面面积 S₂（m²，可空）", "S2_m2", "400")
	add_input_row("断面间距 L（m，可空）", "L_m", "100")
	add_input_row("矿石体重 γ（t/m³）", "density_t_m3", "2.8")
	add_input_row("品位（%，可空）", "grade_percent", "1.5")

func run() -> Dictionary:
	var bad := []
	var p := {
		"S1_m2": num_field(_fields["S1_m2"], "断面面积 S₁", bad),
		"density_t_m3": num_field(_fields["density_t_m3"], "矿石体重", bad),
	}
	if not bad.is_empty():
		return fail_input(bad)
	var s2 := opt_num_field(_fields["S2_m2"], NAN, "相邻断面面积 S₂", bad)
	var len_m := opt_num_field(_fields["L_m"], NAN, "断面间距", bad)
	var grade := opt_num_field(_fields["grade_percent"], 0.0, "品位", bad)
	if not bad.is_empty():
		return fail_input(bad)
	if is_finite(s2) or is_finite(len_m):
		# 两者给其一即走块段路径（core 校验其完整性）
		p["S2_m2"] = s2
		p["L_m"] = len_m
	if is_finite(grade) and grade != 0.0:
		p["grade_percent"] = grade
	return CORE.reserve(p)
