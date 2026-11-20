# scenes/calculators/cogo/b5_convert.gd —— B5 角度格式换算（度/度分秒/gon/rad/象限角）
extends "res://scenes/calculators/cogo/cogo_calc_base.gd"

const CORE := preload("res://core/cogo/angle_tools.gd")

func _init() -> void:
	_entry_id = "b5_convert"
	_example_inputs = {"angle_text": "30.5"}

func get_title() -> String:
	return "角度格式换算（B5）"

func get_description() -> String:
	return "十进制度 ⇄ 度分秒 ⇄ gon（百分度）⇄ 弧度，并给出象限角。输入可写 30.5、30°30′00″ 或 30 30 00；1 gon = 0.9°。"

func _build_rows() -> void:
	add_input_row("角度输入", "angle_text", "30.5 或 30 30 00")

func run() -> Dictionary:
	var text := String(_fields["angle_text"].text).strip_edges()
	if text.is_empty():
		return fail_input(["请输入「角度输入」"])
	return CORE.convert({"dms": text})
