# scenes/calculators/adjustment/c1_open_traverse.gd —— C1 支导线展点计算器
extends "res://scenes/calculators/adjustment/adj_panel_base.gd"

const TR := preload("res://core/adjustment/traverse.gd")

func _build_fields() -> void:
	add_input_row("起点 x（东, m）", "start_x", "5000.000")
	add_input_row("起点 y（北, m）", "start_y", "5000.000")
	add_input_row("起始方位角 α（°/′/″ 或十进制度）", "az_start", "95.5 或 95 30 00",
			LineEdit.KEYBOARD_TYPE_DEFAULT, "", "row", true)  # 角度档：度分秒含空格
	_add_text_area("转折角（左角，每行一个，十进制度）", "angles",
			"178.250556\n236.249583")
	_add_text_area("边长（每行一个，m，边数=角数+1）", "sides", "950.004\n1100.003\n200.002")
	add_input_row("点名（可选，逗号分隔）", "point_names", "P1,P2", LineEdit.KEYBOARD_TYPE_DEFAULT)

func _parse_dms(text: String) -> float:
	var v := GKAngles.parse_dms(text)
	if is_nan(v):
		return _num(text)
	return v

func run() -> Dictionary:
	var errors := PackedStringArray()
	var sx := _num(_field_text("start_x"))
	var sy := _num(_field_text("start_y"))
	var az := _parse_dms(_field_text("az_start"))
	var angles := _parse_lines(_field_text("angles"))
	var sides := _parse_lines(_field_text("sides"))
	if is_nan(sx) or is_nan(sy):
		errors.append("起点坐标须为数字")
	if is_nan(az):
		errors.append("起始方位角须为度分秒或十进制度")
	var ang_list := []
	for row: Array in angles:
		if row.size() != 1:
			errors.append("转折角每行应只有 1 个数值")
			continue
		var v := _num(row[0])
		if is_nan(v):
			errors.append("转折角含非法数值：%s" % String(row[0]))
		ang_list.append(v)
	var side_list := []
	for row2: Array in sides:
		if row2.size() != 1:
			errors.append("边长每行应只有 1 个数值")
			continue
		var v2 := _num(row2[0])
		if is_nan(v2):
			errors.append("边长含非法数值：%s" % String(row2[0]))
		side_list.append(v2)
	if errors.size() > 0:
		return _parse_fail(errors)
	var names := PackedStringArray()
	var pn_text: String = String(_field_text("point_names")).replace("，", ",")
	for tok: String in pn_text.split(",", false):
		names.append(tok.strip_edges())
	return TR.open_traverse({
		"start": [sx, sy], "az_start_deg": az,
		"angles_deg": ang_list, "sides_m": side_list,
		"point_names": Array(names),
	})

func get_title() -> String:
	return "支导线展点（C1）"

func get_description() -> String:
	return "由起点、起始方位角、左角串与边长串逐点推算坐标。支导线无检核条件，成果可靠性取决于观测质量，仅宜用于低精度放样/图根。"

func get_entry_id() -> String:
	return "c1_open_traverse"
