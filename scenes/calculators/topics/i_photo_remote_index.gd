# scenes/calculators/topics/i_photo_remote_index.gd —— I-遥感 遥感指数
extends "res://scenes/calculators/topics/topics_calc_base.gd"

const CORE := preload("res://core/topics/photogrammetry.gd")

func _init() -> void:
	_entry_id = "i_photo_remote_index"
	_example_inputs = {
		"red": "0.20", "nir": "0.80", "green": "0.30",
		"blue": "0.15", "swir1": "0.25", "swir2": "0.18",
		"custom_expression": "",
	}

func get_title() -> String:
	return "遥感指数（NDVI 等 10 种）（I）"

func get_description() -> String:
	return "按提供的波段反射率/DN 自动计算可算的全部内置指数：NDVI、EVI、SAVI、NDWI、MNDWI、NDBI、NBR、BAI、VARI、NDSI（波段不足的自动跳过）。支持自定义表达式（变量 b1..bn，需在下方按波段名映射）。波段名：red/green/blue/nir/swir1/swir2。"

func _build_rows() -> void:
	add_input_row("red（红）", "red", "0.20")
	add_input_row("green（绿）", "green", "0.30")
	add_input_row("blue（蓝）", "blue", "0.15")
	add_input_row("nir（近红外）", "nir", "0.80")
	add_input_row("swir1（短波红外1）", "swir1", "0.25")
	add_input_row("swir2（短波红外2）", "swir2", "0.18")
	add_input_row("自定义表达式（可空）", "custom_expression", "(b1-b2)/(b1+b2)")
	add_input_row("自定义波段映射（b1=…;…）", "custom_bands", "")

func run() -> Dictionary:
	var bad := []
	var bands := {}
	for key in ["red", "green", "blue", "nir", "swir1", "swir2"]:
		var v := opt_num_field(_fields[key], NAN, key, bad)
		if not bad.is_empty():
			return fail_input(bad)
		if is_finite(v):
			bands[key] = v
	if bands.is_empty() and _fields["custom_expression"].text.strip_edges().is_empty():
		return fail_input(["请至少输入一个波段反射率或 DN"])
	var p := {"bands": bands}
	var expr: String = _fields["custom_expression"].text.strip_edges()
	if not expr.is_empty():
		p["custom_expression"] = expr
	var map_text: String = _fields["custom_bands"].text.strip_edges()
	if not map_text.is_empty():
		var names := []
		for rec: String in map_text.replace("，", ",").replace("；", ";").replace(" ", "").split(";", false):
			# 记录格式 b1=red 或 b1:red（只取等号后波段名，顺序即 b1..bn）
			var name_part := rec.split("=")[1] if rec.contains("=") else rec.split(":")[1] if rec.contains(":") else ""
			if name_part.is_empty() or not bands.has(name_part):
				return {"ok": false, "value": {}, "steps": [], "formula": "",
						"error": "自定义波段映射格式错误（应为 b1=red;b2=nir;…，且波段已填值）：%s" % rec}
			names.append(name_part)
		p["custom_bands"] = names
	return CORE.remote_index(p)
