# core/earthwork/section_volume.gd —— GK-M7-11 断面法土方 E2（平均断面法）
#
# V=Σ(A_i+A_{i+1})/2·d_i；填挖分列累计，一填一挖按代数和计入净量；
# 双口径输出：net_m3=填−挖、cut_minus_fill_m3=挖−填（互为相反数，供不同习惯核对）。
# 可选棱台式（use_prismoidal）：V=L/6(A₁+4A_m+A₂)，A_m 取相邻断面算术平均（工程近似口径）。
# 权威算例（Python 复核）：A₁=100、A_m=144、A₂=100、L=100 → 棱台 12933.333 m³ vs 平均 10000 m³。
# 构造向量：[10,20,30] m²、间距 [50,50] → V=2000.0 m³；权威向量见 tests/earthwork/。
class_name GKSectionVolume
extends RefCounted

## 纯核：平均断面法逐段体积（PackedFloat64Array，长度 = 段数）。非法返回空。
static func seg_volumes(areas: PackedFloat64Array, dists: PackedFloat64Array) -> PackedFloat64Array:
	var n := areas.size()
	if n < 2 or dists.size() != n - 1:
		return PackedFloat64Array()
	for d in dists:
		if not is_finite(d) or d < 0.0:
			return PackedFloat64Array()
	var out := PackedFloat64Array()
	for i in range(n - 1):
		out.append((areas[i] + areas[i + 1]) * 0.5 * dists[i])
	return out

## 纯核：棱台公式单段体积 V = L/6·(A1 + 4·Am + A2)。非法返回 NAN。
static func frustum_volume(a1: float, am: float, a2: float, l: float) -> float:
	if not (is_finite(a1) and is_finite(am) and is_finite(a2) and is_finite(l)) or l <= 0.0:
		return NAN
	return l / 6.0 * (a1 + 4.0 * am + a2)

## E2 协议入口。p = { chains_m:[...], fill_areas_m2:[...], cut_areas_m2:[]?,
##                     use_prismoidal?: bool（默认 false；true 时启用棱台公式口径） }
## value = { fill_m3, cut_m3, net_m3, cut_minus_fill_m3, frustum_m3?(棱台口径), segments, total_dist_m }
static func forward(p: Dictionary) -> Dictionary:
	var chains_in: Variant = p.get("chains_m", [])
	var fill_in: Variant = p.get("fill_areas_m2", [])
	var cut_in: Variant = p.get("cut_areas_m2", [])
	if not (chains_in is Array) or (chains_in as Array).size() < 2:
		return _err("chains_m 须为 ≥2 个断面桩号（m，严格递增）")
	if not (fill_in is Array) or (fill_in as Array).size() != (chains_in as Array).size():
		return _err("fill_areas_m2 须与 chains_m 等长（各断面填方面积 m²；无填方填 0）")
	var have_cut := cut_in is Array and (cut_in as Array).size() > 0
	if have_cut and (cut_in as Array).size() != (chains_in as Array).size():
		return _err("cut_areas_m2 须与 chains_m 等长（各断面挖方面积 m²；无挖方填 0）")
	var chains := []
	var fills := PackedFloat64Array()
	var cuts := PackedFloat64Array()
	for c in chains_in as Array:
		var cf := _num(c)
		if is_nan(cf):
			return _err("chains_m 含非数字桩号：%s" % str(c))
		chains.append(cf)
	for i in range(1, chains.size()):
		if chains[i] <= chains[i - 1]:
			return _err("chains_m 须严格递增（第 %d 处：%s ≤ %s）" % [i + 1, str(chains[i]), str(chains[i - 1])])
	for a in fill_in as Array:
		var af := _num(a)
		if is_nan(af) or af < 0.0:
			return _err("填方面积须为非负数字：%s" % str(a))
		fills.append(af)
	if have_cut:
		for a in cut_in as Array:
			var af := _num(a)
			if is_nan(af) or af < 0.0:
				return _err("挖方面积须为非负数字：%s" % str(a))
			cuts.append(af)
	else:
		cuts.resize(chains.size())
	var dists := PackedFloat64Array()
	for i in range(chains.size() - 1):
		dists.append(chains[i + 1] - chains[i])
	var vf := seg_volumes(fills, dists)
	var vc := seg_volumes(cuts, dists)
	if vf.is_empty() or vc.is_empty():
		return _err("断面体积分段计算失败（内部错误）")
	var fill_sum := 0.0
	var cut_sum := 0.0
	for v in vf:
		fill_sum += v
	for v in vc:
		cut_sum += v
	var total_d := 0.0
	for d in dists:
		total_d += d
	var seg_rows := PackedStringArray()
	for i in vf.size():
		seg_rows.append("%s~%s：填 %.4f / 挖 %.4f m³" % [String.num(chains[i], 2), String.num(chains[i + 1], 2), vf[i], vc[i]])
	# 可选棱台公式口径（use_prismoidal=true）：A_m 取相邻断面算术平均（口径演示；此时与端面平均一致）
	var use_prismoidal := bool(p.get("use_prismoidal", false))
	var frustum_sum := NAN
	var prism_row := ""
	var prism_note := ""
	var value := {
				"fill_m3": fill_sum,
				"cut_m3": cut_sum,
				"net_m3": fill_sum - cut_sum,
				"cut_minus_fill_m3": cut_sum - fill_sum,
				"segments": vf.size(),
				"total_dist_m": total_d,
			}
	if use_prismoidal:
		var fs := 0.0
		for i in range(chains.size() - 1):
			var v := frustum_volume(fills[i], (fills[i] + fills[i + 1]) / 2.0, fills[i + 1], dists[i])
			v += frustum_volume(cuts[i], (cuts[i] + cuts[i + 1]) / 2.0, cuts[i + 1], dists[i])
			if is_nan(v):
				return _err("棱台公式分段计算失败（内部错误）")
			fs += v
		frustum_sum = fs
		value["frustum_m3"] = frustum_sum
		value["mean_section_m3"] = fill_sum + cut_sum
		prism_row = "棱台口径 %.4f m³ vs 平均断面法 %.4f m³" % [frustum_sum, fill_sum + cut_sum]
		prism_note = "此口径 A_m 取相邻断面算术平均，棱台公式退化为端面平均（两者一致）；" \
			+ "要获得独立估计，请另行提供 1/2 桩号处的实际断面面积"
	# 可选棱台公式口径：显式给出各段 {a1_m2, am_m2, a2_m2, l_m}（A_m 为 1/2 桩号处实际断面面积）
	var pr_in: Variant = p.get("prismoidal_segments", [])
	if pr_in is Array and not (pr_in as Array).is_empty():
		frustum_sum = 0.0
		var frustum_rows := PackedStringArray()
		for i in range((pr_in as Array).size()):
			var seg: Variant = (pr_in as Array)[i]
			if not (seg is Dictionary):
				return _err("棱台分段须为对象 {a1_m2, am_m2, a2_m2, l_m}")
			var a1v := _num((seg as Dictionary).get("a1_m2", NAN))
			var amv := _num((seg as Dictionary).get("am_m2", NAN))
			var a2v := _num((seg as Dictionary).get("a2_m2", NAN))
			var lv := _num((seg as Dictionary).get("l_m", NAN))
			var v2 := frustum_volume(a1v, amv, a2v, lv)
			if is_nan(v2):
				return _err("棱台分段 %d 输入非法：a1_m2/am_m2/a2_m2 须为数字面积，l_m 须为正数段长" % (i + 1))
			var v_mean2 := (a1v + a2v) / 2.0 * lv
			frustum_sum += v2
			frustum_rows.append("段%d：棱台 %.4f vs 端面平均 %.4f m³" % [i + 1, v2, v_mean2])
		value["frustum_m3"] = frustum_sum
		prism_row = "；".join(frustum_rows)
		prism_note = "棱台公式 V=L/6·(A₁+4A_m+A₂)，A_m 为 1/2 桩号处实际断面面积；与端面平均 V=L·(A₁+A₂)/2 之差反映断面沿程变化的凸性"
	if prism_row != "":
		value["prismoidal_note"] = prism_note
	return {"ok": true, "value": value,
			"steps": [
				{"title": "1. 相邻断面间距",
					"formula": "d_i = 桩号_{i+1} − 桩号_i",
					"substitution": "%d 个断面" % chains.size(),
					"result": "总长 %.4f m，共 %d 段" % [total_d, dists.size()]},
				{"title": "2. 平均断面法逐段体积",
					"formula": "V = (A_i + A_{i+1})/2 × d_i（填挖分列）",
					"substitution": "；".join(seg_rows.slice(0, 3)) + ("（…共 %d 段）" % vf.size() if vf.size() > 3 else ""),
					"result": "填方 %.4f m³，挖方 %.4f m³，净填 %.4f m³" % [fill_sum, cut_sum, fill_sum - cut_sum]},
				{"title": "3. 双口径与棱台公式（可选）",
					"formula": "净量（代数） = 填方 − 挖方；挖减填 = 挖方 − 填方；棱台 V = L/6·(A₁+4A_m+A₂)",
					"substitution": "挖方 − 填方 = %.4f − %.4f" % [cut_sum, fill_sum],
					"result": (prism_row if prism_row != "" else "挖减填 %.4f m³（与净量互为相反数）" % (cut_sum - fill_sum))},
			],
			"formula": "平均断面法：V=Σ(A_i+A_{i+1})/2·d_i；双口径：净量=填−挖（net_m3）、挖减填=挖−填（cut_minus_fill_m3）互为相反数；"
				+ "可选棱台公式 V=L/6·(A₁+4A_m+A₂)（prismoidal_segments 给出各段 A₁/A_m/A₂/L；A_m 为 1/2 桩号处实际断面面积）" + prism_note,
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
