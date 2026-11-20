# scenes/calculators/route/ui_common.gd —— M7 计算器 UI 公共解析工具（route 域私有）
#
# 职责：把 LineEdit 文本解析为 core 可接受的输入；解析失败一律返回"可被 core
# 中文校验识别"的形式（NAN / 空数组），不在 UI 层抛错崩溃；量级小、纯静态。
extends RefCounted

## 单值文本 → float（空/非法 → NAN，由 core 统一给中文错误）
static func to_f(text: String) -> float:
	var t := text.strip_edges()
	if t.is_empty() or not t.is_valid_float():
		return NAN
	return t.to_float()

## 单值文本 → float；空文本返回 default（可选字段）
static func to_f_or(text: String, default: float) -> float:
	var t := text.strip_edges()
	if t.is_empty():
		return default
	return to_f(t)

## 列表文本 → Array[String]（分隔符：逗号/分号/空白/中文逗号），空元素剔除
static func to_list(text: String) -> Array:
	var t := text.strip_edges()
	if t.is_empty():
		return []
	var normalized := t.replace("，", ",").replace("；", ";")
	normalized = normalized.replace(",", " ").replace(";", " ").replace("\t", " ")
	while "  " in normalized:
		normalized = normalized.replace("  ", " ")
	return normalized.split(" ", false)

## 键值列表文本（"a=b" 或 "a=b,c=d; ..."）→ Array[Dictionary]
## 每项含 missing 键列表（供 UI 中文报错）；失败项被跳过并在 error 中说明。
static func to_kv_rows(text: String, keys: Array) -> Dictionary:
	var rows := []
	var errors := PackedStringArray()
	var raw := to_list_multi(text, ";")
	for i in raw.size():
		var parts := to_list(raw[i])
		if parts.is_empty():
			continue
		if parts.size() != keys.size():
			errors.append("第 %d 行应为 %d 个值（%s），实际 %d 个" % [i + 1, keys.size(), "，".join(keys), parts.size()])
			continue
		var row := {}
		for k in keys.size():
			row[keys[k]] = parts[k]
		rows.append(row)
	return {"rows": rows, "errors": errors}

## 按给定分隔符切分的列表（保留空段剔除），用于多行/分号结构
static func to_list_multi(text: String, sep: String) -> Array:
	var t := text.strip_edges().replace("；", sep)
	if t.is_empty():
		return []
	var out := []
	for part in t.split(sep, false):
		var p := part.strip_edges()
		if not p.is_empty():
			out.append(p)
	return out

## 二维网格文本（每行空格/逗号分隔，行间分号）→ Array[Array[String]]
static func to_grid(text: String) -> Array:
	var rows := to_list_multi(text, ";")
	var out := []
	for r: String in rows:
		var vals := to_list(r)
		if not vals.is_empty():
			out.append(vals)
	return out
