# scenes/calculators/topics/i_geo_attitude.gd —— I-地质 产状换算/真厚度（双模式）
extends "res://scenes/calculators/topics/topics_calc_base.gd"

const CORE := preload("res://core/topics/geology.gd")

func _init() -> void:
	_entry_id = "i_geo_attitude"
	_example_inputs = {
		"mode": "真厚度",
		"strike_deg": "45", "dip_deg": "30",
		"width_m": "100", "profile_az_deg": "135",
	}

func get_title() -> String:
	return "地质产状换算/真厚度（I）"

func get_description() -> String:
	return "模式一（产状换算）：走向 → 倾向（=走向+90°）与象限式文本（N45°E 等）；给剖面方位时附视倾角 tanβ=tanα·sinγ。模式二（真厚度）：剖面水平宽度 L、真倾角 α、剖面与走向夹角 γ → t = L·sinα·sinγ（剖面垂直走向时 t = L·sinα）。"

func _build_rows() -> void:
	add_input_row("计算模式", "mode", "真厚度")
	add_input_row("走向（°，0-360）", "strike_deg", "45")
	add_input_row("真倾角（°，0-90）", "dip_deg", "30")
	add_input_row("剖面水平宽度（m）", "width_m", "100")
	add_input_row("剖面方位（°）", "profile_az_deg", "135")

func run() -> Dictionary:
	var bad := []
	var mode: String = _fields["mode"].text.strip_edges()
	var strike := num_field(_fields["strike_deg"], "走向", bad)
	var dip := num_field(_fields["dip_deg"], "真倾角", bad)
	var paz := num_field(_fields["profile_az_deg"], "剖面方位", bad)
	if not bad.is_empty():
		return fail_input(bad)
	if mode == "产状换算":
		var p := {"strike_deg": strike, "dip_deg": dip}
		if not _fields["profile_az_deg"].text.strip_edges().is_empty():
			p["profile_az_deg"] = paz
		return CORE.attitude(p)
	# 默认：真厚度
	var width := num_field(_fields["width_m"], "剖面水平宽度", bad)
	if not bad.is_empty():
		return fail_input(bad)
	return CORE.true_thickness({
		"width_m": width, "dip_deg": dip,
		"profile_az_deg": paz, "strike_deg": strike,
	})
