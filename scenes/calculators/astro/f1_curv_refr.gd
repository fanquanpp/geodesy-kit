# scenes/calculators/astro/f1_curv_refr.gd —— F1 球气差/三角高程（双模式）
extends "res://scenes/calculators/astro/astro_calc_base.gd"

const CORE := preload("res://core/astro/curvature_refraction.gd")

func _init() -> void:
	_entry_id = "f1_curv_refr"
	_example_inputs = {
		"D_m": "1000", "k": "0.14",
		"alpha_deg": "2", "i_m": "1.5", "v_m": "1.5",
		"R_m": "", "mode": "三角高程",
	}

func get_title() -> String:
	return "球气差/三角高程（F1）"

func get_description() -> String:
	return "模式一：水平距离 D 的球气差 c₁=D²/(2R)、折光差 r=k·c₁、综合改正 f=(1−k)·D²/(2R)（k 常用 0.13/0.14 可配，默认 0.14）。模式二（三角高程）：h = D·tanα + f + i − v 单向观测高差。R 默认 WGS84 平均半径 6371008.7714 m。"

func _build_rows() -> void:
	add_input_row("计算模式", "mode", "三角高程")
	add_input_row("水平距离 D（m）", "D_m", "1000")
	add_input_row("折光系数 k", "k", "0.14")
	add_input_row("竖直角 α（°，仰正）", "alpha_deg", "2")
	add_input_row("仪器高 i（m）", "i_m", "1.5")
	add_input_row("目标高 v（m）", "v_m", "1.5")
	add_input_row("曲率半径 R（m，可空）", "R_m", "")

func _mode(edit: LineEdit) -> String:
	var t := edit.text.strip_edges()
	return "三角高程" if t != "球气差" else "球气差"

func run() -> Dictionary:
	var bad := []
	var mode := _mode(_fields["mode"])
	var d := num_field(_fields["D_m"], "水平距离", bad)
	var k := num_field(_fields["k"], "折光系数", bad)
	var r := opt_num_field(_fields["R_m"], CORE.DEFAULT_R_M, "曲率半径", bad)
	if not bad.is_empty():
		return fail_input(bad)
	if mode == "三角高程":
		var alpha := ang_field(_fields["alpha_deg"], "竖直角", bad)
		var i := num_field(_fields["i_m"], "仪器高", bad)
		var v := num_field(_fields["v_m"], "目标高", bad)
		if not bad.is_empty():
			return fail_input(bad)
		return CORE.trig_height({
			"D_m": d, "alpha_deg": alpha, "i_m": i, "v_m": v, "k": k, "R_m": r,
		})
	return CORE.correction({"D_m": d, "k": k, "R_m": r})
