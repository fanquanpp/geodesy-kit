# scenes/calculators/projection/zone_query.gd —— a5_zone_query 带号/中央子午线查询（A5）
# 计算器契约：继承 GKCalculatorBase（经 proj_calc_base），run() 返回 §5 协议。
extends "res://scenes/calculators/projection/proj_calc_base.gd"

const _ZN := preload("res://core/projection/zones.gd")

func get_title() -> String:
	return "带号/中央子午线查询（A5）"

func get_description() -> String:
	return "由经度给出 3°/6° 带号、中央子午线、y 带号前缀规则与 CGCS2000 的 EPSG 码。"

func _setup() -> void:
	_add_row("经度 L（°）", "lon_deg", "如 116.3913", true)

func run() -> Dictionary:
	var p := _fail_or(_params())
	if bool(p.get("ok", true)) == false and p.has("error"):
		return p
	var lon_text := String(p.get("lon_deg", ""))
	if not lon_text.is_valid_float():
		return {"ok": false, "value": {}, "steps": [], "formula": "分带查询", "error": "经度不是有效数字（十进制度）"}
	var lon := lon_text.to_float()
	var q := _ZN.query(lon)
	if q.is_empty():
		return {"ok": false, "value": {}, "steps": [], "formula": "分带查询", "error": "经度超出范围（|L| ≤ 180°）"}
	var z6 := int(q["zone6"])
	var z3 := int(q["zone3"])
	var epsg_line := "%d（6°带%d带前缀）/ %d（6°带%d自然y）/ %d（3°带%d带前缀）/ %d（3°带%d自然y）" % [
		_ZN.epsg_of("CGCS2000", "6", z6, true), z6, _ZN.epsg_of("CGCS2000", "6", z6, false), z6,
		_ZN.epsg_of("CGCS2000", "3", z3, true), z3, _ZN.epsg_of("CGCS2000", "3", z3, false), z3]
	var value := {
		"lon_deg": lon,
		"zone6": z6, "l0_6_deg": q["l0_6"],
		"zone3": z3, "l0_3_deg": q["l0_3"],
		"band3_valid": bool(q["band3_valid"]),
		"y_prefix_rule": "y通用 = 带号×10^6 + 500km + 自然y",
		"epsg_cgcs2000": epsg_line,
	}
	var steps := [{"title": "1. 分带归属", "formula": "6°带 n=floor(L/6)+1（L0=6n−3）；3°带 n=floor(L/3+0.5)（L0=3n）",
		"substitution": "L=%.6f" % lon,
		"result": "6°带 %d（L0=%.1f°）；3°带 %d（L0=%.1f°）" % [z6, float(q["l0_6"]), z3, float(q["l0_3"])]}]
	return {"ok": true, "value": value, "steps": steps,
			"formula": "高斯投影分带（中国惯例；EPSG 码经 pyproj 官方数据库核读）", "error": ""}