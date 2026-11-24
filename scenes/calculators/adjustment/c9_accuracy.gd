# scenes/calculators/adjustment/c9_accuracy.gd —— C9 点位中误差与误差椭圆计算器
extends "res://scenes/calculators/adjustment/adj_panel_base.gd"

const AC := preload("res://core/adjustment/accuracy.gd")

func _build_fields() -> void:
	_add_section("协因数阵 2×2 子阵（x=东、y=北）")
	add_input_row("qxx（x 东方向）", "qxx", "0.0000820048")
	add_input_row("qyy（y 北方向）", "qyy", "0.0000561621")
	add_input_row("qxy（协因数）", "qxy", "-0.0000000035566")
	add_input_row("单位权中误差 σ0", "sigma0", "0.371017784")
	_add_section("说明")
	var note := Label.new()
	note.text = "输入间接平差法方程逆 N⁻¹ 的对应 2×2 子阵与 μ₀（C5 结果页给出）。输出 A/B 半轴（m）、主轴方位 φE（从北顺时针 [0°,180°)）、点位中误差 Mp=σ0·√(qxx+qyy)。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.theme_type_variation = &"Muted"
	_inputs_root.add_child(note)

func run() -> Dictionary:
	var errors := PackedStringArray()
	var qxx := _num(_field_text("qxx"))
	var qyy := _num(_field_text("qyy"))
	var qxy := _num(_field_text("qxy"))
	var sigma0 := _num(_field_text("sigma0"))
	if is_nan(qxx) or is_nan(qyy) or is_nan(qxy):
		errors.append("协因数分量须为数字")
	if is_nan(sigma0) or sigma0 <= 0.0:
		errors.append("σ0 须为正数")
	if errors.size() > 0:
		return _parse_fail(errors)
	return AC.ellipse_from_q({"qxx": qxx, "qyy": qyy, "qxy": qxy, "sigma0": sigma0})

func get_title() -> String:
	return "点位中误差与误差椭圆（C9）"

func get_description() -> String:
	return "由协因数阵计算误差椭圆：A²/B² 由特征根给出，φE 为主轴方位（从北顺时针），Mp=√(A²+B²)。半轴非负判据内置。"

func get_entry_id() -> String:
	return "c9_accuracy"
