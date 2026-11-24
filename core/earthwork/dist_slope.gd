# core/earthwork/dist_slope.gd —— GK-M7-13 平距/斜距/高差/坡度换算 E4
#
# 设计约定（docs/ARCHITECTURE.md §4 GK-M7 / §5）：
#   - 关系：斜距² = 平距² + 高差²；坡度 i = Δh/平距（%）；坡度角 θ = atan(Δh/平距)；
#   - 输入四量 {dh_m, d_horiz_m, d_slope_m, slope_pct}（或 slope_deg）中任意两个
#     独立量即可解全部（给定第三个时做一致性校验，容差 1e-6 相对）；
#   - 权威向量【构造·本会话】：Δh=30、平距 500 → 斜距 500.8992、坡度 6.00%；
#   - 校验失败 ok=false + 中文 error（缺独立量、斜距<|高差|、坡度矛盾等）。
class_name GKDistSlope
extends RefCounted

## E4 协议入口。
## p = { dh_m?, d_horiz_m?, d_slope_m?, slope_pct? 或 slope_deg? }（≥2 个独立量）
## value = { dh_m, d_horiz_m, d_slope_m, slope_pct, slope_deg }
static func forward(p: Dictionary) -> Dictionary:
	var dh := _num(p.get("dh_m", NAN))
	var horiz := _num(p.get("d_horiz_m", NAN))
	var slope_d := _num(p.get("d_slope_m", NAN))
	var pct := _num(p.get("slope_pct", NAN))
	var adeg := _num(p.get("slope_deg", NAN))
	if not is_nan(pct) and not is_nan(adeg):
		return _err("slope_pct 与 slope_deg 只需其一（二者等价）")
	if is_nan(pct) and not is_nan(adeg):
		pct = tan(deg_to_rad(adeg)) * 100.0
	# 已知量计数与解算
	var given := 0
	if not is_nan(dh): given += 1
	if not is_nan(horiz): given += 1
	if not is_nan(slope_d): given += 1
	if not is_nan(pct): given += 1
	if given < 2:
		return _err("至少需要两个独立量：dh_m（高差）/ d_horiz_m（平距）/ d_slope_m（斜距）/ slope_pct 或 slope_deg（坡度），当前仅 %d 个" % given)
	# 路径1：高差+平距（最常见；若同时给了斜距，转发做三量一致性校验）
	if not is_nan(dh) and not is_nan(horiz):
		if horiz <= 0.0:
			return _err("平距必须大于 0")
		return _pack(dh, horiz, pct, adeg, slope_d)
	# 路径2：高差+斜距
	if not is_nan(dh) and not is_nan(slope_d):
		if slope_d <= 0.0:
			return _err("斜距必须大于 0")
		if absf(slope_d) < absf(dh):
			return _err("斜距（%s m）必须不小于高差绝对值（%s m）" % [str(slope_d), str(absf(dh))])
		horiz = sqrt(slope_d * slope_d - dh * dh)
		return _pack(dh, horiz, pct, adeg)
	# 路径3：平距+斜距
	if not is_nan(horiz) and not is_nan(slope_d):
		if horiz <= 0.0 or slope_d <= 0.0:
			return _err("平距与斜距都必须大于 0")
		if slope_d < horiz:
			return _err("斜距（%s m）不能小于平距（%s m）" % [str(slope_d), str(horiz)])
		dh = sqrt(slope_d * slope_d - horiz * horiz)
		return _pack(dh, horiz, pct, adeg)
	# 路径4：平距+坡度
	if not is_nan(horiz) and not is_nan(pct):
		if horiz <= 0.0:
			return _err("平距必须大于 0")
		dh = horiz * pct / 100.0
		return _pack(dh, horiz, pct, adeg)
	# 路径5：高差+坡度
	if not is_nan(dh) and not is_nan(pct):
		if pct == 0.0:
			if absf(dh) > 1e-12:
				return _err("坡度为 0% 时高差必须为 0")
			# 零解：Δh=0、坡度 0 → 平距/斜距不定（任意值均满足），返回完整零解并说明
			return _pack(0.0, 0.0, pct, adeg)
		horiz = dh / (pct / 100.0)
		if horiz <= 0.0:
			return _err("解出平距 %s m ≤ 0：请检查高差与坡度符号（坡度符号应与高差一致）" % str(horiz))
		return _pack(dh, horiz, pct, adeg)
	# 路径6：斜距+坡度
	if not is_nan(slope_d) and not is_nan(pct):
		if slope_d <= 0.0:
			return _err("斜距必须大于 0")
		var sf := pct / 100.0
		horiz = slope_d / sqrt(1.0 + sf * sf)
		dh = horiz * sf
		return _pack(dh, horiz, pct, adeg)
	return _err("给定量组合不足（需两个独立量）")

# ---------- 内部工具 ----------

## 组装协议结果；第三/四个已知量存在时做一致性校验（相对容差 1e-6，超差写 warn）。
## 零解特殊情形（Δh=0 且平距=0）：平距为 0 时坡度无定义，斜距取 0（完整零解），不产生 NaN。
static func _pack(dh: float, horiz: float, pct_in: float, _adeg_in: float, slope_d_in := NAN) -> Dictionary:
	var zero_horiz := absf(horiz) < 1e-12
	var pct := 0.0 if zero_horiz else dh / horiz * 100.0
	var slope_d := sqrt(horiz * horiz + dh * dh)
	var adeg := 0.0 if zero_horiz else rad_to_deg(atan2(absf(dh), horiz))
	var warn := ""
	if zero_horiz:
		warn = "；说明：Δh=0 且平距=0 为零解（水平零距离），坡度无定义、斜距取 0"
	if not is_nan(pct_in) and absf(pct_in) > 1e-12:
		if absf(pct_in - pct) > 1e-6 * maxf(absf(pct), 1.0):
			warn += "；注意：输入坡度 %s%% 与由高差/平距解出的 %s%% 存在差异" % [str(pct_in), str(pct)]
	# 一致性校验：高差 + 平距 + 斜距三量自洽（相对容差 1e-6，超差写 warn）
	if not is_nan(slope_d_in) and absf(slope_d_in) > 1e-12:
		if absf(slope_d_in - slope_d) > 1e-6 * maxf(slope_d, 1.0):
			warn += "；注意：输入斜距 %s m 与由高差/平距解出的 %s m 存在差异（三者不一致）" % [str(slope_d_in), str(slope_d)]
	var value := {
		"dh_m": dh,
		"d_horiz_m": horiz,
		"d_slope_m": slope_d,
		"slope_pct": pct,
		"slope_deg": adeg,
	}
	var steps := [
		{"title": "1. 平距与高差 → 斜距",
			"formula": "斜距 = √(平距² + 高差²)",
			"substitution": "√(%.4f² + %.4f²)" % [horiz, dh],
			"result": "%.4f m" % slope_d},
		{"title": "2. 坡度与坡度角",
			"formula": "i = Δh/平距 × 100%；θ = arctan(|Δh|/平距)" + ("（平距为 0 时坡度无定义，取 0）" if zero_horiz else ""),
			"substitution": "%.4f/%.4f" % [dh, horiz],
			"result": "i = %s%%，θ = %s°%s" % [str(pct), str(adeg), warn]},
	]
	return {"ok": true, "value": value, "steps": steps,
			"formula": "平距/斜距/高差/坡度换算：斜距²=平距²+高差²，i=Δh/平距（符号随高差，下坡为负）",
			"error": ""}

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
