# core/math/matrix.gd —— GK-M1 叶子库：稠密矩阵基本运算
#
# 设计约定（docs/ARCHITECTURE.md §4 GK-M1 / §9）：
#   - 纯静态函数、零引擎依赖：extends RefCounted，禁止 Node/FileAccess 等引擎类；
#   - 矩阵表示：Array（长度=行数 m）× PackedFloat64Array（长度=列数 n），行主序；
#   - 输入校验先行：维度不符/奇异/非正定一律返回空容器 []，不抛异常、不输出堆栈；
#   - 数值方式：求逆与解方程用部分主元高斯消元（Gauss-Jordan / 前后代入）+ 零行检测判奇异；
#     Cholesky 用于对称正定方程（平差法方程 N·x=b 的标准路径），双路径可互检；
#   - ⚠ GDScript 陷阱（本会话实测）：`(expr as PackedFloat64Array)[i] = v` 是对
#     临时副本赋值，写不回容器 —— 凡对容器内的行做修改，一律
#     "var row: PackedFloat64Array = M[i]; row[i] = ...; M[i] = row" 读改写回；
#   - GDScript float 即 64 位双精度；浮点比较一律用容差，不用 ==。
#
# API 冻结提示：本文件公开签名按 Wave 0 纪律冻结，后续只增不改（ARCHITECTURE.md §9.2）。
class_name GKMatrix
extends RefCounted

## 矩阵乘法 C = A·B（A: m×k，B: k×n）
static func multiply(A: Array, B: Array) -> Array:
	if A.is_empty() or B.is_empty():
		return []
	var m := A.size()
	var k: int = (A[0] as PackedFloat64Array).size()
	var k2 := B.size()
	var n: int = (B[0] as PackedFloat64Array).size()
	if k != k2:
		return []
	var C := []
	for i in m:
		var row := PackedFloat64Array()
		row.resize(n)
		var Ai: PackedFloat64Array = A[i]
		for j in n:
			var s := 0.0
			for t in k:
				s += Ai[t] * (B[t] as PackedFloat64Array)[j]
			row[j] = s
		C.append(row)
	return C

## 矩阵转置
static func transpose(A: Array) -> Array:
	if A.is_empty():
		return []
	var m := A.size()
	var n: int = (A[0] as PackedFloat64Array).size()
	var T := []
	for j in n:
		var row := PackedFloat64Array()
		row.resize(m)
		for i in m:
			row[i] = (A[i] as PackedFloat64Array)[j]
		T.append(row)
	return T

## 单位矩阵 n×n
static func identity(n: int) -> Array:
	var I := []
	for i in n:
		var row := PackedFloat64Array()
		row.resize(n)
		row[i] = 1.0
		I.append(row)
	return I

## 矩阵 × 向量 b = A·x（A: m×k，x: 长度 k）
static func mat_vec(A: Array, x: PackedFloat64Array) -> PackedFloat64Array:
	if A.is_empty():
		return PackedFloat64Array()
	var m := A.size()
	var k: int = (A[0] as PackedFloat64Array).size()
	if x.size() != k:
		return PackedFloat64Array()
	var b := PackedFloat64Array()
	b.resize(m)
	for i in m:
		var s := 0.0
		var Ai: PackedFloat64Array = A[i]
		for t in k:
			s += Ai[t] * x[t]
		b[i] = s
	return b

## 求逆（部分主元 Gauss-Jordan + 零行奇异检测）。奇异返回 []。
static func inverse(A: Array) -> Array:
	if A.is_empty():
		return []
	var n := A.size()
	if (A[0] as PackedFloat64Array).size() != n:
		return []
	# 输入尺度（零行相对阈值用）
	var scale := 1.0
	for i in n:
		for j in n:
			scale = maxf(scale, absf((A[i] as PackedFloat64Array)[j]))
	# 增广 [A | I]
	var M := []
	for i in n:
		var row := PackedFloat64Array()
		row.resize(2 * n)
		for j in n:
			row[j] = float((A[i] as PackedFloat64Array)[j])
		row[n + i] = 1.0
		M.append(row)
	for col in n:
		# 部分主元：选当前列绝对值最大的行
		var piv := col
		for r in range(col + 1, n):
			if absf((M[r] as PackedFloat64Array)[col]) > absf((M[piv] as PackedFloat64Array)[col]):
				piv = r
		if absf((M[piv] as PackedFloat64Array)[col]) < 1e-300:
			return []  # 全零列 → 奇异
		if piv != col:
			var tmp: PackedFloat64Array = M[col]
			M[col] = M[piv]
			M[piv] = tmp
		var prow: PackedFloat64Array = M[col]
		var d: float = prow[col]
		for j in 2 * n:
			prow[j] /= d
		M[col] = prow
		for r in n:
			if r != col:
				var f: float = (M[r] as PackedFloat64Array)[col]
				if f != 0.0:
					var rrow: PackedFloat64Array = M[r]
					for j in 2 * n:
						rrow[j] -= f * prow[j]
					M[r] = rrow
	# 零行检测：部分主元不选中全零行，须显式判（如 [[1,2],[2,4]]）
	for r in n:
		var all_zero := true
		var rrow: PackedFloat64Array = M[r]
		for j in n:
			if absf(rrow[j]) > 1e-12 * scale:
				all_zero = false
				break
		if all_zero:
			return []
	var inv := []
	for i in n:
		var row := PackedFloat64Array()
		row.resize(n)
		for j in n:
			row[j] = (M[i] as PackedFloat64Array)[n + j]
		inv.append(row)
	return inv

## 解线性方程组 A·x = b（部分主元高斯消元 + 前后代入）。奇异返回空。
static func solve(A: Array, b: PackedFloat64Array) -> PackedFloat64Array:
	if A.is_empty():
		return PackedFloat64Array()
	var n := A.size()
	if (A[0] as PackedFloat64Array).size() != n or b.size() != n:
		return PackedFloat64Array()
	var scale := 1.0
	for i in n:
		for j in n:
			scale = maxf(scale, absf((A[i] as PackedFloat64Array)[j]))
	# 增广 [A | b]
	var M := []
	for i in n:
		var row := PackedFloat64Array()
		row.resize(n + 1)
		for j in n:
			row[j] = float((A[i] as PackedFloat64Array)[j])
		row[n] = b[i]
		M.append(row)
	for col in n:
		var piv := col
		for r in range(col + 1, n):
			if absf((M[r] as PackedFloat64Array)[col]) > absf((M[piv] as PackedFloat64Array)[col]):
				piv = r
		if absf((M[piv] as PackedFloat64Array)[col]) < 1e-300:
			return PackedFloat64Array()
		if piv != col:
			var tmp: PackedFloat64Array = M[col]
			M[col] = M[piv]
			M[piv] = tmp
		var prow: PackedFloat64Array = M[col]
		for r in range(col + 1, n):
			var f: float = (M[r] as PackedFloat64Array)[col] / prow[col]
			if f != 0.0:
				var rrow: PackedFloat64Array = M[r]
				for j in range(col, n + 1):
					rrow[j] -= f * prow[j]
				M[r] = rrow
	# 零行检测（行内 [0..n-1] 全零而末元非零 → 无解；全零 → 多解，均不返回唯一解）
	for r in n:
		var all_zero := true
		var rrow: PackedFloat64Array = M[r]
		for j in n:
			if absf(rrow[j]) > 1e-12 * scale:
				all_zero = false
				break
		if all_zero:
			return PackedFloat64Array()
	var x := PackedFloat64Array()
	x.resize(n)
	for i in range(n - 1, -1, -1):
		var s: float = (M[i] as PackedFloat64Array)[n]
		var irow: PackedFloat64Array = M[i]
		for j in range(i + 1, n):
			s -= irow[j] * x[j]
		x[i] = s / irow[i]
	return x

## Cholesky 分解：对称正定 A = L·Lᵀ，返回下三角 L。非对称/非正定返回 []。
static func cholesky(A: Array, sym_tol := 1e-9) -> Array:
	if A.is_empty():
		return []
	var n := A.size()
	if (A[0] as PackedFloat64Array).size() != n:
		return []
	# 对称性检查（相对容差）
	var scale := 1.0
	for i in n:
		for j in n:
			scale = maxf(scale, absf((A[i] as PackedFloat64Array)[j]))
	for i in n:
		for j in range(i + 1, n):
			if absf((A[i] as PackedFloat64Array)[j] - (A[j] as PackedFloat64Array)[i]) > sym_tol * scale:
				return []
	var L := []
	for i in n:
		var row := PackedFloat64Array()
		row.resize(n)
		L.append(row)
	for i in n:
		var Li: PackedFloat64Array = L[i]  # 读改写回（GDScript 陷阱，见文件头）
		for j in range(i + 1):
			var s: float = (A[i] as PackedFloat64Array)[j]
			for k in j:
				s -= Li[k] * (L[j] as PackedFloat64Array)[k]
			if i == j:
				if s <= 0.0:
					return []  # 非正定（含半正定奇异）
				Li[j] = sqrt(s)
			else:
				Li[j] = s / (L[j] as PackedFloat64Array)[j]
		L[i] = Li
	return L

## Cholesky 路径解对称正定方程 A·x = b（内部分解 L，前代+回代）。失败返回空。
static func cholesky_solve(A: Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var L := cholesky(A)
	if L.is_empty() or b.size() != A.size():
		return PackedFloat64Array()
	var n := A.size()
	# 前代 L·y = b
	var y := PackedFloat64Array()
	y.resize(n)
	for i in n:
		var s: float = b[i]
		var Li: PackedFloat64Array = L[i]
		for k in i:
			s -= Li[k] * y[k]
		y[i] = s / Li[i]
	# 回代 Lᵀ·x = y
	var x := PackedFloat64Array()
	x.resize(n)
	for i in range(n - 1, -1, -1):
		var s: float = y[i]
		for k in range(i + 1, n):
			s -= (L[k] as PackedFloat64Array)[i] * x[k]
		x[i] = s / (L[i] as PackedFloat64Array)[i]
	return x
