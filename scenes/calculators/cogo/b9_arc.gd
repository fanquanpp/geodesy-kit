# scenes/calculators/cogo/b9_arc.gd —— B9 圆弧要素反算（圆心+半径+起止方位）
extends "res://scenes/calculators/cogo/cogo_calc_base.gd"

const CORE := preload("res://core/cogo/circle_tools.gd")

func _init() -> void:
	_entry_id = "b9_arc"
	_example_inputs = {
		"cx_m": "0", "cy_m": "0", "r_m": "100",
		"az1_deg": "0", "az2_deg": "90", "dir": "顺时针",
	}

func get_title() -> String:
	return "圆弧要素反算（方位式）（B9）"

func get_description() -> String:
	return "由圆心、半径与起止方位角计算圆弧要素：圆心角、弧长、弦长、弓高、扇形/弓形面积。方向默认顺时针（方位系）；起止方位相同按全圆 360° 处理。"

func _build_rows() -> void:
	add_input_row("圆心 x（东，m）", "cx_m", "0")
	add_input_row("圆心 y（北，m）", "cy_m", "0")
	add_input_row("半径 R（m）", "r_m", "100")
	add_input_row("起始方位角 α₁", "az1_deg", "0（或 0 00 00）")
	add_input_row("终止方位角 α₂", "az2_deg", "90（或 90 00 00）")
	add_input_row("弧方向", "dir", "顺时针（默认）/ 逆时针", LineEdit.KEYBOARD_TYPE_DEFAULT)

func run() -> Dictionary:
	var bad: Array = []
	var cx := num_field(_fields["cx_m"], "圆心 x", bad)
	var cy := num_field(_fields["cy_m"], "圆心 y", bad)
	var r := num_field(_fields["r_m"], "半径", bad)
	var az1 := ang_field(_fields["az1_deg"], "起始方位角", bad)
	var az2 := ang_field(_fields["az2_deg"], "终止方位角", bad)
	if not bad.is_empty():
		return fail_input(bad)
	return CORE.arc_by_azimuth({
		"cx_m": cx, "cy_m": cy, "r_m": r,
		"az1_deg": az1, "az2_deg": az2,
		"dir": String(_fields["dir"].text).strip_edges(),
	})
