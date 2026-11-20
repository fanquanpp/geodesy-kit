# core/transform/height_fit.gd —— GK-M4-3（A10）：GNSS 高程拟合（平面 3 参 / 曲面 6 参 / 带状分段）
#
# 模型（坐标系约定：先以坐标重心 (x0,y0) 为拟合原点做中心化，改善法方程条件，系数同时
# 给出"中心化形式"与"绝对坐标形式"两套，便于直接移植到其它软件）：
#   平面（3 参数）：H = c0 + c1·ξ + c2·η，          ξ = x − x0，η = y − y0
#   曲面（6 参数）：H = c0 + c1·ξ + c2·η + c3·ξ² + c4·η² + c5·ξη
#   带状分段：沿线轴向坐标 u（axis=x 取 x，axis=y 取 y）等宽分段，每段独立拟合
#             H = c0 + c1·(u−mid)（order=1）或 H = c0 + c1·(u−mid) + c2·(u−mid)²（order=2）；
#             分段边界不强制连续（各段独立 LS，头注如实声明）。
# 求解：正规方程 N = BᵀB 直接用 GKMatrix.cholesky_solve（core/math，Wave 0 冻结 API）。
#   注：ARCHITECTURE.md §4 GK-M4 原计划"经 M1 least_squares"，而 least_squares.gd 尚未建
#   （M1 施工者负责），本文件按地基"可直接用 GKMatrix.cholesky_solve 组装"的口径内联组成
#   正规方程，待 M1 least_squares.gd 就位后可无缝替换调用。此为如实记录的依赖降级，见交付说明。
# 求参输出公共点残差表、单位权中误差 σ0 与 >3σ 粗差中文提示；纯 GDScript、零引擎依赖。
class_name GKHeightFit
extends RefCounted

## 拟合（§5 协议入口）。p：{xy: [[x,y],...], h: [..], model, segments, order, axis}
## value：{model: 可供 predict() 复用的模型字典, coeffs_center, coeffs_abs, sigma0_m, rms_m,
##          residuals_m, outliers, warnings, origin, n_points, n_unknown, redundancy, ...}
static func fit(p: Dictionary) -> Dictionary:
	var model_key := _norm_model(String(p.get("model", "plane")))
	if model_key != "plane" and model_key != "surface" and model_key != "strip":
		return _err("", "模型仅支持 plane（平面）/ surface（曲面）/ strip（带状分段），收到：%s" % String(p.get("model", "plane")))
	var formula := _model_formula(model_key)
	var xy := _parse_points(p.get("xy", []), 2)
	if not xy.ok:
		return _err(formula, xy.error)
	var hres := _parse_floats(p.get("h", []), "高程 h")
	if not hres.ok:
		return _err(formula, hres.error)
	var h: PackedFloat64Array = hres.vals
	var n: int = xy.points.size()
	if n != h.size():
		return _err(formula, "平面坐标点数（%d）与高程个数（%d）不一致" % [n, h.size()])
	# 中心化原点（坐标重心）
	var sx := 0.0
	var sy := 0.0
	for q: PackedFloat64Array in xy.points:
		sx += q[0]
		sy += q[1]
	var x0 := sx / n
	var y0 := sy / n
	var steps := []
	# —— 带状分段：轴向坐标、分段、每段点归类 ——
	var segs := []
	if model_key == "strip":
		var sres := _strip_prepare(p, xy.points, x0, y0)
		if not sres.ok:
			return _err(formula, sres.error)
		segs = sres.segments
		_strip_fill_rows(segs, xy.points, h)
		var seg_rows := PackedStringArray()
		for s in segs:
			seg_rows.append("第%d段：u∈[%.3f, %.3f]，mid=%.3f，%d 点" % [s["idx"] + 1, s["u_lo"], s["u_hi"], s["mid"], s["pt_idx"].size()])
		steps.append({
			"title": "1. 带状分段与拟合原点",
			"formula": "沿 %s 轴等宽分 %d 段，每段独立拟合 %d 参数（分段边界不强制连续）" % [sres.axis, sres.n_segments, sres.order + 1],
			"substitution": "\n".join(seg_rows),
			"result": "拟合原点（重心）(%.4f, %.4f) m" % [x0, y0],
		})
	else:
		var n_unknown := 3 if model_key == "plane" else 6
		if n < n_unknown:
			return _err(formula, "%s需要 %d 个参数，当前仅 %d 个点" % ["平面拟合" if model_key == "plane" else "曲面拟合", n_unknown, n])
		steps.append({
			"title": "1. 模型与中心化",
			"formula": _model_formula(model_key),
			"substitution": "拟合原点（重心）x0=%.4f，y0=%.4f（ξ=x−x0，η=y−y0）" % [x0, y0],
			"result": "%d 点，模型 %d 参数" % [n, n_unknown],
		})
	# —— 组成误差方程并求解 ——
	var total_unknown := 0
	var seg_solutions := []
	if model_key == "strip":
		for s: Dictionary in segs:
			var r := _solve_segment(s["rows"], s["l"], s["order"])
			if not r.ok:
				return _err(formula, r.error)
			total_unknown += r.coeffs.size()
			seg_solutions.append(r)
	else:
		var B := []
		var l := PackedFloat64Array()
		for i in n:
			var q: PackedFloat64Array = xy.points[i]
			var xi := q[0] - x0
			var yi := q[1] - y0
			if model_key == "plane":
				B.append(PackedFloat64Array([1.0, xi, yi]))
			else:
				B.append(PackedFloat64Array([1.0, xi, yi, xi * xi, yi * yi, xi * yi]))
			l.append(h[i])
		var r := _solve_normal(B, l)
		if not r.ok:
			return _err(formula, r.error)
		total_unknown = r.coeffs.size()
		seg_solutions.append(r)
	# —— 残差、σ0、3σ 检核 ——
	var v := PackedFloat64Array()
	v.resize(n)
	var ss := 0.0
	for i in n:
		var hfit := _eval_at(model_key, segs, seg_solutions, xy.points[i], x0, y0)
		v[i] = hfit - h[i]
		ss += v[i] * v[i]
	var redundancy := n - total_unknown
	var sigma0 := sqrt(ss / redundancy) if redundancy > 0 else 0.0
	var warnings := PackedStringArray()
	var outliers := []
	var limit := 3.0 * sigma0
	var residuals := []
	for i in n:
		var q: PackedFloat64Array = xy.points[i]
		residuals.append([i + 1, q[0], q[1], h[i], h[i] + v[i], v[i]])
		if redundancy > 0 and sigma0 > 0.0 and absf(v[i]) > limit:
			outliers.append(i + 1)
			warnings.append("第 %d 点（x=%.3f，y=%.3f）拟合残差 %.4f m 超过 3σ（σ0=%.4f m，3σ=%.4f m），疑似粗差，建议剔除该点后重新拟合" % [i + 1, q[0], q[1], v[i], sigma0, limit])
	var rms := sqrt(ss / n)
	# —— 系数输出（中心化形式 + 绝对坐标形式） ——
	var value := {
		"model_kind": model_key,
		"origin_x_m": x0,
		"origin_y_m": y0,
		"n_points": n,
		"n_unknown": total_unknown,
		"redundancy": redundancy,
		"sigma0_m": sigma0,
		"rms_m": rms,
		"residuals_m": residuals,
		"outliers": outliers,
		"warnings": Array(warnings),
	}
	var model_dict := {}
	var coeffs_center := []
	var coeffs_abs := []
	if model_key == "strip":
		var axis := String(segs[0]["axis"])
		var u_min: float = segs[0]["u_lo"]
		var du: float = segs[0]["u_hi"] - segs[0]["u_lo"]
		var seg_list := []
		var seg_text := PackedStringArray()
		for s_i in segs.size():
			var c: PackedFloat64Array = seg_solutions[s_i]["coeffs"]
			var mid: float = segs[s_i]["mid"]
			var abs_c := _strip_abs_coeffs(c, mid)
			coeffs_center.append(Array(c))
			coeffs_abs.append(abs_c)
			seg_list.append({"mid": mid, "coeffs_center": Array(c), "coeffs_abs": abs_c})
			seg_text.append("第%d段 [%.3f, %.3f]：%s" % [s_i + 1, segs[s_i]["u_lo"], segs[s_i]["u_hi"], _coeff_text(c, "ξ=u−%.3f" % mid)])
		model_dict = {
			"kind": "strip",
			"axis": axis,
			"u_min": u_min,
			"du": du,
			"n_segments": segs.size(),
			"segments": seg_list,
		}
		value["segments"] = seg_text
		steps.append({
			"title": "2. 各段拟合系数",
			"formula": "每段独立最小二乘（N=BᵀB，Cholesky）",
			"substitution": "\n".join(seg_text),
			"result": "共 %d 段、%d 个未知参数" % [segs.size(), total_unknown],
		})
	else:
		var c: PackedFloat64Array = seg_solutions[0]["coeffs"]
		coeffs_center = Array(c)
		if model_key == "plane":
			coeffs_abs = _plane_abs_coeffs(c, x0, y0)
			model_dict = {"kind": "plane", "origin": [x0, y0], "coeffs_center": coeffs_center}
		else:
			coeffs_abs = _surface_abs_coeffs(c, x0, y0)
			model_dict = {"kind": "surface", "origin": [x0, y0], "coeffs_center": coeffs_center}
		value["coeffs_center"] = coeffs_center
		value["coeffs_abs"] = coeffs_abs
		steps.append({
			"title": "2. 法方程组成与求解",
			"formula": "N·ĉ = Bᵀl，N = BᵀB（对称正定，Cholesky 分解求解）",
			"substitution": "N 为 %d×%d 矩阵；B 行按中心化坐标 ξ=x−%.4f、η=y−%.4f 代入" % [total_unknown, total_unknown, x0, y0],
			"result": _coeff_text(c, "中心化形式"),
		})
		steps.append({
			"title": "3. 绝对坐标形式系数（可直接移植）",
			"formula": "H 关于绝对坐标 x、y 的展开",
			"substitution": "由中心化系数平移展开（x0=%.4f，y0=%.4f）" % [x0, y0],
			"result": _coeff_text(PackedFloat64Array(coeffs_abs), "绝对形式"),
		})
	value["model"] = model_dict
	# —— 精度评定与粗差检核步骤 ——
	var step_idx := steps.size() + 1
	steps.append({
		"title": "%d. 精度评定" % step_idx,
		"formula": "σ0 = √(VᵀV / (n − %d))" % total_unknown,
		"substitution": "VᵀV = %.9f m²，自由度 = %d" % [ss, redundancy],
		"result": "σ0 = %.6f m，RMS = %.6f m" % [sigma0, rms],
	})
	if redundancy > 0 and sigma0 > 0.0:
		steps.append({
			"title": "%d. 粗差检核（3σ 准则）" % (step_idx + 1),
			"formula": "|v| > 3σ0 判为疑似粗差",
			"substitution": "3σ0 = %.6f m" % limit,
			"result": "无粗差" if warnings.is_empty() else "\n".join(warnings),
		})
	else:
		steps.append({
			"title": "%d. 粗差检核（3σ 准则）" % (step_idx + 1),
			"formula": "|v| > 3σ0",
			"substitution": "",
			"result": "无多余观测，不具备残差检核能力（结果无精度信息）",
		})
	return {"ok": true, "value": value, "steps": steps, "formula": formula, "error": ""}

## 预测点高程（§5 协议入口）。p：{model: fit() 输出的模型字典, x, y}
static func predict(p: Dictionary) -> Dictionary:
	var md: Variant = p.get("model", {})
	if not (md is Dictionary) or (md as Dictionary).is_empty():
		return _err("H = f(x, y)（用最近一次拟合的模型字典预测）", "缺少模型字典：请先完成一次拟合，或粘贴 fit() 输出的 model")
	var model: Dictionary = md
	var xres := _parse_one(p.get("x"), "预测点 x")
	if not xres.ok:
		return _err("", xres.error)
	var yres := _parse_one(p.get("y"), "预测点 y")
	if not yres.ok:
		return _err("", yres.error)
	var x: float = xres.val
	var y: float = yres.val
	var kind := String(model.get("kind", ""))
	var formula := ""
	var h := NAN
	var extrapolated := false
	var substitution := ""
	if kind == "plane" or kind == "surface":
		var origin: Array = model.get("origin", [])
		if origin.size() != 2:
			return _err("", "模型字典缺少 origin（拟合原点），数据不完整")
		var cc: Array = model.get("coeffs_center", [])
		var need := 3 if kind == "plane" else 6
		if cc.size() != need:
			return _err("", "模型字典系数不完整（应有 %d 个，实际 %d 个）" % [need, cc.size()])
		var xi: float = x - float(origin[0])
		var yi: float = y - float(origin[1])
		h = float(cc[0]) + float(cc[1]) * xi + float(cc[2]) * yi
		if kind == "surface":
			h += float(cc[3]) * xi * xi + float(cc[4]) * yi * yi + float(cc[5]) * xi * yi
		formula = "H = c0 + c1·ξ + c2·η" + (" + c3·ξ² + c4·η² + c5·ξη" if kind == "surface" else "") + "，ξ=x−x0，η=y−y0"
		substitution = "ξ = %.4f − %.4f = %.4f，η = %.4f − %.4f = %.4f，c=(%s)" % [x, float(origin[0]), xi, y, float(origin[1]), yi, _num_list_text(cc)]
	elif kind == "strip":
		var axis := String(model.get("axis", "x"))
		var u := x if axis == "x" else y
		var u_min: float = float(model.get("u_min", NAN))
		var du: float = float(model.get("du", NAN))
		var nseg := int(model.get("n_segments", 0))
		if not (is_finite(u_min) and is_finite(du)) or nseg < 1 or du <= 0.0:
			return _err("", "模型字典分段信息不完整（u_min/du/n_segments）")
		var u_max := u_min + du * nseg
		if u < u_min - 1e-12 or u > u_max + 1e-12:
			extrapolated = true
		var s_idx := int(floor((u - u_min) / du))
		s_idx = clampi(s_idx, 0, nseg - 1)
		var seg: Dictionary = model["segments"][s_idx]
		var mid: float = float(seg["mid"])
		var c: Array = seg["coeffs_center"]
		var xi := u - mid
		h = float(c[0]) + float(c[1]) * xi
		if c.size() > 2:
			h += float(c[2]) * xi * xi
		formula = "带状分段：%s 轴第 %d/%d 段，H = c0 + c1·(u−mid)%s" % [axis, s_idx + 1, nseg, " + c2·(u−mid)²" if c.size() > 2 else ""]
		substitution = "u = %.4f，mid = %.4f，u−mid = %.4f，c=(%s)" % [u, mid, xi, _num_list_text(c)]
	else:
		return _err("", "模型字典 kind 无法识别（应为 plane/surface/strip）：%s" % kind)
	var value := {"h_m": h, "extrapolated": extrapolated}
	var extra := ""
	if extrapolated:
		value["warnings"] = ["预测点超出拟合数据覆盖范围，属外插，可靠性降低"]
		extra = "（外插，可靠性降低）"
	var steps := [{
		"title": "1. 模型代入",
		"formula": formula,
		"substitution": substitution,
		"result": "H = %.6f m%s" % [h, extra],
	}]
	return {"ok": true, "value": value, "steps": steps, "formula": formula, "error": ""}

# ---------- 内部：带状分段准备 ----------

static func _strip_prepare(p: Dictionary, points: Array, x0: float, y0: float) -> Dictionary:
	var axis := String(p.get("axis", "x")).strip_edges().to_lower()
	if axis != "x" and axis != "y":
		return {"ok": false, "error": "带状拟合轴向 axis 仅支持 x 或 y，收到：%s" % axis}
	var n_segments := int(p.get("segments", 2))
	if n_segments < 1:
		return {"ok": false, "error": "分段数 segments 至少为 1，收到：%s" % str(p.get("segments", 2))}
	var order := int(p.get("order", 1))
	if order != 1 and order != 2:
		return {"ok": false, "error": "带状分段每段多项式阶数 order 仅支持 1 或 2，收到：%d" % order}
	var n := points.size()
	var per := order + 1
	if n < n_segments * per:
		return {"ok": false, "error": "带状分段共需至少 %d 点（%d 段 × %d 参数），当前 %d 点" % [n_segments * per, n_segments, per, n]}
	var u_min := INF
	var u_max := -INF
	for q: PackedFloat64Array in points:
		var u := q[0] if axis == "x" else q[1]
		u_min = minf(u_min, u)
		u_max = maxf(u_max, u)
	var du := (u_max - u_min) / n_segments
	if du <= 0.0:
		return {"ok": false, "error": "带状拟合的 %s 坐标范围为零，无法分段" % axis}
	var segs := []
	for s in n_segments:
		segs.append({
			"idx": s,
			"u_lo": u_min + s * du,
			"u_hi": u_min + (s + 1) * du,
			"mid": u_min + (s + 0.5) * du,
			"axis": axis,
			"n_segments": n_segments,
			"order": order,
			"rows": [],
			"l": PackedFloat64Array(),
			"pt_idx": [],
		})
	for i in n:
		var q: PackedFloat64Array = points[i]
		var u := q[0] if axis == "x" else q[1]
		var s_idx := int(floor((u - u_min) / du))
		s_idx = clampi(s_idx, 0, n_segments - 1)
		segs[s_idx]["pt_idx"].append(i)
	return {"ok": true, "segments": segs, "axis": axis, "n_segments": n_segments, "order": order, "error": ""}

# 注意：_strip_prepare 只做分段归类；各行组装在 fit() 主流程中根据 pt_idx 与 h 完成。
# 为避免双重解析 h，fit() 对 strip 分支在调用本函数后按 pt_idx 填充 rows/l。
static func _strip_fill_rows(segs: Array, points: Array, h: PackedFloat64Array) -> void:
	for s: Dictionary in segs:
		var order := int(s["order"])
		var mid: float = s["mid"]
		var rows := []
		var l := PackedFloat64Array()
		for i: int in s["pt_idx"]:
			var q: PackedFloat64Array = points[i]
			var u := q[0] if String(s["axis"]) == "x" else q[1]
			var xi := u - mid
			if order == 2:
				rows.append(PackedFloat64Array([1.0, xi, xi * xi]))
			else:
				rows.append(PackedFloat64Array([1.0, xi]))
			l.append(h[i])
		s["rows"] = rows
		s["l"] = l

# ---------- 内部：正规方程求解 ----------

static func _solve_normal(B: Array, l: PackedFloat64Array) -> Dictionary:
	var At := GKMatrix.transpose(B)
	var N := GKMatrix.multiply(At, B)
	var rhs := GKMatrix.mat_vec(At, l)
	if N.is_empty() or rhs.is_empty():
		return {"ok": false, "error": "法方程组成异常（维度不匹配）"}
	var x := GKMatrix.cholesky_solve(N, rhs)
	var xg := GKMatrix.solve(N, rhs)  # 独立路径互检（高斯消元含相对容差零行/奇异检测）
	if x.is_empty() or xg.is_empty():
		return {"ok": false, "error": "法方程奇异，无法求解——点位分布退化（如所有点共线），请检查点位配置"}
	# 双路径一致性：严重病态时两路径解显著分叉（Cholesky 对近奇异 N 因 sqrt 取整可能漏检）
	var max_x := 1.0
	for val in x:
		max_x = maxf(max_x, absf(val))
	for k in x.size():
		if absf(x[k] - xg[k]) > 1e-4 * max_x:
			return {"ok": false, "error": "法方程严重病态（双解路径不一致），请检查点位几何配置"}
	return {"ok": true, "coeffs": x, "error": ""}

static func _solve_segment(rows: Array, l: PackedFloat64Array, order: int) -> Dictionary:
	var need := order + 1
	if rows.size() < need:
		return {"ok": false, "error": "某分段只有 %d 点，不足 %d 个参数" % [rows.size(), need]}
	var r := _solve_normal(rows, l)
	return r

# ---------- 内部：系数换算与求值 ----------

## 平面：H = c0 + c1·(x−x0) + c2·(y−y0) → H = A0 + A1·x + A2·y
static func _plane_abs_coeffs(c: PackedFloat64Array, x0: float, y0: float) -> Array:
	var a0 := c[0] - c[1] * x0 - c[2] * y0
	return [a0, c[1], c[2]]

## 曲面：H = c0 + c1ξ + c2η + c3ξ² + c4η² + c5ξη → H = A0 + A1x + A2y + A3x² + A4y² + A5xy
static func _surface_abs_coeffs(c: PackedFloat64Array, x0: float, y0: float) -> Array:
	var a0 := c[0] - c[1] * x0 - c[2] * y0 + c[3] * x0 * x0 + c[4] * y0 * y0 + c[5] * x0 * y0
	var a1 := c[1] - 2.0 * c[3] * x0 - c[5] * y0
	var a2 := c[2] - 2.0 * c[4] * y0 - c[5] * x0
	return [a0, a1, a2, c[3], c[4], c[5]]

## 带状单段：H = c0 + c1·(u−mid)[ + c2·(u−mid)²] → H = d0 + d1·u[ + d2·u²]
static func _strip_abs_coeffs(c: PackedFloat64Array, mid: float) -> Array:
	var d2 := c[2] if c.size() > 2 else 0.0
	var d1 := c[1] - 2.0 * d2 * mid
	var d0 := c[0] - c[1] * mid + d2 * mid * mid
	if c.size() > 2:
		return [d0, d1, d2]
	return [d0, d1]

## 在某点求拟合值（fit 内部：segs/seg_solutions 两种形态统一）
static func _eval_at(model_key: String, segs: Array, seg_solutions: Array, q: PackedFloat64Array, x0: float, y0: float) -> float:
	if model_key == "strip":
		var axis := String(segs[0]["axis"])
		var u_min: float = segs[0]["u_lo"]
		var du: float = segs[0]["u_hi"] - segs[0]["u_lo"]
		var u := q[0] if axis == "x" else q[1]
		var s_idx := int(floor((u - u_min) / du))
		s_idx = clampi(s_idx, 0, segs.size() - 1)
		var c: PackedFloat64Array = seg_solutions[s_idx]["coeffs"]
		var xi := u - float(segs[s_idx]["mid"])
		var h := c[0] + c[1] * xi
		if c.size() > 2:
			h += c[2] * xi * xi
		return h
	var xi := q[0] - x0
	var yi := q[1] - y0
	var cc: PackedFloat64Array = seg_solutions[0]["coeffs"]
	var h2 := cc[0] + cc[1] * xi + cc[2] * yi
	if cc.size() > 3:
		h2 += cc[3] * xi * xi + cc[4] * yi * yi + cc[5] * xi * yi
	return h2

# ---------- 内部：解析与文本 ----------

static func _norm_model(s: String) -> String:
	var t := s.strip_edges().to_lower()
	if t == "plane" or t == "平面" or t == "平面拟合" or t == "planar":
		return "plane"
	if t == "surface" or t == "曲面" or t == "曲面拟合" or t == "quad" or t == "二次曲面":
		return "surface"
	if t == "strip" or t == "带状" or t == "带状分段" or t == "分段" or t == "带状拟合":
		return "strip"
	return t  # 未知值留给主流程报中文错

static func _model_formula(model_key: String) -> String:
	match model_key:
		"plane":
			return "平面拟合：H = c0 + c1·ξ + c2·η（ξ=x−x0，η=y−y0，重心为原点）"
		"surface":
			return "曲面拟合：H = c0 + c1·ξ + c2·η + c3·ξ² + c4·η² + c5·ξη（二次多项式 6 参数）"
		"strip":
			return "带状分段拟合：沿线轴向等宽分段，每段 H = c0 + c1·(u−mid) [+ c2·(u−mid)²]"
	return "未知模型：%s（支持 plane 平面 / surface 曲面 / strip 带状分段）" % model_key

static func _parse_points(v: Variant, dim: int) -> Dictionary:
	if not (v is Array) or (v as Array).is_empty():
		return {"ok": false, "points": [], "error": "点集为空：请输入至少 1 个点（每行 x,y）"}
	var pts := []
	var arr: Array = v
	for i in arr.size():
		var item: Variant = arr[i]
		if not (item is Array or item is PackedFloat64Array):
			return {"ok": false, "points": [], "error": "第 %d 个点不是数组（应为 x,y 数值列表）" % (i + 1)}
		var vals := PackedFloat64Array()
		var raw: Array = Array(item) if item is PackedFloat64Array else (item as Array)
		if raw.size() != dim:
			return {"ok": false, "points": [], "error": "第 %d 个点应为 %d 个分量，实际 %d 个" % [i + 1, dim, raw.size()]}
		for j in raw.size():
			var rv: Variant = raw[j]
			if not (rv is float or rv is int or rv is String):
				return {"ok": false, "points": [], "error": "第 %d 个点第 %d 分量类型不支持" % [i + 1, j + 1]}
			var f := 0.0
			if rv is String:
				var s := String(rv).strip_edges()
				if s.is_empty():
					return {"ok": false, "points": [], "error": "第 %d 个点第 %d 分量为空" % [i + 1, j + 1]}
				if not s.is_valid_float():
					return {"ok": false, "points": [], "error": "第 %d 个点第 %d 分量不是有效数字：“%s”" % [i + 1, j + 1, s]}
				f = s.to_float()
			else:
				f = float(rv)
			if not is_finite(f):
				return {"ok": false, "points": [], "error": "第 %d 个点第 %d 分量不是有限数值" % [i + 1, j + 1]}
			vals.append(f)
		pts.append(vals)
	return {"ok": true, "points": pts, "error": ""}

static func _parse_floats(v: Variant, what: String) -> Dictionary:
	if not (v is Array) or (v as Array).is_empty():
		return {"ok": false, "vals": PackedFloat64Array(), "error": "%s 为空：请至少输入 1 个数值" % what}
	var vals := PackedFloat64Array()
	var arr: Array = v
	for i in arr.size():
		var rv: Variant = arr[i]
		if not (rv is float or rv is int or rv is String):
			return {"ok": false, "vals": PackedFloat64Array(), "error": "%s 第 %d 个值类型不支持" % [what, i + 1]}
		var f := 0.0
		if rv is String:
			var s := String(rv).strip_edges()
			if s.is_empty() or not s.is_valid_float():
				return {"ok": false, "vals": PackedFloat64Array(), "error": "%s 第 %d 个值不是有效数字：“%s”" % [what, i + 1, s]}
			f = s.to_float()
		else:
			f = float(rv)
		if not is_finite(f):
			return {"ok": false, "vals": PackedFloat64Array(), "error": "%s 第 %d 个值不是有限数值" % [what, i + 1]}
		vals.append(f)
	return {"ok": true, "vals": vals, "error": ""}

static func _parse_one(v: Variant, what: String) -> Dictionary:
	var r := _parse_floats([v], what)
	if not r.ok:
		return r
	return {"ok": true, "val": r.vals[0], "error": ""}

static func _num_list_text(arr: Array) -> String:
	var parts := PackedStringArray()
	for v: Variant in arr:
		parts.append("%.9f" % float(v))
	return ", ".join(parts)

static func _coeff_text(c: PackedFloat64Array, prefix: String) -> String:
	var names := []
	if c.size() == 3:
		names = ["c0", "c1", "c2"]
	elif c.size() == 6:
		names = ["c0", "c1", "c2", "c3", "c4", "c5"]
	else:
		names = ["d0", "d1", "d2"]
	var parts := PackedStringArray()
	for i in c.size():
		parts.append("%s = %.9f" % [names[i], c[i]])
	return "%s：%s" % [prefix, "，".join(parts)]

static func _err(formula: String, msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": formula, "error": msg}
