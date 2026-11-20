# scenes/calculators/astro/f6_time_sys.gd —— F6 时间系统换算
extends "res://scenes/calculators/astro/astro_calc_base.gd"

const CORE := preload("res://core/astro/time_sys.gd")

func _init() -> void:
	_entry_id = "f6_time_sys"
	_example_inputs = {
		"year": "2024", "month": "6", "day": "21",
		"hour": "0", "minute": "0", "second": "0",
	}

func get_title() -> String:
	return "时间系统换算（F6）"

func get_description() -> String:
	return "UTC 日历 → 儒略日 JD / 简化儒略日 MJD / 年积日 DOY / GPS 周·周内秒 / 累计闰秒与 GPS 时标度周内秒。GPS 周起点 1980-01-06 00:00 UTC（周号连续计数，1024 周滚转只是接收机 10bit 表示问题）；闰秒表取 IERS 公告（截至 2017-01-01 共 18 秒，其后未新增）。"

func _build_rows() -> void:
	add_input_row("年（1901-2099）", "year", "2024")
	add_input_row("月（1-12）", "month", "6")
	add_input_row("日（1-31）", "day", "21")
	add_input_row("时（UTC，0-23）", "hour", "0")
	add_input_row("分（0-59）", "minute", "0")
	add_input_row("秒（0-59.999）", "second", "0")

func run() -> Dictionary:
	var bad := []
	var year := int(num_field(_fields["year"], "年", bad))
	var month := int(num_field(_fields["month"], "月", bad))
	var day := int(num_field(_fields["day"], "日", bad))
	var hour := int(num_field(_fields["hour"], "时", bad))
	var minute := int(num_field(_fields["minute"], "分", bad))
	var second := num_field(_fields["second"], "秒", bad)
	if not bad.is_empty():
		return fail_input(bad)
	return CORE.convert({
		"year": year, "month": month, "day": day,
		"hour": hour, "minute": minute, "second": second,
	})
