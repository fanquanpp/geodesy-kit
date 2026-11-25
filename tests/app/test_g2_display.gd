# tests/app/test_g2_display.gd —— G2 批量转换展示层中文化（P2 包验收）
# 口径：机器键（rows/n_ok/n_err/pipeline/label/in_cols/out_cols）不得出现在
# 结果卡/步骤卡文本；结果卡含中文统计行；失败行步骤卡红字 + 错误列；
# 列名全中文且括号全角；报告对 rows 摘要化、机器键不逐项进报告表。
extends "res://tests/test_case_base.gd"

const BC := preload("res://app/batch_convert.gd")
const _Report := preload("res://app/report.gd")

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

## 结果卡/步骤卡文本里不得出现机器键原文（验收标准②）
static func _has_machine_key(text: String) -> String:
	for k: String in ["rows", "n_ok", "n_err", "pipeline", "in_cols", "out_cols"]:
		if text.contains(k):
			return k
	if text.contains("line="):
		return "line="
	return ""

# ---------- 展示层：场景面板冒烟 ----------

func test_g2_panel_result_and_step_text_no_machine_keys() -> void:
	var scene := load("res://scenes/calculators/tools/batch_convert.tscn")
	assert_true(scene != null, "G2 场景可加载")
	if scene == null:
		return
	var inst: Node = scene.instantiate()
	var t := _tree()
	t.root.add_child(inst)
	var calc := inst as GKCalculatorBase
	assert_true(calc != null, "根脚本继承 GKCalculatorBase")
	if calc == null:
		t.root.remove_child(inst)
		inst.free()
		return
	# 1 成功行 + 1 解析失败行，覆盖成功卡与失败卡两种渲染
	calc.set_inputs({"pipeline": "blh_to_xyz", "datum": "WGS84",
			"text": "P1, 39.9075, 116.3913, 43.5\nbad, 200, 116, 0"})
	var res: Dictionary = calc.run()
	assert_true(bool(res.get("ok", false)), "含坏行仍整体成功：" + String(res.get("error", "")))
	calc._on_run()
	# 结果卡：中文统计行（成功 N 行，失败 M 行口径），无机器键
	var card_text := String(calc._result_card.call("get_text"))
	var bad := _has_machine_key(card_text)
	assert_true(bad.is_empty(), "结果卡不含机器键（发现：%s，文本：%s）" % [bad, card_text])
	assert_true(card_text.contains("成功 1 行"), "结果卡统计行含「成功 1 行」：" + card_text)
	assert_true(card_text.contains("失败 1 行"), "结果卡统计行含「失败 1 行」")
	# 步骤卡：逐行卡文本无机器键、无 line=，失败行有错误列文案
	var step_texts := ""
	var steps_widget: Node = calc._steps_widget
	for c in steps_widget.get_children():
		step_texts += _collect_labels(c) + "\n"
	bad = _has_machine_key(step_texts)
	assert_true(bad.is_empty(), "步骤卡不含机器键（发现：%s）" % bad)
	assert_true(step_texts.contains("错误："), "失败行步骤卡含错误列文案")
	assert_true(step_texts.contains("纬度超出范围"), "失败行错误文案与单点同口径")
	assert_true(step_texts.contains("X 坐标（m）"), "成功行列名为中文全角（X 坐标（m））")
	t.root.remove_child(inst)
	inst.free()

static func _collect_labels(node: Node) -> String:
	var out := ""
	if node is Label:
		out += String((node as Label).text) + "\n"
	for c in node.get_children():
		out += _collect_labels(c)
	return out

## 失败行步骤卡红字（ErrorCard/ErrorLabel 变体；主题缺失回退默认，不报错）
func test_g2_panel_failed_row_step_card_red() -> void:
	var scene := load("res://scenes/calculators/tools/batch_convert.tscn")
	if scene == null:
		return
	var inst: Node = scene.instantiate()
	var t := _tree()
	t.root.add_child(inst)
	var calc := inst as GKCalculatorBase
	if calc == null:
		t.root.remove_child(inst)
		inst.free()
		return
	calc.set_inputs({"pipeline": "blh_to_xyz", "datum": "WGS84",
			"text": "P1, 39.9075, 116.3913, 43.5\nbad, 200, 116, 0"})
	calc.run()
	calc._on_run()
	var steps_widget: Node = calc._steps_widget
	var red_cards := 0
	for c in steps_widget.get_children():
		if c is PanelContainer and (c as PanelContainer).theme_type_variation == &"ErrorCard":
			red_cards += 1
			var has_error_label := false
			for lab in _labels_of(c):
				if (lab as Label).theme_type_variation == &"ErrorLabel":
					has_error_label = true
			assert_true(has_error_label, "失败行卡片内含 ErrorLabel 变体 Label")
	assert_int_eq(red_cards, 1, "恰有 1 张失败行红卡")
	t.root.remove_child(inst)
	inst.free()

static func _labels_of(node: Node) -> Array:
	var out := []
	if node is Label:
		out.append(node)
	for c in node.get_children():
		out.append_array(_labels_of(c))
	return out

# ---------- 列名规范 ----------

## 结果列名全中文、括号全角，不含半角英文列名（验收标准③）
func test_g2_out_cols_chinese_fullwidth() -> void:
	for key: String in BC.PIPELINES.keys():
		var pipe: Dictionary = BC.PIPELINES[key]
		for col: Variant in pipe["out_cols"]:
			var col_s := String(col)
			assert_false(col_s.contains("(") or col_s.contains(")"),
					"%s 列名「%s」无半角括号" % [key, col_s])
			assert_false(col_s.contains("(m)") or col_s.contains("(deg)") or col_s.contains("(°)"),
					"%s 列名「%s」无半角英文列名" % [key, col_s])
			assert_true(col_s.contains("（"), "%s 列名「%s」含全角括号" % [key, col_s])

# ---------- 报告导出 ----------

## G2 报告：rows 不逐项进报告表，以中文统计 + 前 10 行明细呈现（验收标准④）
func test_g2_report_rows_summarized() -> void:
	var r: Dictionary = BC.convert({"pipeline": "blh_to_gauss",
		"params": {"datum": "CGCS2000", "l0_deg": "117"},
		"text": "A, 30, 117, 0\nB, 32.5, 118.25, 0"})
	assert_true(bool(r["ok"]), "G2 计算成功：" + String(r.get("error", "")))
	var md := _Report.render_markdown("批量坐标转换", "g2_batch_convert", {}, r)
	# 机器键不逐项进报告表
	assert_false(md.contains("| rows |"), "报告表无 | rows | 行")
	for k: String in ["n_ok", "n_err", "pipeline", "in_cols", "out_cols"]:
		assert_false(md.contains("| %s |" % k), "报告表无 | %s | 行" % k)
	# 中文统计行（summary 原文）
	assert_true(md.contains("成功 2 行"), "报告含中文统计行（成功 2 行）")
	assert_true(md.contains("失败 0 行"), "报告含中文统计行（失败 0 行）")
	# 前 10 行明细：2 行都在预览内
	assert_true(md.contains("前 2 行明细"), "报告含明细段")
	assert_true(md.contains("- 第 1 行 A："), "明细含第 1 行点名")
	# 大数组撑爆回归：20 行只预览 10 行
	var text := ""
	for i in 20:
		text += "P%d, 30, 117, 0\n" % (i + 1)
	var big: Dictionary = BC.convert({"pipeline": "blh_to_gauss",
		"params": {"datum": "CGCS2000", "l0_deg": "117"}, "text": text})
	var md2 := _Report.render_markdown("批量坐标转换", "g2_batch_convert", {}, big)
	assert_true(md2.contains("前 10 行明细"), "大数组只预览 10 行")
	assert_true(md2.contains("（其余 10 行详见导出 CSV）"), "超预览部分提示导出 CSV")

## 非 G2 计算器报告行为不变：键名原文设计保留（验收标准④后半）
func test_report_non_g2_keys_unchanged() -> void:
	var result := {
		"ok": true,
		"value": {"x_m": 3597986.6234, "y_m": 617474.9201, "ok_limit": false,
				"f_beta_s": 12.5, "limit_s": 9.0, "basis": "图根导线"},
		"steps": [
			{"title": "1. 子午线弧长", "formula": "X=a(m0·B-…)", "substitution": "B=0.567rad", "result": "3320113.3978 m"},
		],
		"formula": "高斯-克吕格正算（Krüger 6 阶）", "error": "",
	}
	var md := _Report.render_markdown("高斯投影正算", "a3_gauss_fwd", {"B_deg": "30", "L_deg": "117"}, result)
	# P11 报告定点口径：_fmt 改 printf 定点 6 位（尾零补齐），键名原文保留不变
	assert_true(md.contains("| x_m | 3597986.623400 |"), "非 G2 键名原文保留（x_m，6 位定点）")
	assert_true(md.contains("| f_beta_s | 12.500000 |"), "限差明细键保留（f_beta_s，6 位定点）")
	assert_true(md.contains("## 限差检核") and md.contains("超限"), "限差检核节不变")

## rows → CSV：失败行按 max_v 补齐空值列（与表头字段数一致，Excel 状态列不错位）。
## 固定样本与 tests/tools/test_tools.gd test_batch_rows_to_csv 同源。数值格式
## 直接取 String.num(·, 6) 引擎口径（未传 decimals 时默认 6 位），不假设尾零处理。
func test_rows_to_csv_byte_identical() -> void:
	var rows := [
		{"line": 1, "name": "P1", "values": [1.5, 2.25], "error": ""},
		{"line": 2, "name": "坏,点", "values": [], "error": "纬度超出范围"},
	]
	var csv := BC.rows_to_csv(rows)
	var expected := "行号,点名,值1,值2,状态\n1,P1,%s,%s,成功\n2,\"坏,点\",,,失败：纬度超出范围" \
			% [String.num(1.5, 6), String.num(2.25, 6)]
	assert_eq(csv, expected, "CSV 固定样本逐字节一致")

## 表头真实列名：传 out_cols 时输出管线列名而非泛化的「值N」（冷审问题⑦）
func test_rows_to_csv_out_cols_header() -> void:
	var rows := [{"line": 1, "name": "P1", "values": [1.5], "error": ""}]
	var csv := BC.rows_to_csv(rows, ["X 坐标（m）"], 6)
	assert_true(csv.begins_with("行号,点名,X 坐标（m）,状态"), "表头用 out_cols 真实列名")
