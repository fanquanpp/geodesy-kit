# scenes/calculators/adjustment/c4_no_orient_traverse.gd —— C4 无定向导线计算器
extends "res://scenes/calculators/adjustment/c3_connect_traverse.gd"

func _build_fields() -> void:
	_add_section("已知数据（仅有起终点坐标，无已知方位角）")
	add_input_row("起点 A x（东, m）", "start_x", "2000.000")
	add_input_row("起点 A y（北, m）", "start_y", "3000.000")
	add_input_row("终点 B x（东, m）", "end_x", "3600.000")
	add_input_row("终点 B y（北, m）", "end_y", "2800.000")
	_add_section("观测数据")
	_add_text_area("转折角（左角，每行一个，度）", "angles",
			"237.094757\n200.224859")
	_add_text_area("边长（每行一个 m，边数=角数+1）", "sides",
			"640.312424\n632.455532\n640.312424")
	add_input_row("中间点名（可选，逗号分隔）", "point_names", "P1,P2")
	# C4 不需要限差字段（无方位检核，仅有坐标附合）

func run() -> Dictionary:
	var errors := PackedStringArray()
	var sx := _num(_field_text("start_x"))
	var sy := _num(_field_text("start_y"))
	var ex := _num(_field_text("end_x"))
	var ey := _num(_field_text("end_y"))
	if is_nan(sx) or is_nan(sy) or is_nan(ex) or is_nan(ey):
		errors.append("起终点坐标须为数字")
	var ang_list := _lines_to_nums(_field_text("angles"), errors, "转折角")
	var side_list := _lines_to_nums(_field_text("sides"), errors, "边长")
	if errors.size() > 0:
		return _parse_fail(errors)
	return TR.no_orient_traverse({
		"start": [sx, sy], "end": [ex, ey],
		"angles_deg": ang_list, "sides_m": side_list,
		"point_names": _inter_names(ang_list.size()),
	})

func get_title() -> String:
	return "无定向导线（C4）"

func get_description() -> String:
	return "两端点已知但无已知方位角：假定起始方向推算→按 AB 方向旋转全图定向→坐标闭合差按边长比例分配（近似平差）。结果含旋转角 δ。"

func get_entry_id() -> String:
	return "c4_no_orient_traverse"
