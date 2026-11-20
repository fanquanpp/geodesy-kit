# scenes/calculators/cogo/a2_inv_3d.gd —— 三维坐标反算（平距/斜距/竖直角/方位角）
extends "res://scenes/calculators/cogo/cogo_calc_base.gd"

const CORE := preload("res://core/cogo/cogo.gd")

func _init() -> void:
	_entry_id = "a2_inv_3d"
	_example_inputs = {
		"x0_m": "1000", "y0_m": "1000", "h0_m": "100",
		"x_m": "1246.2019", "y_m": "1426.4058", "h_m": "186.5241",
		"hi_m": "1.5", "ht_m": "1.8",
	}

func get_title() -> String:
	return "三维坐标反算（A2）"

func get_description() -> String:
	return "由测站与目标点三维坐标反算平距、斜距、竖直角（指向棱镜中心，仰角为正）与方位角。约定：x=东、y=北，方位角北起顺时针。"

func _build_rows() -> void:
	add_input_row("测站 x（东，m）", "x0_m", "1000")
	add_input_row("测站 y（北，m）", "y0_m", "1000")
	add_input_row("测站高程 H₀（m）", "h0_m", "100")
	add_input_row("目标点 x（东，m）", "x_m", "1246.2019")
	add_input_row("目标点 y（北，m）", "y_m", "1426.4058")
	add_input_row("目标点高程 H（m）", "h_m", "186.5241")
	add_input_row("仪器高 i（m）", "hi_m", "1.5")
	add_input_row("棱镜高 t（m）", "ht_m", "1.8")

func run() -> Dictionary:
	var bad: Array = []
	var x0 := num_field(_fields["x0_m"], "测站 x", bad)
	var y0 := num_field(_fields["y0_m"], "测站 y", bad)
	var h0 := num_field(_fields["h0_m"], "测站高程", bad)
	var x := num_field(_fields["x_m"], "目标点 x", bad)
	var y := num_field(_fields["y_m"], "目标点 y", bad)
	var h := num_field(_fields["h_m"], "目标点高程", bad)
	var hi := num_field(_fields["hi_m"], "仪器高", bad)
	var ht := num_field(_fields["ht_m"], "棱镜高", bad)
	if not bad.is_empty():
		return fail_input(bad)
	return CORE.inverse_3d({
		"x0_m": x0, "y0_m": y0, "h0_m": h0,
		"x_m": x, "y_m": y, "h_m": h,
		"hi_m": hi, "ht_m": ht,
	})
