# scenes/calculators/cogo/a1_fwd_3d.gd —— 三维坐标正算（斜距/竖直角/仪高/棱镜高）
extends "res://scenes/calculators/cogo/cogo_calc_base.gd"

const CORE := preload("res://core/cogo/cogo.gd")

# 距离类型选项（OptionButton，杜绝自由文本输错；值与 core.forward_3d 契约一致）
const DIST_MODES := [["斜距", "斜距"], ["平距", "平距"]]

var _dist_mode_opt: OptionButton

func _init() -> void:
	_entry_id = "a1_fwd_3d"
	_example_inputs = {
		"x0_m": "1000", "y0_m": "1000", "h0_m": "100",
		"az_deg": "30", "dist_m": "500", "v_deg": "10",
		"hi_m": "1.5", "ht_m": "1.8", "dist_mode": "斜距",
	}

func get_title() -> String:
	return "三维坐标正算（全站仪）（A1）"

func get_description() -> String:
	return "由测站三维坐标、方位角、斜距（或平距）、竖直角与仪高/棱镜高推算待定点三维坐标。竖直角仰角为正；可输 12.5 或 12 30 00。"

func _build_rows() -> void:
	add_input_row("测站 x（东，m）", "x0_m", "1000")
	add_input_row("测站 y（北，m）", "y0_m", "1000")
	add_input_row("测站高程 H₀（m）", "h0_m", "100")
	add_input_row("坐标方位角 α", "az_deg", "30（或 30 00 00）")
	add_input_row("距离（m）", "dist_m", "500")
	add_input_row("竖直角 v（仰角+）", "v_deg", "10（或 10 00 00）")
	add_input_row("仪器高 i（m）", "hi_m", "1.5")
	add_input_row("棱镜高 t（m）", "ht_m", "1.8")
	_add_dist_mode_row()

## 距离类型下拉（OptionButton 惯例同 bursa_calc._add_option_row；行高 96 触控目标）
func _add_dist_mode_row() -> void:
	var row := HBoxContainer.new()
	var lab := Label.new()
	lab.text = "距离类型"
	lab.custom_minimum_size = Vector2(180, 0)
	row.add_child(lab)
	_dist_mode_opt = OptionButton.new()
	_dist_mode_opt.custom_minimum_size = Vector2(0, 96)
	_dist_mode_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in DIST_MODES.size():
		_dist_mode_opt.add_item(String(DIST_MODES[i][1]))
		_dist_mode_opt.set_item_metadata(i, String(DIST_MODES[i][0]))
	_dist_mode_opt.select(0)
	row.add_child(_dist_mode_opt)
	_inputs_root.add_child(row)

func _dist_mode() -> String:
	var ob := _dist_mode_opt
	return String(ob.get_item_metadata(ob.selected)) if ob.selected >= 0 else "斜距"

func run() -> Dictionary:
	var bad: Array = []
	var x0 := num_field(_fields["x0_m"], "测站 x", bad)
	var y0 := num_field(_fields["y0_m"], "测站 y", bad)
	var h0 := num_field(_fields["h0_m"], "测站高程", bad)
	var az := ang_field(_fields["az_deg"], "坐标方位角", bad)
	var dist := num_field(_fields["dist_m"], "距离", bad)
	var v := ang_field(_fields["v_deg"], "竖直角", bad)
	var hi := num_field(_fields["hi_m"], "仪器高", bad)
	var ht := num_field(_fields["ht_m"], "棱镜高", bad)
	if not bad.is_empty():
		return fail_input(bad)
	return CORE.forward_3d({
		"x0_m": x0, "y0_m": y0, "h0_m": h0,
		"az_deg": az, "dist_m": dist, "v_deg": v,
		"hi_m": hi, "ht_m": ht, "dist_mode": _dist_mode(),
	})
