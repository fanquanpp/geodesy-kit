# scenes/calculators/astro/f4_sun_events.gd —— F4 日出日落/昼长（ha0 法）
extends "res://scenes/calculators/astro/astro_calc_base.gd"

const CORE := preload("res://core/astro/sun_events.gd")

func _init() -> void:
	_entry_id = "f4_sun_events"
	_example_inputs = {
		"year": "2024", "month": "6", "day": "21",
		"lat_deg": "39.9075", "lon_deg": "116.3913",
		"tz_hours": "8", "h0_deg": "-0.833",
	}

func get_title() -> String:
	return "日出日落/昼长（F4）"

func get_description() -> String:
	return "按 ha0 = arccos[cos90.833°/(cosφcosδ) − tanφtanδ] 求日出日落时角（含折光与太阳视半径综合地平高度 −0.833°，可改）。时区可选（东正西负），输出 UTC 与本地时刻。极昼/极夜给出判别提示。适用 1901-2099 年。"

func _build_rows() -> void:
	add_input_row("年（1901-2099）", "year", "2024")
	add_input_row("月（1-12）", "month", "6")
	add_input_row("日（1-31）", "day", "21")
	add_input_row("纬度（°，北正）", "lat_deg", "39.9075")
	add_input_row("经度（°，东正）", "lon_deg", "116.3913")
	add_input_row("时区（小时，东正）", "tz_hours", "8")
	add_input_row("地平高度阈值 h₀（°）", "h0_deg", "-0.833")

func run() -> Dictionary:
	var bad := []
	var year := int(num_field(_fields["year"], "年", bad))
	var month := int(num_field(_fields["month"], "月", bad))
	var day := int(num_field(_fields["day"], "日", bad))
	var lat := num_field(_fields["lat_deg"], "纬度", bad)
	var lon := num_field(_fields["lon_deg"], "经度", bad)
	var tz := num_field(_fields["tz_hours"], "时区", bad)
	var h0 := num_field(_fields["h0_deg"], "地平高度阈值", bad)
	if not bad.is_empty():
		return fail_input(bad)
	return CORE.sun_events({
		"year": year, "month": month, "day": day,
		"lat_deg": lat, "lon_deg": lon,
		"tz_hours": tz, "h0_deg": h0,
	})
