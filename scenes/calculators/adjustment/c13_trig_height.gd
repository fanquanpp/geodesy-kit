# scenes/calculators/adjustment/c13_trig_height.gd —— 三角高程计算器（单向/对向）
extends "res://scenes/calculators/adjustment/adj_panel_base.gd"

const LV := preload("res://core/adjustment/leveling.gd")

func _build_fields() -> void:
	_add_section("往测（A→B）")
	add_input_row("水平距离 D（m）", "d_m", "2000")
	add_input_row("竖直角 α（°/′/″ 或度，仰角正）", "v_angle", "2")
	add_input_row("仪器高 i（m）", "i_m", "1.5")
	add_input_row("目标高 v（m）", "v_m", "1.5")
	_add_section("返测（B→A，对向观测可选）")
	add_input_row("竖直角 α返（度，仰角正）", "v_angle_back", "-2")
	add_input_row("仪器高 i返（m）", "i_back", "1.5")
	add_input_row("目标高 v返（m）", "v_back", "1.5")
	_add_section("常数（可自定）")
	add_input_row("大气折光系数 k（默认 0.13）", "k", "0.13")
	add_input_row("地球曲率半径 R（m，默认 6371008.7714）", "r_m", "6371008.7714")

func _opt_num(text: String) -> Variant:
	var t := text.strip_edges()
	if t.is_empty():
		return null
	var v := _num(t)
	return null if is_nan(v) else v

func run() -> Dictionary:
	var errors := PackedStringArray()
	var d := _num(_field_text("d_m"))
	var alpha := GKAngles.parse_dms(_field_text("v_angle"))
	if is_nan(alpha):
		alpha = _num(_field_text("v_angle"))
	var i_h := _num(_field_text("i_m"))
	var v_h := _num(_field_text("v_m"))
	if is_nan(d) or d <= 0.0:
		errors.append("平距须为正数")
	if is_nan(alpha) or is_nan(i_h) or is_nan(v_h):
		errors.append("竖直角/仪器高/目标高须为数字")
	if errors.size() > 0:
		return _parse_fail(errors)
	var p := {
		"D_m": d, "v_angle_deg": alpha, "i_m": i_h, "v_m": v_h,
	}
	var k: Variant = _opt_num(_field_text("k"))
	if k != null:
		p["k"] = k
	var r: Variant = _opt_num(_field_text("r_m"))
	if r != null:
		p["R_m"] = r
	# 对向观测（三项都填才启用）
	var ab: Variant = _opt_num(_field_text("v_angle_back"))
	var ib: Variant = _opt_num(_field_text("i_back"))
	var vb: Variant = _opt_num(_field_text("v_back"))
	if ab != null and ib != null and vb != null:
		p["back"] = {"v_angle_deg": ab, "i_m": ib, "v_m": vb}
	return LV.trig_height(p)

func get_title() -> String:
	return "三角高程（单向/对向）（C13）"

func get_description() -> String:
	return "h = D·tanα + i − v + (1−k)·D²/(2R)；对向观测取均值时球气差自动抵消。k/R 可自定。M6-3 组成部分（单向近似平差口径，对向均值含折光改正）。"

func get_entry_id() -> String:
	return "c13_trig_height"
