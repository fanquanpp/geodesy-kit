# scenes/calculators/cogo/b9_arc_3p.gd —— B9 圆弧要素反算（三点式：弧过 P₁→P₂→P₃）
extends "res://scenes/calculators/cogo/cogo_calc_base.gd"

const CORE := preload("res://core/cogo/circle_tools.gd")

func _init() -> void:
	_entry_id = "b9_arc_3p"
	_example_inputs = {
		"x1_m": "500", "y1_m": "700",
		"x2_m": "641.421356", "y2_m": "641.421356",
		"x3_m": "700", "y3_m": "500",
	}

func get_title() -> String:
	return "圆弧要素反算（三点式）（B9）"

func get_description() -> String:
	return "由弧上按行进顺序的三个点 P₁→P₂→P₃ 先定圆，再由圆心到三点方位判定弧方向（P₂ 所在侧），输出圆心角、弧长、弦长、弓高与扇形/弓形面积。"

func _build_rows() -> void:
	add_input_row("起点 P₁ x（东，m）", "x1_m", "500")
	add_input_row("起点 P₁ y（北，m）", "y1_m", "700")
	add_input_row("弧上点 P₂ x（东，m）", "x2_m", "641.421356")
	add_input_row("弧上点 P₂ y（北，m）", "y2_m", "641.421356")
	add_input_row("终点 P₃ x（东，m）", "x3_m", "700")
	add_input_row("终点 P₃ y（北，m）", "y3_m", "500")

func run() -> Dictionary:
	var bad: Array = []
	var x1 := num_field(_fields["x1_m"], "起点 P₁ x", bad, "x1_m")
	var y1 := num_field(_fields["y1_m"], "起点 P₁ y", bad, "y1_m")
	var x2 := num_field(_fields["x2_m"], "弧上点 P₂ x", bad, "x2_m")
	var y2 := num_field(_fields["y2_m"], "弧上点 P₂ y", bad, "y2_m")
	var x3 := num_field(_fields["x3_m"], "终点 P₃ x", bad, "x3_m")
	var y3 := num_field(_fields["y3_m"], "终点 P₃ y", bad, "y3_m")
	if not bad.is_empty():
		return fail_input(bad)
	return CORE.arc_by_points({
		"x1_m": x1, "y1_m": y1, "x2_m": x2, "y2_m": y2, "x3_m": x3, "y3_m": y3,
	})
