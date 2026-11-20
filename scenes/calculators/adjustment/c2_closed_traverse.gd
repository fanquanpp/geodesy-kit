# scenes/calculators/adjustment/c2_closed_traverse.gd —— C2 闭合导线平差计算器
extends "res://scenes/calculators/adjustment/c3_connect_traverse.gd"

# 面板与解析复用 C3（去掉终点坐标/终方位角输入），run 改走 closed_traverse。
# 注意：_build_fields 由本类覆写；c3 的终点字段不创建，run 不读取。

func _build_fields() -> void:
	_add_section("已知数据")
	add_input_row("起点 A x（东, m）", "start_x", "1000.000")
	add_input_row("起点 A y（北, m）", "start_y", "1000.000")
	add_input_row("起始边方位角 α（°/′/″ 或度）", "az_start", "80.537678")
	_add_section("观测数据（n 边形：左角 n 个、边长 n 条）")
	_add_text_area("转折角（左角，每行一个，度）", "angles",
			"108.924644\n71.075356\n108.924644\n71.075356")
	_add_text_area("边长（每行一个 m）", "sides",
			"304.138127\n304.138127\n304.138127\n304.138127")
	_add_section("限差（可选，留空不检核；规范限差表未核读，请自输并注明依据）")
	add_input_row("角度闭合差限差（±″）", "limit_fb_s", "60")
	add_input_row("相对闭合差限差（1/k 的 k）", "limit_rel_k", "2000")

func run() -> Dictionary:
	var errors := PackedStringArray()
	var sx := _num(_field_text("start_x"))
	var sy := _num(_field_text("start_y"))
	var az1 := _parse_dms(_field_text("az_start"))
	if is_nan(sx) or is_nan(sy):
		errors.append("起点坐标须为数字")
	if is_nan(az1):
		errors.append("起始方位角须为度分秒或十进制度")
	var ang_list := _lines_to_nums(_field_text("angles"), errors, "转折角")
	var side_list := _lines_to_nums(_field_text("sides"), errors, "边长")
	if ang_list.size() != side_list.size():
		errors.append("闭合导线转折角个数应等于边长个数（n 边形 n 角 n 边）")
	if errors.size() > 0:
		return _parse_fail(errors)
	var p := {
		"start": [sx, sy], "az_start_deg": az1,
		"angles_deg": ang_list, "sides_m": side_list,
		"point_names": _inter_names(ang_list.size() - 1),
	}
	var lim_fb: Variant = _opt_num(_field_text("limit_fb_s"))
	if lim_fb != null:
		p["limit_fb_s"] = lim_fb
	var lim_rel: Variant = _opt_num(_field_text("limit_rel_k"))
	if lim_rel != null:
		p["limit_rel_k"] = lim_rel
	return TR.closed_traverse(p)

func get_title() -> String:
	return "闭合导线平差（C2）"

func get_description() -> String:
	return "闭合环导线：角度闭合差（推算终边方位应回到起始方位）反号均分，坐标闭合差按边长比例反号分配（Bowditch，近似平差）。"

func get_entry_id() -> String:
	return "c2_closed_traverse"
