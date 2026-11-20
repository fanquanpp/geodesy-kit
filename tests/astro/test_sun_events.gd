# tests/astro/test_sun_events.gd —— GK-M8-2（F4）日出日落/时角/赤纬
# 向量来源：ARCHITECTURE.md §4 GK-M8【构造】F4 北京 2024-06-21：
#   ha0=112.5345°、日出 UTC 20.7695h（前一日，北京 04:46）、日落 11.7741h、昼长 15.0046h
#   （判据：日出高度≈−0.833°）。构造口径经本会话 Python 复核（交付说明附偏差量）：
#   本实现在"中天时刻 δ/EoT"上求 δ，与向量（δ 取 06Z 值）互差 ha0<0.001°、时刻<0.001h。
extends "res://tests/test_case_base.gd"

const SE := preload("res://core/astro/sun_events.gd")
const S := preload("res://core/astro/solar.gd")

func test_f4_beijing() -> void:
	var r := SE.sun_events({
		"year": 2024, "month": 6, "day": 21,
		"lat_deg": 39.9075276, "lon_deg": 116.3912757, "tz_hours": 8.0,
	})
	assert_true(r["ok"], "F4 北京算例应成功")
	if bool(r["ok"]):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["ha0_deg"]), 112.5345, 0.005, "F4 半昼长时角 ha0")
		assert_almost_eq(float(v["sunrise_utc_h"]), 20.7695, 0.002, "F4 日出 UTC（前一日）")
		assert_almost_eq(float(v["sunset_utc_h"]), 11.7741, 0.002, "F4 日落 UTC")
		assert_almost_eq(float(v["daylen_h"]), 15.0046, 0.005, "F4 昼长")
		assert_almost_eq(float(v["sunrise_local_h"]), 4.7692, 0.002, "F4 北京时间日出 04:46")
		# 赤纬与权威 F3 向量（δ=+23.43811°）相差 <0.001°
		assert_almost_eq(float(v["decl_deg"]), 23.43811, 0.001, "中天时刻太阳赤纬")
		assert_int_eq(int(v["sunrise_day_shift"]), -1, "日出在前一 UTC 日")
		# δ/EoT 与昼长自洽：昼长 = 2·ha0/15
		assert_almost_eq(float(v["daylen_h"]), 2.0 * float(v["ha0_deg"]) / 15.0, 1e-12, "昼长与 ha0 自洽")

func test_criterion_altitude_at_sunrise() -> void:
	# 判据：日出时刻太阳高度 ≈ −0.833°（用 GKSolar 在日出时刻交叉复核）
	var r := SE.sun_events({
		"year": 2024, "month": 6, "day": 21,
		"lat_deg": 39.9075276, "lon_deg": 116.3912757,
	})
	assert_true(r["ok"], "算例应成功")
	if bool(r["ok"]):
		var v: Dictionary = r["value"]
		var rh := float(v["sunrise_utc_h"])
		var hour := int(floor(rh))
		var minute := int(round((rh - hour) * 60.0))
		if minute >= 60:
			minute -= 60
			hour += 1
		var sr := S.solar_position({
			"year": 2024, "month": 6, "day": 20, "hour": hour, "minute": minute, "second": 0.0,
			"lat_deg": 39.9075276, "lon_deg": 116.3912757,
		})
		assert_true(sr["ok"], "日出时刻太阳位置应可算")
		if bool(sr["ok"]):
			var alt := float(sr["value"]["elev_deg"])
			assert_almost_eq(alt, -0.833, 0.02, "日出时刻太阳高度 ≈ −0.833°")

func test_ha0_formula_direct() -> void:
	# 分派公式直代：ha0 = arccos[cos(90.833°)/(cosφcosδ) − tanφ·tanδ]，δ=+23.43811
	var phi := deg_to_rad(39.9075276)
	var delta := deg_to_rad(23.43811)
	var cos_ha0 := cos(deg_to_rad(90.833)) / (cos(phi) * cos(delta)) - tan(phi) * tan(delta)
	var ha0_ref := rad_to_deg(acos(cos_ha0))
	var r := SE.sun_events({
		"year": 2024, "month": 6, "day": 21,
		"lat_deg": 39.9075276, "lon_deg": 116.3912757,
	})
	if bool(r["ok"]):
		assert_almost_eq(float(r["value"]["ha0_deg"]), ha0_ref, 0.001, "ha0 与分派公式直代一致（δ 微差内）")

func test_polar_day_and_night() -> void:
	# 极夜：北纬 80° 冬至（δ≈−23.44°）→ cos(ha0)>1
	var night := SE.sun_events({"year": 2024, "month": 12, "day": 21, "lat_deg": 80.0, "lon_deg": 0.0})
	assert_true(night["ok"], "极夜算例 ok=true（含中文说明）")
	assert_true(bool(night["value"].get("polar", false)) and not bool(night["value"].get("polar_day", true)), "北半球冬至 80°N 为极夜")
	# 极昼：北纬 80° 夏至（δ≈+23.44°）→ cos(ha0)<−1
	var day := SE.sun_events({"year": 2024, "month": 6, "day": 21, "lat_deg": 80.0, "lon_deg": 0.0})
	assert_true(day["ok"], "极昼算例 ok=true")
	assert_true(bool(day["value"].get("polar", false)) and bool(day["value"].get("polar_day", false)), "80°N 夏至为极昼")
	# 中纬度不受影响
	var mid := SE.sun_events({"year": 2024, "month": 6, "day": 21, "lat_deg": 39.9075276, "lon_deg": 116.3912757})
	assert_false(bool(mid["value"].get("polar", false)), "北京非极昼极夜")

func test_h0_configurable() -> void:
	# h0=0°（几何地平，不含折光与视半径）→ 昼长略短于 h0=−0.833°
	var r1 := SE.sun_events({"year": 2024, "month": 6, "day": 21, "lat_deg": 39.9075276, "lon_deg": 116.3912757})
	var r2 := SE.sun_events({"year": 2024, "month": 6, "day": 21, "lat_deg": 39.9075276, "lon_deg": 116.3912757, "h0_deg": 0.0})
	assert_true(r1["ok"] and r2["ok"], "两种 h0 均可算")
	if bool(r1["ok"]) and bool(r2["ok"]):
		assert_true(float(r2["value"]["daylen_h"]) < float(r1["value"]["daylen_h"]), "h0=0° 昼长 < h0=−0.833°")

func test_invalid_inputs() -> void:
	var bad_lat := SE.sun_events({"year": 2024, "month": 6, "day": 21, "lat_deg": 90.0, "lon_deg": 116.0})
	assert_false(bool(bad_lat["ok"]), "纬度 90 应拒绝")
	var bad_month := SE.sun_events({"year": 2024, "month": 0, "day": 21, "lat_deg": 39.9, "lon_deg": 116.0})
	assert_false(bool(bad_month["ok"]), "月份 0 应拒绝")
	var bad_tz := SE.sun_events({"year": 2024, "month": 6, "day": 21, "lat_deg": 39.9, "lon_deg": 116.0, "tz_hours": 13.0})
	assert_false(bool(bad_tz["ok"]), "时区 ±13 应拒绝")
	for r: Dictionary in [bad_lat, bad_month, bad_tz]:
		assert_true(String(r["error"]).length() > 0, "失败必带中文错误")
		assert_true((r["value"] as Dictionary).is_empty(), "失败时 value 为空")
