# core/adjustment/tolerance.gd —— GK-M6-4 限差检核（C8：用户自输限差模式 + 限差表查表模式）
#
# 设计约定（docs/ARCHITECTURE.md §4 GK-M6 / §5 协议 / §0 落地补 #2）：
#   - ⚠ 诚实声明：data/tolerance.json 目前为占位空表（GB 50026 等规范限差未逐条核读，
#     不伪造标准值）。本模块提供两种模式：
#       1) 用户自输限差（check_scalar / check_relative / √n·k、√L·k 公式推算助手）——当前主用；
#       2) 限差表查表（lookup_table）——app 层读 data/tolerance.json 后整表传入，
#          查不到即返回中文提示"未收录，请改用自输限差"，绝不编造限差；
#   - 超限不是计算失败：ok=true 且 value.ok_limit=false（§5 规则③）；只有输入非法才 ok=false；
#   - 超限提示必须含"限差值/实际值/依据"三要素（basis 字段 + steps 明细）；
#   - 全部静态函数、零引擎依赖。
class_name GKAdjustTolerance
extends RefCounted

## 标量双侧限差检核（如角度闭合差 fβ、高差闭合差 fh）
## p = {name: 检核项中文, actual: 实际值, limit: 双侧限差（±）, basis: 依据文本,
##      unit?: 单位文本（"″"/"mm" 等，仅展示用）}
## value: {f_actual, limit_value, ok_limit, basis}
static func check_scalar(p: Dictionary) -> Dictionary:
	if not p.has("name") or String(p["name"]).is_empty():
		return _fail("缺少检核项名称 name")
	if not p.has("actual") or not _finite_num(p.get("actual")):
		return _fail("缺少实际值 actual（数值）")
	if not p.has("limit") or not _finite_num(p.get("limit")) or float(p["limit"]) < 0.0:
		return _fail("缺少非负限差 limit（双侧 ±，数值）")
	var name := String(p["name"])
	var actual := float(p["actual"])
	var limit := absf(float(p["limit"]))
	var unit := String(p.get("unit", ""))
	var basis := String(p.get("basis", "用户输入限差"))
	if basis.is_empty():
		basis = "用户输入限差"
	var ok := absf(actual) <= limit
	var value := {
		"f_actual": actual,
		"limit_value": limit,
		"ok_limit": ok,
		"basis": basis,
	}
	var verdict := "通过" if ok else "超限"
	var steps := [
		{
			"title": "1. 限差检核（%s）" % name,
			"formula": "|实际值| ≤ 限差 → 通过；否则超限",
			"substitution": "|%s| = %s %s，限差 ±%s %s" % [name, _fmt(absf(actual)), unit, _fmt(limit), unit],
			"result": "%s（依据：%s）" % [verdict, basis],
		},
	]
	if not ok:
		steps.append({
			"title": "2. 超限提示",
			"formula": "超限三要素：实际值 / 限差值 / 依据",
			"substitution": "实际 %s %s > 限差 %s %s" % [_fmt(actual), unit, _fmt(limit), unit],
			"result": "请复核观测与已知数据；如需规范限差请先核读 GB 50026 等并填入 data/tolerance.json",
		})
	return _ok(value, steps, "限差检核：%s（%s 模式）" % [name, basis])

## 相对精度限差检核（如导线相对闭合差 1/k：实际 k ≥ 限差 k 即通过）
## p = {name, actual_k: 实际分母 k, limit_k: 限差分母 k, basis?}
## value: {rel_actual_k, rel_limit_k, ok_limit, basis}
static func check_relative(p: Dictionary) -> Dictionary:
	if not p.has("actual_k") or not _finite_num(p.get("actual_k")) or float(p["actual_k"]) <= 0.0:
		return _fail("缺少正的 actual_k（相对闭合差分母，如 1/2000 中的 2000）")
	if not p.has("limit_k") or not _finite_num(p.get("limit_k")) or float(p["limit_k"]) <= 0.0:
		return _fail("缺少正的 limit_k（限差分母）")
	var name := String(p.get("name", "相对闭合差"))
	var actual_k := float(p["actual_k"])
	var limit_k := float(p["limit_k"])
	var basis := String(p.get("basis", "用户输入限差"))
	if basis.is_empty():
		basis = "用户输入限差"
	var ok := actual_k >= limit_k
	var value := {
		"rel_actual_k": actual_k,
		"rel_limit_k": limit_k,
		"ok_limit": ok,
		"basis": basis,
	}
	var steps := [
		{
			"title": "1. 相对精度限差检核（%s）" % name,
			"formula": "实际 1/k_actual ≥ 1/k_limit → 通过（k 越大精度越高）",
			"substitution": "实际 1/%s，限差 1/%s" % [_fmt(actual_k), _fmt(limit_k)],
			"result": ("通过" if ok else "超限") + "（依据：%s）" % basis,
		},
	]
	return _ok(value, steps, "相对精度限差检核：%s" % name)

## 角度闭合差限差公式推算：限差 = k·√n（k 为用户输入的测角推算系数，n 为角数）
## ⚠ k 不是规范值：本函数只做纯数学推算，系数来源与限差依据由调用方如实标注
static func angle_limit_sqrt_n(p: Dictionary) -> Dictionary:
	if not p.has("k_coef") or not _finite_num(p.get("k_coef")) or float(p["k_coef"]) <= 0.0:
		return _fail("缺少正的 k_coef（测角推算系数，用户输入）")
	if not p.has("n") or not _finite_num(p.get("n")) or int(p["n"]) < 1:
		return _fail("缺少正整数 n（转折角个数）")
	var k_coef := float(p["k_coef"])
	var n := int(p["n"])
	var limit := k_coef * sqrt(float(n))
	return _ok({"limit_value": limit, "k_coef": k_coef, "n": n}, [
		{
			"title": "1. 角度闭合差限差推算",
			"formula": "限差 = k·√n（纯数学推算；k 由用户输入，非规范值）",
			"substitution": "k = %s，n = %d" % [_fmt(k_coef), n],
			"result": "限差 = %s″" % _fmt(limit),
		},
	], "角度限差推算 k·√n（系数来源由用户声明）")

## 高差闭合差限差公式推算：限差 = k·√L（L 为路线长 km，k 为用户输入系数，单位 mm）
## ⚠ k 不是规范值：本函数只做纯数学推算，系数来源与限差依据由调用方如实标注
static func level_limit_sqrt_l(p: Dictionary) -> Dictionary:
	if not p.has("k_coef") or not _finite_num(p.get("k_coef")) or float(p["k_coef"]) <= 0.0:
		return _fail("缺少正的 k_coef（每公里推算系数 mm，用户输入）")
	if not p.has("L_km") or not _finite_num(p.get("L_km")) or float(p["L_km"]) <= 0.0:
		return _fail("缺少正的 L_km（路线长）")
	var k_coef := float(p["k_coef"])
	var l_km := float(p["L_km"])
	var limit := k_coef * sqrt(l_km)
	return _ok({"limit_value": limit, "k_coef": k_coef, "L_km": l_km}, [
		{
			"title": "1. 高差闭合差限差推算",
			"formula": "限差 = k·√L_km（mm；纯数学推算；k 由用户输入，非规范值）",
			"substitution": "k = %s mm，L = %s km" % [_fmt(k_coef), _fmt(l_km)],
			"result": "限差 = %s mm" % _fmt(limit),
		},
	], "水准限差推算 k·√L（系数来源由用户声明）")

## 限差表查表模式：table 为 app 层读入的 data/tolerance.json 的 tolerances 数组
## p = {table: Array, kind: 条目类型, level: 等级}
## 命中返回条目（limit_value/limit_formula/basis 原样透传）；查不到返回 ok=false 中文提示。
## ⚠ 当前 data/tolerance.json 为占位空表（规范未核读），实际调用会走"未收录"分支。
static func lookup_table(p: Dictionary) -> Dictionary:
	var table: Variant = p.get("table")
	var kind := String(p.get("kind", ""))
	var level := String(p.get("level", ""))
	if not (table is Array):
		return _fail("缺少限差表 table（app 层读入 data/tolerance.json 的 tolerances 数组）")
	if kind.is_empty() or level.is_empty():
		return _fail("缺少 kind（限差类别）或 level（等级）")
	for e_v in table:
		if not (e_v is Dictionary):
			continue
		var e: Dictionary = e_v
		if String(e.get("kind", "")) == kind and String(e.get("level", "")) == level:
			return _ok({
				"entry_kind": kind,
				"entry_level": level,
				"limit_value": e.get("limit_value", NAN),
				"limit_formula": String(e.get("limit_formula", "")),
				"basis": String(e.get("basis", "")),
				"ok_limit": is_finite(float(e.get("limit_value", NAN))),
			}, [
				{
					"title": "1. 限差表查表",
					"formula": "按 kind + level 在 data/tolerance.json 中精确匹配",
					"substitution": "kind = %s，level = %s" % [kind, level],
					"result": "命中（依据：%s）" % String(e.get("basis", "未注明")),
				},
			], "限差表查表（data/tolerance.json 驱动）")
	return _fail("限差表未收录类别 %s / 等级 %s：当前 data/tolerance.json 为占位空表（规范限差未核读），请改用自输限差模式（check_scalar/check_relative），或在核读 GB 50026 等规范后补入数据" % [kind, level])

# ---------- 内部 ----------

static func _finite_num(v) -> bool:
	if not (v is float or v is int):
		return false
	return is_finite(float(v))

static func _fmt(v: float) -> String:
	if not is_finite(v):
		if v > 0.0:
			return "+∞"
		elif v < 0.0:
			return "−∞"
		return "NaN"
	return "%.6f" % v

static func _ok(value: Dictionary, steps: Array, formula: String) -> Dictionary:
	return {"ok": true, "value": value, "steps": steps, "formula": formula, "error": ""}

static func _fail(error: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": error}
