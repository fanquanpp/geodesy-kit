# scenes/calculators/cogo/b5_propagate.gd —— B5 方位角推算（左角/右角）
extends "res://scenes/calculators/cogo/cogo_calc_base.gd"

const CORE := preload("res://core/cogo/angle_tools.gd")

func _init() -> void:
	_entry_id = "b5_propagate"
	_example_inputs = {"az_prev_deg": "95.5", "angle_deg": "178.250556", "turn": "左"}

func get_title() -> String:
	return "方位角推算（B5）"

func get_description() -> String:
	return "由前一边方位角与转折角推算后一边方位角：左角 α_后=α_前+β−180°，右角 α_后=α_前−β+180°，结果规范化到 [0°,360°)。角度可输 178.2506 或 178 15 02。"

func _build_rows() -> void:
	add_input_row("前一边方位角 α_前", "az_prev_deg", "95.5（或 95 30 00）")
	add_input_row("转折角 β", "angle_deg", "178.250556（或 178 15 02）")
	add_input_row("转折角类型", "turn", "左（默认）/ 右")

func run() -> Dictionary:
	var bad: Array = []
	var az_prev := ang_field(_fields["az_prev_deg"], "前一边方位角", bad)
	var angle := ang_field(_fields["angle_deg"], "转折角", bad)
	if not bad.is_empty():
		return fail_input(bad)
	return CORE.propagate({
		"az_prev_deg": az_prev, "angle_deg": angle,
		"turn": String(_fields["turn"].text).strip_edges(),
	})
