# core/route/alignment_el.gd —— GK-M7-4 线元法 D2（直线/缓和曲线/圆曲线元拼接）
#
# 设计约定（docs/ARCHITECTURE.md §4 GK-M7 / §5）：
#   - 纯静态、零引擎依赖；坐标系：x=东(E)、y=北(N)，方位角自北起顺时针；
#   - ★ 线元（element）契约（D 组冻结，D1/D4/D6 复用，只增不改）：
#       {"type": "line"|"arc"|"spiral",    # 类型仅用于展示/校验提示
#        "len":  float,                    # 线元长度 (m)，>0
#        "k0":   float, "k1": float}       # 带符号曲率 (1/m)：右转(顺时针)为正；
#                                          # line 段 k0=k1=0；arc 段 k0=k1=±1/R；
#                                          # spiral 段曲率沿弧长线性过渡 k(s)=k0+(k1−k0)s/len
#     起点 start = {"x_m": 东, "y_m": 北, "bearing_deg": 方位角, "chain_m": 起点里程(默认0)}
#   - 定位积分：θ(s)=θ0+k0·s+(k1−k0)s²/(2L)，位置为 ∫(cosθ,sinθ)ds：
#       路径A 公式链：常曲率解析闭式（直线/圆曲线）+ 16 阶幂级数展开（广义缓和段）；
#       路径B 数值积分：自适应辛普森（任意转角精度可靠，生产路径）；
#     双路径互检由 tests/route/test_alignment_el.gd 承担（架构 §4 GK-M7 要求）；
#   - 校验失败返回 ok=false + 中文 error；纯核函数失败返回空容器（地基纪律）。
class_name GKAlignmentEl
extends RefCounted

const K_TOL := 1e-13       # 曲率差判零阈值（1/m）
const CHAIN_TOL := 1e-6    # 里程越界容差 (m)

# ---------- 元素构造器（返回线元字典，供 UI/其他模块组装） ----------

static func make_line(len: float) -> Dictionary:
	return {"type": "line", "len": len, "k0": 0.0, "k1": 0.0}

## 圆曲线元：r>0，turn_deg 带符号转角（右转正/左转负），长度 = r·|turn|
static func make_arc(r: float, turn_deg: float) -> Dictionary:
	var k := 0.0 if r <= 0.0 else 1.0 / r
	var turn_rad := deg_to_rad(turn_deg)
	return {"type": "arc", "len": absf(r * turn_rad), "k0": k * (1.0 if turn_deg >= 0.0 else -1.0),
			"k1": k * (1.0 if turn_deg >= 0.0 else -1.0)}

## 缓和曲线元：r0→r1 半径过渡（INF 表示直线上曲率 0），dir=+1右/−1左
static func make_spiral(r0: float, r1: float, len: float, dir: int) -> Dictionary:
	var k0 := 0.0 if r0 <= 0.0 else dir * 1.0 / r0
	var k1 := 0.0 if r1 <= 0.0 else dir * 1.0 / r1
	return {"type": "spiral", "len": len, "k0": k0, "k1": k1}

## 元素总转角（rad，带符号）：Σ (k0+k1)/2·len —— 曲率对弧长的积分
static func turn_total_rad(elements: Array) -> float:
	var t := 0.0
	for el: Dictionary in elements:
		var ln := _num(el.get("len", NAN))
		var k0 := _num(el.get("k0", 0.0)) if el.has("k0") else 0.0
		var k1 := _num(el.get("k1", 0.0)) if el.has("k1") else 0.0
		if is_nan(ln) or is_nan(k0) or is_nan(k1):
			return NAN
		t += (k0 + k1) * 0.5 * ln
	return t

# ---------- 积分内核 ----------

## 元素内 bearing（rad，未规范化，连续累计）。
static func bearing_at_rad(theta0: float, k0: float, k1: float, len: float, s: float) -> float:
	var ls := clampf(s, 0.0, len)
	return theta0 + k0 * ls + (k1 - k0) * ls * ls / (2.0 * len)

## 相对元素起点的全局轴增量 [dn, de]（生产路径：常曲率解析 / 广义缓和段辛普森）。
## 非法输入返回空。
static func local_delta(theta0: float, k0: float, k1: float, len: float, s: float) -> PackedFloat64Array:
	if not (is_finite(theta0) and is_finite(k0) and is_finite(k1) and is_finite(len)) \
			or len <= 0.0 or s < -1e-9:
		return PackedFloat64Array()
	var ls := clampf(s, 0.0, len)
	var dk := k1 - k0
	if absf(dk) < K_TOL:
		# 常曲率：直线 / 圆曲线解析闭式
		if absf(k0) < K_TOL:
			return PackedFloat64Array([ls * cos(theta0), ls * sin(theta0)])
		var the := theta0 + k0 * ls
		return PackedFloat64Array([(sin(the) - sin(theta0)) / k0, (cos(theta0) - cos(the)) / k0])
	var f := func(t: float) -> PackedFloat64Array:
		var th := theta0 + k0 * t + dk * t * t / (2.0 * len)
		return PackedFloat64Array([cos(th), sin(th)])
	var v := _simpson(f, 0.0, ls)
	return PackedFloat64Array([v[0], v[1]])

## 自适应辛普森积分（双分量 PackedFloat64Array 被积函数；全程 float64，
## 不用 Vector2——其为 32 位浮点，测量级计算精度不足；与 local_delta_series 构成双路径）
static func _simpson(f: Callable, a: float, b: float, eps := 1e-12, depth := 50) -> PackedFloat64Array:
	if a == b:
		return PackedFloat64Array([0.0, 0.0])
	var fa: PackedFloat64Array = f.call(a)
	var fb: PackedFloat64Array = f.call(b)
	var fm: PackedFloat64Array = f.call((a + b) * 0.5)
	return _simpson_rec(f, a, b, fa, fm, fb, eps, depth)

static func _simpson_rec(f: Callable, a: float, b: float, fa: PackedFloat64Array, fm: PackedFloat64Array, fb: PackedFloat64Array, tol: float, depth: int) -> PackedFloat64Array:
	var m := (a + b) * 0.5
	var whole := PackedFloat64Array([(b - a) / 6.0 * (fa[0] + 4.0 * fm[0] + fb[0]), (b - a) / 6.0 * (fa[1] + 4.0 * fm[1] + fb[1])])
	var fl: PackedFloat64Array = f.call((a + m) * 0.5)
	var fr: PackedFloat64Array = f.call((m + b) * 0.5)
	var left := PackedFloat64Array([(m - a) / 6.0 * (fa[0] + 4.0 * fl[0] + fm[0]), (m - a) / 6.0 * (fa[1] + 4.0 * fl[1] + fm[1])])
	var right := PackedFloat64Array([(b - m) / 6.0 * (fm[0] + 4.0 * fr[0] + fb[0]), (b - m) / 6.0 * (fm[1] + 4.0 * fr[1] + fb[1])])
	var err := sqrt(pow(left[0] + right[0] - whole[0], 2.0) + pow(left[1] + right[1] - whole[1], 2.0))
	if depth <= 0 or err <= 15.0 * tol:
		return PackedFloat64Array([left[0] + right[0] + (left[0] + right[0] - whole[0]) / 15.0,
				left[1] + right[1] + (left[1] + right[1] - whole[1]) / 15.0])
	var lrec := _simpson_rec(f, a, m, fa, fl, fm, tol * 0.5, depth - 1)
	var rrec := _simpson_rec(f, m, b, fm, fr, fb, tol * 0.5, depth - 1)
	return PackedFloat64Array([lrec[0] + rrec[0], lrec[1] + rrec[1]])

## 双路径之公式链：16 阶幂级数展开 e^{i(k0 t + dk t²/2L)} 逐阶累加积分。
## 供与 local_delta 互检；转角过大（|θ|>约1.2 rad）时级数截断误差增大，
## 生产请用 local_delta。非法输入返回空。
static func local_delta_series(theta0: float, k0: float, k1: float, len: float, s: float, order := 16) -> PackedFloat64Array:
	if not (is_finite(theta0) and is_finite(k0) and is_finite(k1) and is_finite(len)) \
			or len <= 0.0 or s < -1e-9:
		return PackedFloat64Array()
	var ls := clampf(s, 0.0, len)
	var dk := k1 - k0
	var aq := k0            # t 项系数（乘 i 后进入指数）
	var bq := dk / (2.0 * len)  # t² 项系数
	var cr := PackedFloat64Array()
	var ci := PackedFloat64Array()
	cr.resize(order + 1)
	ci.resize(order + 1)
	cr[0] = 1.0
	ci[0] = 0.0
	var zr := 0.0
	var zi := 0.0
	for n in range(order + 1):
		if n > 0:
			var ncr := PackedFloat64Array()
			var nci := PackedFloat64Array()
			ncr.resize(order + 1)
			nci.resize(order + 1)
			# (A·t + B·t²)/n，A=i·aq，B=i·bq
			for p in range(order + 1):
				if cr[p] == 0.0 and ci[p] == 0.0:
					continue
				if p + 1 <= order:
					ncr[p + 1] += -ci[p] * aq / n
					nci[p + 1] += cr[p] * aq / n
				if p + 2 <= order:
					ncr[p + 2] += -ci[p] * bq / n
					nci[p + 2] += cr[p] * bq / n
			cr = ncr
			ci = nci
		for p in range(order + 1):
			if cr[p] != 0.0:
				zr += cr[p] * pow(ls, p + 1) / (p + 1)
			if ci[p] != 0.0:
				zi += ci[p] * pow(ls, p + 1) / (p + 1)
	var dn := zr * cos(theta0) - zi * sin(theta0)
	var de := zr * sin(theta0) + zi * cos(theta0)
	return PackedFloat64Array([dn, de])

# ---------- 协议入口 ----------

## D2-装配：线元序列 + 起点 → 分段信息。value.segs 为机器可读分段表。
static func build(p: Dictionary) -> Dictionary:
	var els := _check_elements(p.get("elements", []))
	if els.is_empty():
		return _err("elements 须为非空线元数组，每个线元含 len>0 与曲率 k0/k1（契约见 core/route/alignment_el.gd 头注）")
	var st := _check_start(p.get("start", {}))
	if st.is_empty():
		return _err("start 须含 x_m、y_m、bearing_deg（数字），chain_m 可选")
	var segs := _assemble(els, st)
	if segs.is_empty():
		return _err("线元装配失败：存在非法线元（len<=0 或曲率非数字）")
	var value := {"total_len_m": 0.0, "start_x_m": st["x"], "start_y_m": st["y"],
			"start_bearing_deg": rad_to_deg(st["th"]), "chain0_m": st["chain"], "segs": segs}
	value["total_len_m"] = float(segs[segs.size() - 1]["chain1_m"]) - st["chain"]
	var steps := []
	for seg: Dictionary in segs:
		steps.append({
			"title": "线元%d：%s（长 %.4f m，里程 %s ~ %s）" % [seg["index"], _type_cn(seg["type"]), seg["len_m"], _chain_str(seg["chain0_m"]), _chain_str(seg["chain1_m"])],
			"formula": "θ(s) = θ0 + k0·s + (k1−k0)·s²/(2L)；(Δn,Δe) = ∫(cosθ,sinθ)ds",
			"substitution": "θ0=%.4f°，k0=%.8f，k1=%.8f" % [seg["bearing0_deg"], seg["k0"], seg["k1"]],
			"result": "终点(%s, %s)，方位 %.4f°" % [String.num(seg["x1_m"], 4), String.num(seg["y1_m"], 4), seg["bearing1_deg"]],
		})
	return {"ok": true, "value": value, "steps": steps,
			"formula": "线元法：任意线元曲率沿弧长线性过渡（直线/圆曲线/缓和曲线统一模型），坐标由 ∫cosθ、∫sinθ 积分得（常曲率解析、广义缓和段自适应辛普森）",
			"error": ""}

## D2-正算：里程 → 坐标/方位/曲率。
static func point_at(p: Dictionary) -> Dictionary:
	var els := _check_elements(p.get("elements", []))
	if els.is_empty():
		return _err("elements 须为非空线元数组")
	var st := _check_start(p.get("start", {}))
	if st.is_empty():
		return _err("start 须含 x_m、y_m、bearing_deg（数字）")
	var chain := _num(p.get("chain_m", NAN))
	if is_nan(chain):
		return _err("chain_m 须为数字里程（m）")
	var segs := _assemble(els, st)
	if segs.is_empty():
		return _err("线元装配失败：存在非法线元")
	var c0: float = st["chain"]
	var c1: float = segs[segs.size() - 1]["chain1_m"]
	if chain < c0 - CHAIN_TOL or chain > c1 + CHAIN_TOL:
		return _err("里程 %s 超出路线范围 [%s, %s]，请检查桩号" % [_chain_str(chain), _chain_str(c0), _chain_str(c1)])
	chain = clampf(chain, c0, c1)
	var seg: Dictionary = {}
	for g: Dictionary in segs:
		if chain <= float(g["chain1_m"]) + CHAIN_TOL:
			seg = g
			break
	if seg.is_empty():
		seg = segs[segs.size() - 1]
	var s := chain - float(seg["chain0_m"])
	var th0 := deg_to_rad(float(seg["bearing0_deg"]))
	var pt := _seg_point(seg, st, s)
	if pt.is_empty():
		return _err("里程定位计算失败")
	var th := bearing_at_rad(th0, float(seg["k0"]), float(seg["k1"]), float(seg["len_m"]), s)
	var k_mid := float(seg["k0"]) + (float(seg["k1"]) - float(seg["k0"])) * s / maxf(float(seg["len_m"]), 1e-12)
	var radius := 0.0 if absf(k_mid) < K_TOL else 1.0 / absf(k_mid)
	return {"ok": true, "value": {
				"x_m": pt[0], "y_m": pt[1],
				"bearing_deg": rad_to_deg(th),
				"elem_index": int(seg["index"]),
				"elem_type_cn": _type_cn(seg["type"]),
				"s_in_elem_m": s,
				"radius_m": radius,
				"curvature_rad_per_m": k_mid,
				"chain_m": chain,
			},
			"steps": [{
				"title": "里程定位（线元%d %s）" % [seg["index"], _type_cn(seg["type"])],
				"formula": "θ(s) = θ0 + k0·s + (k1−k0)·s²/(2L)；X = x0 + Δe，Y = y0 + Δn",
				"substitution": "桩号 %s：线元内 s = %.4f m，θ0=%.4f°" % [_chain_str(chain), s, float(seg["bearing0_deg"])],
				"result": "X=%.4f m，Y=%.4f m，切线方位 %.4f°" % [pt[0], pt[1], rad_to_deg(th)],
			}],
			"formula": "线元法正算：里程 → 线元定位 → 曲率积分得坐标",
			"error": ""}

## D2-采样：等间距桩号列 → 坐标/方位数组（纵横断面、D4 放样、D7 路基共用）
static func sample(p: Dictionary) -> Dictionary:
	var els := _check_elements(p.get("elements", []))
	if els.is_empty():
		return _err("elements 须为非空线元数组")
	var st := _check_start(p.get("start", {}))
	if st.is_empty():
		return _err("start 须含 x_m、y_m、bearing_deg（数字）")
	var step := _num(p.get("step_m", NAN))
	if is_nan(step) or step <= 0.0:
		return _err("step_m 须为正数采样间距（m）")
	var segs := _assemble(els, st)
	if segs.is_empty():
		return _err("线元装配失败")
	var c0: float = st["chain"]
	var total: float = float(segs[segs.size() - 1]["chain1_m"]) - c0
	var n := int(floor(total / step)) + 1
	var chains := PackedFloat64Array()
	var xs := PackedFloat64Array()
	var ys := PackedFloat64Array()
	var bs := PackedFloat64Array()
	var idx := 0
	for i in n:
		var chain := c0 + step * i
		if i == n - 1 and total > step * (n - 1):
			chain = c0 + total  # 末点补齐
		var seg: Dictionary = segs[idx]
		while chain > float(seg["chain1_m"]) + CHAIN_TOL and idx < segs.size() - 1:
			idx += 1
			seg = segs[idx]
		var s := chain - float(seg["chain0_m"])
		var th0 := deg_to_rad(float(seg["bearing0_deg"]))
		var pt := _seg_point(seg, st, s)
		if pt.is_empty():
			return _err("采样点计算失败（里程 %s）" % _chain_str(chain))
		chains.append(chain)
		xs.append(pt[0])
		ys.append(pt[1])
		bs.append(rad_to_deg(bearing_at_rad(th0, float(seg["k0"]), float(seg["k1"]), float(seg["len_m"]), s)))
	return {"ok": true, "value": {
				"chains_m": chains, "xs_m": xs, "ys_m": ys, "bearings_deg": bs,
				"count": chains.size(), "total_len_m": total,
			},
			"steps": [{"title": "等间距采样", "formula": "桩号 = 起点 + i·step（末点取路线终点）",
				"substitution": "step = %.4f m，总长 %.4f m" % [step, total],
				"result": "共 %d 点" % chains.size()}],
			"formula": "线元法等间距采样（首尾必含）",
			"error": ""}

## D2-反算：坐标 → 最近里程 + 偏距（右正左负）。
## 逐线元粗扫 128 点 + 三分/黄金分割细化，对大转角圆曲线同样稳健。
static func inverse(p: Dictionary) -> Dictionary:
	var els := _check_elements(p.get("elements", []))
	if els.is_empty():
		return _err("elements 须为非空线元数组")
	var st := _check_start(p.get("start", {}))
	if st.is_empty():
		return _err("start 须含 x_m、y_m、bearing_deg（数字）")
	var px := _num(p.get("x_m", NAN))
	var py := _num(p.get("y_m", NAN))
	if is_nan(px) or is_nan(py):
		return _err("x_m、y_m 须为数字坐标（东、北）")
	var segs := _assemble(els, st)
	if segs.is_empty():
		return _err("线元装配失败")
	var best_d2 := INF
	var best_chain := NAN
	var best_idx := -1
	var best_s := 0.0
	for seg: Dictionary in segs:
		var ln: float = seg["len_m"]
		var n_samples := 128
		var lb := 0.0
		var ld2 := INF
		for i in range(n_samples + 1):
			var s := ln * i / n_samples
			var pt := _seg_point(seg, st, s)
			var d2v := pow(pt[0] - px, 2.0) + pow(pt[1] - py, 2.0)
			if d2v < ld2:
				ld2 = d2v
				lb = s
		# 黄金分割细化 [lb−h, lb+h]
		var h := ln / n_samples
		var lo := maxf(lb - h, 0.0)
		var hi := minf(lb + h, ln)
		var gr := (sqrt(5.0) - 1.0) / 2.0
		var c1 := hi - gr * (hi - lo)
		var c2 := lo + gr * (hi - lo)
		var f1 := _d2(seg, st, c1, px, py)
		var f2 := _d2(seg, st, c2, px, py)
		for _it in 80:
			if f1 < f2:
				hi = c2
				c2 = c1
				f2 = f1
				c1 = hi - gr * (hi - lo)
				f1 = _d2(seg, st, c1, px, py)
			else:
				lo = c1
				c1 = c2
				f1 = f2
				c2 = lo + gr * (hi - lo)
				f2 = _d2(seg, st, c2, px, py)
		var s_best := (lo + hi) * 0.5
		var d2_best := _d2(seg, st, s_best, px, py)
		if d2_best < best_d2:
			best_d2 = d2_best
			best_chain = float(seg["chain0_m"]) + s_best
			best_idx = int(seg["index"])
			best_s = s_best
	var foot := _seg_point(segs[best_idx], st, best_s)
	var th := deg_to_rad(float(segs[best_idx]["bearing0_deg"]))
	var k0: float = segs[best_idx]["k0"]
	var k1: float = segs[best_idx]["k1"]
	var ln2: float = segs[best_idx]["len_m"]
	th = bearing_at_rad(th, k0, k1, ln2, best_s)
	# 偏距：P−F 在"右法线"上的投影（右正左负）。右法线（东,北）= (cosθ, −sinθ)
	var offset := (px - foot[0]) * cos(th) + (py - foot[1]) * (-sin(th))
	var side := "右侧" if offset >= 0.0 else "左侧"
	return {"ok": true, "value": {
				"chain_m": best_chain,
				"offset_m": offset,
				"offset_side": side,
				"min_dist_m": sqrt(maxf(best_d2, 0.0)),
				"elem_index": best_idx,
				"elem_type_cn": _type_cn(segs[best_idx]["type"]),
				"foot_x_m": foot[0],
				"foot_y_m": foot[1],
				"bearing_deg": rad_to_deg(th),
			},
			"steps": [{
				"title": "坐标反算（最近点法）",
				"formula": "min‖P − Q(s)‖²，s∈各线元；偏距 = (P−F)·右法线",
				"substitution": "P=(%.4f, %.4f)，落于线元%d（%s）" % [px, py, best_idx, _type_cn(segs[best_idx]["type"])],
				"result": "桩号 %s，偏距 %.4f m（%s），垂距 %.4f m" % [_chain_str(best_chain), offset, side, sqrt(maxf(best_d2, 0.0))],
			}],
			"formula": "线元法反算：逐线元最近点搜索（粗扫+黄金分割细化）→ 桩号与偏距",
			"error": ""}

# ---------- 内部工具 ----------

## 装配线元序列 → 分段表（全局坐标累计）。失败返回 []。
static func _assemble(els: Array, st: Dictionary) -> Array:
	var segs := []
	var x: float = st["x"]
	var y: float = st["y"]
	var th: float = st["th"]
	var chain: float = st["chain"]
	for i in els.size():
		var el: Dictionary = els[i]
		var ln := _num(el.get("len", NAN))
		var k0 := _num(el.get("k0", 0.0)) if el.has("k0") else 0.0
		var k1 := _num(el.get("k1", 0.0)) if el.has("k1") else 0.0
		if is_nan(ln) or ln <= 0.0 or is_nan(k0) or is_nan(k1):
			return []
		var d := local_delta(th, k0, k1, ln, ln)
		if d.is_empty():
			return []
		var th1 := bearing_at_rad(th, k0, k1, ln, ln)
		segs.append({
			"index": i,
			"type": String(el.get("type", "spiral")),
			"len_m": ln, "k0": k0, "k1": k1,
			"chain0_m": chain, "chain1_m": chain + ln,
			"x0_m": x, "y0_m": y, "bearing0_deg": rad_to_deg(th),
			"x1_m": x + d[1], "y1_m": y + d[0], "bearing1_deg": rad_to_deg(th1),
			"turn_deg": rad_to_deg(th1 - th),
		})
		x = x + d[1]
		y = y + d[0]
		th = th1
		chain = chain + ln
	return segs

## 线元内 s 处全局坐标 [x_east, y_north]（用 seg 表中起点/方位）
static func _seg_point(seg: Dictionary, st: Dictionary, s: float) -> PackedFloat64Array:
	var d := local_delta(deg_to_rad(float(seg["bearing0_deg"])), float(seg["k0"]), float(seg["k1"]), float(seg["len_m"]), s)
	if d.is_empty():
		return PackedFloat64Array()
	return PackedFloat64Array([float(seg["x0_m"]) + d[1], float(seg["y0_m"]) + d[0]])

static func _d2(seg: Dictionary, st: Dictionary, s: float, px: float, py: float) -> float:
	var pt := _seg_point(seg, st, s)
	return pow(pt[0] - px, 2.0) + pow(pt[1] - py, 2.0)

static func _check_elements(v: Variant) -> Array:
	if not (v is Array) or (v as Array).is_empty():
		return []
	for el: Variant in v as Array:
		if not (el is Dictionary):
			return []
		var ln := _num((el as Dictionary).get("len", NAN))
		if is_nan(ln) or ln <= 0.0:
			return []
		var typ := String((el as Dictionary).get("type", "spiral"))
		if typ == "line":
			continue  # line 允许省略 k0/k1（默认 0）
		var k0 := _num((el as Dictionary).get("k0", NAN))
		var k1 := _num((el as Dictionary).get("k1", NAN))
		if is_nan(k0) or is_nan(k1):
			return []
	return v as Array

static func _check_start(v: Variant) -> Dictionary:
	if not (v is Dictionary):
		return {}
	var x := _num((v as Dictionary).get("x_m", NAN))
	var y := _num((v as Dictionary).get("y_m", NAN))
	var az := _num((v as Dictionary).get("bearing_deg", NAN))
	if is_nan(x) or is_nan(y) or is_nan(az):
		return {}
	var chain := _num((v as Dictionary).get("chain_m", 0.0)) if (v as Dictionary).has("chain_m") else 0.0
	if is_nan(chain):
		return {}
	return {"x": x, "y": y, "th": deg_to_rad(az), "chain": chain}

static func _type_cn(t: String) -> String:
	match t:
		"line": return "直线"
		"arc": return "圆曲线"
		_: return "缓和曲线"

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
