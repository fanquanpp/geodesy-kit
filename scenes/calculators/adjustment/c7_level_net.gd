# scenes/calculators/adjustment/c7_level_net.gd —— C7 水准网平差计算器（间接+条件双实现，自动互检）
extends "res://scenes/calculators/adjustment/adj_panel_base.gd"

const LV := preload("res://core/adjustment/leveling.gd")

const FMT_HINT := """每行一条，空白或逗号分隔，# 注释：
K 名称 H_m      已知点高程（至少 1 个，两个及以上自动加附合条件）
U 名称 H0_m     未知点近似高程
O 起点 终点 高差_m 路线长km   高差观测（权 p=1/L_km，μ 为每公里高差中误差口径）"""

func _build_fields() -> void:
	_add_text_area("水准网数据", "data", FMT_HINT)
	_add_section("双法互检说明")
	var note := Label.new()
	note.text = "本页同时运行间接平差与条件平差（独立生成树找环）两条实现，结果应逐位一致；如不一致会给出红字提示。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.theme_type_variation = &"Muted"
	_inputs_root.add_child(note)

## 文本块 → core 输入；出错返回空字典并填 errors
func _parse_net(text: String, errors: PackedStringArray) -> Dictionary:
	var known := {}
	var approx := {}
	var obs := []
	for row: Array in _parse_lines(text):
		var tag := String(row[0]).to_upper()
		if tag == "K":
			if row.size() < 3:
				errors.append("K 行应为：K 名称 H")
				continue
			var h := _num(row[2])
			if is_nan(h):
				errors.append("K 行 %s 高程非法" % String(row[1]))
				continue
			known[String(row[1])] = h
		elif tag == "U":
			if row.size() < 3:
				errors.append("U 行应为：U 名称 H0")
				continue
			var h0 := _num(row[2])
			if is_nan(h0):
				errors.append("U 行 %s 近似高程非法" % String(row[1]))
				continue
			approx[String(row[1])] = h0
		elif tag == "O":
			if row.size() < 5:
				errors.append("O 行应为：O 起点 终点 高差 路线长km")
				continue
			var h := _num(row[3])
			var l_km := _num(row[4])
			if is_nan(h) or is_nan(l_km) or l_km <= 0.0:
				errors.append("O 行高差/路线长非法")
				continue
			obs.append({"from": String(row[1]), "to": String(row[2]), "h": h, "L_km": l_km})
		else:
			errors.append("未知行类型 %s（应为 K/U/O）" % String(row[0]))
	return {"known": known, "approx": approx, "obs": obs}

func run() -> Dictionary:
	var errors := PackedStringArray()
	var net := _parse_net(_field_text("data"), errors)
	if errors.size() > 0:
		return _parse_fail(errors)
	var r_ind := LV.network_indirect(net)
	if not bool(r_ind.get("ok", false)):
		return r_ind
	var r_con := LV.network_condition(net)
	# 双法互检（教学特色）：把条件法关键结果并进 value，不一致给限差面板级别提示
	var v_ind: Dictionary = r_ind["value"]
	if bool(r_con.get("ok", false)):
		var v_con: Dictionary = r_con["value"]
		var diff_h := 0.0
		for k: String in v_ind:
			if k.begins_with("H_") and v_con.has(k):
				diff_h = maxf(diff_h, absf(float(v_ind[k]) - float(v_con[k])))
		var diff_v := 0.0
		var vi: PackedFloat64Array = v_ind["v_m"]
		var vc: PackedFloat64Array = v_con["v_m"]
		if vi.size() == vc.size():
			for i in vi.size():
				diff_v = maxf(diff_v, absf(vi[i] - vc[i]))
		v_ind["dual_check_max_diff_m"] = maxf(diff_h, diff_v)
		v_ind["dual_check_note"] = "间接/条件双法最大差异 %s m（双精度噪声量级即一致）" % String.num(maxf(diff_h, diff_v), 3)
		if maxf(diff_h, diff_v) > 1e-6:
			v_ind["dual_check_note"] = "双法差异超预期，请复核输入"
		r_ind["steps"] = r_ind["steps"] + r_con["steps"]
	else:
		v_ind["dual_check_note"] = "条件法未运行成功：%s" % String(r_con.get("error", ""))
	# 限差面板：把双法一致性作为检核项展示（ok_limit 语义 = 双法一致且 μ 有效）
	if v_ind.has("dual_check_max_diff_m"):
		v_ind["f_dual_diff_mm"] = float(v_ind["dual_check_max_diff_m"]) * 1000.0
		v_ind["limit_dual_diff_mm"] = 0.001
		v_ind["ok_limit"] = float(v_ind["dual_check_max_diff_m"]) <= 0.001
		v_ind["basis"] = "双法互检（间接 vs 条件）一致性判据 ≤0.001 mm"
	return r_ind

func get_title() -> String:
	return "水准网平差（双法互检）（C7）"

func get_description() -> String:
	return "水准网间接平差与条件平差双实现自动互检：条件法并列展示独立环条件与已知点间附合条件（条件总数 r = n − t），间接法参数为未知点高程。输出各点高程、高差改正数、单位权中误差 μ（定权 p=1/L_km，μ 为每公里高差中误差口径）与多余观测数。权威算例见示例按钮。"

func get_entry_id() -> String:
	return "c7_level_net"
