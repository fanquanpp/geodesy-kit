# core/earthwork/plumb.gd —— GK-M7-14 垂直度 E5
#
# 顶部相对底部水平偏移 (dx,dy)：总偏移=√(dx²+dy²)；倾斜率=总偏移/H；N=H/总偏移；θ=arctan(偏移/H)。
# 限差一律由用户输入（H/1000 或直接给 mm 偏移），不内置规范表（JGJ/T 8 因构件而异，与 C8 同口径）；
# ok_limit=总偏移 ≤ 限差偏移。
# 构造向量（自洽）：H=50、dx=0.04、dy=0.03 → 总偏移 0.0500、倾斜率 1/1000、θ=0.0573°。
# 校验失败 ok=false + 中文 error（H>0、dx/dy/限差合法）。
class_name GKPlumb
extends RefCounted

## E5 协议入口。p = { h_m, dx_m=0, dy_m=0, limit_den?(如1000 表示 H/1000),
##                    limit_offset_mm?(直接给限差偏移) }
## value = { offset_m, offset_mm, dx_m, dy_m, ratio, one_over_n, angle_deg,
##           ok_limit?, limit_offset_mm?, basis? }
static func forward(p: Dictionary) -> Dictionary:
	var h := _num(p.get("h_m", NAN))
	var dx := _num(p.get("dx_m", 0.0)) if p.has("dx_m") else 0.0
	var dy := _num(p.get("dy_m", 0.0)) if p.has("dy_m") else 0.0
	if is_nan(h) or is_nan(dx) or is_nan(dy):
		return _err("输入缺失：h_m（高度）、dx_m/dy_m（顶部水平偏移，默认 0）均须为数字")
	if h <= 0.0:
		return _err("高度 h_m 必须大于 0")
	var offset := sqrt(dx * dx + dy * dy)
	var ratio := offset / h
	var one_over_n := 0.0 if offset < 1e-15 else h / offset
	var adeg := rad_to_deg(atan2(offset, h))
	var value := {
		"h_m": h,
		"dx_m": dx, "dy_m": dy,
		"offset_m": offset,
		"offset_mm": offset * 1000.0,
		"ratio": ratio,
		"one_over_n": one_over_n,
		"angle_deg": adeg,
	}
	var lim_txt := ""
	var has_limit := false
	var limit_offset := NAN
	if p.has("limit_den"):
		var den := _num(p["limit_den"])
		if is_nan(den) or den <= 0.0:
			return _err("limit_den 须为正数（如输入 1000 表示限差 H/1000）")
		limit_offset = h / den
		has_limit = true
		lim_txt = "H/%d" % int(den) if den == floorf(den) else "H/%.4f" % den
	elif p.has("limit_offset_mm"):
		limit_offset = _num(p["limit_offset_mm"]) / 1000.0
		if is_nan(limit_offset) or limit_offset <= 0.0:
			return _err("limit_offset_mm 须为正数限差偏移（mm）")
		has_limit = true
		lim_txt = "%s mm" % String.num(limit_offset * 1000.0, 4)
	if has_limit:
		value["limit_offset_m"] = limit_offset
		value["ok_limit"] = offset <= limit_offset
		value["basis"] = "限差 %s（用户输入）" % lim_txt
	var steps := [
		{"title": "1. 总水平偏移",
			"formula": "δ = √(dx² + dy²)",
			"substitution": "√(%.4f² + %.4f²)" % [dx, dy],
			"result": "%.4f m（%.2f mm）" % [offset, offset * 1000.0]},
		{"title": "2. 倾斜率与倾角",
			"formula": "倾斜率 = δ/H；1/N：N = H/δ；θ = arctan(δ/H)",
			"substitution": "δ=%.4f m，H=%.4f m" % [offset, h],
			"result": "倾斜率 %.6f（≈1/%s），θ = %.6f°" % [ratio, String.num(one_over_n, 2) if one_over_n > 0.0 else "∞", adeg]},
	]
	if has_limit:
		var ok := bool(value["ok_limit"])
		steps.append({"title": "3. 限差检核",
			"formula": "δ ≤ 限差偏移 → 合格",
			"substitution": "δ = %.4f m，限差 %s" % [offset, lim_txt],
			"result": "合格（δ ≤ 限差）" if ok else "超限（δ > 限差 %s）" % lim_txt})
	return {"ok": true, "value": value, "steps": steps,
			"formula": "垂直度检核：总偏移 δ=√(dx²+dy²)，倾斜率=δ/H（1/N 表达），倾角 θ=arctan(δ/H)；限差由用户输入（规范限值因构件而异）",
			"error": ""}

# ---------- 内部工具 ----------

static func _num(v: Variant) -> float:
	if v is float or v is int:
		return float(v)
	if v is String:
		var t := String(v).strip_edges()
		if t.is_valid_float():
			return t.to_float()
	return NAN

static func _err(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": msg}
