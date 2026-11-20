# tests/astro/test_solar.gd —— GK-M8-1（F3）太阳方位角/高度角
# 向量来源：ARCHITECTURE.md §4 GK-M8【权威·NOAA 算法，本会话 pvlib 互差≤0.007°】
# （本会话施工前已在 Python 复核：3 例全部复现，偏差 ≤0.0005°，见交付说明）
extends "res://tests/test_case_base.gd"

const S := preload("res://core/astro/solar.gd")

func _case() -> Dictionary:
	return {
		"ok": false, "value": {}, "steps": [], "formula": "", "error": "未调用"
	}

func test_f3_case1() -> void:
	# (2024-03-20 12:00Z, 40.0, −105.25) → az=78.719°/zen=102.900°/δ=+0.14703°/EoT=−7.291min
	var r := S.solar_position({
		"year": 2024, "month": 3, "day": 20, "hour": 12, "minute": 0, "second": 0.0,
		"lat_deg": 40.0, "lon_deg": -105.25,
	})
	assert_true(r["ok"], "算例 1 应成功")
	if bool(r["ok"]):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["az_deg"]), 78.719, 0.002, "F3-1 方位角")
		assert_almost_eq(float(v["zen_deg"]), 102.900, 0.002, "F3-1 天顶距（几何）")
		assert_almost_eq(float(v["decl_deg"]), 0.14703, 1e-5, "F3-1 太阳赤纬")
		assert_almost_eq(float(v["eot_min"]), -7.291, 0.002, "F3-1 均时差")

func test_f3_case2() -> void:
	# (2024-06-21 06:00Z, 39.9075, 116.3913) → az=240.788°/zen=27.358°/δ=+23.43811°/EoT=−1.871min
	var r := S.solar_position({
		"year": 2024, "month": 6, "day": 21, "hour": 6, "minute": 0, "second": 0.0,
		"lat_deg": 39.9075, "lon_deg": 116.3913,
	})
	assert_true(r["ok"], "算例 2 应成功")
	if bool(r["ok"]):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["az_deg"]), 240.788, 0.002, "F3-2 方位角")
		assert_almost_eq(float(v["zen_deg"]), 27.358, 0.002, "F3-2 天顶距")
		assert_almost_eq(float(v["decl_deg"]), 23.43811, 1e-5, "F3-2 太阳赤纬")
		assert_almost_eq(float(v["eot_min"]), -1.871, 0.002, "F3-2 均时差")

func test_f3_case3() -> void:
	# (2024-01-01 03:00Z, −33.8678, 151.2073) → az=304.675°/zen=17.307°/δ=−23.04888°/EoT=−3.152min
	var r := S.solar_position({
		"year": 2024, "month": 1, "day": 1, "hour": 3, "minute": 0, "second": 0.0,
		"lat_deg": -33.8678, "lon_deg": 151.2073,
	})
	assert_true(r["ok"], "算例 3 应成功")
	if bool(r["ok"]):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["az_deg"]), 304.675, 0.002, "F3-3 方位角")
		assert_almost_eq(float(v["zen_deg"]), 17.307, 0.002, "F3-3 天顶距")
		assert_almost_eq(float(v["decl_deg"]), -23.04888, 1e-5, "F3-3 太阳赤纬")
		assert_almost_eq(float(v["eot_min"]), -3.152, 0.002, "F3-3 均时差")

func test_protocol_shape() -> void:
	var r := S.solar_position({
		"year": 2024, "month": 3, "day": 20, "hour": 12, "minute": 0, "second": 0.0,
		"lat_deg": 40.0, "lon_deg": -105.25,
	})
	assert_true(r.has("ok") and r.has("value") and r.has("steps") and r.has("formula") and r.has("error"), "§5 协议五键齐备")
	var steps: Array = r["steps"]
	assert_true(steps.size() >= 4, "步骤数 ≥ 4")
	for st: Dictionary in steps:
		assert_true(st.has("title") and st.has("formula") and st.has("substitution") and st.has("result"), "步骤四字段齐备")
	# 天顶距 elev = 90 − zen 自洽
	var v: Dictionary = r["value"]
	assert_almost_eq(float(v["elev_deg"]), 90.0 - float(v["zen_deg"]), 1e-12, "elev = 90 − zen")
	# 方位角归一化
	assert_between(float(v["az_deg"]), 0.0, 360.0, "方位角在 [0,360)")

func test_refraction_option() -> void:
	var r := S.solar_position({
		"year": 2024, "month": 3, "day": 20, "hour": 12, "minute": 0, "second": 0.0,
		"lat_deg": 40.0, "lon_deg": -105.25, "with_refraction": true,
	})
	assert_true(r["ok"], "折光选项应成功")
	if bool(r["ok"]):
		var v: Dictionary = r["value"]
		assert_true(v.has("elev_apparent_deg") and v.has("refr_corr_deg"), "含视高度角与折光改正键")
		# 太阳在地平线下（zen≈102.9°），折光改正为 NOAA 分段经验式的小值
		assert_almost_eq(float(v["zen_deg"]), 102.900, 0.002, "几何天顶距不受折光开关影响")
		assert_between(float(v["refr_corr_deg"]), -0.5, 0.5, "地平线下折光改正量级")

func test_jd_consistency() -> void:
	# 与 F6 权威常数同源：JD(2000-01-01 12UT) = 2451545.0
	assert_almost_eq(S.calc_jd(2000, 1, 1) + 0.5, 2451545.0, 1e-9, "J2000.0 儒略日")
	# 太阳赤纬在两至两分附近的物理常识范围
	var t_eq := S.julian_cent(2451545.0 + 90.0)  # ~春分附近
	var d_eq: float = S.sun_declination(t_eq)
	assert_between(d_eq, -5.0, 5.0, "J2000+90d 赤纬接近 0")

func test_invalid_inputs() -> void:
	var bad_year := S.solar_position({"year": 1800, "month": 1, "day": 1, "hour": 0, "minute": 0, "second": 0.0, "lat_deg": 40.0, "lon_deg": 0.0})
	assert_false(bool(bad_year["ok"]), "年份 1800 应拒绝（适用 1901-2099）")
	var bad_month := S.solar_position({"year": 2024, "month": 13, "day": 1, "hour": 0, "minute": 0, "second": 0.0, "lat_deg": 40.0, "lon_deg": 0.0})
	assert_false(bool(bad_month["ok"]), "月份 13 应拒绝")
	var bad_lat := S.solar_position({"year": 2024, "month": 1, "day": 1, "hour": 0, "minute": 0, "second": 0.0, "lat_deg": 90.0, "lon_deg": 0.0})
	assert_false(bool(bad_lat["ok"]), "纬度 90 应拒绝（±89.8 界限）")
	var bad_hour := S.solar_position({"year": 2024, "month": 1, "day": 1, "hour": 24, "minute": 0, "second": 0.0, "lat_deg": 40.0, "lon_deg": 0.0})
	assert_false(bool(bad_hour["ok"]), "小时 24 应拒绝")
	for r: Dictionary in [bad_year, bad_month, bad_lat, bad_hour]:
		assert_true(String(r["error"]).length() > 0, "错误信息为中文可读且非空")
		assert_true((r["value"] as Dictionary).is_empty(), "失败时 value 为空字典")
