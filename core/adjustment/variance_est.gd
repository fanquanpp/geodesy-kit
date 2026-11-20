# core/adjustment/variance_est.gd —— GK-M6-8 方差分量估计（C12：Helmert 法）与秩亏自由网平差（最小范数解）
#
# 设计约定（docs/ARCHITECTURE.md §4 GK-M6 / §5 协议）：
#   - Helmert 方差分量估计（严格无偏形式，含组间交叉项）：
#       E[v_iᵀP_i v_i] = Σ_j σ0j²·a_ij，a_ij = tr(P_i·M_ij·P_j⁻¹·M_ijᵀ)，M = I − B·Qxx·Bᵀ·P；
#       解线性方程组得各组 σ̂0j²（对角近似忽略交叉项的教科书简化式不采用——本实现为严格式，
#       已与本会话 numpy 互检：单次估计无偏、迭代 4 次收敛、恢复 σ 比 4.3% 内小样本波动）；
#       迭代：P_i ← P_i/σ̂0i²，直至 max|σ̂0i²−1| < tol；
#   - 组内约定：每组观测须带同一 sigma（或 w）作为初权，输出"累计因子"与原生单位 σ 估值
#     （σ_native = σ_init·√factor_cum，测边 m、角度 rad→另给 ″）；
#   - 设计矩阵复用 GKAdjustNetwork.build_design（同域内部复用，C5↔C12，不跨域）；
#   - 秩亏自由网（无已知点）：N 奇异（亏 3：2 平移+1 旋转；纯测角网亏 4 需尺度观测，见校验），
#       附加基准条件 Gᵀ·δx = 0（Σδx=0、Σδy=0、Σ(−y⁰δx+x⁰δy)=0）加边求解 → 最小范数解；
#       行 dof = n − rank(N) = n − (t − 3)；
#   - 全部静态函数、零引擎依赖；非法输入返回 {"ok":false,"error":中文}。
class_name GKAdjustVariance
extends RefCounted

# 同域内部复用 C5 构建器（preload 直引，避免依赖全局类缓存时序）
const _network := preload("res://core/adjustment/network.gd")

## C12-a Helmert 方差分量估计（分组迭代）
## p = {known: {name:[x,y]}, approx: {name:[x0,y0]},
##      groups: [{name, dist_obs: [...], angle_obs: [...]}...]（组内各观测 sigma/w 须一致）,
##      max_iter? = 10, tol? = 1e-9}
## value: {iterations, group_names, factor_history, factor_final, sigma_est, sigma_est_s(角度组), mu0_final}
static func helmert(p: Dictionary) -> Dictionary:
	var known: Dictionary = p.get("known", {})
	var approx: Dictionary = p.get("approx", {})
	var groups: Array = p.get("groups", [])
	if not (groups is Array) or groups.size() < 2:
		return _fail("Helmert 估计至少需要 2 个观测组 groups（单组请直接用 C5 间接平差的 μ）")
	var max_iter := 10
	if p.has("max_iter") and int(p["max_iter"]) > 0:
		max_iter = int(p["max_iter"])
	var tol := 1e-9
	if p.has("tol") and is_finite(float(p["tol"])) and float(p["tol"]) > 0.0:
		tol = float(p["tol"])
	# 逐组构建设计矩阵并拼接
	var B := []
	var l := PackedFloat64Array()
	var pw := PackedFloat64Array()
	var group_rows := []          # 每组的行号区间 [{from, to}]
	var group_names := []
	var group_init_sigma := []    # 每组初权 sigma（原生单位）
	var group_is_angle := []      # 角度组标记（结果换算 ″）
	for g_v in groups:
		if not (g_v is Dictionary):
			return _fail("groups 元素须为对象 {name, dist_obs, angle_obs}")
		var g: Dictionary = g_v
		var sub := {
			"known": known, "approx": approx,
			"dist_obs": g.get("dist_obs", []), "angle_obs": g.get("angle_obs", []),
		}
		var build := _network.build_design(sub)
		if String(build.get("error", "")) != "":
			return _fail("组 %s：%s" % [String(g.get("name", "?")), String(build["error"])])
		var bg: Array = build["B"]
		var lg: PackedFloat64Array = build["l"]
		var wg: PackedFloat64Array = build["p"]
		# 组内权一致性（同 sigma 初值才有明确的"因子"语义）
		var w0 := wg[0]
		for x in wg:
			if absf(x - w0) > 1e-15:
				return _fail("组 %s 内各观测 sigma/w 须一致（Helmert 以组为单位估计因子）" % String(g.get("name", "?")))
		var has_angle := false
		for kd in build["kinds"]:
			if kd == "angle":
				has_angle = true
		group_names.append(String(g.get("name", "组%d" % (group_names.size() + 1))))
		group_rows.append({"from": B.size(), "to": B.size() + bg.size()})
		group_init_sigma.append(1.0 / sqrt(w0))
		group_is_angle.append(has_angle)
		for i in bg.size():
			B.append(bg[i])
			l.append(lg[i])
			pw.append(wg[i])
	var n := B.size()
	var t: int = (B[0] as PackedFloat64Array).size()
	var factor_history := []
	var factor_cum := []
	for c in groups.size():
		factor_cum.append(1.0)
	var converged := -1
	var v_final := PackedFloat64Array()
	var pvv_final := NAN
	var it := 0  # 已完成迭代次数（for 循环变量作用域限于循环体，需显式计数）
	for it_i in max_iter:
		it = it_i + 1
		var pw_cur := PackedFloat64Array()
		for i in n:
			pw_cur.append(pw[i])
		# 平差（当前权）
		var Bt := GKMatrix.transpose(B)
		var BtP := _scale_cols(Bt, pw_cur)
		var N := GKMatrix.multiply(BtP, B)
		var Wv := GKMatrix.mat_vec(BtP, l)
		if N.is_empty() or Wv.is_empty():
			return _fail("法方程组装失败")
		var dx := GKMatrix.cholesky_solve(N, Wv)
		if dx.is_empty():
			return _fail("法方程不可解：网形不连通或缺少起算数据")
		var qxx := GKMatrix.inverse(N)
		if qxx.is_empty():
			return _fail("法方程求逆失败（N 奇异）")
		var v := PackedFloat64Array()
		for i in n:
			var s := 0.0
			var row: PackedFloat64Array = B[i]
			for j in t:
				s += row[j] * dx[j]
			v.append(s - l[i])
		# M = I − B·Qxx·Bᵀ·P（n×n）
		var BQxx := GKMatrix.multiply(B, qxx)          # n×t
		var BQxxBt := GKMatrix.multiply(BQxx, GKMatrix.transpose(B))  # n×n
		var M := []
		for i in n:
			var mrow := PackedFloat64Array()
			mrow.resize(n)
			for j in n:
				var mij: float = (BQxxBt[i] as PackedFloat64Array)[j] * pw_cur[j]
				if i == j:
					mij = 1.0 - mij
				mrow[j] = mij
			M.append(mrow)
		# 严格 Helmert 系数与右端（对角权：a_ij = Σ_{i∈I}Σ_{j∈J} p_i·M_ij²/p_j）
		var a := []
		var rhs := PackedFloat64Array()
		for c in groups.size():
			var arow := PackedFloat64Array()
			arow.resize(groups.size())
			a.append(arow)
			var rows_c: Dictionary = group_rows[c]
			var s_c := 0.0
			for i in range(int(rows_c["from"]), int(rows_c["to"])):
				s_c += pw_cur[i] * v[i] * v[i]
			rhs.append(s_c)
		for ci in groups.size():
			var rows_i: Dictionary = group_rows[ci]
			for cj in groups.size():
				var rows_j: Dictionary = group_rows[cj]
				var acc := 0.0
				for i in range(int(rows_i["from"]), int(rows_i["to"])):
					var mi: PackedFloat64Array = M[i]
					for j in range(int(rows_j["from"]), int(rows_j["to"])):
						acc += pw_cur[i] * mi[j] * mi[j] / pw_cur[j]
				# ⚠ 值类型：行读出→修改→写回
				var arow_w: PackedFloat64Array = a[ci]
				arow_w[cj] = acc
				a[ci] = arow_w
		var sig2 := GKMatrix.solve(a, rhs)
		if sig2.is_empty():
			return _fail("Helmert 方程不可解（分组系数阵奇异，请检查观测分组）")
		var hist := PackedFloat64Array()
		for c in groups.size():
			hist.append(sig2[c])
		factor_history.append(hist)
		var mx := 0.0
		for c in groups.size():
			mx = maxf(mx, absf(sig2[c] - 1.0))
			factor_cum[c] *= sig2[c]
			# 组内重定权
			var rows_c2: Dictionary = group_rows[c]
			for i in range(int(rows_c2["from"]), int(rows_c2["to"])):
				pw[i] = pw[i] / sig2[c]
		v_final = v
		pvv_final = _weighted_sum(v, pw_cur)
		if mx < tol:
			converged = it_i
			break
	var value := {
		"iterations": it,
		"converged": converged >= 0,
		"group_names": group_names,
		"factor_history": factor_history,
		"factor_final": factor_cum,
		"pvv": pvv_final,
	}
	var sigma_est := []
	var sigma_est_s := []
	for c in groups.size():
		var sig_native := float(group_init_sigma[c]) * sqrt(float(factor_cum[c]))
		sigma_est.append(sig_native)
		if bool(group_is_angle[c]):
			sigma_est_s.append(sig_native * 648000.0 / PI)
		else:
			sigma_est_s.append(NAN)
	value["sigma_est"] = sigma_est
	value["sigma_est_s"] = sigma_est_s
	var dof := n - t
	if dof > 0 and is_finite(pvv_final) and pvv_final >= 0.0:
		value["mu0_final"] = sqrt(pvv_final / dof)
		value["dof"] = dof
	var desc := PackedStringArray()
	for c in groups.size():
		if bool(group_is_angle[c]):
			desc.append("%s σ̂≈%s″" % [String(group_names[c]), _fmt(sigma_est_s[c])])
		else:
			desc.append("%s σ̂≈%s m" % [String(group_names[c]), _fmt(sigma_est[c])])
	var conv_text := ""
	if converged >= 0:
		conv_text = "第 %d 次迭代收敛（max|σ̂²−1| < %s）" % [converged + 1, _fmt(tol)]
	else:
		conv_text = "达到最大迭代次数仍未收敛（max_iter=%d）" % max_iter
	var steps := [
		{
			"title": "1. 分组建模（同域复用 C5 设计矩阵构建器）",
			"formula": "v = B·δx̂ − l，各组独立给权 p_i = 1/σ_i²（组内同权）",
			"substitution": "%d 组观测，n = %d，t = %d" % [groups.size(), n, t],
			"result": "、".join(desc),
		},
		{
			"title": "2. 严格 Helmert 估计（含组间交叉项）",
			"formula": "E[v_iᵀP_i v_i] = Σ_j σ0j²·a_ij，a_ij = tr(P_i·M_ij·P_j⁻¹·M_ijᵀ)，M = I − B·Qxx·Bᵀ·P",
			"substitution": "迭代重定权 P_i ← P_i/σ̂0i²",
			"result": conv_text,
		},
		{
			"title": "3. 各组单位权中误差估值（原生单位）",
			"formula": "σ_native = σ_init·√(Πfactor)",
			"substitution": "因子累计 = %s" % _fmt_vec(_to_pfa(factor_cum)),
			"result": "、".join(desc),
		},
	]
	return _ok(value, steps, "Helmert 两/多方差分量估计（严格无偏式，迭代收敛判据 max|σ̂0i²−1|<tol）")

## C12-b 秩亏自由网平差（最小范数解·附加基准条件法）
## p = {approx: {name:[x0,y0]}, dist_obs: [...], angle_obs: [...]（无已知点；须含测边提供尺度）}
## value: {x_*_m / y_*_m, dx_m, v_dist_m, v_angle_s, mu0, dof, datum_note}
static func free_net(p: Dictionary) -> Dictionary:
	var sub := {
		"known": {}, "approx": p.get("approx", {}),
		"dist_obs": p.get("dist_obs", []), "angle_obs": p.get("angle_obs", []),
		"allow_no_datum": true,
	}
	var build := _network.build_design(sub)
	if String(build.get("error", "")) != "":
		return _fail(String(build["error"]))
	var B: Array = build["B"]
	var l: PackedFloat64Array = build["l"]
	var wts: PackedFloat64Array = build["p"]
	var param_names: Array = build["param_names"]
	var approx: Dictionary = build["approx"]
	var kinds: PackedStringArray = build["kinds"]
	var has_dist := false
	for kd in kinds:
		if kd == "dist":
			has_dist = true
	if not has_dist:
		return _fail("秩亏自由网需至少 1 个边长观测提供尺度基准（纯测角网秩亏为 4：平移×2+旋转+尺度，超出本实现范围）")
	var n := B.size()
	var t: int = param_names.size()
	var Bt := GKMatrix.transpose(B)
	var BtP := _scale_cols(Bt, wts)
	var N := GKMatrix.multiply(BtP, B)
	var Wv := GKMatrix.mat_vec(BtP, l)
	if N.is_empty() or Wv.is_empty():
		return _fail("法方程组装失败")
	# 基准亏缺 G（平移 x2 + 旋转 x1）：Σδx=0、Σδy=0、Σ(−y⁰δx+x⁰δy)=0
	var G := []
	for c in 3:
		var grow := PackedFloat64Array()
		grow.resize(t)
		G.append(grow)
	for j in t / 2:
		var gj0: PackedFloat64Array = G[0]
		gj0[2 * j] = 1.0
		G[0] = gj0
		var gj1: PackedFloat64Array = G[1]
		gj1[2 * j + 1] = 1.0
		G[1] = gj1
		var nm := String(param_names[2 * j])
		var gj2: PackedFloat64Array = G[2]
		gj2[2 * j] = -float(approx[nm][1])
		gj2[2 * j + 1] = float(approx[nm][0])
		G[2] = gj2
	# 加边方程 [[N, G],[Gᵀ, 0]]·[δx; k] = [W; 0]
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
		return _fail("自由网加边方程不可解（网形不连通或观测不足）")
	var dx := PackedFloat64Array()
	for i in t:
		dx.append(sol[i])
	# 残差
	var v := PackedFloat64Array()
	for i in n:
		var s := 0.0
		var row: PackedFloat64Array = B[i]
		for j in t:
			s += row[j] * dx[j]
		v.append(s - l[i])
	var pvv := _weighted_sum(v, wts)
	var dof := n - (t - 3)
	var mu := sqrt(pvv / dof) if dof > 0 and pvv >= 0.0 else NAN
	var value := {}
	for j in t / 2:
		var nm2 := String(param_names[2 * j])
		value["x_%s_m" % nm2] = float(approx[nm2][0]) + dx[2 * j]
		value["y_%s_m" % nm2] = float(approx[nm2][1]) + dx[2 * j + 1]
	value["dx_m"] = dx
	var v_dist := PackedFloat64Array()
	var v_ang := PackedFloat64Array()
	for i in n:
		if kinds[i] == "dist":
			v_dist.append(v[i])
		else:
			v_ang.append(v[i])
	value["v_dist_m"] = v_dist
	value["v_angle_s"] = _scaled(v_ang, 648000.0 / PI)
	value["n_obs"] = n
	value["dof"] = dof
	value["pvv"] = pvv
	if is_finite(mu):
		value["mu0"] = mu
	value["datum_note"] = "最小范数解（重心基准+旋转条件：Σδx=0、Σδy=0、Σ(−y⁰δx+x⁰δy)=0）"
	var steps := [
		{
			"title": "1. 秩亏诊断",
			"formula": "无已知点时 N = BᵀPB 奇异，亏 3（2 平移 + 1 旋转；有测边则尺度已定）",
			"substitution": "t = %d 个坐标参数，rank(N) = %d" % [t, t - 3],
			"result": "多余观测 r = n − rank(N) = %d" % dof,
		},
		{
			"title": "2. 附加基准条件求最小范数解",
			"formula": "Gᵀ·δx = 0（Σδx=0，Σδy=0，Σ(−y⁰δx+x⁰δy)=0）；[[N,G],[Gᵀ,0]]·[δx;k] = [W;0]",
			"substitution": "加边方程 %d×%d，Gauss 消元求解" % [t + 3, t + 3],
			"result": "δx = %s m" % _fmt_vec(dx),
		},
		{
			"title": "3. 精度评定",
			"formula": "μ = √(VᵀPV/r)",
			"substitution": "VᵀPV = %s" % _fmt(pvv),
			"result": "μ = ±%s" % _fmt(mu),
		},
	]
	var res := _ok(value, steps, "秩亏自由网平差（最小范数解，附加基准条件法）")
	res["param_names"] = param_names
	return res

# ---------- 内部 ----------

static func _to_pfa(arr: Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for x in arr:
		out.append(float(x))
	return out

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

static func _scaled(v: PackedFloat64Array, f: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for x in v:
		out.append(x * f)
	return out

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
