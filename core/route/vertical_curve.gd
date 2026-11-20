# core/route/vertical_curve.gd —— GK-M7-5 竖曲线 D3（对称抛物线）
#
# 设计约定（docs/ARCHITECTURE.md §4 GK-M7 / §5）：
#   - 二次抛物线竖曲线（坡差小、可视为曲率均匀）：
#       y(x) = y_BVC + g1·x + (g2−g1)·x²/(2L)，x 自 BVC 起，坡度 i 以小数计；
#       BVC 桩号 = PVI − L/2，高程 = PVI高程 − g1·L/2；EVC 高程 = PVI高程 + g2·L/2；
#       外距 E = L·(g2−g1)/8（带符号：凸形为负，凹形为正）；
#       K = L/|g2−g1|（每 1% 坡差所需曲线长，输出参考量）；
#   - 权威向量【构造·本会话】：g1=+3%、g2=−2%、L=400、PVI(1000,100)→
#       BVC(800, 94.000)、EVC 高程 96.000、中点 97.5000、E=−2.500、桩900=96.3750；
#   - 校验失败 ok=false + 中文 error（L>0、查询桩号须在竖曲线范围内等）。
class_name GKVerticalCurve
extends RefCounted

## 纯核：x（自 BVC 起）处设计高程
static func elev_at(x: float, bvc_elev: float, g1: float, g2: float, l_len: float) -> float:
	if not (is_finite(x) and is_finite(bvc_elev) and is_finite(g1) and is_finite(g2) and is_finite(l_len)) \
			or l_len <= 0.0:
		return NAN
	return bvc_elev + g1 * x + (g2 - g1) * x * x / (2.0 * l_len)

## D3 协议入口。p = { g1_pct, g2_pct, l_m, pvi_chain_m, pvi_elev_m, stakes_m?=[...] }
## value = { bvc_chain_m, bvc_elev_m, evc_chain_m, evc_elev_m, pvi_elev_m,
##           mid_elev_m, e_m, k_m_per_pct, stakes_m, elevs_m }
static func forward(p: Dictionary) -> Dictionary:
	var g1 := _num(p.get("g1_pct", NAN))
	var g2 := _num(p.get("g2_pct", NAN))
	var l_len := _num(p.get("l_m", NAN))
	var pvic := _num(p.get("pvi_chain_m", NAN))
	var pvie := _num(p.get("pvi_elev_m", NAN))
	if is_nan(g1) or is_nan(g2) or is_nan(l_len) or is_nan(pvic) or is_nan(pvie):
		return _err("输入缺失：g1_pct、g2_pct、l_m、pvi_chain_m、pvi_elev_m 均须为数字")
	if l_len <= 0.0:
		return _err("竖曲线长 L 必须大于 0（当前 %s m）" % str(l_len))
	if absf(g1) > 100.0 or absf(g2) > 100.0:
		return _err("纵坡 %% 应在 ±100%% 以内（当前 g1=%s%%，g2=%s%%）" % [str(g1), str(g2)])
	var g1f := g1 / 100.0
	var g2f := g2 / 100.0
	var bvc_chain := pvic - l_len / 2.0
	var bvc_elev := pvie - g1f * l_len / 2.0
	var evc_chain := pvic + l_len / 2.0
	var evc_elev := pvie + g2f * l_len / 2.0
	var mid_elev := elev_at(l_len / 2.0, bvc_elev, g1f, g2f, l_len)
	var e_ext := l_len * (g2f - g1f) / 8.0
	var dg := absf(g2f - g1f)
	var k_val := l_len / (dg * 100.0)  # 每 1% 坡差曲线长（m）
	var shape := "凸形" if (g2f - g1f) < 0.0 else ("凹形" if (g2f - g1f) > 0.0 else "坡度不变（直线）")
	var value := {
		"bvc_chain_m": bvc_chain, "bvc_elev_m": bvc_elev,
		"evc_chain_m": evc_chain, "evc_elev_m": evc_elev,
		"pvi_chain_m": pvic, "pvi_elev_m": pvie,
		"mid_elev_m": mid_elev,
		"e_m": e_ext,
		"k_m_per_pct": k_val,
		"shape": shape,
		"l_m": l_len,
	}
	var steps := [
		{"title": "1. 竖曲线起点 BVC / 终点 EVC",
			"formula": "BVC桩号 = PVI − L/2；BVC高程 = PVI高程 − g1·L/2；EVC高程 = PVI高程 + g2·L/2",
			"substitution": "PVI(%s, %s)，g1=%s%%，g2=%s%%，L=%s m" % [String.num(pvic, 3), String.num(pvie, 3), String.num(g1, 3), String.num(g2, 3), String.num(l_len, 3)],
			"result": "BVC(%s, %.4f)，EVC(%s, %.4f)" % [String.num(bvc_chain, 3), bvc_elev, String.num(evc_chain, 3), evc_elev]},
		{"title": "2. 曲线中点高程与外距 E",
			"formula": "y(x) = y_BVC + g1·x + (g2−g1)x²/(2L)；E = L·(g2−g1)/8",
			"substitution": "x = L/2 = %s m" % String.num(l_len / 2.0, 3),
			"result": "中点高程 %.4f m；E = %.4f m（%s，凸为负/凹为正）" % [mid_elev, e_ext, shape]},
	]
	# 查询桩号
	var stakes := PackedFloat64Array()
	var elevs := PackedFloat64Array()
	var q_in: Variant = p.get("stakes_m", [])
	if q_in is Array and not (q_in as Array).is_empty():
		var idx := 1
		for q in q_in as Array:
			var qf := _num(q)
			if is_nan(qf):
				return _err("stakes_m 含非数字桩号：%s" % str(q))
			if qf < bvc_chain - 1e-9 or qf > evc_chain + 1e-9:
				return _err("查询桩号 %s 超出竖曲线范围 [%s, %s]" % [str(qf), String.num(bvc_chain, 3), String.num(evc_chain, 3)])
			var x := qf - bvc_chain
			var ez := elev_at(x, bvc_elev, g1f, g2f, l_len)
			stakes.append(qf)
			elevs.append(ez)
			if idx <= 3:
				steps.append({"title": "%d. 桩号 %s 设计高程" % [steps.size() + 1, String.num(qf, 3)],
					"formula": "y = y_BVC + g1·x + (g2−g1)·x²/(2L)",
					"substitution": "x = 桩号 − BVC = %s m" % String.num(x, 4),
					"result": "%.4f m" % ez})
			idx += 1
	value["stakes_m"] = stakes
	value["elevs_m"] = elevs
	return {"ok": true, "value": value, "steps": steps,
			"formula": "对称二次抛物线竖曲线：y = y_BVC + g1·x + (g2−g1)·x²/(2L)（坡度以小数代入；曲率均匀近似在坡差小时成立）",
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
