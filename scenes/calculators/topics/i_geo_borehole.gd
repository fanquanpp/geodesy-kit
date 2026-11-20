# scenes/calculators/topics/i_geo_borehole.gd —— I-地质 钻孔测斜三维坐标
extends "res://scenes/calculators/topics/topics_calc_base.gd"

const CORE := preload("res://core/topics/geology.gd")

func _init() -> void:
	_entry_id = "i_geo_borehole"
	_example_inputs = {
		"collar_x": "1000", "collar_y": "2000", "collar_z": "500",
		"stations": "50,2,45;100,4,50;150,6,55",
	}

func get_title() -> String:
	return "钻孔测斜三维坐标（I）"

func get_description() -> String:
	return "平均角法（平衡正切法）逐段推算钻孔三维轨迹：输入孔口坐标（x 东、y 北、z 向上）与测斜记录 测深,天顶角,方位角;…（天顶角自铅垂线起算 0-90°，方位角北起顺时针）。输出各测站坐标、孔底坐标与水平偏距。"

func _build_rows() -> void:
	add_input_row("孔口 X（m，东）", "collar_x", "1000")
	add_input_row("孔口 Y（m，北）", "collar_y", "2000")
	add_input_row("孔口 Z（m，向上）", "collar_z", "500")
	add_input_row("测斜记录（测深,天顶角,方位;…）", "stations", "50,2,45;100,4,50;150,6,55")

func run() -> Dictionary:
	var bad := []
	var cx := num_field(_fields["collar_x"], "孔口 X", bad)
	var cy := num_field(_fields["collar_y"], "孔口 Y", bad)
	var cz := num_field(_fields["collar_z"], "孔口 Z", bad)
	var stations := text_field(_fields["stations"], "测斜记录", bad)
	if not bad.is_empty():
		return fail_input(bad)
	return CORE.borehole({
		"collar_x": cx, "collar_y": cy, "collar_z": cz, "stations": stations,
	})
