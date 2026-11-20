# tests/mathk/test_errprop.gd —— GK-M1 误差传播定律（构造向量，解析可验证）
extends "res://tests/test_case_base.gd"

const E := preload("res://core/math/errprop.gd")

func test_linear_sigma() -> void:
	# σ(x+y) = √(σx²+σy²) = √2（σx=σy=1）
	assert_almost_eq(E.linear_sigma(PackedFloat64Array([1, 1]), PackedFloat64Array([1, 1])), 1.4142135623730951, 1e-9, "和函数")
	# σ(k·x) = |k|·σx = 6（k=2, σx=3）
	assert_almost_eq(E.linear_sigma(PackedFloat64Array([2]), PackedFloat64Array([3])), 6.0, 1e-12, "倍数函数")
	# 长度不一致 → NAN
	assert_true(is_nan(E.linear_sigma(PackedFloat64Array([1]), PackedFloat64Array([1, 2]))), "长度不一致")

func test_propagate_generic() -> void:
	# z = x + y，σ=√2（与解析式一致）
	var f_sum := func(vals: Array) -> float: return vals[0] + vals[1]
	var s1 := E.propagate(f_sum, PackedFloat64Array([10, 20]), PackedFloat64Array([1, 1]))
	assert_almost_eq(s1, 1.4142135623730951, 1e-6, "线性函数数值传播")
	# z = x·y：σz=√((∂z/∂x)²σx²+(∂z/∂y)²σy²)=√(y²σx²+x²σy²)，x=2,y=3,σx=0.1,σy=0.3 → √0.45
	var f_mul := func(vals: Array) -> float: return vals[0] * vals[1]
	var s2 := E.propagate(f_mul, PackedFloat64Array([2, 3]), PackedFloat64Array([0.1, 0.3]))
	assert_almost_eq(s2, 0.6708203932499369, 1e-6, "乘积函数数值传播")
	# z = √x：∂z/∂x = 1/(2√x)，x=4,σx=0.08 → σz=0.08/(2·2)=0.02
	var f_sqrt := func(vals: Array) -> float: return sqrt(vals[0])
	var s3 := E.propagate(f_sqrt, PackedFloat64Array([4]), PackedFloat64Array([0.08]))
	assert_almost_eq(s3, 0.02, 1e-8, "开方函数数值传播")

func test_product_relative_sigma() -> void:
	assert_almost_eq(E.product_relative_sigma(0.01, 0.02), 0.022360679774997898, 1e-12, "乘积相对中误差")
	assert_true(is_nan(E.product_relative_sigma(NAN, 0.1)), "非有限输入")
