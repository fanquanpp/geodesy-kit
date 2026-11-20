# scenes/calculators/topics/i_gis_haversine.gd —— I-GIS 大圆距离（Haversine）
extends "res://scenes/calculators/topics/topics_calc_base.gd"

const CORE := preload("res://core/topics/gis_measure.gd")

func _init() -> void:
	_entry_id = "i_gis_haversine"
	_example_inputs = {
		"lat1": "39.9075276", "lon1": "116.3912757",
		"lat2": "31.1666667", "lon2": "121.4666667",
	}

func get_title() -> String:
	return "GIS 大圆距离（Haversine）（I）"

func get_description() -> String:
	return "球面 Haversine 大圆距离（平均半径 R₁=6371008.7714 m，可改）。输入两点经纬度（度，东经北纬为正）。米级精度需求请改用椭球大地线（M2 geodesic）。"

func _build_rows() -> void:
	add_input_row("点1 纬度（°）", "lat1", "39.9075276")
	add_input_row("点1 经度（°，东正）", "lon1", "116.3912757")
	add_input_row("点2 纬度（°）", "lat2", "31.1666667")
	add_input_row("点2 经度（°，东正）", "lon2", "121.4666667")
	add_input_row("球半径 R（m，可空）", "R_m", "")

func run() -> Dictionary:
	var bad := []
	var lat1 := num_field(_fields["lat1"], "点1 纬度", bad)
	var lon1 := num_field(_fields["lon1"], "点1 经度", bad)
	var lat2 := num_field(_fields["lat2"], "点2 纬度", bad)
	var lon2 := num_field(_fields["lon2"], "点2 经度", bad)
	var r := opt_num_field(_fields["R_m"], CORE.R_MEAN_M, "球半径", bad)
	if not bad.is_empty():
		return fail_input(bad)
	return CORE.haversine({"lat1": lat1, "lon1": lon1, "lat2": lat2, "lon2": lon2, "R_m": r})
