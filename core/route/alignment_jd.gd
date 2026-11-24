# core/route/alignment_jd.gd —— GK-M7-3 交点法中线正反算 D1
#
# 复用本域内核：要素算 GKCurveElements（B3），定位委托 GKAlignmentEl（D2）；M7 域内互调不违反跨域禁令。
# 输入 p：start={x_m,y_m,bearing_deg?,chain_m=0}（起点须在 JD1 切线上，bearing 缺省取起点→JD1 方向）；
#   jds=[{x_m,y_m,r_m>0,l0_m≥0},…]（≥1）；end_bearing_deg? 缺省→末交点不设曲线（直线收尾）。
# 转角 Δ_i 右转正；里程：chain(JD_i)=chain(HZ_{i−1})+S(JD_{i−1},JD_i)−T_{i−1}，本段直线长=S_i−T_{i−1}−T_i。
# 主点 ZH/HY/QZ/YZ/HZ（l0=0 时 ZY/QZ/YZ）；正算 chain→XY 与反算 XY→chain+偏距（右正左负）均委托 D2。
# 校验失败 ok=false + 中文 error（曲线伸入锚点之前、转角为零、|α|≥180° 等）。
class_name GKAlignmentJd
extends RefCounted

const El := preload("res://core/route/alignment_el.gd")
const Cur := preload("res://core/route/curve_elements.gd")

## 装配正算：返回要素 + 主点里程/坐标 + 线元分段表。
static func forward(p: Dictionary) -> Dictionary:
	var b := build_elements(p)
	if not bool(b.get("ok", false)):
		return b  # 已是协议错误结构
	var curves: Array = b["value"]["curves"]
	var value := {
		"total_len_m": b["value"]["total_len_m"],
		"start_x_m": b["value"]["start_x_m"],
		"start_y_m": b["value"]["start_y_m"],
		"start_bearing_deg": b["value"]["start_bearing_deg"],
		"curve_count": curves.size(),
		"curves": curves,
		"jds": b["value"]["jds"],
		"main_points": b["value"]["main_points"],
		"segs": b["value"]["segs"],
	}
	var steps: Array = []
	for c: Dictionary in curves:
		steps.append({
			"title": "JD%d 曲线要素（%s，α=%s）" % [int(c["jd_index"]) + 1, String(c["dir_cn"]), String(c["alpha_txt"])],
			"formula": "β0=l0/(2R)；p=l0²/(24R)−l0⁴/(2688R³)；m=l0/2−l0³/(240R²)；T=(R+p)tan(α/2)+m；L=R·α+l0",
			"substitution": "R=%s m，l0=%s m" % [String.num(float(c["r_m"]), 4), String.num(float(c["l0_m"]), 4)],
			"result": "T=%.4f m，L=%.4f m，E=%.4f m，q=%.4f m" % [float(c["t_m"]), float(c["l_m"]), float(c["e_m"]), float(c["q_m"])],
		})
		steps.append({
			"title": "JD%d 主点里程与坐标" % (int(c["jd_index"]) + 1),
			"formula": "ZH=JD−T；HY=ZH+l0；QZ=ZH+L/2；YZ=ZH+L−l0；HZ=ZH+L",
			"substitution": "JD 里程 %s，JD(%s, %s)" % [_chain_str(float(c["chain_jd_m"])), String.num(float(c["jd_x_m"]), 3), String.num(float(c["jd_y_m"]), 3)],
			"result": "ZH %s(%.3f, %.3f) → HZ %s(%.3f, %.3f)" % [
				_chain_str(float(c["chain_zh_m"])), float(c["zh_x_m"]), float(c["zh_y_m"]),
				_chain_str(float(c["chain_hz_m"])), float(c["hz_x_m"]), float(c["hz_y_m"])],
		})
	return {"ok": true, "value": value, "steps": steps,
			"formula": "交点法正算：由 JD 序列推各切线方位与转角 → 对称基本型曲线要素（B3）→ 主点里程/坐标（坐标定位走线元法 D2）。精度注记：切线长 T 取布告式级数要素，坐标按真回旋线（曲率线性、数值积分）定位，两者存在级数截断级差异（一般 ≤1e-4 m 量级）",
			"error": ""}

## D1-正算：里程 → XY。p 增加 chain_m。
static func point_at(p: Dictionary) -> Dictionary:
	var b := build_elements(p)
	if not bool(b.get("ok", false)):
		return b
	return El.point_at({"elements": b["elements"], "start": b["start"], "chain_m": p.get("chain_m", NAN)})

## D1-反算：XY → 里程 + 偏距（右正左负）。p 增加 x_m/y_m。
static func inverse(p: Dictionary) -> Dictionary:
	var b := build_elements(p)
	if not bool(b.get("ok", false)):
		return b
	return El.inverse({"elements": b["elements"], "start": b["start"],
			"x_m": p.get("x_m", NAN), "y_m": p.get("y_m", NAN)})

## 核心：由 start+jds 装配全线线元序列（委托 D2 build 出分段表）。
## 返回协议结构；value 含 segs/curves/jds/main_points/total_len_m；
## 顶层另附 elements/start（供 point_at/inverse 委托）。
static func build_elements(p: Dictionary) -> Dictionary:
	var st_in: Dictionary = p.get("start", {})
	var jd_in: Variant = p.get("jds", [])
	if not (jd_in is Array) or (jd_in as Array).is_empty():
		return _err("jds 须为非空交点数组，每个交点含 x_m、y_m、r_m（l0_m 可选）")
	var jds := []
	for j in jd_in as Array:
		if not (j is Dictionary):
			return _err("jds 数组元素须为对象 {x_m, y_m, r_m, l0_m}")
		var xj := _num((j as Dictionary).get("x_m", NAN))
		var yj := _num((j as Dictionary).get("y_m", NAN))
		var rj := _num((j as Dictionary).get("r_m", NAN))
		var l0j := _num((j as Dictionary).get("l0_m", 0.0)) if (j as Dictionary).has("l0_m") else 0.0
		if is_nan(xj) or is_nan(yj):
			return _err("交点坐标 x_m/y_m 须为数字")
		if is_nan(rj) or rj <= 0.0:
			return _err("交点半径 r_m 必须大于 0")
		if is_nan(l0j) or l0j < 0.0:
			return _err("缓和曲线长 l0_m 不能为负")
		jds.append({"x": xj, "y": yj, "r": rj, "l0": l0j})
	var sx := _num(st_in.get("x_m", NAN))
	var sy := _num(st_in.get("y_m", NAN))
	var chain0 := _num(st_in.get("chain_m", 0.0)) if st_in.has("chain_m") else 0.0
	if is_nan(sx) or is_nan(sy):
		return _err("start 须含 x_m、y_m（数字）")
	if is_nan(chain0):
		return _err("start.chain_m 须为数字里程")
	var az_in := _num(st_in.get("bearing_deg", NAN))
	if is_nan(az_in):
		var dx0: float = jds[0]["x"] - sx
		var dy0: float = jds[0]["y"] - sy
		if absf(dx0) < 1e-12 and absf(dy0) < 1e-12:
			return _err("start.bearing_deg 缺省时起点不能与 JD1 重合：请给出起始切线方位角 bearing_deg")
		az_in = GKAngles.azimuth(dx0, dy0)
	var end_az := NAN
	if p.has("end_bearing_deg"):
		end_az = _num(p["end_bearing_deg"])
		if is_nan(end_az):
			return _err("end_bearing_deg 须为数字方位角")
	# —— 逐段距离与方位 ——
	var n := jds.size()
	var azs := PackedFloat64Array()   # azs[i] = 方位(锚点_i → JD_i)，azs[0] 为 起点→JD0
	var dists := PackedFloat64Array() # dists[i] = 距离(锚点_i → JD_i)
	var px := sx
	var py := sy
	for i in n:
		var dx: float = jds[i]["x"] - px
		var dy: float = jds[i]["y"] - py
		var d := sqrt(dx * dx + dy * dy)
		if d < 1e-9:
			return _err("第 %d 个交点与前一点重合，无法定向" % (i + 1))
		azs.append(GKAngles.azimuth(dx, dy))
		dists.append(d)
		px = jds[i]["x"]
		py = jds[i]["y"]
	# —— 逐交点装配线元 ——
	# 里程/直线段几何：HZ_{i−1} 位于 JD_{i−1}→JD_i 连线上、距 JD_{i−1} 为 T_{i−1}，
	# 故本段直线长 = D_i − T_{i−1}（上一曲线切线）− T_i（本交点曲线切线）；
	# chain(JD_i) = chain(HZ_{i−1}) + (D_i − T_{i−1})。
	var elements := []
	var curves := []
	var th := deg_to_rad(az_in)      # 当前切线方位（rad，连续累计）
	var chain_anchor := chain0       # 当前锚点（起点或上一曲线 HZ）里程
	var prev_t := 0.0                # 上一交点曲线切线长（无曲线为 0）
	var az_err := false
	for i in n:
		var seg_az := azs[i]
		var ddeg := absf(GKAngles.normalize_deg(rad_to_deg(th) - seg_az))
		if minf(ddeg, 360.0 - ddeg) > 1e-4:
			az_err = true  # 直线段方位与当前切线不一致（容差 1e-4°，容忍毫米级取整坐标的方位噪声）
		var jd_chain_i := chain_anchor + dists[i] - prev_t
		var is_last := (i == n - 1)
		var has_curve := true
		var out_az := 0.0
		if is_last:
			if is_nan(end_az):
				has_curve = false
			else:
				out_az = end_az
		else:
			out_az = azs[i + 1]
		var delta := 0.0
		if has_curve:
			delta = _signed_diff(out_az, rad_to_deg(th))
			if absf(delta) < 1e-9:
				has_curve = false
			elif absf(delta) >= 180.0:
				return _err("JD%d 转角 |α|=%.4f°≥180°：交点法切线长公式失效，请改用线元法（D2）或匝道模块（D6）" % [i + 1, absf(delta)])
		var r: float = jds[i]["r"]
		var l0: float = jds[i]["l0"]
		var line_len := dists[i] - prev_t
		var elc := {}
		if has_curve:
			elc = Cur.elements(r, l0, deg_to_rad(absf(delta)))
			if elc.is_empty():
				return _err("JD%d 曲线要素计算失败：请检查 R/l0 与转角（2β0 不得大于 α）" % (i + 1))
			line_len -= float(elc["t_m"])
			if line_len < -1e-9:
				return _err("JD%d 曲线伸入上一锚点之前：本段距离 %.4f m 不足以容纳上一曲线切线 %.4f m 与本曲线切线 %.4f m，请增大交点间距或减小 R/l0" % [i + 1, dists[i], prev_t, float(elc["t_m"])])
		if line_len > 1e-9:
			elements.append(El.make_line(line_len))
		chain_anchor = jd_chain_i
		if has_curve:
			var dir := 1 if delta > 0.0 else -1
			var idx_first := elements.size()
			var idx_arc := elements.size() if l0 <= 0.0 else elements.size() + 1
			if l0 > 0.0:
				elements.append(El.make_spiral(0.0, r, l0, dir))
			# 圆曲线段：中心角 = α − 2β0（β0=l0/(2R)）
			elements.append(El.make_arc(r, dir * (absf(delta) - rad_to_deg(l0 / r))))
			if l0 > 0.0:
				elements.append(El.make_spiral(r, 0.0, l0, dir))
			var idx_last := elements.size() - 1
			curves.append({
				"jd_index": i,
				"jd_x_m": jds[i]["x"], "jd_y_m": jds[i]["y"],
				"chain_jd_m": jd_chain_i,
				"chain_zh_m": jd_chain_i - float(elc["t_m"]),
				"chain_hz_m": jd_chain_i - float(elc["t_m"]) + float(elc["l_m"]),
				"alpha_deg": delta,
				"alpha_txt": GKAngles.deg_to_dms_str(absf(delta), 1),
				"dir_cn": "右转" if dir > 0 else "左转",
				"r_m": r, "l0_m": l0,
				"t_m": float(elc["t_m"]), "l_m": float(elc["l_m"]),
				"e_m": float(elc["e_m"]), "q_m": float(elc["q_m"]),
				"beta0_deg": float(elc["beta0_deg"]), "p_m": float(elc["p_m"]), "m_m": float(elc["m_m"]),
				"seg_indices": [idx_first, idx_arc, idx_last] if l0 > 0.0 else [idx_arc],
			})
			chain_anchor = jd_chain_i + (float(elc["l_m"]) - float(elc["t_m"]))  # 推进到 HZ
			prev_t = float(elc["t_m"])
			th = th + deg_to_rad(delta)
		else:
			prev_t = 0.0
	if az_err:
		return _err("装配检核失败：某直线段方位与切线方位不一致，请检查交点坐标与起始方位")
	# —— 委托 D2 装配 ——
	var bp := {"elements": elements, "start": {"x_m": sx, "y_m": sy, "bearing_deg": az_in, "chain_m": chain0}}
	var built := El.build(bp)
	if not bool(built.get("ok", false)):
		return _err(String(built.get("error", "线元装配失败")))
	var segs: Array = built["value"]["segs"]
	# —— 主点坐标（自分段表取接点） ——
	var main_points := []
	for c: Dictionary in curves:
		var idxs: Array = c["seg_indices"]
		var first_seg: Dictionary = segs[int(idxs[0])]
		var arc_seg: Dictionary = segs[int(idxs[1])] if idxs.size() > 2 else first_seg
		var last_seg: Dictionary = segs[int(idxs[idxs.size() - 1])]
		var chain_zh: float = c["chain_zh_m"]
		var l_m: float = c["l_m"]
		var l0v: float = c["l0_m"]
		if l0v > 0.0:
			main_points.append({"name": "ZH", "chain_m": chain_zh, "x_m": first_seg["x0_m"], "y_m": first_seg["y0_m"]})
			main_points.append({"name": "HY", "chain_m": chain_zh + l0v, "x_m": arc_seg["x0_m"], "y_m": arc_seg["y0_m"]})
			main_points.append({"name": "QZ", "chain_m": chain_zh + l_m / 2.0, "x_m": NAN, "y_m": NAN})
			main_points.append({"name": "YZ", "chain_m": chain_zh + l_m - l0v, "x_m": arc_seg["x1_m"], "y_m": arc_seg["y1_m"]})
			main_points.append({"name": "HZ", "chain_m": float(c["chain_hz_m"]), "x_m": last_seg["x1_m"], "y_m": last_seg["y1_m"]})
		else:
			main_points.append({"name": "ZY", "chain_m": chain_zh, "x_m": arc_seg["x0_m"], "y_m": arc_seg["y0_m"]})
			main_points.append({"name": "QZ", "chain_m": chain_zh + l_m / 2.0, "x_m": NAN, "y_m": NAN})
			main_points.append({"name": "YZ", "chain_m": chain_zh + l_m, "x_m": arc_seg["x1_m"], "y_m": arc_seg["y1_m"]})
		c["zh_x_m"] = first_seg["x0_m"]
		c["zh_y_m"] = first_seg["y0_m"]
		c["hz_x_m"] = last_seg["x1_m"]
		c["hz_y_m"] = last_seg["y1_m"]
	for mp: Dictionary in main_points:
		if String(mp["name"]) == "QZ":
			var pr := El.point_at({"elements": elements, "start": bp["start"], "chain_m": float(mp["chain_m"])})
			if bool(pr.get("ok", false)):
				mp["x_m"] = pr["value"]["x_m"]
				mp["y_m"] = pr["value"]["y_m"]
	var jd_rows := []
	for i in n:
		jd_rows.append({"jd_index": i + 1, "x_m": jds[i]["x"], "y_m": jds[i]["y"],
			"r_m": jds[i]["r"], "l0_m": jds[i]["l0"]})
	return {"ok": true, "value": {
				"segs": segs,
				"curves": curves,
				"jds": jd_rows,
				"main_points": main_points,
				"start_x_m": sx, "start_y_m": sy,
				"start_bearing_deg": az_in,
				"total_len_m": float(segs[segs.size() - 1]["chain1_m"]) - chain0,
			},
			"elements": elements, "start": bp["start"],
			"steps": [], "formula": "", "error": ""}

# ---------- 内部工具 ----------

## 方位差归化到 (−180°, 180°]，右转正
static func _signed_diff(a_deg: float, b_deg: float) -> float:
	var d := GKAngles.normalize_deg(a_deg - b_deg)
	if d > 180.0:
		d -= 360.0
	return d

static func _num(v: Variant) -> float:
	if v is float or v is int:
		return float(v)
	if v is String:
		var t := String(v).strip_edges()
		if t.is_valid_float():
			return t.to_float()
	return NAN

static func _chain_str(c: float) -> String:
	if not is_finite(c):
		return "—"
	var k := int(floorf(c / 1000.0))
	var rest := c - k * 1000.0
	return "K%d+%08.3f" % [k, rest]

static func _err(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": msg}
