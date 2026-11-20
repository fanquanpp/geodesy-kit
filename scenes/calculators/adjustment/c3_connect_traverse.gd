# scenes/calculators/adjustment/c3_connect_traverse.gd —— C3 附合导线平差计算器（Bowditch 近似平差）
extends "res://scenes/calculators/adjustment/adj_panel_base.gd"

const TR := preload("res://core/adjustment/traverse.gd")

func _build_fields() -> void:
	_add_section("起终已知数据")
	add_input_row("起点 A x（东, m）", "start_x", "5000.000")
	add_input_row("起点 A y（北, m）", "start_y", "5000.000")
	add_input_row("终点 B x（东, m）", "end_x", "7143.2712")
	add_input_row("终点 B y（北, m）", "end_y", "4663.7980")
	add_input_row("起始边方位角 α起（°/′/″ 或度）", "az_start", "95.5")
	add_input_row("终止边方位角 α终（°/′/″ 或度）", "az_end", "150")
	_add_section("观测数据")
	_add_text_area("转折角（左角，每行一个，度）", "angles", "178.250556\n236.249583")
	_add_text_area("边长（每行一个 m，边数=角数+1）", "sides", "950.004\n1100.003\n200.002")
	_add_section("限差（可选，留空不检核；规范限差表未核读，请自输并注明依据）")
	add_input_row("角度闭合差限差（±″）", "limit_fb_s", "60")
	add_input_row("相对闭合差限差（1/k 的 k）", "limit_rel_k", "2000")

func _parse_dms(text: String) -> float:
	var v := GKAngles.parse_dms(text)
	if is_nan(v):
		return _num(text)
	return v

func _lines_to_nums(text: String, errors: PackedStringArray, what: String) -> Array:
	var out := []
	for row: Array in _parse_lines(text):
		if row.size() != 1:
			errors.append("%s 每行应只有 1 个数值" % what)
			continue
		var v := _num(row[0])
		if is_nan(v):
			errors.append("%s 含非法数值：%s" % [what, String(row[0])])
		out.append(v)
	return out

func _opt_num(text: String) -> Variant:
	var t := text.strip_edges()
	if t.is_empty():
		return null
	var v := _num(t)
	return null if is_nan(v) else v

func run() -> Dictionary:
	var errors := PackedStringArray()
	var sx := _num(_field_text("start_x"))
	var sy := _num(_field_text("start_y"))
	var ex := _num(_field_text("end_x"))
	var ey := _num(_field_text("end_y"))
	var az1 := _parse_dms(_field_text("az_start"))
	var az2 := _parse_dms(_field_text("az_end"))
	if is_nan(sx) or is_nan(sy) or is_nan(ex) or is_nan(ey):
		errors.append("起终点坐标须为数字")
	if is_nan(az1) or is_nan(az2):
		errors.append("起/终方位角须为度分秒或十进制度")
	var ang_list := _lines_to_nums(_field_text("angles"), errors, "转折角")
	var side_list := _lines_to_nums(_field_text("sides"), errors, "边长")
	if errors.size() > 0:
		return _parse_fail(errors)
	var p := {
		"start": [sx, sy], "end": [ex, ey],
		"az_start_deg": az1, "az_end_deg": az2,
		"angles_deg": ang_list, "sides_m": side_list,
		"point_names": _inter_names(ang_list.size()),
	}
	var lim_fb: Variant = _opt_num(_field_text("limit_fb_s"))
	if lim_fb != null:
		p["limit_fb_s"] = lim_fb
	var lim_rel: Variant = _opt_num(_field_text("limit_rel_k"))
	if lim_rel != null:
		p["limit_rel_k"] = lim_rel
	return TR.connect_traverse(p)

func _inter_names(n_ang: int) -> Array:
	var out := []
	if _fields.has("point_names"):
		var t: LineEdit = _fields["point_names"]
		var txt: String = String(t.text).replace("，", ",")
		for tok: String in txt.split(",", false):
			out.append(tok.strip_edges())
	return out

func get_title() -> String:
	return "附合导线平差（C3）"

func get_description() -> String:
	return "两端附合于已知点与已知方位：角度闭合差反号均分→推算方位角→坐标闭合差按边长比例反号分配（Bowditch，近似平差）。限差留空则不检核。"

func get_entry_id() -> String:
	return "c3_connect_traverse"
