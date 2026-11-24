# core/route/segment_link.gd —— GK-M7-7 超高/加宽/断链 D5
#
# 超高/加宽：对称基本型曲线上的线性过渡（教学口径；生产规范 JTG D20 含渐变率，formula 尾注注明）：
# 进口 [0,l0] 线性升、圆曲线段满值、出口 [L−l0,L] 线性降（自 ZH 起算）。
# 断链值 Δ=b−a：Δ<0 长链（桩号重复）、Δ>0 短链（桩号跳过）；实际里程=设计里程+Σ(a_i−b_i)（已越过者）；
# 断链前后桩号两点实际里程相等（同一位置），往返换算闭合（测试覆盖）；断链表须按桩号单调不交错。
# 校验失败 ok=false + 中文 error。
class_name GKSegmentLink
extends RefCounted

const Cur := preload("res://core/route/curve_elements.gd")

# ---------- 断链 ----------

## 断链双向换算。p = { breaks:[{before_chain_m, after_chain_m},...],
##                    chains_m:[...], direction:"d2a"(默认)|"a2d" }
## value = { chains_in_m, chains_out_m, shifts_m, break_count,
##           breaks:[{before_chain_m, after_chain_m, delta_m, shift_m, kind}] }
## 区域表模型：断链把里程线分成若干"修正区"，区内里程平移量恒定；
##   长链时前后桩号区间重复（[b_i, a_i]），换算约定取首次出现（断链前）区域。
static func chain_convert(p: Dictionary) -> Dictionary:
	var breaks_in: Variant = p.get("breaks", [])
	if not (breaks_in is Array) or (breaks_in as Array).is_empty():
		return _err("breaks 须为非空断链数组：[{before_chain_m, after_chain_m}, ...]")
	var breaks := []
	for b in breaks_in as Array:
		if not (b is Dictionary):
			return _err("breaks 元素须为对象 {before_chain_m, after_chain_m}")
		var a := _num((b as Dictionary).get("before_chain_m", NAN))
		var bb := _num((b as Dictionary).get("after_chain_m", NAN))
		if is_nan(a) or is_nan(bb):
			return _err("断链桩号 before_chain_m / after_chain_m 须为数字")
		if a == bb:
			return _err("断链前后桩号相同（%s），不构成断链" % str(a))
		breaks.append({"a": a, "b": bb, "s": a - bb})
	var direction := String(p.get("direction", "d2a"))
	if direction != "d2a" and direction != "a2d":
		return _err("direction 只能取 d2a（设计→实际）或 a2d（实际→设计）")
	var chains_in: Variant = p.get("chains_m", [])
	if not (chains_in is Array) or (chains_in as Array).is_empty():
		return _err("chains_m 须为非空里程数组（m）")
	var chains := []
	for c in chains_in as Array:
		var cf := _num(c)
		if is_nan(cf):
			return _err("chains_m 含非数字里程：%s" % str(c))
		chains.append(cf)
	# 排序与非交错校验（前后桩号均须严格递增，且相邻断链间物理段长为正：a_{i+1} > b_i）
	var sorted_br := breaks.duplicate(true)
	sorted_br.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return float(x["b"]) < float(y["b"]))
	for i in range(1, sorted_br.size()):
		if float(sorted_br[i]["b"]) <= float(sorted_br[i - 1]["b"]) \
				or float(sorted_br[i]["a"]) <= float(sorted_br[i - 1]["a"]) \
				or float(sorted_br[i]["a"]) <= float(sorted_br[i - 1]["b"]):
			return _err("断链表桩号重合或交错（第 %d 处），请检查输入" % (i + 1))
	var n_br := sorted_br.size()
	# —— 实际帧断点位置 A_i（同一物理点的实际里程）：A_i = a_i + Σ_{j<i}s_j ——
	var a_pts := PackedFloat64Array()
	var acc0 := 0.0
	for i in n_br:
		a_pts.append(float(sorted_br[i]["a"]) + acc0)
		acc0 += float(sorted_br[i]["s"])
	# —— 设计帧区域表（d2a 用）：R_0=(−∞, a_1] 修正 0；R_i=[b_i, a_{i+1}] 修正 Σ_{j≤i}s_j ——
	var d_regions := []
	var acc := 0.0
	d_regions.append({"lo": -INF, "hi": float(sorted_br[0]["a"]), "shift": 0.0})
	for i in n_br:
		acc += float(sorted_br[i]["s"])
		var hi := INF if i == n_br - 1 else float(sorted_br[i + 1]["a"])
		d_regions.append({"lo": float(sorted_br[i]["b"]), "hi": hi, "shift": acc})
	# —— 实际帧区域表（a2d 用）：S_0=(−∞, A_1] 修正 0；S_i=[A_i, A_{i+1}] 修正 Σ_{j≤i}s_j ——
	var s_regions := []
	s_regions.append({"lo": -INF, "hi": a_pts[0], "shift": 0.0})
	var acc2 := 0.0
	for i in n_br:
		acc2 += float(sorted_br[i]["s"])
		var hi2 := INF if i == n_br - 1 else a_pts[i + 1]
		s_regions.append({"lo": a_pts[i], "hi": hi2, "shift": acc2})
	# —— 逐桩换算 ——
	var out := []
	var shifts := []
	for c0: float in chains:
		var res := NAN
		if direction == "d2a":
			# 精确命中断链桩号（前 a_i 或后 b_i）：同一物理点 → 实际里程 A_i
			for i in n_br:
				if c0 == float(sorted_br[i]["a"]) or c0 == float(sorted_br[i]["b"]):
					res = a_pts[i]
					break
			if is_nan(res):
				# 区域首中即停（长链重复区 [b_i,a_i] 内取首次出现=断链前区域）
				for rg: Dictionary in d_regions:
					if c0 >= float(rg["lo"]) and c0 <= float(rg["hi"]):
						res = c0 + float(rg["shift"])
						break
				if is_nan(res):
					# 落在短链跳过的桩号缺口内：按其后最近区域（断链后）修正量外推
					for rg: Dictionary in d_regions:
						if float(rg["lo"]) > c0:
							res = c0 + float(rg["shift"])
							break
					if is_nan(res):
						res = c0 + float(d_regions[d_regions.size() - 1]["shift"])
		else:
			# 精确命中断点实际里程 A_i → 断链前桩号 a_i（首次出现约定）
			for i in n_br:
				if c0 == a_pts[i]:
					res = float(sorted_br[i]["a"])
					break
			if is_nan(res):
				# 实际→设计：设计 = 实际 − Σs（实际帧区域表存 Σs，取负号）
				for rg: Dictionary in s_regions:
					if c0 >= float(rg["lo"]) and c0 <= float(rg["hi"]):
						res = c0 - float(rg["shift"])
						break
				if is_nan(res):
					res = c0 - float(s_regions[s_regions.size() - 1]["shift"])
		out.append(res)
		shifts.append(res - c0)
	var br_rows := []
	for br: Dictionary in sorted_br:
		var da: float = br["a"]
		var db: float = br["b"]
		var delta := db - da
		br_rows.append({
			"before_chain_m": da, "after_chain_m": db,
			"delta_m": delta,
			"shift_m": -delta,
			"kind": "长链（桩号重复）" if delta < 0.0 else "短链（桩号跳过）",
		})
	return {"ok": true, "value": {
				"chains_in_m": PackedFloat64Array(chains),
				"chains_out_m": PackedFloat64Array(out),
				"shifts_m": PackedFloat64Array(shifts),
				"break_count": br_rows.size(),
				"breaks": br_rows,
				"direction": direction,
			},
			"steps": [{
				"title": "断链换算（%s）" % ("设计→实际" if direction == "d2a" else "实际→设计"),
				"formula": "输出里程 = 输入里程 + 区间修正量 Σ(前桩号−后桩号)，按断链分区取值",
				"substitution": "%d 处断链，%d 个待换算桩号" % [br_rows.size(), chains.size()],
				"result": "首桩 %s → %s" % [String.num(float(chains[0]), 3), String.num(float(out[0]), 3)],
			}],
			"formula": "断链换算：断链值 Δ=后桩号−前桩号（Δ<0 长链/桩号重复，Δ>0 短链/桩号跳过）；对里程的修正量 s=前桩号−后桩号，按分区累计；长链重复桩号区取首次出现",
			"error": ""}

# ---------- 超高 / 加宽 ----------

## 对称基本型曲线上自 ZH 起任意弧长的超高与加宽（线性过渡简化模型）。
## p = { r_m, l0_m, alpha_deg, e_max_pct, w_max_m=0, query_m:[自 ZH 的弧长...] }
## value = { query_m, e_pct:[...], w_m:[...], l0_m, l_m, e_max_pct, w_max_m }
static func superelevation(p: Dictionary) -> Dictionary:
	var r := _num(p.get("r_m", NAN))
	var l0 := _num(p.get("l0_m", NAN))
	var adeg := _num(p.get("alpha_deg", NAN))
	var emax := _num(p.get("e_max_pct", NAN))
	var wmax := _num(p.get("w_max_m", 0.0)) if p.has("w_max_m") else 0.0
	if is_nan(r) or is_nan(l0) or is_nan(adeg) or is_nan(emax) or is_nan(wmax):
		return _err("输入缺失：r_m、l0_m、alpha_deg、e_max_pct（w_max_m 可选）均须为数字")
	if r <= 0.0:
		return _err("半径 R 必须大于 0")
	if l0 < 0.0:
		return _err("缓和曲线长 l0 不能为负")
	if emax < 0.0 or emax > 12.0:
		return _err("超高值 e_max 须在 0~12%% 之间（当前 %s%%）" % str(emax))
	if wmax < 0.0:
		return _err("加宽值 w_max 不能为负")
	var el := Cur.elements(r, l0, deg_to_rad(adeg))
	if el.is_empty():
		return _err("曲线要素计算失败：请检查 R/l0/α（2β0 不得大于 α，α∈(0°,180°)）")
	var l_total: float = el["l_m"]
	var query_in: Variant = p.get("query_m", [])
	if not (query_in is Array) or (query_in as Array).is_empty():
		return _err("query_m 须为非空弧长数组（自 ZH 起，m）")
	var query := []
	for q in query_in as Array:
		var qf := _num(q)
		if is_nan(qf):
			return _err("query_m 含非数字弧长：%s" % str(q))
		if qf < -1e-9 or qf > l_total + 1e-9:
			return _err("弧长 %s m 超出曲线范围 [0, %.4f] m（自 ZH 起）" % [str(qf), l_total])
		query.append(maxf(qf, 0.0))
	var es := PackedFloat64Array()
	var ws := PackedFloat64Array()
	for x: float in query:
		es.append(_trans_value(x, l_total, l0, emax))
		ws.append(_trans_value(x, l_total, l0, wmax))
	return {"ok": true, "value": {
				"query_m": PackedFloat64Array(query),
				"e_pct": es,
				"w_m": ws,
				"l0_m": l0, "l_m": l_total,
				"e_max_pct": emax, "w_max_m": wmax,
				"l_circ_m": float(el["l_circ_m"]),
			},
			"steps": [
				{"title": "1. 曲线全长（B3 要素）",
					"formula": "L = R·α(rad) + l0",
					"substitution": "R=%s，l0=%s，α=%s°" % [String.num(r, 4), String.num(l0, 4), String.num(adeg, 4)],
					"result": "L = %.4f m（圆曲线段 %.4f m）" % [l_total, float(el["l_circ_m"])]},
				{"title": "2. 线性过渡模型取值",
					"formula": "e(x) = e_max·x/l0（进口段）；e_max（全超高端）；e_max·(L−x)/l0（出口段）",
					"substitution": "e_max=%.4f%%，w_max=%.4f m，l0=%.4f m" % [emax, wmax, l0],
					"result": "逐查询弧长输出 e_pct 与 w_m 数组（首点 %.4f%%，末点 %.4f%%）" % [es[0], es[es.size() - 1]]},
			],
			"formula": "超高/加宽线性过渡（教学简化）：全超高端取满值，缓和段内按弧长线性渐变；生产规范（JTG D20）含渐变率与过渡曲线形式，结果页已注明口径",
			"error": ""}

# ---------- 内部工具 ----------

## 过渡取值：进口 [0,l0] 线性升、中段满值、出口 [L−l0,L] 线性降
static func _trans_value(x: float, l_total: float, l0: float, vmax: float) -> float:
	if l0 <= 0.0:
		return vmax  # 无缓和段：整个曲线取满值（教学口径）
	if x <= l0:
		return vmax * x / l0
	if x >= l_total - l0:
		return vmax * (l_total - x) / l0
	return vmax

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
