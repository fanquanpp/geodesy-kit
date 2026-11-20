# core/adjustment/leveling.gd —— GK-M6-3 水准测量（C6 单一水准路线 / C7 水准网平差·间接+条件双实现 / 三角高程）
#
# 设计约定（docs/ARCHITECTURE.md §4 GK-M6 / §5 协议）：
#   - C7 水准网提供间接平差与条件平差两条独立实现，结果互检（ARCHITECTURE §7.3 双法互检纪律）；
#     两法输出残差 V 应逐位一致（法方程均为满秩对称正定，双精度解到 ~1e-12）；
#   - 条件平差的独立闭合环用生成树找环（BFS 生成树 + 非树边成环），条件系数 ±1；
#   - 权约定：p_i = 1/L_km（按路线长度定权，教材口径）；obs 显式给 "w" 时优先用 w；
#   - 间接平差法方程 N = BᵀPB 对称正定（网连通且有起算数据时），走 GKMatrix.cholesky_solve；
#   - 三角高程：单向 h = D·tanα + i − v + (1−k)·D²/(2R)；对向观测取均值时球气差自动抵消；
#     k（大气折光系数）默认 0.13、R 默认 6371008.7714 m，均可由用户传入；
#   - 全部静态函数、零引擎依赖；输入非法返回 {"ok":false,"error":中文}；超限返回 ok=true 且 ok_limit=false。
class_name GKAdjustLeveling
extends RefCounted

## C6 单一水准路线闭合差与高差改正
## p = {h_start: H_A, h_end: H_B（附合）或 loop: true（闭合环，起终同点）,
##      segs: [{h: 高差 m, L_km: 路线长 km}...], point_names?: [...], limit_mm?（自输限差，可选）}
static func single_route(p: Dictionary) -> Dictionary:
	if not p.has("h_start") or not _finite_num(p.get("h_start")):
		return _fail("缺少起点高程 h_start（m）")
	var is_loop := bool(p.get("loop", false))
	if not is_loop and (not p.has("h_end") or not _finite_num(p.get("h_end"))):
		return _fail("附合路线缺少终点已知高程 h_end（m）；闭合环请传 loop:true")
	var segs_v: Variant = p.get("segs")
	if not (segs_v is Array) or (segs_v as Array).is_empty():
		return _fail("缺少测段 segs（每段 {h: 高差 m, L_km: 路线长 km}）")
	var hs := PackedFloat64Array()
	var ls := PackedFloat64Array()
	for s: Dictionary in segs_v:
		if not s.has("h") or not _finite_num(s.get("h")):
			return _fail("测段高差 h 含非法数值（空/非数字/NaN）")
		if s.has("L_km") and _finite_num(s.get("L_km")) and float(s["L_km"]) > 0.0:
			ls.append(float(s["L_km"]))
		else:
			return _fail("测段路线长 L_km 必须为正数（用于按长度定权分配改正）")
		hs.append(float(s["h"]))
	var n := hs.size()
	var sum_h := _sum(hs)
	var fh := sum_h if is_loop else sum_h - (float(p["h_end"]) - float(p["h_start"]))
	var sum_l := _sum(ls)
	if sum_l <= 0.0:
		return _fail("路线总长为零，无法分配改正数")
	# 高差改正：按路线长比例反号分配
	var vs := PackedFloat64Array()
	for i in n:
		vs.append(-fh * ls[i] / sum_l)
	# 改正后测段高差与各点高程
	var names := _route_names(p, n)
	var value := {}
	var h_pt := float(p["h_start"])
	value["H_%s_m" % names[0]] = h_pt
	for i in n:
		h_pt += hs[i] + vs[i]
		value["H_%s_m" % names[i + 1]] = h_pt
	value["fh_m"] = fh
	value["fh_mm"] = fh * 1000.0
	value["sum_h_m"] = sum_h
	value["sum_l_km"] = sum_l
	value["v_m"] = vs
	value["v_mm"] = _scaled(vs, 1000.0)
	# 限差检核（自输限差；规范限差表未核读，不伪造标准值）
	if p.has("limit_mm") and is_finite(float(p["limit_mm"])):
		var lim := absf(float(p["limit_mm"]))
		value["limit_fh_mm"] = lim
		value["f_fh_mm"] = fh * 1000.0
		value["ok_limit"] = absf(fh * 1000.0) <= lim
		value["basis"] = "用户输入限差（未核读 GB 50026 等规范限差表，data/tolerance.json 为占位）"
	var steps := [
		{
			"title": "1. 高差闭合差",
			"formula": "附合：fh = Σh − (H_终 − H_起)；闭合环：fh = Σh",
			"substitution": "Σh = %s m，闭合差 fh = %s m = %s mm" % [_fmt(sum_h), _fmt(fh), _fmt(fh * 1000.0)],
			"result": "%d 个测段，路线总长 %s km" % [n, _fmt(sum_l)],
		},
		{
			"title": "2. 高差改正（按路线长比例反号分配）",
			"formula": "v_i = −fh · L_i / ΣL",
			"substitution": "首段改正 v_1 = −(%s)×%s/%s = %s m" % [_fmt(fh), _fmt(ls[0]), _fmt(sum_l), _fmt(vs[0])],
			"result": "Σv = %s m（应恰为 −fh）" % _fmt(-fh),
		},
		{
			"title": "3. 改正后高程推算",
			"formula": "H_{i+1} = H_i + h_i + v_i",
			"substitution": "逐段累加",
			"result": "终点推算高程 %s m" % _fmt(value["H_%s_m" % names[n]]),
		},
	]
	return _ok(value, steps, "单一水准路线高差改正（按路线长比例分配）")

## C7 水准网平差——间接平差（参数：未知点高程）
## p = {known: {name: H}, approx: {name: H0}, obs: [{from, to, h, L_km 或 w}]}
## 返回与 network_condition 同构（value.v_m / mu_m / dof / H_各点_m），供双法互检
static func network_indirect(p: Dictionary) -> Dictionary:
	var prep := _prepare_net(p)
	if prep.get("error", "") != "":
		return _fail(String(prep["error"]))
	var obs: Array = prep["obs"]
	var unknown_names: Array = prep["unknown_names"]
	var known: Dictionary = prep["known"]
	var approx: Dictionary = prep["approx"]
	var weights: PackedFloat64Array = prep["weights"]
	var t: int = unknown_names.size()
	var n: int = obs.size()
	# 误差方程 v_i = Σ c·δx − l_i；l_i = h_obs − (H0_to − H0_from)（已知点代入真高程）
	var B := []
	var l := PackedFloat64Array()
	for o: Dictionary in obs:
		var row := PackedFloat64Array()
		row.resize(t)
		var f: String = o["from"]
		var tt: String = o["to"]
		if unknown_names.has(f):
			row[unknown_names.find(f)] = -1.0
		if unknown_names.has(tt):
			row[unknown_names.find(tt)] = 1.0
		var h0f: float = float(known[f]) if known.has(f) else float(approx[f])
		var h0t: float = float(known[tt]) if known.has(tt) else float(approx[tt])
		l.append(float(o["h"]) - (h0t - h0f))
		B.append(row)
	# 法方程 N = BᵀPB，W = BᵀPl
	var Bt := GKMatrix.transpose(B)
	var BtP := _scale_cols(Bt, weights)  # Bᵀ·P（P 对角）
	var N := GKMatrix.multiply(BtP, B)
	var Wv := GKMatrix.mat_vec(BtP, l)
	if N.is_empty() or Wv.is_empty():
		return _fail("法方程组装失败（观测数为 0 或维度异常）")
	var dx := GKMatrix.cholesky_solve(N, Wv)
	if dx.is_empty():
		return _fail("法方程不可解：网形不连通、缺少起算数据或无多余观测，请检查已知点与观测图形")
	var heights := {}
	var value := {}
	for i in t:
		var nm: String = unknown_names[i]
		heights[nm] = float(approx[nm]) + dx[i]
	for k: String in known:
		heights[k] = float(known[k])
	# 残差与精度
	var v_res := PackedFloat64Array()
	for i in n:
		var s := 0.0
		var row: PackedFloat64Array = B[i]
		for j in t:
			s += row[j] * dx[j]
		v_res.append(s - l[i])
	var pvv := _weighted_sum(v_res, weights)
	var dof := n - t
	var mu := NAN
	if dof > 0 and pvv >= 0.0:
		mu = sqrt(pvv / dof)
	_fill_net_result(value, heights, v_res, mu, n, n - t, unknown_names, dx)
	var steps := [
		{
			"title": "1. 误差方程",
			"formula": "v = B·x̂ − l，l = h_观 − (H0_至 − H0_自)；x̂ = H0 + δx",
			"substitution": "n = %d 个高差观测，t = %d 个未知点高程" % [n, t],
			"result": "多余观测 r = n − t = %d" % dof,
		},
		{
			"title": "2. 法方程组成与求解",
			"formula": "N = BᵀPB，W = BᵀPl，N·δx = W（Cholesky 分解求解）",
			"substitution": "权 p = 1/L（按路线长定权）",
			"result": _fmt_vec(dx) + " m",
		},
		{
			"title": "3. 精度评定",
			"formula": "μ = √(VᵀPV / (n − t))",
			"substitution": "VᵀPV = %s" % _fmt(pvv),
			"result": ("μ = ±%s m" % _fmt(mu)) if dof > 0 else "无多余观测，无法评定精度",
		},
	]
	return _ok(value, steps, "水准网间接平差（参数：未知点高程）")

## C7 水准网平差——条件平差（独立闭合环条件方程，生成树找环）
## 输入输出与 network_indirect 同构，供双法互检
static func network_condition(p: Dictionary) -> Dictionary:
	var prep := _prepare_net(p)
	if prep.get("error", "") != "":
		return _fail(String(prep["error"]))
	var obs: Array = prep["obs"]
	var known: Dictionary = prep["known"]
	var weights: PackedFloat64Array = prep["weights"]
	var n: int = obs.size()
	# 图：节点 = 全部点名；生成树（BFS，优先从已知点出发）
	var nodes: Array = prep["nodes"]
	var adj := {}
	for i in n:
		var f: String = obs[i]["from"]
		var tt: String = obs[i]["to"]
		if not adj.has(f):
			adj[f] = []
		if not adj.has(tt):
			adj[tt] = []
		adj[f].append({"to": tt, "idx": i, "forward": true})
		adj[tt].append({"to": f, "idx": i, "forward": false})
	var root := ""
	for k: String in known:
		if nodes.has(k):
			root = k
			break
	if root == "":
		return _fail("条件法需要至少一个已知高程点作为起算基准（间接法同）")
	var parent := {}      # node -> {node: 父, idx: 树边观测号, forward: 观测方向是否 父→子}
	var depth := {}
	var visited := {}
	var queue := [root]
	visited[root] = true
	depth[root] = 0
	while not queue.is_empty():
		var u: String = queue.pop_front()
		for e: Dictionary in adj[u]:
			var w: String = e["to"]
			if visited.has(w):
				continue
			visited[w] = true
			parent[w] = {"node": u, "idx": e["idx"], "forward": e["forward"]}
			depth[w] = depth[u] + 1
			queue.append(w)
	if visited.size() != nodes.size():
		return _fail("水准网不连通（存在与起算点无路径相连的测段），无法组成闭合条件")
	var n_tree := nodes.size() - 1
	if n - n_tree < 1:
		return _fail("无多余观测（n = %d，必要观测 = %d），无需也不可平差" % [n, n_tree])
	# 非树边 → 独立闭合环条件：系数 ±1，w = Σ±h
	var A := []
	var w_vec := PackedFloat64Array()
	for i in n:
		if parent.values().any(func(pe): return int(pe["idx"]) == i):
			continue  # 树边
		var f: String = obs[i]["from"]
		var tt: String = obs[i]["to"]
		var coef := PackedFloat64Array()
		coef.resize(n)
		coef[i] = 1.0  # 环方向：from→to（即该观测方向）
		var cu: String = f
		var cv: String = tt
		# 环方向 f→tt→(沿树上行回 LCA)→(沿树下行到 f)；f 分支在环中为下行（沿观测正向 +1），
		# tt 分支为上行（逆观测正向 −1）；backward 观测（观测方向 child→parent）符号相反。
		while depth[cu] > depth[cv]:
			var pu: Dictionary = parent[cu]
			coef[pu["idx"]] += 1.0 if bool(pu["forward"]) else -1.0
			cu = pu["node"]
		while depth[cv] > depth[cu]:
			var pv: Dictionary = parent[cv]
			coef[pv["idx"]] += -1.0 if bool(pv["forward"]) else 1.0
			cv = pv["node"]
		while cu != cv:
			var pu2: Dictionary = parent[cu]
			coef[pu2["idx"]] += 1.0 if bool(pu2["forward"]) else -1.0
			cu = pu2["node"]
			var pv2: Dictionary = parent[cv]
			coef[pv2["idx"]] += -1.0 if bool(pv2["forward"]) else 1.0
			cv = pv2["node"]
		A.append(coef)
		var s := 0.0
		for j in n:
			s += coef[j] * float(obs[j]["h"])
		w_vec.append(s)
	var r := A.size()
	# 联系数 K = −(A P⁻¹ Aᵀ)⁻¹ w；改正 v = P⁻¹AᵀK
	var APinv := []
	for row_v in A:
		var row := PackedFloat64Array()
		for j in n:
			row.append(row_v[j] / weights[j])
		APinv.append(row)
	var APAt := GKMatrix.multiply(APinv, GKMatrix.transpose(A))
	var K := GKMatrix.cholesky_solve(APAt, _neg(w_vec))
	if K.is_empty():
		return _fail("条件方程联系数不可解（条件独立性与权检查失败）")
	var v_res := PackedFloat64Array()
	v_res.resize(n)
	for c in r:
		var row_c: PackedFloat64Array = A[c]
		for j in n:
			if row_c[j] != 0.0:
				v_res[j] += row_c[j] / weights[j] * K[c]
	# 改正后高程：沿生成树用改正后观测推算
	var h_adj := PackedFloat64Array()
	for i in n:
		h_adj.append(float(obs[i]["h"]) + v_res[i])
	var heights := {}
	heights[root] = float(known[root]) if known.has(root) else float(prep["approx"][root])
	# BFS 按树推算
	var done := {root: true}
	var queue2 := [root]
	while not queue2.is_empty():
		var u: String = queue2.pop_front()
		for e: Dictionary in adj[u]:
			var w: String = e["to"]
			if done.has(w) or not parent.has(w):
				continue
			var pe: Dictionary = parent[w]
			if int(pe["idx"]) != int(e["idx"]):
				continue
			var base: float = heights[u]
			if bool(e["forward"]):
				heights[w] = base + h_adj[e["idx"]]
			else:
				heights[w] = base - h_adj[e["idx"]]
			done[w] = true
			queue2.append(w)
	for k: String in known:
		heights[k] = float(known[k])
	var pvv := _weighted_sum(v_res, weights)
	var mu := sqrt(pvv / r) if pvv >= 0.0 else NAN
	var value := {}
	_fill_net_result(value, heights, v_res, mu, n, r, [], PackedFloat64Array())
	value["w_m"] = w_vec
	var steps := [
		{
			"title": "1. 独立闭合环条件方程（生成树找环）",
			"formula": "Σ±(h + v) = 0，即 A·v + w = 0；w = Σ±h",
			"substitution": "%d 个独立环，闭合差 w = %s m" % [r, _fmt_vec(w_vec)],
			"result": "多余观测 r = %d" % r,
		},
		{
			"title": "2. 联系数与改正数",
			"formula": "K = −(A P⁻¹ Aᵀ)⁻¹ w；v = P⁻¹AᵀK",
			"substitution": "权 p = 1/L",
			"result": "v = %s m" % _fmt_vec(v_res),
		},
		{
			"title": "3. 精度评定",
			"formula": "μ = √(VᵀPV / r)",
			"substitution": "VᵀPV = −Kᵀw = %s" % _fmt(pvv),
			"result": "μ = ±%s m" % _fmt(mu),
		},
	]
	return _ok(value, steps, "水准网条件平差（独立环条件法，与间接法双实现互检）")

## 三角高程（单向 / 对向取均值）
## p = {D_m: 平距, v_angle_deg: 竖直角（仰角正）, i_m: 仪器高, v_m: 目标高,
##      k?: 折光系数 默认 0.13, R_m?: 默认 6371008.7714,
##      back?: {v_angle_deg, i_m, v_m}（对向观测返测，取均值时球气差抵消）}
static func trig_height(p: Dictionary) -> Dictionary:
	if not p.has("D_m") or not _finite_num(p.get("D_m")) or float(p["D_m"]) <= 0.0:
		return _fail("缺少平距 D_m（须为正数）")
	for k in ["v_angle_deg", "i_m", "v_m"]:
		if not p.has(k) or not _finite_num(p.get(k)):
			return _fail("缺少 %s（%s）" % [k, "竖直角deg / 仪器高m / 目标高m"])
	var D := float(p["D_m"])
	var alpha := deg_to_rad(float(p["v_angle_deg"]))
	var i_h := float(p["i_m"])
	var v_h := float(p["v_m"])
	var k_r := 0.13
	if p.has("k") and _finite_num(p.get("k")):
		k_r = float(p["k"])
	if k_r < 0.0 or k_r >= 1.0:
		return _fail("大气折光系数 k 应在 [0, 1) 内（默认 0.13）")
	var R := 6371008.7714
	if p.has("R_m") and _finite_num(p.get("R_m")) and float(p["R_m"]) > 0.0:
		R = float(p["R_m"])
	var f_ball := (1.0 - k_r) * D * D / (2.0 * R)
	var h_one := D * tan(alpha) + i_h - v_h + f_ball
	var value := {"h_m": h_one, "f_ballistic_m": f_ball}
	var steps := [
		{
			"title": "1. 单向三角高程",
			"formula": "h_AB = D·tanα + i_A − v_B + (1−k)·D²/(2R)",
			"substitution": "D = %s m，α = %s°，i = %s m，v = %s m，k = %s" % [_fmt(D), _fmt(float(p["v_angle_deg"])), _fmt(i_h), _fmt(v_h), _fmt(k_r)],
			"result": "h = %s m（球气差改正 f = %s m）" % [_fmt(h_one), _fmt(f_ball)],
		},
	]
	if p.has("back"):
		var b: Dictionary = p["back"]
		for k2 in ["v_angle_deg", "i_m", "v_m"]:
			if not b.has(k2) or not _finite_num(b.get(k2)):
				return _fail("对向观测 back 缺少 %s" % k2)
		var alpha2 := deg_to_rad(float(b["v_angle_deg"]))
		var i2 := float(b["i_m"])
		var v2 := float(b["v_m"])
		# 对向均值：h = [D(tanα_往 − tanα_返) + (i往 − v返) − (i返 − v往)] / 2，球气差抵消
		var h_two := 0.5 * (D * (tan(alpha) - tan(alpha2)) + (i_h - v2) - (i2 - v_h))
		value["h_two_way_m"] = h_two
		value["h_one_way_m"] = h_one
		steps.append({
			"title": "2. 对向观测取均值",
			"formula": "h = [D(tanα_往 − tanα_返) + (i_往 − v_返) − (i_返 − v_往)] / 2（球气差自动抵消）",
			"substitution": "α_返 = %s°，i_返 = %s m，v_返 = %s m" % [_fmt(float(b["v_angle_deg"])), _fmt(i2), _fmt(v2)],
			"result": "对向均值 h = %s m" % _fmt(h_two),
		})
	return _ok(value, steps, "三角高程计算（k=%.2f，R=%.1f m）" % [k_r, R])

# ---------- 内部 ----------

## 水准网输入规整与校验
static func _prepare_net(p: Dictionary) -> Dictionary:
	var known: Dictionary = p.get("known", {})
	var approx: Dictionary = p.get("approx", {})
	var obs: Array = p.get("obs", [])
	if not (known is Dictionary) or not (approx is Dictionary) or not (obs is Array):
		return {"error": "known/approx/obs 数据结构不合法"}
	if obs.is_empty():
		return {"error": "缺少高差观测 obs（每条 {from, to, h, L_km 或 w}）"}
	if known.is_empty():
		return {"error": "缺少已知高程点 known（至少 1 个）"}
	var nodes := []
	for k: String in known:
		if not _finite_num(known[k]):
			return {"error": "已知点 %s 高程含非法数值" % k}
		nodes.append(k)
	for k: String in approx:
		if not _finite_num(approx[k]):
			return {"error": "未知点 %s 近似高程含非法数值" % k}
		if not nodes.has(k):
			nodes.append(k)
	var weights := PackedFloat64Array()
	for o_v in obs:
		if not (o_v is Dictionary):
			return {"error": "观测条目须为对象 {from, to, h, L_km 或 w}"}
		var o: Dictionary = o_v
		if not o.has("from") or not o.has("to") or not o.has("h"):
			return {"error": "观测条目缺少 from/to/h 字段"}
		var f := String(o["from"])
		var tt := String(o["to"])
		if f == tt:
			return {"error": "观测自点与至点相同：%s" % f}
		if not nodes.has(f):
			return {"error": "观测 from 点 %s 未在 known/approx 中定义" % f}
		if not nodes.has(tt):
			return {"error": "观测 to 点 %s 未在 known/approx 中定义" % tt}
		if not _finite_num(o.get("h")):
			return {"error": "观测 %s→%s 高差 h 含非法数值" % [f, tt]}
		if o.has("w") and _finite_num(o.get("w")) and float(o["w"]) > 0.0:
			weights.append(float(o["w"]))
		elif o.has("L_km") and _finite_num(o.get("L_km")) and float(o["L_km"]) > 0.0:
			weights.append(1.0 / float(o["L_km"]))
		else:
			return {"error": "观测 %s→%s 缺少正的权 w 或路线长 L_km" % [f, tt]}
	var unknown_names := []
	for k: String in approx:
		unknown_names.append(k)
	unknown_names.sort()
	return {"error": "", "known": known, "approx": approx, "obs": obs,
			"nodes": nodes, "unknown_names": unknown_names, "weights": weights}

## 间接/条件共用结果填充
static func _fill_net_result(value: Dictionary, heights: Dictionary, v_res: PackedFloat64Array,
		mu: float, n: int, dof: int, unknown_names: Array, dx: PackedFloat64Array) -> void:
	for k: String in heights:
		value["H_%s_m" % k] = heights[k]
	value["v_m"] = v_res
	value["v_mm"] = _scaled(v_res, 1000.0)
	value["n_obs"] = n
	value["dof"] = dof
	if is_finite(mu):
		value["mu_m"] = mu
		value["mu_mm"] = mu * 1000.0
	if not dx.is_empty():
		value["dx_m"] = dx
	if not unknown_names.is_empty():
		value["unknown_names"] = unknown_names

static func _route_names(p: Dictionary, n_seg: int) -> Array:
	var names: Array = []
	var start_name := String(p.get("start_name", "A"))
	var end_name := String(p.get("end_name", "B"))
	var inter: Array = p.get("point_names", [])
	names.append(start_name)
	for i in n_seg - 1:
		if i < inter.size() and String(inter[i]) != "":
			names.append(String(inter[i]))
		else:
			names.append("P%d" % (i + 1))
	names.append(end_name)
	return names

## 对角权向量与向量运算
## 按列缩放（Bᵀ·P：P 为对角权，缩放观测轴 = Bt 的列轴）
static func _scale_cols(Bt: Array, diag: PackedFloat64Array) -> Array:
	var out := []
	for i in Bt.size():
		var src: PackedFloat64Array = Bt[i]
		var row := PackedFloat64Array()
		row.resize(src.size())
		for j in src.size():
			row[j] = src[j] * diag[j]
		out.append(row)
	return out

static func _weighted_sum(v: PackedFloat64Array, diag: PackedFloat64Array) -> float:
	var s := 0.0
	for i in v.size():
		s += v[i] * v[i] * diag[i]
	return s

static func _neg(v: PackedFloat64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for x in v:
		out.append(-x)
	return out

static func _scaled(v: PackedFloat64Array, f: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for x in v:
		out.append(x * f)
	return out

static func _sum(v: PackedFloat64Array) -> float:
	var s := 0.0
	for x in v:
		s += x
	return s

static func _finite_num(v) -> bool:
	if not (v is float or v is int):
		return false
	return is_finite(float(v))

static func _fmt(v: float) -> String:
	if not is_finite(v):
		if v > 0.0:
			return "+∞"
		elif v < 0.0:
			return "−∞"
		return "NaN"
	return "%.6f" % v

static func _fmt_vec(v: PackedFloat64Array) -> String:
	var parts := PackedStringArray()
	for x in v:
		parts.append(_fmt(x))
	return "、".join(parts)

static func _ok(value: Dictionary, steps: Array, formula: String) -> Dictionary:
	return {"ok": true, "value": value, "steps": steps, "formula": formula, "error": ""}

static func _fail(error: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": error}
