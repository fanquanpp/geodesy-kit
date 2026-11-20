# scenes/calculators/topics/i_photo_flight.gd —— I-摄影 航摄设计
extends "res://scenes/calculators/topics/topics_calc_base.gd"

const CORE := preload("res://core/topics/photogrammetry.gd")

func _init() -> void:
	_entry_id = "i_photo_flight"
	_example_inputs = {
		"f_m": "0.035", "pixel_um": "3.9", "img_w_px": "8192", "img_h_px": "5460",
		"H_m": "200", "forward_overlap": "0.65", "side_overlap": "0.35",
		"area_w_m": "1000", "area_h_m": "1500",
	}

func get_title() -> String:
	return "航摄设计（比例尺/GSD/重叠度）（I）"

func get_description() -> String:
	return "航摄基本关系：摄影比例尺 1:m = 1:(H/f)、GSD = 像元×H/f、单片地面覆盖 = 行列×GSD、航向摄影基线 B = 覆盖宽×(1−航向重叠)、旁向航线间隔 D = 覆盖高×(1−旁向重叠)；给定测区宽/长时估算航线数与像片总数（航线沿长边敷设）。"

func _build_rows() -> void:
	add_input_row("焦距 f（m）", "f_m", "0.035")
	add_input_row("像元尺寸（μm）", "pixel_um", "3.9")
	add_input_row("影像宽（像素）", "img_w_px", "8192")
	add_input_row("影像高（像素）", "img_h_px", "5460")
	add_input_row("相对航高 H（m）", "H_m", "200")
	add_input_row("航向重叠度（0-1）", "forward_overlap", "0.65")
	add_input_row("旁向重叠度（0-1）", "side_overlap", "0.35")
	add_input_row("测区宽（m，可空）", "area_w_m", "1000")
	add_input_row("测区长（m，可空）", "area_h_m", "1500")

func run() -> Dictionary:
	var bad := []
	var p := {
		"f_m": num_field(_fields["f_m"], "焦距", bad),
		"pixel_um": num_field(_fields["pixel_um"], "像元尺寸", bad),
		"img_w_px": num_field(_fields["img_w_px"], "影像宽", bad),
		"img_h_px": num_field(_fields["img_h_px"], "影像高", bad),
		"H_m": num_field(_fields["H_m"], "相对航高", bad),
		"forward_overlap": num_field(_fields["forward_overlap"], "航向重叠度", bad),
		"side_overlap": num_field(_fields["side_overlap"], "旁向重叠度", bad),
	}
	if not bad.is_empty():
		return fail_input(bad)
	var aw := opt_num_field(_fields["area_w_m"], NAN, "测区宽", bad)
	var ah := opt_num_field(_fields["area_h_m"], NAN, "测区长", bad)
	if not bad.is_empty():
		return fail_input(bad)
	if is_finite(aw) and is_finite(ah):
		p["area_w_m"] = aw
		p["area_h_m"] = ah
	return CORE.flight_design(p)
