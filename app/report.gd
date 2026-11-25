# app/report.gd —— G3 计算报告导出（ARCHITECTURE.md §5 协议渲染）
#
# 职责：把任意一次计算的 §5 协议结果（{ok, value, steps, formula, error}）
# 汇总为可读报告：
#   - Markdown：标题 → 元信息（时间/条目/引擎版本）→ 输入回显表 → 使用公式
#     → 步骤四列表格（title/formula/substitution/result）→ 结果表
#     → 限差检核（通过/超限+依据）→ 尾注；
#   - 纯文本：同构去表格线。
# 失败的计算也可导出（含中文 error 一节），满足"每一步可追溯"。
# 落盘：user://reports/<entry_id>_<yyyyMMdd_HHmmss>.md；桌面端显示绝对路径。
# I/O 经 platform/file_io.gd（引擎 I/O 统一收口），本层不做 FileAccess 直写。
class_name GKReport
extends RefCounted

const DIR := "user://reports"
const FOOTNOTE := "本报告由 GeodesyKit 自动生成，供教学演示与步骤追溯，不替代生产级平差/工程软件。"
## rows 摘要化预览行数上限（完整明细走 CSV 导出，不进报告表）
const PREVIEW_ROWS := 10

## 渲染 Markdown 报告。title=计算器名；inputs=输入快照；result=§5 协议结果。
## sections（可选，默认 {} 全量向后兼容）：区块开关字典——键 ∈ {inputs, formula,
## steps, results, limits}，值 false 的区块整节不输出；未列出的区块照常输出。
## 用途：调用方按 UI 折叠态/用户勾选裁剪报告分区（本施工项①折叠契约的报告侧）。
static func render_markdown(title: String, entry_id: String, inputs: Dictionary,
		result: Dictionary, sections: Dictionary = {}) -> String:
	var L: Array[String] = []
	L.append("# %s" % title)
	L.append("")
	L.append("- 时间：%s" % _now_text())
	L.append("- 条目：%s" % (entry_id if not entry_id.is_empty() else "（未登记）"))
	L.append("- 引擎：%s" % Engine.get_version_info().get("string", "Godot"))
	L.append("")
	# 输入回显表
	if _section_on(sections, "inputs") or inputs.is_empty():
		if inputs.is_empty():
			L.append("## 输入")
			L.append("")
			L.append("（无输入快照）")
		else:
			L.append("## 输入")
			L.append("")
			L.append("| 参数 | 值 |")
			L.append("| --- | --- |")
			for k: String in inputs.keys():
				L.append("| %s | %s |" % [_md_cell(k), _md_cell(str(inputs[k]))])
		L.append("")
	# 使用公式
	var formula := String(result.get("formula", ""))
	if not formula.is_empty() and _section_on(sections, "formula"):
		L.append("## 使用公式")
		L.append("")
		L.append(formula)
		L.append("")
	# 步骤四列表格（§5 规则②：title/formula/substitution/result）
	var steps: Array = result.get("steps", [])
	if not steps.is_empty() and _section_on(sections, "steps"):
		L.append("## 计算步骤")
		L.append("")
		L.append("| 步骤 | 公式 | 代入 | 结果 |")
		L.append("| --- | --- | --- | --- |")
		for st: Dictionary in steps:
			L.append("| %s | %s | %s | %s |" % [
				_md_cell(String(st.get("title", ""))),
				_md_cell(String(st.get("formula", ""))),
				_md_cell(String(st.get("substitution", ""))),
				_md_cell(String(st.get("result", ""))),
			])
		L.append("")
	# 结果表 / 错误
	var ok := bool(result.get("ok", false))
	if ok:
		var value: Dictionary = result.get("value", {})
		if not value.is_empty() and _section_on(sections, "results"):
			L.append("## 结果")
			L.append("")
			L.append("| 量 | 值 |")
			L.append("| --- | --- |")
			for k: String in value.keys():
				if is_meta_key(k):
					continue  # 机器契约键（rows/n_ok/…）不逐项进报告，见 value 摘要
				L.append("| %s | %s |" % [_md_cell(k), _md_cell(_fmt(value[k]))])
			_append_value_summary(L, value)
			L.append("")
		var lim := _limits_lines(result)
		if not lim.is_empty() and _section_on(sections, "limits"):
			L.append("## 限差检核")
			L.append("")
			for line: String in lim:
				L.append("- %s" % line)
			L.append("")
	else:
		L.append("## 错误")
		L.append("")
		L.append("本次计算未完成：%s" % String(result.get("error", "未知错误")))
		L.append("")
	L.append("---")
	L.append("")
	L.append(FOOTNOTE)
	L.append("")
	return "\n".join(L)

## 区块开关谓词：sections 缺键（或空字典）= 输出该区块（默认全量，向后兼容）；
## 仅显式 false 才裁剪。
static func _section_on(sections: Dictionary, key: String) -> bool:
	if not sections.has(key):
		return true
	return bool(sections[key])

## 纯文本版：同构去表格线。
## 纯文本版：同构去表格线。sections 透传 render_markdown（区块裁剪口径一致）。
static func render_text(title: String, entry_id: String, inputs: Dictionary,
		result: Dictionary, sections: Dictionary = {}) -> String:
	var md := render_markdown(title, entry_id, inputs, result, sections)
	var out := md
	# 表格行 → 键值行（去掉分隔行与竖线），保持可读缩进
	var lines := out.split("\n")
	var L: Array[String] = []
	var prev_table := false
	for line: String in lines:
		if line.begins_with("|"):
			if line.contains("---"):
				continue  # 分隔行
			var cells := line.trim_prefix("|").trim_suffix("|").split("|")
			var cells2: Array[String] = []
			for c in cells:
				cells2.append(c.replace("\\|", "|").strip_edges())
			if cells2.size() == 2:
				L.append("%s：%s" % [cells2[0], cells2[1]])
			else:
				L.append(" · " + " ┃ ".join(cells2))
			prev_table = true
		else:
			if prev_table and not line.strip_edges().is_empty():
				L.append("")
			prev_table = line.begins_with("|")
			L.append(line)
	return "\n".join(L)

## 落盘到 user://reports/。返回 {ok, path, text_path, error}；path 为可显示的绝对路径。
## sections（可选，向后兼容）：区块裁剪字典——键 ∈ {inputs, formula, steps,
## results, limits}（与 render_markdown 的区块注释同名），值为 false 的区块整节
## 不输出；缺省 {} 全量（与 UI 折叠态无关的既有报告行为不变）。
static func save(title: String, entry_id: String, inputs: Dictionary, result: Dictionary,
		sections: Dictionary = {}) -> Dictionary:
	var md := render_markdown(title, entry_id, inputs, result, sections)
	var stamp := "%04d%02d%02d_%02d%02d%02d" % _now_tuple()
	var rel := "%s/%s_%s.md" % [DIR, _safe_id(entry_id), stamp]
	if not GKFileIO.write_text(rel, md):
		return {"ok": false, "path": "", "text_path": "", "error": "报告写入失败：%s" % ProjectSettings.globalize_path(rel)}
	var abs := ProjectSettings.globalize_path(rel)
	return {"ok": true, "path": abs, "rel_path": rel,
			"text_path": "", "error": ""}

## 另存为纯文本（可选）。返回 {ok, path, error}。sections 透传（同 save）。
static func save_text(title: String, entry_id: String, inputs: Dictionary, result: Dictionary,
		sections: Dictionary = {}) -> Dictionary:
	var txt := render_text(title, entry_id, inputs, result, sections)
	var stamp := "%04d%02d%02d_%02d%02d%02d" % _now_tuple()
	# 文件名安全化与 save() 同一收口：含 / 或 .. 的 id 不得写出 reports 目录
	var rel := "%s/%s_%s.txt" % [DIR, _safe_id(entry_id), stamp]
	if not GKFileIO.write_text(rel, txt):
		return {"ok": false, "path": "", "error": "报告写入失败：%s" % ProjectSettings.globalize_path(rel)}
	return {"ok": true, "path": ProjectSettings.globalize_path(rel), "rel_path": rel, "error": ""}

# ---------- 内部 ----------

## 机器契约键判定（与 calculator_base 的 is_meta_key 同一前缀口径，P3 合入后收口）：
## G2 批量转换的 value 七键（rows/n_ok/n_err/pipeline/label/in_cols/out_cols）是
## 机器契约，不逐项进报告表——rows 由 _append_value_summary 摘要化，
## 其余统计/列名键在报告里没有可读意义。summary 展示键不在此列（用户可见统计行）。
static func is_meta_key(k: String) -> bool:
	return k == "rows" or k == "n_ok" or k == "n_err" or k == "pipeline" \
			or k == "label" or k == "in_cols" or k == "out_cols"

## value 摘要化（防报告表被大数组撑爆）：
## - 有 summary 展示键（G2 统计行）→ 原文输出；
## - 有 rows 行数组（G2）→ 前 PREVIEW_ROWS 行明细（超预览提示导出 CSV）；
## - 其余 value 不加任何内容（非 G2 计算器报告行为不变）。
static func _append_value_summary(L: Array[String], value: Dictionary) -> void:
	var rows: Array = []
	if value.get("rows", null) is Array:
		rows = value["rows"]
	if value.has("summary"):
		L.append("")
		L.append(String(value["summary"]))
		_append_rows_preview(L, rows)
		return
	if rows.is_empty():
		return
	_append_rows_preview(L, rows)

## rows 明细预览：统计行（无 summary 键时）+ 前 PREVIEW_ROWS 行 + 超预览提示
static func _append_rows_preview(L: Array[String], rows: Array) -> void:
	if rows.is_empty():
		return
	var preview := mini(rows.size(), PREVIEW_ROWS)
	if preview > 0:
		L.append("")
		L.append("前 %d 行明细：" % preview)
		for i in preview:
			var r: Dictionary = rows[i]
			var vals: Array = r.get("values", [])
			var err := String(r.get("error", ""))
			var body := ""
			if not err.is_empty():
				body = "错误：%s" % err
			else:
				var parts := PackedStringArray()
				for j in vals.size():
					parts.append(_fmt(vals[j]))
				body = "值：" + "，".join(parts)
			L.append("- 第 %d 行 %s：%s" % [int(r.get("line", 0)), String(r.get("name", "")), body])
	if rows.size() > preview:
		L.append("（其余 %d 行详见导出 CSV）" % (rows.size() - preview))

## 条目 id 的文件名安全化：只保留字母数字下划线连字符（小写），空则回退 "report"。
## save()/save_text() 共用收口，防止含 / 或 .. 的 id 写出 reports 目录。
static func _safe_id(entry_id: String) -> String:
	var id_part := entry_id if not entry_id.strip_edges().is_empty() else "report"
	var chars := id_part.to_lower()
	var safe := ""
	for c: String in chars.split(""):
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_" or c == "-":
			safe += c
	return "report" if safe.is_empty() else safe

## 限差检核行（ok_limit + f_*/limit_*/rel_*/basis 键，§5 规则③）
static func _limits_lines(result: Dictionary) -> Array:
	var value: Dictionary = result.get("value", {})
	if not value.has("ok_limit"):
		return []
	var out := []
	var ok := bool(value["ok_limit"])
	out.append("结论：%s" % ("通过" if ok else "超限"))
	for k: String in value.keys():
		if GKCalculatorBase.is_limit_key(k) and k != "ok_limit":
			out.append("%s = %s" % [k, _fmt(value[k])])
	return out

static func _md_cell(s: String) -> String:
	# Markdown 表格内竖线转义 + 换行压平
	return s.replace("|", "\\|").replace("\n", " ⏎ ")

static func _fmt(v: Variant) -> String:
	if v is float or v is int:
		var f := float(v)
		if is_finite(f):
			if is_zero_approx(f):
				f = 0.0  # 清洗 "-0"：与结果卡口径一致（calculator_base._format_num）
			if f != 0.0 and absf(f) < 1.0e-9:
				return String.num_scientific(f)  # 极小值防「0.000000」假零
			# 报告 6 位定点（比结果卡默认 4 位多 2 位备复核），尾零补齐对齐表格列
			return "%.*f" % [6, f]
	return str(v)

static func _now_tuple() -> Array:
	var d := Time.get_datetime_dict_from_system()
	return [d.year, d.month, d.day, d.hour, d.minute, d.second]

static func _now_text() -> String:
	var t := _now_tuple()
	return "%04d-%02d-%02d %02d:%02d:%02d" % [t[0], t[1], t[2], t[3], t[4], t[5]]
