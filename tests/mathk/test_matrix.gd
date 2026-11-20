# tests/mathk/test_matrix.gd —— GK-M1 矩阵内核回归（向量来源：ARCHITECTURE.md §4 GK-M1【构造】）
# 构造：已知 x=(1,2,3) 构造 A(5×3)、b=Ax（手算硬编码，不依赖被测乘法），
# 法方程 N=AᵀA、rhs=Aᵀb 均手算硬编码，Cholesky/消元/求逆三路径解回 x（残差<1e-12）。
# 注：assert_vector_almost_eq 只接 Vector/Array，PackedFloat64Array 行一律经 _row() 转换。
extends "res://tests/test_case_base.gd"

const M := preload("res://core/math/matrix.gd")

func _mat(rows: Array) -> Array:
	var A := []
	for r in rows:
		A.append(PackedFloat64Array(r))
	return A

func _row(p) -> Array:
	return Array(p)

func test_multiply_and_transpose() -> void:
	var C := M.multiply(_mat([[1, 2], [3, 4]]), _mat([[5, 6], [7, 8]]))
	assert_eq(C.size(), 2, "行数")
	assert_eq((C[0] as PackedFloat64Array).size(), 2, "列数")
	assert_vector_almost_eq(_row(C[0]), [19.0, 22.0], 1e-12, "C[0]")
	assert_vector_almost_eq(_row(C[1]), [43.0, 50.0], 1e-12, "C[1]")
	var T := M.transpose(_mat([[1, 2, 3], [4, 5, 6]]))
	assert_vector_almost_eq(_row(T[0]), [1.0, 4.0], 1e-12, "T[0]")
	assert_vector_almost_eq(_row(T[2]), [3.0, 6.0], 1e-12, "T[2]")
	# 维度不符返回空
	assert_true(M.multiply(_mat([[1, 2]]), _mat([[1, 2]])).is_empty(), "维度不符应返回空")
	# mat_vec（手算）：[[1,2,0],[2,1,1]]·(1,2,3) = (5, 7)
	var b := M.mat_vec(_mat([[1, 2, 0], [2, 1, 1]]), PackedFloat64Array([1, 2, 3]))
	assert_vector_almost_eq(_row(b), [5.0, 7.0], 1e-12, "mat_vec")

func test_inverse_and_solve_elimination() -> void:
	var A := _mat([[2, 1, 0], [1, 3, 1], [0, 1, 2]])
	var Ainv := M.inverse(A)
	assert_false(Ainv.is_empty(), "非奇异矩阵求逆不应为空")
	var I3 := M.multiply(A, Ainv)
	assert_vector_almost_eq(_row(I3[0]), [1.0, 0.0, 0.0], 1e-10, "A·A⁻¹ 第一行")
	assert_vector_almost_eq(_row(I3[1]), [0.0, 1.0, 0.0], 1e-10, "A·A⁻¹ 第二行")
	assert_vector_almost_eq(_row(I3[2]), [0.0, 0.0, 1.0], 1e-10, "A·A⁻¹ 第三行")
	# 奇异矩阵（部分主元后出现零行）
	assert_true(M.inverse(_mat([[1, 2], [2, 4]])).is_empty(), "奇异矩阵应返回空")
	# 非方阵
	assert_true(M.inverse(_mat([[1, 2, 3], [4, 5, 6]])).is_empty(), "非方阵应返回空")

func test_solve_double_path_recovers_x() -> void:
	# N·x = rhs 的手工构造解 x=(1,2,3)：N=[[10,5,5],[5,15,5],[5,5,4]]，rhs=(35,50,27)
	var N := _mat([[10, 5, 5], [5, 15, 5], [5, 5, 4]])
	var rhs := PackedFloat64Array([35, 50, 27])
	var x1 := M.solve(N, rhs)
	assert_vector_almost_eq(_row(x1), [1.0, 2.0, 3.0], 1e-12, "消元路径 x")
	# 求逆路径：x = N⁻¹·rhs
	var Ninv := M.inverse(N)
	var x2 := M.mat_vec(Ninv, rhs)
	assert_vector_almost_eq(_row(x2), [1.0, 2.0, 3.0], 1e-12, "求逆路径 x")
	# 奇异方程返回空
	assert_true(M.solve(_mat([[1, 2], [2, 4]]), PackedFloat64Array([1, 2])).is_empty(), "奇异方程应返回空")

func test_cholesky_double_path_recovers_x() -> void:
	var N := _mat([[10, 5, 5], [5, 15, 5], [5, 5, 4]])
	var rhs := PackedFloat64Array([35, 50, 27])
	var x := M.cholesky_solve(N, rhs)
	assert_vector_almost_eq(_row(x), [1.0, 2.0, 3.0], 1e-12, "Cholesky 路径 x")
	# L·Lᵀ ≈ N（重建检查）
	var L := M.cholesky(N)
	var LLt := M.multiply(L, M.transpose(L))
	assert_vector_almost_eq(_row(LLt[0]), [10.0, 5.0, 5.0], 1e-10, "L·Lᵀ 第一行")
	assert_vector_almost_eq(_row(LLt[1]), [5.0, 15.0, 5.0], 1e-10, "L·Lᵀ 第二行")
	assert_vector_almost_eq(_row(LLt[2]), [5.0, 5.0, 4.0], 1e-10, "L·Lᵀ 第三行")

func test_cholesky_rejections() -> void:
	# 非对称
	assert_true(M.cholesky(_mat([[1, 2], [3, 4]])).is_empty(), "非对称应返回空")
	# 非正定（负对角）
	assert_true(M.cholesky(_mat([[1, 0], [0, -4]])).is_empty(), "非正定应返回空")
	# 半正定（奇异）也不可分解
	assert_true(M.cholesky(_mat([[1, 1], [1, 1]])).is_empty(), "半正定奇异应返回空")
	# 求解失败同样返回空
	var x := M.cholesky_solve(_mat([[1, 2], [3, 4]]), PackedFloat64Array([1, 2]))
	assert_true(x.is_empty(), "非对称方程应返回空")

func test_overdetermined_5x3_authority_vector() -> void:
	# 【构造·权威向量】已知 x=(1,2,3) 构造 A(5×3)、b=Ax（逐项手算，不依赖被测乘法）：
	# A=[[1,1,0],[1,0,1],[0,2,1],[1,1,1],[1,1,1]]，b=A·x=(3,4,7,6,6)
	# N=AᵀA=[[4,3,3],[3,7,4],[3,4,4]]（det=21>0 正定，手算），Aᵀb=N·x=(19,29,23)
	var A := _mat([[1, 1, 0], [1, 0, 1], [0, 2, 1], [1, 1, 1], [1, 1, 1]])
	var b := PackedFloat64Array([3, 4, 7, 6, 6])
	var N := _mat([[4, 3, 3], [3, 7, 4], [3, 4, 4]])
	var rhs := PackedFloat64Array([19, 29, 23])
	# 消元路径
	var x1 := M.solve(N, rhs)
	assert_vector_almost_eq(_row(x1), [1.0, 2.0, 3.0], 1e-12, "5×3 法方程消元路径 x")
	# Cholesky 路径（双路径互检）
	var x2 := M.cholesky_solve(N, rhs)
	assert_vector_almost_eq(_row(x2), [1.0, 2.0, 3.0], 1e-12, "5×3 法方程 Cholesky 路径 x")
	# 回代残差 ||A·x−b||∞ < 1e-12
	var Ax := M.mat_vec(A, x2)
	assert_eq(Ax.size(), 5, "残差向量长度")
	var expected := PackedFloat64Array([3, 4, 7, 6, 6])
	for i in 5:
		assert_almost_eq(Ax[i] - expected[i], 0.0, 1e-12, "A·x−b 残差[%d]" % i)
