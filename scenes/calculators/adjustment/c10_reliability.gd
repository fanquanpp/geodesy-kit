# scenes/calculators/adjustment/c10_reliability.gd —— C10 粗差探测计算器（数据探测法）
# 工作流：输入与 C5 相同的网形数据 → 先做间接平差 → 用其残差/协因数做数据探测
extends "res://scenes/calculators/adjustment/c5_network.gd"

const RL := preload("res://core/adjustment/reliability.gd")

func _build_fields() -> void:
	_add_text_area("网形与观测数据（同 C5 格式）", "data", FMT_HINT)
	_add_section("探测阈值（教学口径，可自定）")
	add_input_row("可疑阈值 |w|>", "k_warn", "2.0")
	add_input_row("粗差阈值 |w|>", "k_gross", "3.0")
	var note := Label.new()
	note.text = "先按 C5 间接平差求解，再对每个观测计算：多余观测分量 r_i=p_i·q_v_i（Σr=n−t）、学生化残差 w_i=v_i/(σ0·√q_v_i)。σ0 取平差 μ₀。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.theme_type_variation = &"Muted"
	_inputs_root.add_child(note)

func run() -> Dictionary:
	var errors := PackedStringArray()
	var net := _parse_network(_field_text("data"), errors)
	if errors.size() > 0:
		return _parse_fail(errors)
	var build := NW.build_design(net)
	if String(build.get("error", "")) != "":
		return {"ok": false, "value": {}, "steps": [], "formula": "",
				"error": String(build["error"])}
	var res := NW.adjust(net)
	if not bool(res.get("ok", false)):
		return res
	var mu: float = float(res["value"].get("mu0", NAN))
	if not is_finite(mu) or mu <= 0.0:
		return {"ok": false, "value": {}, "steps": [], "formula": "",
				"error": "无多余观测或 μ₀ 无效，无法进行粗差探测（数据探测法需要多余观测）"}
	var k_warn := _num(_field_text("k_warn"))
	var k_gross := _num(_field_text("k_gross"))
	if is_nan(k_warn) or k_warn <= 0.0:
		k_warn = 2.0
	if is_nan(k_gross) or k_gross <= 0.0:
		k_gross = 3.0
	# 残差序列（与观测同序：测边在前、角度在后，与 build_design 行序一致）
	var v_all := PackedFloat64Array()
	for x in res["value"]["v_dist_m"]:
		v_all.append(float(x))
	for x in res["value"]["v_angle_rad"]:
		v_all.append(float(x))
	var sn := RL.data_snooping({"B": build["B"], "v": v_all, "p_w": build["p"],
		"qxx": res["qxx"], "sigma0": mu, "k_warn": k_warn, "k_gross": k_gross})
	if not bool(sn.get("ok", false)):
		return sn
	var value: Dictionary = res["value"]
	var sv: Dictionary = sn["value"]
	# 观测级明细并入结果（键名与观测序一致）
	var flags: PackedStringArray = sv["flags"]
	var w_arr: PackedFloat64Array = sv["w"]
	var r_arr: PackedFloat64Array = sv["r"]
	for i in flags.size():
		value["w_%d" % (i + 1)] = w_arr[i]
		value["r_%d" % (i + 1)] = r_arr[i]
		value["flag_%d" % (i + 1)] = flags[i]
	value["sum_r"] = float(sv["sum_r"])
	value["arg_max_abs_w"] = int(sv["arg_max_abs_w"]) + 1
	value["gross_count"] = (sv["gross_indices"] as Array).size()
	value["warn_count"] = (sv["warn_indices"] as Array).size()
	# 限差面板：Σr=n−t 一致性 + 粗差计数
	value["f_sum_r_dev"] = absf(float(sv["sum_r"]) - float(sv["n_minus_t"]))
	value["limit_sum_r_dev"] = 1e-6
	value["ok_limit"] = value["f_sum_r_dev"] <= 1e-6 and value["gross_count"] == 0
	value["basis"] = "Σr=n−t 一致性；粗差计数=0（教学口径 k=%.1f/%.1f）" % [k_warn, k_gross]
	res["steps"] = res["steps"] + (sn["steps"] as Array)
	return res

func get_title() -> String:
	return "粗差探测与可靠性（C10）"

func get_description() -> String:
	return "数据探测法（Baarda）：学生化残差 w_i 与多余观测分量 r_i。|w| 超阈值标记可疑/粗差（阈值可自定，教学口径）。Σr=n−t 作总量检核。"

func get_entry_id() -> String:
	return "c10_reliability"
