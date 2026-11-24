# scenes/calculators/adjustment/c11_gnss_net.gd —— C11 GNSS 向量网三维平差计算器
# 注：输入若为 BLH 需先由 M2 转 XYZ（本页直接接收 XYZ；跨域转换由 app 编排层负责）
extends "res://scenes/calculators/adjustment/adj_panel_base.gd"

const GN := preload("res://core/adjustment/gnss_net.gd")

const FMT_HINT := """每行一条，空白或逗号分隔，# 注释：
K 名称 X Y Z      已知点（地心直角坐标 m，固定基准至少 1 个）
U 名称 X0 Y0 Z0   未知点近似坐标
B 起点 终点 dx dy dz [σ_m]   基线向量（σ 默认 0.01 m）"""

func _build_fields() -> void:
	_add_text_area("GNSS 网数据（XYZ）", "data", FMT_HINT)
	add_input_row("基准：fixed / free（无已知点选 free）", "datum", "fixed", LineEdit.KEYBOARD_TYPE_DEFAULT)
	_add_section("说明")
	var note := Label.new()
	note.text = "三维基线向量间接平差。fixed=固定基准（需已知点）；free=秩亏自由网最小范数解（ΣδX=ΣδY=ΣδZ=0）。BLH→XYZ 请先用「椭球与大地线」域的 BLH↔XYZ 计算器转换。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.theme_type_variation = &"Muted"
	_inputs_root.add_child(note)

func _parse_net(text: String, errors: PackedStringArray) -> Dictionary:
	var known := {}
	var approx := {}
	var baselines := []
	for row: Array in _parse_lines(text):
		var tag := String(row[0]).to_upper()
		if tag == "K":
			if row.size() < 5:
				errors.append("K 行应为：K 名称 X Y Z")
				continue
			var c := [_num(row[2]), _num(row[3]), _num(row[4])]
			if is_nan(c[0]) or is_nan(c[1]) or is_nan(c[2]):
				errors.append("K 行 %s 坐标须为数字" % String(row[1]))
				continue
			known[String(row[1])] = c
		elif tag == "U":
			if row.size() < 5:
				errors.append("U 行应为：U 名称 X0 Y0 Z0")
				continue
			var c0 := [_num(row[2]), _num(row[3]), _num(row[4])]
			if is_nan(c0[0]) or is_nan(c0[1]) or is_nan(c0[2]):
				errors.append("U 行 %s 近似坐标须为数字" % String(row[1]))
				continue
			approx[String(row[1])] = c0
		elif tag == "B":
			if row.size() < 6:
				errors.append("B 行应为：B 起点 终点 dx dy dz [σ]")
				continue
			var d := [_num(row[3]), _num(row[4]), _num(row[5])]
			if is_nan(d[0]) or is_nan(d[1]) or is_nan(d[2]):
				errors.append("B 行基线分量须为数字")
				continue
			var sig := 0.01
			if row.size() >= 7:
				sig = _num(row[6])
				if is_nan(sig) or sig <= 0.0:
					errors.append("B 行 σ 非法：%s" % String(row[6]))
					continue
			baselines.append({"from": String(row[1]), "to": String(row[2]),
					"dx": d[0], "dy": d[1], "dz": d[2], "sigma": sig})
		else:
			errors.append("未知行类型 %s（应为 K/U/B）" % String(row[0]))
	return {"known": known, "approx": approx, "baselines": baselines}

func run() -> Dictionary:
	var errors := PackedStringArray()
	var net := _parse_net(_field_text("data"), errors)
	if errors.size() > 0:
		return _parse_fail(errors)
	var datum := _field_text("datum").strip_edges().to_lower()
	if datum.is_empty():
		datum = "fixed"
	if datum != "fixed" and datum != "free":
		return {"ok": false, "value": {}, "steps": [], "formula": "",
				"error": "基准只支持 fixed / free"}
	net["datum"] = datum
	return GN.adjust(net)

func get_title() -> String:
	return "GNSS 向量网平差（C11）"

func get_description() -> String:
	return "三维基线向量间接平差（固定基准/秩亏自由网）。输入地心直角坐标 XYZ 与基线向量；BLH 需先经椭球域 BLH↔XYZ 转换（core 不横向依赖，由编排层转换）。"

func get_entry_id() -> String:
	return "c11_gnss_net"
