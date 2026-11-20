# scenes/calculators/topics/i_gis_buffer_idw_area.gd —— I-GIS 缓冲范围/IDW/球面面积（三模式）
extends "res://scenes/calculators/topics/topics_calc_base.gd"

const CORE := preload("res://core/topics/gis_measure.gd")

func _init() -> void:
	_entry_id = "i_gis_buffer_idw_area"
	_example_inputs = {
		"mode": "球面面积",
		"lat": "39.9", "lon": "116.4", "radius_m": "5000",
		"samples": "39.9,116.4,50;40.0,116.5,60;39.8,116.6,55",
		"target_lat": "39.95", "target_lon": "116.45", "power": "2",
		"ring": "39.90,116.39;39.95,116.50;40.00,116.50;39.95,116.39",
	}

func get_title() -> String:
	return "GIS 缓冲范围/IDW/球面面积（I）"

func get_description() -> String:
	return "模式一（缓冲范围）：中心点 + 半径 → 包含缓冲圆的经纬度范围框。模式二（IDW 插值）：样本 lat,lon,val;… + 目标点 → 反距离加权估值（幂 p 默认 2，精确命中直返）。模式三（球面面积）：顶点 lat,lon;…（≥3，逆/顺时针皆可）→ Chamberlain–Duquette 球面面积（m²/km²/公顷/亩）。"

func _build_rows() -> void:
	add_input_row("计算模式", "mode", "球面面积")
	add_input_row("中心纬度（°）", "lat", "39.9")
	add_input_row("中心经度（°，东正）", "lon", "116.4")
	add_input_row("缓冲半径（m）", "radius_m", "5000")
	add_input_row("样本（lat,lon,val;…）", "samples", "39.9,116.4,50;…")
	add_input_row("目标纬度（°）", "target_lat", "39.95")
	add_input_row("目标经度（°）", "target_lon", "116.45")
	add_input_row("IDW 幂 p", "power", "2")
	add_input_row("面积顶点（lat,lon;…）", "ring", "39.90,116.39;…")

func run() -> Dictionary:
	var bad := []
	var mode: String = _fields["mode"].text.strip_edges()
	if mode == "缓冲范围":
		var lat := num_field(_fields["lat"], "中心纬度", bad)
		var lon := num_field(_fields["lon"], "中心经度", bad)
		var radius := num_field(_fields["radius_m"], "缓冲半径", bad)
		if not bad.is_empty():
			return fail_input(bad)
		return CORE.buffer_bbox({"lat": lat, "lon": lon, "radius_m": radius})
	if mode == "IDW 插值":
		var samples := text_field(_fields["samples"], "样本", bad)
		var tlat := num_field(_fields["target_lat"], "目标纬度", bad)
		var tlon := num_field(_fields["target_lon"], "目标经度", bad)
		var pw := opt_num_field(_fields["power"], 2.0, "IDW 幂", bad)
		if not bad.is_empty():
			return fail_input(bad)
		return CORE.idw({"samples": samples, "target_lat": tlat, "target_lon": tlon, "power": pw})
	# 默认：球面面积
	var ring := text_field(_fields["ring"], "面积顶点", bad)
	if not bad.is_empty():
		return fail_input(bad)
	return CORE.spherical_area({"ring": ring})
