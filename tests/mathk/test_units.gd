# tests/mathk/test_units.gd —— GK-M1-5 单位换算回归
#
# 向量来源（ARCHITECTURE.md §4 GK-M1）：
#   【权威·定义精确】1 英亩=4046.8564224 m²、1 亩=2000/3 m²；
#   面积例 152000 m²=228 亩=15.2 公顷=37.560018 英亩。
#   【构造】1 ft=0.3048 m（1959 国际码协议定义精确）、1 us_survey_ft=1200/3937 m
#   （定义精确，约 0.30480060960121924 m）。
# 注：37.560018 为架构向量 6 位小数舍入值（152000/4046.8564224=37.5600179820...），
#     断言容差取 5e-7。
extends "res://tests/test_case_base.gd"

const U := preload("res://core/math/units.gd")

func test_length_definitions() -> void:
	assert_almost_eq(U.to_meter(1.0, "m"), 1.0, 1e-15, "1 m")
	assert_almost_eq(U.to_meter(1.0, "km"), 1000.0, 1e-12, "1 km = 1000 m")
	assert_almost_eq(U.to_meter(1.0, "ft"), 0.3048, 1e-15, "1 ft = 0.3048 m（定义精确）")
	assert_almost_eq(U.to_meter(1.0, "us_survey_ft"), 0.30480060960121924, 1e-15, "1 测图英尺 = 1200/3937 m")
	assert_almost_eq(U.to_meter(1.0, "mi"), 1609.344, 1e-9, "1 mi = 1609.344 m")
	# 测图英尺与国际英尺之比 ≈ 1.000002（教学要点：旧美制资料换算必须区分）
	var ratio := U.to_meter(1.0, "us_survey_ft") / 0.3048
	assert_almost_eq(ratio, 1.000002, 1e-8, "sft/ft ≈ 1.000002")
	# 往返一致
	assert_almost_eq(U.from_meter(U.to_meter(1234.5, "ft"), "ft"), 1234.5, 1e-9, "ft 往返")
	assert_almost_eq(U.convert_length(1.0, "us_survey_ft", "ft"), 1.000002, 1e-8, "sft→ft")

func test_area_definitions() -> void:
	assert_almost_eq(U.to_m2(1.0, "m2"), 1.0, 1e-15, "1 m²")
	assert_almost_eq(U.to_m2(1.0, "mu"), 2000.0 / 3.0, 1e-9, "1 亩 = 2000/3 m²（定义精确）")
	assert_almost_eq(U.to_m2(1.0, "ha"), 10000.0, 1e-12, "1 公顷 = 10000 m²")
	assert_almost_eq(U.to_m2(1.0, "acre"), 4046.8564224, 1e-9, "1 英亩 = 4046.8564224 m²（定义精确）")
	assert_almost_eq(U.to_m2(1.0, "km2"), 1000000.0, 1e-9, "1 km² = 10⁶ m²")
	# 交叉定义互检：1 acre = 43560 international ft²；1 ha = 15 亩
	assert_almost_eq(U.to_m2(1.0, "acre") / (0.3048 * 0.3048), 43560.0, 1e-6, "1 acre = 43560 ft²")
	assert_almost_eq(U.to_m2(1.0, "ha") / U.to_m2(1.0, "mu"), 15.0, 1e-9, "1 公顷 = 15 亩")

func test_area_example_authority_vector() -> void:
	var m2 := 152000.0
	assert_almost_eq(U.from_m2(m2, "mu"), 228.0, 1e-9, "152000 m² = 228 亩（权威）")
	assert_almost_eq(U.from_m2(m2, "ha"), 15.2, 1e-12, "152000 m² = 15.2 公顷（权威）")
	assert_almost_eq(U.from_m2(m2, "acre"), 37.560018, 5e-7, "152000 m² = 37.560018 英亩（权威）")
	assert_almost_eq(U.from_m2(m2, "km2"), 0.152, 1e-12, "0.152 km²")
	# 回程换算（37.560018 为舍入向量，回程容差放大到 1e-3 m²）
	assert_almost_eq(U.convert_area(228.0, "mu", "m2"), 152000.0, 1e-6, "228 亩 → m²")
	assert_almost_eq(U.convert_area(15.2, "ha", "m2"), 152000.0, 1e-9, "15.2 ha → m²")
	assert_almost_eq(U.convert_area(37.560018, "acre", "m2"), 152000.0, 1e-3, "37.560018 acre → m²（舍入回程）")
	# 亩 ↔ 公顷（15 倍关系）
	assert_almost_eq(U.convert_area(228.0, "mu", "ha"), 15.2, 1e-9, "228 亩 = 15.2 公顷")

func test_area_breakdown_and_aliases() -> void:
	var d: Dictionary = U.area_breakdown(152000.0)
	assert_false(d.is_empty(), "breakdown 应非空")
	if not d.is_empty():
		assert_almost_eq(d["m2"], 152000.0, 1e-12, "breakdown m²")
		assert_almost_eq(d["mu"], 228.0, 1e-9, "breakdown 亩")
		assert_almost_eq(d["ha"], 15.2, 1e-12, "breakdown 公顷")
		assert_almost_eq(d["acre"], 37.560018, 5e-7, "breakdown 英亩")
		assert_almost_eq(d["km2"], 0.152, 1e-12, "breakdown km²")
	assert_true(U.area_breakdown(NAN).is_empty(), "NAN 输入返回空")
	assert_true(U.area_breakdown(INF).is_empty(), "INF 输入返回空")
	# 中文别名
	assert_almost_eq(U.convert_area(152000.0, "平方米", "亩"), 228.0, 1e-9, "中文别名：平方米→亩")
	assert_almost_eq(U.convert_area(152000.0, "平方米", "英亩"), 37.560018, 5e-7, "中文别名：平方米→英亩")
	assert_almost_eq(U.convert_length(1.0, "英尺", "m"), 0.3048, 1e-15, "中文别名：英尺→m")
	assert_almost_eq(U.convert_length(1.0, "测图英尺", "m"), 0.30480060960121924, 1e-15, "中文别名：测图英尺")
	# 单位清单（稳定顺序）
	assert_true(U.list_length_units().has("us_survey_ft"), "长度清单含测图英尺")
	assert_true(U.list_area_units().has("mu"), "面积清单含亩")

func test_invalid_inputs() -> void:
	assert_true(is_nan(U.convert_length(1.0, "ly", "m")), "未知单位 → NAN")
	assert_true(is_nan(U.convert_length(1.0, "", "m")), "空单位名 → NAN")
	assert_true(is_nan(U.convert_area(1.0, "m2", "ft")), "面积表内查长度单位（跨量纲）→ NAN")
	assert_true(is_nan(U.convert_length(1.0, "m", "mu")), "长度表内查面积单位（跨量纲）→ NAN")
	assert_true(is_nan(U.convert_length(NAN, "m", "ft")), "NAN 输入 → NAN")
	assert_true(is_nan(U.to_meter(INF, "km")), "INF 输入 → NAN")
	assert_true(is_nan(U.from_m2(NAN, "mu")), "NAN 面积 → NAN")
