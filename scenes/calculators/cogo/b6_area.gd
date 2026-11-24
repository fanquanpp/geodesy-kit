# scenes/calculators/cogo/b6_area.gd —— B6 多边形面积（鞋带公式）与亩/公顷/英亩换算
extends "res://scenes/calculators/cogo/cogo_calc_base.gd"

const CORE := preload("res://core/cogo/area_tools.gd")

func _init() -> void:
	_entry_id = "b6_area"
	_example_inputs = {"points_text": "100,100;500,120;520,480;120,500"}

func get_title() -> String:
	return "多边形面积（鞋带公式）（B6）"

func get_description() -> String:
	return "按顶点顺序闭合的多边形鞋带面积，并换算亩（2000/3 m²）、公顷、英亩（4046.8564224 m²）。逐点输入 100,100;500,120;…（逗号分隔 xy，分号分隔点，支持换行）。"

func _build_rows() -> void:
	add_input_row("顶点坐标（按序）", "points_text", "100,100;500,120;520,480;120,500", LineEdit.KEYBOARD_TYPE_DEFAULT)

func run() -> Dictionary:
	var text := String(_fields["points_text"].text).strip_edges()
	if text.is_empty():
		return fail_input(["请输入「顶点坐标」"])
	return CORE.polygon_area({"points": text})
