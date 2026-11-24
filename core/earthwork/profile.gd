# core/earthwork/profile.gd —— GK-M7-15 纵断面内插 / 横断面数据 E6
#
# 纵断面：按桩号升序地面线线性内插；查询超范围默认报错（clamp=true 端点截断）。
# 横断面：设计线 design(o)=z_c−i·|o|/100 与地面点列（offset 右正左负、升序）逐点求挖填高，
# 分段精确积分填/挖面积（线性高差场，变号段零点分割为三角形，与 DTM 同一精确性口径）。
# 构造向量（自洽）：地面平 100、设计中心 103、i=0、o∈[−20,20] → 挖方面积 120.0 m²；
# 纵断面 (0,100)(100,102)(200,101) 桩 150 → 101.5。校验失败 ok=false + 中文 error。
class_name GKProfile
extends RefCounted

# ---------- 纵断面内插 ----------

## 纯核：线性内插。points 按 chain 升序；超范围返回 NAN。
static func interp(points: Array, chain: float) -> float:
	if points.size() < 2 or not is_finite(chain):
		return NAN
	if chain < float(points[0][0]) or chain > float(points[points.size() - 1][0]):
		return NAN
	for i in range(points.size() - 1):
		var x1: float = points[i][0]
		var x2: float = points[i + 1][0]
		if chain >= x1 and chain <= x2:
			if x2 == x1:
				return float(points[i][1])
			var t := (chain - x1) / (x2 - x1)
			return float(points[i][1]) * (1.0 - t) + float(points[i + 1][1]) * t
	return NAN

## E6-纵断面协议入口。p = { points:[{chain_m, elev_m},...], query_chains_m:[...], clamp=false }
## value = { query_chains_m, elevs_m, chain_min_m, chain_max_m }
static func interp_forward(p: Dictionary) -> Dictionary:
	var pts_in: Variant = p.get("points", [])
	if not (pts_in is Array) or (pts_in as Array).size() < 2:
		return _err("points 须为 ≥2 点的纵断面地面线：[{chain_m, elev_m}, ...]（桩号升序）")
	var pts := []
	for q in pts_in as Array:
		if not (q is Dictionary):
			return _err("points 元素须为对象 {chain_m, elev_m}")
		var c := _num((q as Dictionary).get("chain_m", NAN))
		var z := _num((q as Dictionary).get("elev_m", NAN))
		if is_nan(c) or is_nan(z):
			return _err("纵断面点 chain_m/elev_m 须为数字")
		pts.append([c, z])
	for i in range(1, pts.size()):
		if float(pts[i][0]) <= float(pts[i - 1][0]):
			return _err("纵断面 chain_m 须严格递增（第 %d 点）" % (i + 1))
	var do_clamp := bool(p.get("clamp", false))
	var q_in: Variant = p.get("query_chains_m", [])
	if not (q_in is Array) or (q_in as Array).is_empty():
		return _err("query_chains_m 须为非空桩号数组（m）")
	var qs := PackedFloat64Array()
	var zs := PackedFloat64Array()
	var c_min: float = pts[0][0]
	var c_max: float = pts[pts.size() - 1][0]
	for q in q_in as Array:
		var qf := _num(q)
		if is_nan(qf):
			return _err("query_chains_m 含非数字桩号：%s" % str(q))
		var ez := interp(pts, qf)
		if is_nan(ez):
			if do_clamp:
				ez = float(pts[0][1]) if qf < c_min else float(pts[pts.size() - 1][1])
			else:
				return _err("查询桩号 %s 超出纵断面地面线范围 [%s, %s]（可置 clamp=true 端点截断）" % [str(qf), String.num(c_min, 3), String.num(c_max, 3)])
		qs.append(qf)
		zs.append(ez)
	return {"ok": true, "value": {
				"query_chains_m": qs,
				"elevs_m": zs,
				"chain_min_m": c_min,
				"chain_max_m": c_max,
			},
			"steps": [{"title": "纵断面线性内插",
				"formula": "z = z_i + (z_{i+1} − z_i)·(x − x_i)/(x_{i+1} − x_i)",
				"substitution": "地面线 %d 点，查询 %d 个桩号" % [pts.size(), qs.size()],
				"result": "首查询 %s → %.4f m" % [String.num(float(qs[0]), 3), float(zs[0])]}],
			"formula": "纵断面内插：相邻地面线点间线性内插（纵断面地面线折线模型）",
			"error": ""}

# ---------- 横断面数据 ----------

## 纯核：单区间 [x1,x2] 上线性高差场 h = 地面 − 设计 的正部/负部面积（精确）。
## 返回 [fill_area, cut_area]（均≥0；h>0 地面高于设计 → 挖方；h<0 → 填方）。
## 非法返回空。
static func interval_areas(h1: float, h2: float, w: float) -> PackedFloat64Array:
	if not (is_finite(h1) and is_finite(h2) and is_finite(w)) or w <= 0.0:
		return PackedFloat64Array()
	var fill := 0.0
	var cut := 0.0
	if h1 >= 0.0 and h2 >= 0.0:
		cut = (h1 + h2) * w / 2.0
	elif h1 <= 0.0 and h2 <= 0.0:
		fill = (absf(h1) + absf(h2)) * w / 2.0
	else:
		# 变号：零点分割，正部/负部均为三角形
		var t0 := w * h1 / (h1 - h2)  # 零点距左端
		if h1 > 0.0:
			cut = h1 * t0 / 2.0
			fill = absf(h2) * (w - t0) / 2.0
		else:
			fill = absf(h1) * t0 / 2.0
			cut = h2 * (w - t0) / 2.0
	return PackedFloat64Array([fill, cut])

## E6-横断面协议入口。p = {
##   design_elev_m（中心设计高程）, cross_slope_pct=0（路拱横坡，两侧对称外降）,
##   section:[{offset_m, elev_m},...]（offset 右正左负，升序）,
##   design_offsets_m?:[...]（可选：指定计算挖填高的偏距点，默认取地面线点） }
## value = { fill_area_m2, cut_area_m2, heights:[{offset_m, ground_elev_m, design_elev_m, dh_m}], offsets_m, dhs_m }
static func cross_section(p: Dictionary) -> Dictionary:
	var zd := _num(p.get("design_elev_m", NAN))
	var i_pct := _num(p.get("cross_slope_pct", 0.0)) if p.has("cross_slope_pct") else 0.0
	if is_nan(zd) or is_nan(i_pct):
		return _err("design_elev_m（中心设计高程）与 cross_slope_pct 须为数字")
	var sec_in: Variant = p.get("section", [])
	if not (sec_in is Array) or (sec_in as Array).size() < 2:
		return _err("section 须为 ≥2 点的横断面地面线：[{offset_m, elev_m}, ...]（offset 右正左负，升序）")
	var sec := []
	for q in sec_in as Array:
		if not (q is Dictionary):
			return _err("section 元素须为对象 {offset_m, elev_m}")
		var o := _num((q as Dictionary).get("offset_m", NAN))
		var z := _num((q as Dictionary).get("elev_m", NAN))
		if is_nan(o) or is_nan(z):
			return _err("横断面点 offset_m/elev_m 须为数字")
		sec.append([o, z])
	for i in range(1, sec.size()):
		if float(sec[i][0]) <= float(sec[i - 1][0]):
			return _err("横断面 offset_m 须严格递增（第 %d 点）" % (i + 1))
	# 逐点挖填高（设计线含对称路拱 |o| 外降；路拱变坡点 o=0 处自动分段）
	var heights := []
	var offsets := PackedFloat64Array()
	var dhs := PackedFloat64Array()
	var design := func(o: float) -> float:
		return zd - i_pct * absf(o) / 100.0
	for pt: Array in sec:
		var o: float = pt[0]
		var dline: float = design.call(o)
		var dh: float = float(pt[1]) - dline
		heights.append({"offset_m": o, "ground_elev_m": float(pt[1]), "design_elev_m": dline, "dh_m": dh})
		offsets.append(o)
		dhs.append(dh)
	# 分段精确面积：设计线在 o=0 有 |o| 折点，先按 o=0 分割区间
	var fill_sum := 0.0
	var cut_sum := 0.0
	for i in range(sec.size() - 1):
		var spans := [[float(sec[i][0]), float(sec[i + 1][0])]]
		if float(sec[i][0]) < 0.0 and float(sec[i + 1][0]) > 0.0:
			spans = [[float(sec[i][0]), 0.0], [0.0, float(sec[i + 1][0])]]
		for sp: Array in spans:
			var x1: float = sp[0]
			var x2: float = sp[1]
			if x2 <= x1 + 1e-15:
				continue
			var g1 := _interp_arr(sec, x1)
			var g2 := _interp_arr(sec, x2)
			var h1: float = g1 - design.call(x1)
			var h2: float = g2 - design.call(x2)
			var ar := interval_areas(h1, h2, x2 - x1)
			if ar.is_empty():
				return _err("横断面面积积分失败（内部错误）")
			fill_sum += ar[0]
			cut_sum += ar[1]
	return {"ok": true, "value": {
				"fill_area_m2": fill_sum,
				"cut_area_m2": cut_sum,
				"net_area_m2": fill_sum - cut_sum,
				"design_elev_m": zd,
				"cross_slope_pct": i_pct,
				"offsets_m": offsets,
				"dhs_m": dhs,
				"heights": heights,
			},
			"steps": [
				{"title": "1. 设计线与逐点挖填高",
					"formula": "design(o) = z_c − i·|o|/100；h = 地面 − 设计（h>0 挖，h<0 填）",
					"substitution": "z_c=%.4f，i=%.4f%%，地面线 %d 点" % [zd, i_pct, sec.size()],
					"result": "首点 o=%s：地面 %.4f，设计 %.4f，h %.4f m" % [String.num(offsets[0], 3), float(sec[0][1]), design.call(float(sec[0][0])), float(dhs[0])]},
				{"title": "2. 横断面填挖面积（分段精确积分）",
					"formula": "区间线性高差场积分；变号段在零点分割为三角形：A=h·t/2",
					"substitution": "%d 个地面线区间（路拱折点 o=0 自动分割）" % (sec.size() - 1),
					"result": "挖方面积 %.4f m²，填方面积 %.4f m²，净 %.4f m²" % [cut_sum, fill_sum, fill_sum - cut_sum]},
			],
			"formula": "横断面：设计线 = 中心高程 + 对称路拱（i% 外降）；挖填面积按线性高差场分段精确积分（变号段零点分割），与断面法土方（E2）衔接",
			"error": ""}

# ---------- 内部工具 ----------

## 点列（[x, z]，x 升序）线性内插；范围外返回 NAN
static func _interp_arr(pts: Array, x: float) -> float:
	if x < float(pts[0][0]) - 1e-12 or x > float(pts[pts.size() - 1][0]) + 1e-12:
		return NAN
	for i in range(pts.size() - 1):
		var x1: float = pts[i][0]
		var x2: float = pts[i + 1][0]
		if x >= x1 and x <= x2:
			if x2 == x1:
				return float(pts[i][1])
			var t := (x - x1) / (x2 - x1)
			return float(pts[i][1]) * (1.0 - t) + float(pts[i + 1][1]) * t
	return float(pts[pts.size() - 1][1])

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
