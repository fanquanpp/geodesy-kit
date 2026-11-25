# scenes/calculators/cogo/b7_affine.gd —— B7 点位平移/旋转/缩放（绕枢轴，方位系顺时针）
extends "res://scenes/calculators/cogo/cogo_calc_base.gd"

const CORE := preload("res://core/cogo/affine_tools.gd")

func _init() -> void:
	_entry_id = "b7_affine"
	_example_inputs = {
		"x_m": "300", "y_m": "150",
		"x_pivot_m": "100", "y_pivot_m": "100",
		"rot_deg": "30", "scale": "2", "dx_m": "0", "dy_m": "0",
	}

func get_title() -> String:
	return "点位平移/旋转/缩放（B7）"

func get_description() -> String:
	return "绕枢轴旋转（方位系顺时针正角）并缩放后平移：P′=枢轴+k·R(α)·(P−枢轴)+(dx,dy)。输出含检核键：距离比（=k）与方位偏移（=α）。旋转/缩放/平移留空按 0/1/0 处理。"

func _build_rows() -> void:
	add_input_row("点位 x（东，m）", "x_m", "300")
	add_input_row("点位 y（北，m）", "y_m", "150")
	add_input_row("枢轴 x（东，m）", "x_pivot_m", "100")
	add_input_row("枢轴 y（北，m）", "y_pivot_m", "100")
	add_input_row("旋转角 α（顺时针+）", "rot_deg", "30（或 30 00 00）")
	add_input_row("缩放系数 k", "scale", "2")
	add_input_row("平移 dx（m，可空）", "dx_m", "0")
	add_input_row("平移 dy（m，可空）", "dy_m", "0")

func run() -> Dictionary:
	var bad: Array = []
	var x := num_field(_fields["x_m"], "点位 x", bad, "x_m")
	var y := num_field(_fields["y_m"], "点位 y", bad, "y_m")
	var px := num_field(_fields["x_pivot_m"], "枢轴 x", bad, "x_pivot_m")
	var py := num_field(_fields["y_pivot_m"], "枢轴 y", bad, "y_pivot_m")
	if not bad.is_empty():
		return fail_input(bad)
	var rot := ang_field(_fields["rot_deg"], "旋转角", bad, "rot_deg")
	var scale := opt_num_field(_fields["scale"], 1.0, "缩放系数", bad, "scale")
	var tx := opt_num_field(_fields["dx_m"], 0.0, "平移 dx", bad, "dx_m")
	var ty := opt_num_field(_fields["dy_m"], 0.0, "平移 dy", bad, "dy_m")
	if not bad.is_empty():
		return fail_input(bad)
	if String(_fields["scale"].text).strip_edges() != "" and scale == 0.0:
		return fail_input(["「缩放系数」不能为 0（退化变换）"])
	return CORE.apply({
		"x_m": x, "y_m": y,
		"x_pivot_m": px, "y_pivot_m": py,
		"rot_deg": rot, "scale": scale,
		"dx_m": tx, "dy_m": ty,
	})
