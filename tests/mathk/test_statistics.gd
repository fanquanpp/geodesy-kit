# tests/mathk/test_statistics.gd —— GK-M1 统计内核（向量来源：ARCHITECTURE.md §4 GK-M1【构造】）
# 构造：[1,2,3,4,5] → 均值 3、样本方差 2.5、标准差 1.5811388300841898（贝塞尔 n-1）。
extends "res://tests/test_case_base.gd"

const S := preload("res://core/math/statistics.gd")

func test_basic_statistics() -> void:
	var v := PackedFloat64Array([1, 2, 3, 4, 5])
	assert_almost_eq(S.mean(v), 3.0, 1e-12, "均值")
	assert_almost_eq(S.median(v), 3.0, 1e-12, "中位数")
	assert_almost_eq(S.sample_variance(v), 2.5, 1e-12, "样本方差（Bessel）")
	assert_almost_eq(S.std_sample(v), 1.5811388300841898, 1e-9, "中误差")
	assert_almost_eq(S.population_variance(v), 2.0, 1e-12, "总体方差")
	assert_almost_eq(S.std_population(v), 1.4142135623730951, 1e-9, "总体标准差")
	assert_almost_eq(S.rms(v), 3.3166247903554, 1e-9, "RMS=√11")
	var v2 := PackedFloat64Array([1, 2, 3, 4])
	assert_almost_eq(S.median(v2), 2.5, 1e-12, "偶数个中位数")

func test_empty_and_degenerate_inputs() -> void:
	var e := PackedFloat64Array()
	assert_true(is_nan(S.mean(e)), "空表均值为 NAN")
	assert_true(is_nan(S.median(e)), "空表中位数为 NAN")
	assert_true(is_nan(S.sample_variance(PackedFloat64Array([7.0]))), "单值方差为 NAN（Bessel）")
	assert_almost_eq(S.population_variance(PackedFloat64Array([7.0])), 0.0, 1e-12, "单值总体方差为 0")
	assert_true(is_nan(S.rms(e)), "空表 RMS 为 NAN")

func test_relative_error_and_fraction_text() -> void:
	assert_almost_eq(S.relative_error(0.5, 100.0), 0.005, 1e-15, "相对中误差")
	assert_eq(S.relative_fraction_text(0.005), "1/200", "1/k 文本")
	assert_eq(S.relative_fraction_text(0.0), "∞", "零相对误差")
	assert_true(is_nan(S.relative_error(0.5, 0.0)), "零分母为 NAN")

func test_pauta_outliers() -> void:
	# 构造（解析验证）：11 个 0 + 1 个 30，n=12 → μ=2.5, σ=30/√12≈8.660254，
	# 3σ≈25.98 < |30-2.5|=27.5 → 30 被剔除
	var v := PackedFloat64Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 30])
	var r: Dictionary = S.pauta_outliers(v, 3.0)
	assert_almost_eq(r["mean"], 2.5, 1e-12, "莱依达均值")
	assert_almost_eq(r["sigma"], 8.660254037844387, 1e-9, "莱依达中误差")
	assert_eq((r["removed"] as PackedFloat64Array).size(), 1, "剔除数")
	assert_eq((r["removed"] as PackedFloat64Array)[0], 30.0, "剔除值")
	assert_eq((r["kept"] as PackedFloat64Array).size(), 11, "保留数")
	# 无粗差时全保留
	var r2: Dictionary = S.pauta_outliers(PackedFloat64Array([1, 2, 3, 4, 5]), 3.0)
	assert_eq((r2["removed"] as PackedFloat64Array).size(), 0, "无粗差全保留")
