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

## 渲染 Markdown 报告。title=计算器名；inputs=输入快照；result=§5 协议结果。
static func render_markdown(title: String, entry_id: String, inputs: Dictionary, result: Dictionary) -> String:
	var L: Array[String] = []
	L.append("# %s" % title)
	L.append("")
	L.append("- 时间：%s" % _now_text())
	L.append("- 条目：%s" % (entry_id if not entry_id.is_empty() else "（未登记）"))
	L.append("- 引擎：%s" % Engine.get_version_info().get("string", "Godot"))
	L.append("")
	# 输入回显表
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
	if not formula.is_empty():
		L.append("## 使用公式")
		L.append("")
		L.append(formula)
		L.append("")
	# 步骤四列表格（§5 规则②：title/formula/substitution/result）
	var steps: Array = result.get("steps", [])
	if not steps.is_empty():
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
		if not value.is_empty():
			L.append("## 结果")
			L.append("")
			L.append("| 量 | 值 |")
			L.append("| --- | --- |")
			for k: String in value.keys():
				L.append("| %s | %s |" % [_md_cell(k), _md_cell(_fmt(value[k]))])
			L.append("")
		var lim := _limits_lines(result)
		if not lim.is_empty():
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

## 纯文本版：同构去表格线。
static func render_text(title: String, entry_id: String, inputs: Dictionary, result: Dictionary) -> String:
	var md := render_markdown(title, entry_id, inputs, result)
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
static func save(title: String, entry_id: String, inputs: Dictionary, result: Dictionary) -> Dictionary:
	var md := render_markdown(title, entry_id, inputs, result)
	var stamp := "%04d%02d%02d_%02d%02d%02d" % _now_tuple()
	var rel := "%s/%s_%s.md" % [DIR, _safe_id(entry_id), stamp]
	if not GKFileIO.write_text(rel, md):
		return {"ok": false, "path": "", "text_path": "", "error": "报告写入失败：%s" % ProjectSettings.globalize_path(rel)}
	var abs := ProjectSettings.globalize_path(rel)
	return {"ok": true, "path": abs, "rel_path": rel,
			"text_path": "", "error": ""}

## 另存为纯文本（可选）。返回 {ok, path, error}。
static func save_text(title: String, entry_id: String, inputs: Dictionary, result: Dictionary) -> Dictionary:
	var txt := render_text(title, entry_id, inputs, result)
	var stamp := "%04d%02d%02d_%02d%02d%02d" % _now_tuple()
	# 文件名安全化与 save() 同一收口：含 / 或 .. 的 id 不得写出 reports 目录
	var rel := "%s/%s_%s.txt" % [DIR, _safe_id(entry_id), stamp]
	if not GKFileIO.write_text(rel, txt):
		return {"ok": false, "path": "", "error": "报告写入失败：%s" % ProjectSettings.globalize_path(rel)}
	return {"ok": true, "path": ProjectSettings.globalize_path(rel), "rel_path": rel, "error": ""}

# ---------- 内部 ----------

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
		if k.begins_with("f_") or k.begins_with("limit_") or k.begins_with("rel_") or k == "basis":
			out.append("%s = %s" % [k, _fmt(value[k])])
	return out

static func _md_cell(s: String) -> String:
	# Markdown 表格内竖线转义 + 换行压平
	return s.replace("|", "\\|").replace("\n", " ⏎ ")

static func _fmt(v: Variant) -> String:
	if v is float or v is int:
		var f := float(v)
		if is_finite(f):
			return String.num(f, 6)
	return str(v)

static func _now_tuple() -> Array:
	var d := Time.get_datetime_dict_from_system()
	return [d.year, d.month, d.day, d.hour, d.minute, d.second]

static func _now_text() -> String:
	var t := _now_tuple()
	return "%04d-%02d-%02d %02d:%02d:%02d" % [t[0], t[1], t[2], t[3], t[4], t[5]]
