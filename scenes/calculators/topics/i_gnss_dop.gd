# scenes/calculators/topics/i_gnss_dop.gd —— I-GNSS DOP 精度衰减因子
extends "res://scenes/calculators/topics/topics_calc_base.gd"

const CORE := preload("res://core/topics/gnss.gd")

func _init() -> void:
	_entry_id = "i_gnss_dop"
	_example_inputs = {
		"los": "0.5,0.3,0.8124;0.5,-0.3,0.8124;-0.5,0.3,0.8124;-0.5,-0.3,0.8124",
		"with_clock": "否",
	}

func get_title() -> String:
	return "GNSS DOP 精度衰减因子（I）"

func get_description() -> String:
	return "由卫星视线单位向量（站心指向卫星，每星一行 ex,ey,ez，逗号分隔、分号分行，内部自动归一化）计算 DOP：3×3 位置口径输出 PDOP/HDOP/VDOP；选「含钟差列」时按 4×4 输出 GDOP/TDOP（全等高度角对称星座 4×4 奇异，会报中文退化提示）。PDOP<3 为优。"

func _build_rows() -> void:
	add_input_row("视线向量（ex,ey,ez;…）", "los", "0.5,0.3,0.8124;0.5,-0.3,0.8124;-0.5,0.3,0.8124;-0.5,-0.3,0.8124")
	add_input_row("含钟差列（是/否）", "with_clock", "否")

func run() -> Dictionary:
	var bad := []
	var los_text := text_field(_fields["los"], "视线向量", bad)
	if not bad.is_empty():
		return fail_input(bad)
	var rows := []
	for rec: String in los_text.replace("，", ",").replace("；", ";").replace(" ", "").split(";", false):
		var parts := rec.split(",")
		if parts.size() != 3:
			return {"ok": false, "value": {}, "steps": [], "formula": "",
					"error": "视线向量格式错误（应为 ex,ey,ez 每星 3 个数，分号分隔）：%s" % rec}
		for s in parts:
			if not s.is_valid_float():
				return {"ok": false, "value": {}, "steps": [], "formula": "",
						"error": "视线向量含非数值字段：%s" % rec}
		rows.append([parts[0].to_float(), parts[1].to_float(), parts[2].to_float()])
	var with_clock: bool = _fields["with_clock"].text.strip_edges().to_lower() in ["是", "y", "yes", "1", "true"]
	return CORE.dop({"los": rows, "with_clock": with_clock})
