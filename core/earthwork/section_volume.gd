# core/earthwork/section_volume.gd —— GK-M7-11 断面法土方 E2（平均断面法）
#
# 设计约定（docs/ARCHITECTURE.md §4 GK-M7 / §5）：
#   - 平均断面法：V = Σ (A_i + A_{i+1})/2 × d_i（d_i 为相邻断面间距）；
#     填、挖面积分列累计；相邻两断面一填一挖时，按代数和计入净量
#     （生产中另有棱台/棱柱体公式可选，教学口径以平均断面法为准并尾注声明）；
#   - 构造向量（自洽检核）：断面积 [10, 20, 30] m²、间距 [50, 50] m → V=2000.0 m³；
#   - 校验失败 ok=false + 中文 error（桩号严格递增、面积非负、数组等长）。
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

## E2 协议入口。p = { chains_m:[...], fill_areas_m2:[...], cut_areas_m2:[]? }
## value = { fill_m3, cut_m3, net_m3, segments, total_dist_m }
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
	return {"ok": true, "value": {
				"fill_m3": fill_sum,
				"cut_m3": cut_sum,
				"net_m3": fill_sum - cut_sum,
				"segments": vf.size(),
				"total_dist_m": total_d,
			},
			"steps": [
				{"title": "1. 相邻断面间距",
					"formula": "d_i = 桩号_{i+1} − 桩号_i",
					"substitution": "%d 个断面" % chains.size(),
					"result": "总长 %.4f m，共 %d 段" % [total_d, dists.size()]},
				{"title": "2. 平均断面法逐段体积",
					"formula": "V = (A_i + A_{i+1})/2 × d_i（填挖分列）",
					"substitution": "；".join(seg_rows.slice(0, 3)) + ("（…共 %d 段）" % vf.size() if vf.size() > 3 else ""),
					"result": "填方 %.4f m³，挖方 %.4f m³，净填 %.4f m³" % [fill_sum, cut_sum, fill_sum - cut_sum]},
			],
			"formula": "平均断面法：V=Σ(A_i+A_{i+1})/2·d_i；填挖分列、净值=填−挖；相邻断面一填一挖时近似以平均断面计（生产可选用棱台公式，教学口径已注明）",
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
