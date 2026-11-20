# scenes/calculators/astro/f3_solar_az.gd —— F3 太阳方位角/高度角（NOAA）
extends "res://scenes/calculators/astro/astro_calc_base.gd"

const CORE := preload("res://core/astro/solar.gd")

func _init() -> void:
	_entry_id = "f3_solar_az"
	_example_inputs = {
		"year": "2024", "month": "3", "day": "20", "hour": "12", "minute": "0", "second": "0",
		"lat_deg": "40.0", "lon_deg": "-105.25", "with_refraction": "否",
	}

func get_title() -> String:
	return "太阳方位角/高度角（F3）"

func get_description() -> String:
	return "NOAA 太阳位置算法（真北定向，UTC 输入）。方位角自真北起顺时针；输出几何天顶距（未加折光，可选折光改正后的视高度角作参考）。适用 1901-2099 年（NOAA 电子表格口径）。"

func _build_rows() -> void:
	add_input_row("年（1901-2099）", "year", "2024")
	add_input_row("月（1-12）", "month", "3")
	add_input_row("日（1-31）", "day", "20")
	add_input_row("时（UTC，0-23）", "hour", "12")
	add_input_row("分（0-59）", "minute", "0")
	add_input_row("秒（0-59.999）", "second", "0")
	add_input_row("纬度（°，北正）", "lat_deg", "40.0")
	add_input_row("经度（°，东正）", "lon_deg", "-105.25")
	add_input_row("含折光改正（是/否）", "with_refraction", "否")

func _yes_no(edit: LineEdit) -> bool:
	return edit.text.strip_edges().to_lower() in ["是", "y", "yes", "1", "true"]

func run() -> Dictionary:
	var bad := []
	var year := int(num_field(_fields["year"], "年", bad))
	var month := int(num_field(_fields["month"], "月", bad))
	var day := int(num_field(_fields["day"], "日", bad))
	var hour := int(num_field(_fields["hour"], "时", bad))
	var minute := int(num_field(_fields["minute"], "分", bad))
	var second := num_field(_fields["second"], "秒", bad)
	var lat := num_field(_fields["lat_deg"], "纬度", bad)
	var lon := num_field(_fields["lon_deg"], "经度", bad)
	if not bad.is_empty():
		return fail_input(bad)
	return CORE.solar_position({
		"year": year, "month": month, "day": day,
		"hour": hour, "minute": minute, "second": second,
		"lat_deg": lat, "lon_deg": lon,
		"with_refraction": _yes_no(_fields["with_refraction"]),
	})
