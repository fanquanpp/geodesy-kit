# tests/mathk/test_least_squares.gd —— GK-M1-2 正规方程最小二乘回归
#
# 向量来源（ARCHITECTURE.md §4）：
#   1)【构造】5×3 已知解回代：x=(1,2,3)，A=[[1,1,0],[1,0,1],[0,2,1],[1,1,1],[1,1,1]]、
#      b=A·x=(3,4,7,6,6)（逐项手算，不依赖被测乘法）；
#      N=AᵀA=[[4,3,3],[3,7,4],[3,4,4]]（det=21>0 正定，手算）、Aᵀb=(19,29,23)（手算）；
#      消元/Cholesky 双路径均回收 x，残差 <1e-12。
#   2)【权威·借 M6 水准网】§4 GK-M6 C7（教材公式，numpy 双法互检）：
#      H_A=100.000；h1=+12.513(A→P1, 3.0km)、h2=+20.947(A→P2, 4.0km)、h3=+8.402(P1→P2, 2.0km)，
#      P=diag(1/3,1/4,1/2) → H_P1=112.5237、H_P2=120.9328、V=(+0.0107,−0.0142,+0.0071)m、
#      μ=±10.7mm；条件法闭合差 w=h1+h3−h2=−0.032m 与间接平差结果逐位一致（互检）。
#      本文件独立手算精确值：x̂=(12.5236666667, 20.9327777778)，
#      V=(+0.0106666667, −0.0142222222, +0.0071111111)，VᵀPV=0.0001137778，μ=0.0106666667，
#      Qxx=N⁻¹=[[2,4/3],[4/3,20/9]]（N=[[5/6,−1/2],[−1/2,3/4]]，det=3/8，手算）。
extends "res://tests/test_case_base.gd"

const LS := preload("res://core/math/least_squares.gd")
const M := preload("res://core/math/matrix.gd")

func _mat(rows: Array) -> Array:
	var A := []
	for r in rows:
		A.append(PackedFloat64Array(r))
	return A

func _row(p) -> Array:
	return Array(p)

func test_overdetermined_5x3_recovers_x() -> void:
	var A := _mat([[1, 1, 0], [1, 0, 1], [0, 2, 1], [1, 1, 1], [1, 1, 1]])
	var b := PackedFloat64Array([3, 4, 7, 6, 6])
	var P := PackedFloat64Array([1, 1, 1, 1, 1])  # 等权
	var r: Dictionary = LS.solve(A, b, P)
	assert_false(r.is_empty(), "等权 5×3 最小二乘应成功")
	if r.is_empty():
		return  # 防御：避免空引用触发 runner 已知盲点
	var xhat := r["xhat"] as PackedFloat64Array
	assert_vector_almost_eq(_row(xhat), [1.0, 2.0, 3.0], 1e-12, "5×3 回收 x")
	assert_int_eq(int(r["dof"]), 2, "自由度 n−t=2")
	var v := r["v"] as PackedFloat64Array
	for i in 5:
		assert_almost_eq(v[i], 0.0, 1e-12, "残差 v[%d]（b=A·x 在列空间内）" % i)
	assert_almost_eq(r["vtpv"], 0.0, 1e-18, "VᵀPV≈0")
	assert_almost_eq(r["mu"], 0.0, 1e-12, "μ≈0")

func test_5x3_normal_equations_and_dual_paths() -> void:
	var A := _mat([[1, 1, 0], [1, 0, 1], [0, 2, 1], [1, 1, 1], [1, 1, 1]])
	var b := PackedFloat64Array([3, 4, 7, 6, 6])
	var P := PackedFloat64Array([1, 1, 1, 1, 1])
	var ne: Dictionary = LS.normal_equations(A, b, P)
	assert_false(ne.is_empty(), "法方程组装应成功")
	if ne.is_empty():
		return
	assert_vector_almost_eq(_row((ne["N"] as Array)[0]), [4.0, 3.0, 3.0], 1e-12, "N 第 1 行")
	assert_vector_almost_eq(_row((ne["N"] as Array)[1]), [3.0, 7.0, 4.0], 1e-12, "N 第 2 行")
	assert_vector_almost_eq(_row((ne["N"] as Array)[2]), [3.0, 4.0, 4.0], 1e-12, "N 第 3 行")
	assert_vector_almost_eq(_row(ne["k"] as PackedFloat64Array), [19.0, 29.0, 23.0], 1e-12, "Aᵀb")
	var N: Array = ne["N"]
	var k: PackedFloat64Array = ne["k"]
	# GKMatrix 消元 / Cholesky 双路径（权威向量要求的双路径）
	var x_el := M.solve(N, k)
	assert_vector_almost_eq(_row(x_el), [1.0, 2.0, 3.0], 1e-12, "消元路径 x")
	var x_ch := M.cholesky_solve(N, k)
	assert_vector_almost_eq(_row(x_ch), [1.0, 2.0, 3.0], 1e-12, "Cholesky 路径 x")
	# least_squares 两路径一致
	var r1: Dictionary = LS.solve(A, b, P, true)
	var r2: Dictionary = LS.solve(A, b, P, false)
	assert_false(r1.is_empty() or r2.is_empty(), "LS 双路径应成功")
	if not (r1.is_empty() or r2.is_empty()):
		assert_vector_almost_eq(_row(r1["xhat"] as PackedFloat64Array), [1.0, 2.0, 3.0], 1e-12, "LS Cholesky 路径")
		assert_vector_almost_eq(_row(r2["xhat"] as PackedFloat64Array), [1.0, 2.0, 3.0], 1e-12, "LS 消元路径")
	# Qxx=N⁻¹：N·Qxx≈I
	var qxx: Array = r1["qxx"]
	var I3 := M.multiply(N, qxx)
	assert_vector_almost_eq(_row(I3[0]), [1.0, 0.0, 0.0], 1e-9, "N·Qxx 第 1 行")
	assert_vector_almost_eq(_row(I3[1]), [0.0, 1.0, 0.0], 1e-9, "N·Qxx 第 2 行")
	assert_vector_almost_eq(_row(I3[2]), [0.0, 0.0, 1.0], 1e-9, "N·Qxx 第 3 行")

func test_leveling_network_m6_c7_authority_vector() -> void:
	# 误差方程（以 H_A 为基准：x1=H_P1−H_A、x2=H_P2−H_A）
	#   v1 = x1 − h1 ； v2 = x2 − h2 ； v3 = (x2−x1) − h3
	var B := _mat([[1, 0], [0, 1], [-1, 1]])
	var l := PackedFloat64Array([12.513, 20.947, 8.402])
	var P := PackedFloat64Array([1.0 / 3.0, 1.0 / 4.0, 1.0 / 2.0])
	var r: Dictionary = LS.solve(B, l, P)
	assert_false(r.is_empty(), "水准网间接平差应成功")
	if r.is_empty():
		return
	assert_int_eq(int(r["dof"]), 1, "自由度 n−t=1")
	var xhat := r["xhat"] as PackedFloat64Array
	assert_almost_eq(xhat[0], 12.523666666666667, 1e-9, "x̂1 精确值（手算）")
	assert_almost_eq(xhat[1], 20.932777777777778, 1e-9, "x̂2 精确值（手算）")
	# 架构权威向量（4 位小数舍入，容差 1e-4）
	assert_almost_eq(100.0 + xhat[0], 112.5237, 1e-4, "H_P1=112.5237（权威）")
	assert_almost_eq(100.0 + xhat[1], 120.9328, 1e-4, "H_P2=120.9328（权威）")
	var v := r["v"] as PackedFloat64Array
	assert_almost_eq(v[0], 0.010666666666667, 1e-9, "v1 精确值")
	assert_almost_eq(v[1], -0.014222222222222, 1e-9, "v2 精确值")
	assert_almost_eq(v[2], 0.007111111111111, 1e-9, "v3 精确值")
	assert_almost_eq(v[0], 0.0107, 1e-4, "v1=+0.0107（权威舍入）")
	assert_almost_eq(v[1], -0.0142, 1e-4, "v2=−0.0142（权威舍入）")
	assert_almost_eq(v[2], 0.0071, 1e-4, "v3=+0.0071（权威舍入）")
	assert_almost_eq(r["vtpv"], 0.000113777777778, 1e-12, "VᵀPV（手算）")
	assert_almost_eq(r["mu"], 0.010666666666667, 1e-9, "μ 精确值")
	assert_almost_eq(r["mu"], 0.0107, 1e-4, "μ=±10.7mm（权威舍入）")
	assert_almost_eq(r["mu"] * 1000.0, 10.7, 5e-2, "μ=10.7mm（权威为 1 位小数舍入值）")
	# Qxx = N⁻¹ = [[2,4/3],[4/3,20/9]]（手算）
	var qxx: Array = r["qxx"]
	assert_vector_almost_eq(_row(qxx[0]), [2.0, 4.0 / 3.0], 1e-9, "Qxx 第 1 行")
	assert_vector_almost_eq(_row(qxx[1]), [4.0 / 3.0, 20.0 / 9.0], 1e-9, "Qxx 第 2 行")
	var sigma_x := r["sigma_x"] as PackedFloat64Array
	assert_almost_eq(sigma_x[0], 0.010666666666667 * sqrt(2.0), 1e-9, "σ_x1=μ·√Q11")
	assert_almost_eq(sigma_x[1], 0.010666666666667 * sqrt(20.0 / 9.0), 1e-9, "σ_x2=μ·√Q22")
	# 与条件法互检：闭合差 w=h1+h3−h2=−0.032m；平差后条件式 h1+v1+h3+v3−(h2+v2)=0
	var w := 12.513 + 8.402 - 20.947
	assert_almost_eq(w, -0.032, 1e-12, "条件闭合差 w=−0.032m（权威）")
	assert_almost_eq(v[0] + v[2] - v[1], -w, 1e-9, "平差后条件式闭合（间接/条件互检）")

func test_full_matrix_weight_matches_diagonal() -> void:
	# 同一水准网改用 n×n 全权阵（对角阵的 Array 形态），结果必须与对角权逐位一致
	var B := _mat([[1, 0], [0, 1], [-1, 1]])
	var l := PackedFloat64Array([12.513, 20.947, 8.402])
	var P_diag := PackedFloat64Array([1.0 / 3.0, 1.0 / 4.0, 1.0 / 2.0])
	var P_mat := _mat([[1.0 / 3.0, 0, 0], [0, 1.0 / 4.0, 0], [0, 0, 1.0 / 2.0]])
	var r1: Dictionary = LS.solve(B, l, P_diag)
	var r2: Dictionary = LS.solve(B, l, P_mat)
	assert_false(r1.is_empty() or r2.is_empty(), "两种权形态都应成功")
	if not (r1.is_empty() or r2.is_empty()):
		assert_vector_almost_eq(_row(r2["xhat"] as PackedFloat64Array), _row(r1["xhat"] as PackedFloat64Array), 1e-12, "全权阵=对角权 x̂")
		assert_almost_eq(r2["vtpv"], r1["vtpv"], 1e-15, "VᵀPV 一致")
		assert_almost_eq(r2["mu"], r1["mu"], 1e-12, "μ 一致")

func test_exact_determined_dof_zero() -> void:
	# n=t 恰定：x̂ 仍有效，dof=0，μ 无定义 → NAN
	var B := _mat([[1, 0], [0, 1]])
	var l := PackedFloat64Array([1, 2])
	var r: Dictionary = LS.solve(B, l, PackedFloat64Array([1, 1]))
	assert_false(r.is_empty(), "恰定方程应成功")
	if r.is_empty():
		return
	assert_vector_almost_eq(_row(r["xhat"] as PackedFloat64Array), [1.0, 2.0], 1e-12, "恰定解")
	assert_int_eq(int(r["dof"]), 0, "dof=0")
	assert_true(is_nan(r["mu"]), "恰定时 μ=NAN")
	var sx := r["sigma_x"] as PackedFloat64Array
	assert_true(is_nan(sx[0]), "恰定时 σ_x=NAN")

func test_unit_weight_sigma_helper() -> void:
	var v := PackedFloat64Array([0.010666666666667, -0.014222222222222, 0.007111111111111])
	var P := PackedFloat64Array([1.0 / 3.0, 1.0 / 4.0, 1.0 / 2.0])
	assert_almost_eq(LS.unit_weight_sigma(v, P, 1), 0.010666666666667, 1e-9, "μ 辅助函数")
	assert_true(is_nan(LS.unit_weight_sigma(v, P, 0)), "dof=0 → NAN")
	assert_true(is_nan(LS.unit_weight_sigma(PackedFloat64Array(), P, 1)), "空残差 → NAN")

func test_failures_return_empty() -> void:
	var B2 := _mat([[1, 0], [0, 1]])
	# 观测数不符
	assert_true(LS.solve(B2, PackedFloat64Array([1, 2, 3]), PackedFloat64Array([1, 1, 1])).is_empty(), "l 与行数不符")
	# 欠定 n<t
	assert_true(LS.solve(_mat([[1, 2, 3], [4, 5, 6]]), PackedFloat64Array([1, 2]), PackedFloat64Array([1, 1])).is_empty(), "欠定 n<t")
	# 行宽不一致
	assert_true(LS.solve(_mat([[1, 2], [1]]), PackedFloat64Array([1, 2]), PackedFloat64Array([1, 1])).is_empty(), "行宽不一致")
	# 法方程奇异（B 列线性相关）
	assert_true(LS.solve(_mat([[1, 1], [1, 1], [2, 2]]), PackedFloat64Array([1, 2, 4]), PackedFloat64Array([1, 1, 1])).is_empty(), "秩亏法方程奇异")
	# 权为负
	assert_true(LS.solve(B2, PackedFloat64Array([1, 2]), PackedFloat64Array([-1, 1])).is_empty(), "负权应拒绝")
	# 权阵不对称
	assert_true(LS.solve(B2, PackedFloat64Array([1, 2]), _mat([[1, 2], [0, 1]])).is_empty(), "非对称权阵应拒绝")
	# 权长度不符
	assert_true(LS.solve(B2, PackedFloat64Array([1, 2]), PackedFloat64Array([1])).is_empty(), "权长度不符")
	# 非有限元素
	assert_true(LS.solve(_mat([[NAN, 0], [0, 1]]), PackedFloat64Array([1, 2]), PackedFloat64Array([1, 1])).is_empty(), "B 含 NaN")
	assert_true(LS.solve(B2, PackedFloat64Array([1, INF]), PackedFloat64Array([1, 1])).is_empty(), "l 含 INF")
	# 空输入
	assert_true(LS.solve([], PackedFloat64Array(), PackedFloat64Array()).is_empty(), "空 B")
