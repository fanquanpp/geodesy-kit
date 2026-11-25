# scenes/calculators/cogo/a1_polar_fwd.gd —— A1 坐标正算（极坐标法）
extends "res://scenes/calculators/cogo/cogo_calc_base.gd"

const CORE := preload("res://core/cogo/cogo.gd")

func _init() -> void:
	_entry_id = "a1_polar_fwd"
	_example_inputs = {"x0_m": "1000", "y0_m": "1000", "az_deg": "45", "dist_m": "500"}

func get_title() -> String:
	return "坐标正算（极坐标法）（A1）"

func get_description() -> String:
	return "由已知点坐标、坐标方位角与水平距离推算待定点坐标。约定：x=东（横）、y=北（纵），方位角北起顺时针；方位角可输 45.5 或 45 30 00。"

func _build_rows() -> void:
	# P9.4 坐标输入形式：起点 x|y 坐标对双列（stacked 标签在上 + 单位后缀）
	add_coord_pair_row("起点 x（东）", "x0_m", "起点 y（北）", "y0_m", "m", "m")
	# 角度档 keyboard_angle=true：az 可输 45 30 00 度分秒（键盘须含空格 → DEFAULT）
	add_input_row("坐标方位角 α", "az_deg", "45（或 45 30 00）",
			LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL, "°", "row", true)
	add_input_row("水平距离 D", "dist_m", "500", LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL, "m")

func run() -> Dictionary:
	var bad: Array = []
	var x0 := num_field(_fields["x0_m"], "起点 x", bad, "x0_m")
	var y0 := num_field(_fields["y0_m"], "起点 y", bad, "y0_m")
	var az := ang_field(_fields["az_deg"], "坐标方位角", bad, "az_deg")
	var dist := num_field(_fields["dist_m"], "水平距离", bad, "dist_m")
	if not bad.is_empty():
		return fail_input(bad)
	return CORE.forward({"x0_m": x0, "y0_m": y0, "az_deg": az, "dist_m": dist})
