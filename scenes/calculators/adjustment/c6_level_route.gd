# scenes/calculators/adjustment/c6_level_route.gd —— C6 单一水准路线计算器
extends "res://scenes/calculators/adjustment/adj_panel_base.gd"

const LV := preload("res://core/adjustment/leveling.gd")

func _build_fields() -> void:
	add_input_row("起点已知高程（m）", "h_start", "100.000")
	add_input_row("终点已知高程（m；闭合环留空）", "h_end", "110.000")
	add_input_row("闭合环？（附合留空，闭合环填 1）", "loop", "")
	_add_text_area("测段（每行：高差m 路线长km [测站数]；测站数可省略，全部给出时按站数定权）", "segs",
			"4.251 2.0\n3.008 1.0\n2.745 3.0")
	add_input_row("中间点名（可选，逗号分隔）", "point_names", "B1,B2", LineEdit.KEYBOARD_TYPE_DEFAULT)
	add_input_row("高差闭合差限差（±mm，可选自输）", "limit_mm", "8")

func run() -> Dictionary:
	var errors := PackedStringArray()
	var h_start := _num(_field_text("h_start"))
	if is_nan(h_start):
		errors.append("起点已知高程须为数字")
	var is_loop: bool = String(_field_text("loop")).strip_edges() == "1"
	var h_end := NAN
	if not is_loop:
		h_end = _num(_field_text("h_end"))
		if is_nan(h_end):
			errors.append("附合路线须填终点已知高程（闭合环请在\"闭合环\"填 1）")
	var segs := []
	var ns_count := 0
	var seg_rows := 0
	for row: Array in _parse_lines(_field_text("segs")):
		if row.size() < 2 or row.size() > 3:
			errors.append("测段每行应为：高差 路线长km [测站数]")
			continue
		seg_rows += 1
		var h := _num(row[0])
		var l_km := _num(row[1])
		if is_nan(h) or is_nan(l_km) or l_km <= 0.0:
			errors.append("测段含非法数值或路线长非正：%s" % " ".join(PackedStringArray([String(row[0]), String(row[1])])))
			continue
		var seg := {"h": h, "L_km": l_km}
		if row.size() == 3:
			var ns := _num(row[2])
			if is_nan(ns) or ns <= 0.0:
				errors.append("测段测站数须为正数：%s" % String(row[2]))
				continue
			seg["ns"] = ns
			ns_count += 1
		segs.append(seg)
	if segs.is_empty():
		errors.append("至少需要 1 个测段")
	if ns_count > 0 and ns_count != seg_rows:
		errors.append("按测站数定权需全部测段都给出测站数（当前 %d/%d 行）" % [ns_count, seg_rows])
	if errors.size() > 0:
		return _parse_fail(errors)
	var p := {"h_start": h_start, "segs": segs}
	if is_loop:
		p["loop"] = true
	else:
		p["h_end"] = h_end
	var names := PackedStringArray()
	var pn_text: String = String(_field_text("point_names")).replace("，", ",")
	for tok: String in pn_text.split(",", false):
		names.append(tok.strip_edges())
	if names.size() > 0:
		p["point_names"] = Array(names)
	var lim := _num(_field_text("limit_mm"))
	if is_finite(lim) and lim > 0.0:
		p["limit_mm"] = lim
	return LV.single_route(p)

func get_title() -> String:
	return "单一水准路线（C6）"

func get_description() -> String:
	return "附合/闭合单一水准路线：fh=Σh−(H终−H起)；限差判据通过后按路线长（v=−fh·L/ΣL，每公里等精度口径）或测站数（v=−fh·n/Σn，每站等精度口径）反号分配改正数，Σv=−fh 检核后推算各点高程。限差为自输口径（请按相应等级规范填入）。"

func get_entry_id() -> String:
	return "c6_level_route"
