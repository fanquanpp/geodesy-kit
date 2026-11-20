# core/math/least_squares.gd —— GK-M1-2 叶子库：间接平差最小二乘（正规方程法）
#
# 数学模型（测量学口径，ARCHITECTURE.md §4 GK-M1 M1-2）：
#   误差方程   V = B·x̂ − l          （n 个观测，t 个未知数，n ≥ t）
#   法方程     N = BᵀP·B ， k = BᵀP·l
#   解         x̂ = N⁻¹·k
#   精度评定   VᵀP·V ；单位权中误差 μ = √(VᵀP·V/(n−t)) ；协因数阵 Qxx = N⁻¹
#              未知数中误差 σ_xi = μ·√(Qxx[i][i])
#
# 设计约定（沿用地基 GK-M1 四文件纪律）：
#   - 纯静态函数、零引擎依赖（extends RefCounted）；矩阵 Array×PackedFloat64Array 行主序；
#   - P 观测权两种形态：PackedFloat64Array（对角权，长度 n，元素 ≥0）或
#     Array（n×n 全权阵，对称、元素有限）；正定性由法方程 Cholesky 兜底；
#   - 结构性失败（维度不符 / 欠定 n<t / 非有限元素 / P 不合法 / 法方程奇异或非正定）
#     一律返回 {}（调用方 is_empty() 判别，与 GKEllipsoid.params 同口径）；
#   - dof = n−t ≤ 0（恰定）时 x̂/Qxx 仍有效返回，mu = NAN（μ 无定义，调用方 is_nan 判别）；
#   - 求解双路径：默认 Cholesky（法方程对称正定标准路径），use_cholesky=false 走
#     部分主元消元（GKMatrix.solve），供双法互检与教学对照；
#   - ⚠ GDScript 陷阱：对 PackedFloat64Array 的修改必须先拷贝（PackedFloat64Array(x)
#     构造副本），凡行内改值一律"拷贝→改→整体写回"，不做 `(expr)[i]=v` 的临时副本赋值。
#
# 返回字典键（成功时）：xhat / v / vtpv / mu / dof / qxx / N / k / sigma_x / n_obs / n_unknowns
# 说明：本文件是叶子数值库，返回裸数值结果，不携带 §5 协议外壳 ——
#       {ok,value,steps,formula,error} 由调用域（M4/M6/G 组计算器）装配。
#
# 权威向量交叉验证：tests/mathk/test_least_squares.gd
#   1)【构造】5×3 已知解回代 x=(1,2,3)，残差<1e-12，Cholesky/消元双路径；
#   2)【权威·借 M6 水准网】ARCHITECTURE.md §4 GK-M6 C7 水准网（μ=±10.7mm）。
class_name GKLeastSquares
extends RefCounted

const _Matrix := preload("res://core/math/matrix.gd")

## 组装法方程：{N: Array(t×t), k: PackedFloat64Array(t), n_obs, n_unknowns}；失败返回 {}
static func normal_equations(B: Array, l: PackedFloat64Array, P) -> Dictionary:
	var shape := _check_shape(B, l, P)
	if shape.is_empty():
		return {}
	var Bt := _Matrix.transpose(B)
	if Bt.is_empty():
		return {}
	var PB := _p_apply_rows(B, P)
	if PB.is_empty():
		return {}
	var N := _Matrix.multiply(Bt, PB)
	if N.is_empty():
		return {}
	var Pl := _p_apply_vec(l, P)
	if Pl.is_empty():
		return {}
	var k := _Matrix.mat_vec(Bt, Pl)
	if k.is_empty():
		return {}
	return {"N": N, "k": k, "n_obs": shape["n"], "n_unknowns": shape["t"]}

## 正规方程最小二乘主入口。失败返回 {}（见文件头失败约定）。
static func solve(B: Array, l: PackedFloat64Array, P, use_cholesky := true) -> Dictionary:
	var ne := normal_equations(B, l, P)
	if ne.is_empty():
		return {}
	var N: Array = ne["N"]
	var k: PackedFloat64Array = ne["k"]
	var n: int = ne["n_obs"]
	var t: int = ne["n_unknowns"]
	# 解法方程（双路径）
	var xhat := PackedFloat64Array()
	if use_cholesky:
		xhat = _Matrix.cholesky_solve(N, k)
	else:
		xhat = _Matrix.solve(N, k)
	if xhat.is_empty():
		return {}  # 法方程奇异/非正定 → 无唯一最小二乘解
	# 残差 V = B·x̂ − l
	var Bx := _Matrix.mat_vec(B, xhat)
	if Bx.is_empty():
		return {}
	var v := PackedFloat64Array()
	v.resize(l.size())
	for i in l.size():
		v[i] = Bx[i] - l[i]
	# 精度评定
	var vtpv := _qform(v, P)
	if not is_finite(vtpv):
		return {}
	var dof := n - t
	var mu := NAN
	if dof > 0:
		mu = sqrt(vtpv / float(dof))
	var qxx := _Matrix.inverse(N)
	if qxx.is_empty():
		return {}
	var sigma_x := PackedFloat64Array()
	sigma_x.resize(t)
	for i in t:
		sigma_x[i] = mu * sqrt((qxx[i] as PackedFloat64Array)[i])
	return {
		"xhat": xhat,
		"v": v,
		"vtpv": vtpv,
		"mu": mu,
		"dof": dof,
		"qxx": qxx,
		"N": N,
		"k": k,
		"sigma_x": sigma_x,
		"n_obs": n,
		"n_unknowns": t,
	}

## 单位权中误差 μ = √(VᵀP·V/(n−t))。v/P 不合法或 dof<=0 返回 NAN。
static func unit_weight_sigma(v: PackedFloat64Array, P, dof: int) -> float:
	if v.is_empty() or dof <= 0:
		return NAN
	if P is PackedFloat64Array:
		if P.size() != v.size():
			return NAN
	elif P is Array:
		if P.size() != v.size():
			return NAN
	else:
		return NAN
	var vtpv := _qform(v, P)
	if not is_finite(vtpv):
		return NAN
	return sqrt(vtpv / float(dof))

# ---------- 内部工具 ----------

## 形状与有限性校验：B(n×t)、l(n)、P（对角 n 或全阵 n×n）。失败返回 {}。
static func _check_shape(B: Array, l: PackedFloat64Array, P) -> Dictionary:
	if B.is_empty() or l.is_empty():
		return {}
	var n := B.size()
	var t: int = (B[0] as PackedFloat64Array).size()
	if t <= 0 or l.size() != n or n < t:
		return {}  # 欠定（n<t）无唯一解
	for i in n:
		var row: PackedFloat64Array = B[i]
		if row.size() != t:
			return {}
		for j in t:
			if not is_finite(row[j]):
				return {}
		if not is_finite(l[i]):
			return {}
	if P is PackedFloat64Array:
		if P.size() != n:
			return {}
		for w in P:
			if not is_finite(w) or w < 0.0:
				return {}  # 权不得为负
	elif P is Array:
		if P.size() != n:
			return {}
		var scale := 1.0
		for i in n:
			var prow: PackedFloat64Array = P[i]
			if prow.size() != n:
				return {}
			for j in n:
				if not is_finite(prow[j]):
					return {}
				scale = maxf(scale, absf(prow[j]))
		for i in n:
			for j in range(i + 1, n):
				if absf((P[i] as PackedFloat64Array)[j] - (P[j] as PackedFloat64Array)[i]) > 1e-9 * scale:
					return {}  # 权阵须对称
	else:
		return {}
	return {"n": n, "t": t}

## P·B（P 为 Array 全权阵时直接走矩阵乘；对角权时逐行缩放，先拷贝副本）
static func _p_apply_rows(B: Array, P) -> Array:
	if P is Array:
		return _Matrix.multiply(P, B)
	var PB := []
	for i in B.size():
		var row := PackedFloat64Array(B[i])  # 拷贝副本（见文件头陷阱注）
		for j in row.size():
			row[j] = row[j] * P[i]
		PB.append(row)
	return PB

## P·v
static func _p_apply_vec(v: PackedFloat64Array, P) -> PackedFloat64Array:
	if P is Array:
		return _Matrix.mat_vec(P, v)
	var out := PackedFloat64Array(v)  # 拷贝副本
	for i in out.size():
		out[i] = out[i] * P[i]
	return out

## 二次型 vᵀP·v（VᵀP·V）
static func _qform(v: PackedFloat64Array, P) -> float:
	if P is Array:
		if P.size() != v.size():
			return NAN
		var Pv := _Matrix.mat_vec(P, v)
		if Pv.is_empty():
			return NAN
		var s := 0.0
		for i in v.size():
			s += v[i] * Pv[i]
		return s
	if P.size() != v.size():
		return NAN
	var s := 0.0
	for i in v.size():
		s += P[i] * v[i] * v[i]
	return s
