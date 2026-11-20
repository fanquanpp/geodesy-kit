# core/adjustment/gnss_net.gd —— GK-M6-7 GNSS 向量网三维间接平差（C11）
#
# 设计约定（docs/ARCHITECTURE.md §4 GK-M6 / §5 协议）：
#   - 观测为 GNSS 基线向量（ΔX, ΔY, ΔZ，地心直角坐标系）；调用方（app 编排层）负责先把
#     BLH 经 GK-M2 转 XYZ——core 不横向依赖（ARCHITECTURE §1.1）；
#   - 每条基线 = 3 个同权观测：v = δx_to − δx_from − l，l = d_obs − (X⁰_to − X⁰_from)；
#     权 p_i = 1/σ_i²（σ 为基线分量中误差 m，各分量同权；协方差阵输入暂不支持，如实声明）；
#   - 基准：datum="fixed"（默认，需已知点）或 "free"（秩亏自由网，亏 3 个平移，
#     附加条件 ΣδX = ΣδY = ΣδZ = 0 求最小范数解——附加条件法/拟稳平差口径）；
#   - 法方程 3t×3t 对称正定 → GKMatrix.cholesky_solve；连通性用 BFS 检查后给中文成因；
#   - 全部静态函数、零引擎依赖；非法输入返回 {"ok":false,"error":中文}。
class_name GKAdjustGnssNet
extends RefCounted

const _comp_keys := ["dx", "dy", "dz"]

## C11 GNSS 向量网平差
## p = {known: {name:[X,Y,Z]}, approx: {name:[X0,Y0,Z0]},
##      baselines: [{from,to,dx,dy,dz,sigma}...], datum?: "fixed"|"free"（默认 fixed）}
## 返回 §5 协议；顶层扩展键 "qxx"（3t×3t）供深入分析。
static func adjust(p: Dictionary) -> Dictionary:
	var known: Dictionary = p.get("known", {})
	var approx: Dictionary = p.get("approx", {})
	var baselines: Array = p.get("baselines", [])
	var datum := String(p.get("datum", "fixed"))
	if not (known is Dictionary) or not (approx is Dictionary) or not (baselines is Array):
		return _fail("known/approx/baselines 数据结构不合法")
	if baselines.is_empty():
		return _fail("缺少基线向量 baselines（每条 {from, to, dx, dy, dz, sigma}）")
	if datum == "fixed" and known.is_empty():
		return _fail("固定基准（datum=fixed）需要至少 1 个已知点；无已知点请用 datum=free（最小范数解）")
	if datum != "fixed" and datum != "free":
		return _fail("datum 只支持 fixed / free")
	for k: String in known:
		if not _finite_xyz(known[k]):
			return _fail("已知点 %s 坐标须为 [X, Y, Z] 数值组" % k)
	var names := []
	for k: String in approx:
		names.append(k)
	names.sort()
	if names.is_empty() and known.is_empty():
		return _fail("缺少未知点近似坐标 approx（线性化必需）")
	for k: String in approx:
		if not _finite_xyz(approx[k]):
			return _fail("未知点 %s 近似坐标须为 [X0, Y0, Z0] 数值组" % k)
	var param_names := []
	for nm: String in names:
		param_names.append(nm)
	var t: int = 3 * param_names.size()
	var n: int = 3 * baselines.size()
	# 误差方程与法方程
	var B := []
	var l := PackedFloat64Array()
	var wts := PackedFloat64Array()
	var meta := []
	for bl_v in baselines:
		if not (bl_v is Dictionary):
			return _fail("基线条目须为对象 {from, to, dx, dy, dz, sigma}")
		var bl: Dictionary = bl_v
		for f in ["from", "to", "dx", "dy", "dz", "sigma"]:
			if not bl.has(f):
				return _fail("基线缺少字段 %s" % f)
		var f_nm := String(bl["from"])
		var t_nm := String(bl["to"])
		if f_nm == t_nm:
			return _fail("基线 from/to 不能同名（%s）" % f_nm)
		for c in ["dx", "dy", "dz"]:
			if not _finite_num(bl[c]):
				return _fail("基线 %s→%s 分量 %s 含非法数值" % [f_nm, t_nm, c])
		if not _finite_num(bl["sigma"]) or float(bl["sigma"]) <= 0.0:
			return _fail("基线 %s→%s 的 sigma 须为正数（m）" % [f_nm, t_nm])
		for nm in [f_nm, t_nm]:
			if not known.has(nm) and not approx.has(nm):
				return _fail("基线点名 %s 未在 known/approx 中定义" % nm)
		# 三个分量行：v_c = δx_to[c] − δx_from[c] − l_c（每行只有本分量位置的系数 ±1）
		var p0 := _coord3_of(f_nm, known, approx)
		var q0 := _coord3_of(t_nm, known, approx)
		var sig := float(bl["sigma"])
		var w := 1.0 / (sig * sig)
		for c in 3:
			var row := PackedFloat64Array()
			row.resize(t)
			if approx.has(t_nm):
				row[3 * param_names.find(t_nm) + c] = 1.0
			if approx.has(f_nm):
				row[3 * param_names.find(f_nm) + c] = -1.0
			B.append(row)
			l.append(float(bl[_comp_keys[c]]) - (q0[c] - p0[c]))
			wts.append(w)
		meta.append({"from": f_nm, "to": t_nm})
	# 连通性：所有未知点须与基准（已知点或自由网中彼此）连通
	var conn_err := _check_connectivity(known.keys() + names, baselines, names, datum)
	if conn_err != "":
		return _fail(conn_err)
	var n_full := B.size()
	var Bt := GKMatrix.transpose(B)
	var BtP := _scale_cols(Bt, wts)
	var N := GKMatrix.multiply(BtP, B)
	var Wv := GKMatrix.mat_vec(BtP, l)
	if N.is_empty() or Wv.is_empty():
		return _fail("法方程组装失败")
	var dx := PackedFloat64Array()
	if datum == "fixed":
		dx = GKMatrix.cholesky_solve(N, Wv)
		if dx.is_empty():
			return _fail("法方程不可解：网形不连通或缺少起算数据（N 非正定）")
	else:
		# 秩亏自由网：附加条件 Gᵀ·δx = 0（ΣδX=ΣδY=ΣδZ=0），加边求解最小范数解
		# ⚠ PackedFloat64Array 值类型陷阱：矩阵行一律"读出→修改→写回"
		var G := []
		for c in 3:
			var grow := PackedFloat64Array()
			grow.resize(t)
			for j in param_names.size():
				grow[3 * j + c] = 1.0
			G.append(grow)
		var M := []
		for i in t + 3:
			var mrow0 := PackedFloat64Array()
			mrow0.resize(t + 3)
			M.append(mrow0)
		for i in t:
			var nrow: PackedFloat64Array = N[i]
			var mrow: PackedFloat64Array = M[i]
			for j in t:
				mrow[j] = nrow[j]
			for c in 3:
				mrow[t + c] = G[c][i]
			M[i] = mrow
		for c in 3:
			var grow2: PackedFloat64Array = G[c]
			var mrow2: PackedFloat64Array = M[t + c]
			for j in t:
				mrow2[j] = grow2[j]
			M[t + c] = mrow2
		var rhs := PackedFloat64Array()
		rhs.resize(t + 3)
		for i in t:
			rhs[i] = Wv[i]
		var sol := GKMatrix.solve(M, rhs)
		if sol.is_empty():
			return _fail("自由网加边方程不可解：网形不连通（请检查基线图形）")
		for i in t:
			dx.append(sol[i])
	# 残差与精度
	var v := PackedFloat64Array()
	for i in n_full:
		var s := 0.0
		var row2: PackedFloat64Array = B[i]
		for j in t:
			s += row2[j] * dx[j]
		v.append(s - l[i])
	var pvv := _weighted_sum(v, wts)
	var dof := 0
	if datum == "fixed":
		dof = n_full - t
	else:
		dof = n_full - t + 3
	var mu := NAN
	if dof > 0 and pvv >= 0.0:
		mu = sqrt(pvv / dof)
	# 平差后坐标
	var value := {}
	for j in param_names.size():
		var nm: String = param_names[j]
		value["X_%s_m" % nm] = float(approx[nm][0]) + dx[3 * j]
		value["Y_%s_m" % nm] = float(approx[nm][1]) + dx[3 * j + 1]
		value["Z_%s_m" % nm] = float(approx[nm][2]) + dx[3 * j + 2]
	for k: String in known:
		value["X_%s_m" % k] = float(known[k][0])
		value["Y_%s_m" % k] = float(known[k][1])
		value["Z_%s_m" % k] = float(known[k][2])
	value["n_baselines"] = baselines.size()
	value["n_obs"] = n_full
	value["n_unknown"] = param_names.size()
	value["dof"] = dof
	value["pvv"] = pvv
	if is_finite(mu):
		value["mu0"] = mu
	# 各基线改正向量（与输入同序，每条 3 分量 m）
	var v_bl := PackedFloat64Array()
	for i in n_full:
		v_bl.append(v[i])
	value["v_m"] = v_bl
	var datum_note := ""
	if datum == "fixed":
		datum_note = "固定基准（已知点 %s）" % ", ".join(known.keys())
	else:
		datum_note = "秩亏自由网最小范数解（重心基准：ΣδX=ΣδY=ΣδZ=0）"
	var steps := [
		{
			"title": "1. 基线向量误差方程",
			"formula": "v = δx_to − δx_from − l，l = d_obs − (X⁰_to − X⁰_from)",
			"substitution": "%d 条基线 → n = %d 个分量观测，t = %d 个坐标未知数" % [baselines.size(), n_full, t],
			"result": "多余观测 r = %d" % dof,
		},
		{
			"title": "2. 法方程求解",
			"formula": "N = BᵀPB，x̂ = X⁰ + N⁻¹BᵀPl（Cholesky）" if datum == "fixed" else "N 加边 [N G; Gᵀ 0]（ΣδX=ΣδY=ΣδZ=0）求最小范数解",
			"substitution": "权 p = 1/σ²（σ = 基线分量中误差）",
			"result": datum_note,
		},
		{
			"title": "3. 精度评定",
			"formula": "μ = √(VᵀPV/r)",
			"substitution": "VᵀPV = %s" % _fmt(pvv),
			"result": ("μ = ±%s" % _fmt(mu)) if is_finite(mu) else "无多余观测，精度无法评定",
		},
	]
	var res := _ok(value, steps, "GNSS 向量网三维间接平差（%s；BLH→XYZ 由 app 层经 M2 预转换）" % datum_note)
	if datum == "fixed":
		var qxx := GKMatrix.inverse(N)
		if not qxx.is_empty():
			res["qxx"] = qxx
	res["param_names"] = param_names
	return res

# ---------- 内部 ----------

static func _check_connectivity(all_names: Array, baselines: Array, unknown_names: Array, datum: String) -> String:
	# 未知点连通性：BFS 沿基线图；fixed 时还须触达至少一个已知点
	var adj := {}
	for bl in baselines:
		var f: String = bl["from"]
		var tt: String = bl["to"]
		if not adj.has(f):
			adj[f] = []
		if not adj.has(tt):
			adj[tt] = []
		adj[f].append(tt)
		adj[tt].append(f)
	var known_set := {}
	for k in all_names:
		if not unknown_names.has(k):
			known_set[k] = true
	var start := ""
	for k: String in unknown_names:
		if adj.has(k):
			start = k
			break
	if start == "":
		return "未知点均无基线连接，无法平差"
	var visited := {start: true}
	var queue := [start]
	while not queue.is_empty():
		var u: String = queue.pop_front()
		for w: String in adj.get(u, []):
			if not visited.has(w):
				visited[w] = true
				queue.append(w)
	for nm: String in unknown_names:
		if not visited.has(nm):
			return "未知点 %s 无基线与网连通，无法平差" % nm
	if datum == "fixed":
		var has_known := false
		for nm: String in visited:
			if known_set.has(nm):
				has_known = true
				break
		if not has_known:
			return "固定基准下未知点群与已知点之间无基线连接，缺少起算数据"
	return ""

static func _coord3_of(nm: String, known: Dictionary, approx: Dictionary) -> Array:
	if known.has(nm):
		return known[nm]
	return approx[nm]

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

static func _finite_num(v) -> bool:
	if not (v is float or v is int):
		return false
	return is_finite(float(v))

static func _finite_xyz(arr) -> bool:
	if not (arr is Array) or (arr as Array).size() != 3:
		return false
	for x in arr:
		if not _finite_num(x):
			return false
	return true

static func _fmt(v: float) -> String:
	if not is_finite(v):
		if v > 0.0:
			return "+∞"
		elif v < 0.0:
			return "−∞"
		return "NaN"
	return "%.6f" % v

static func _ok(value: Dictionary, steps: Array, formula: String) -> Dictionary:
	return {"ok": true, "value": value, "steps": steps, "formula": formula, "error": ""}

static func _fail(error: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": error}
