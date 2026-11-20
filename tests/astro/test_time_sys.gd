# tests/astro/test_time_sys.gd —— GK-M8-4（F6）时间系统
# 向量来源：ARCHITECTURE.md §4 GK-M8【权威·常数】JD(2000-01-01 12UT)=2451545.0、
# GPS 周起点 1980-01-06 00:00 UTC、2024-06-21 年积日 173。
# GPS 周/周内秒与闰秒自洽构造经本会话 Python 复核（2024-06-21 00:00 UTC → 周 2319、SOW 432000 s）。
extends "res://tests/test_case_base.gd"

const T := preload("res://core/astro/time_sys.gd")

func test_jd_authority() -> void:
	assert_almost_eq(T.utc_to_jd(2000, 1, 1, 12, 0, 0.0), 2451545.0, 1e-9, "J2000.0 儒略日（权威常数）")
	assert_almost_eq(T.utc_to_jd(1980, 1, 6, 0, 0, 0.0), 2444244.5, 1e-9, "GPS 周起点儒略日")
	assert_almost_eq(T.utc_to_jd(2024, 6, 21, 0, 0, 0.0), 2460482.5, 1e-9, "2024-06-21 00UT 儒略日")

func test_doy_authority() -> void:
	assert_int_eq(T.day_of_year(2024, 6, 21), 173, "2024-06-21 年积日 173（权威）")
	assert_int_eq(T.day_of_year(2024, 12, 31), 366, "2024 闰年 366 天")
	assert_int_eq(T.day_of_year(2023, 12, 31), 365, "2023 平年 365 天")
	assert_int_eq(T.day_of_year(2000, 3, 1), 61, "2000 闰年（400 整除）3 月 1 日 = 61")
	assert_int_eq(T.day_of_year(1900, 3, 1), 60, "1900 平年（百年不闰）3 月 1 日 = 60")
	assert_int_eq(T.day_of_year(2024, 2, 30), 0, "非法日期返回 0")

func test_gps_week_sow() -> void:
	var ws := T.gps_week_sow(2444244.5)
	assert_int_eq(int(ws["week"]), 0, "GPS 纪元周号 0")
	assert_almost_eq(float(ws["sow_s"]), 0.0, 1e-9, "GPS 纪元周内秒 0")
	# 2024-06-21 00:00 UTC：周 2319、SOW 432000 s（Python 构造复核）
	var ws2 := T.gps_week_sow(2460482.5)
	assert_int_eq(int(ws2["week"]), 2319, "2024-06-21 GPS 连续周号 2319")
	assert_almost_eq(float(ws2["sow_s"]), 432000.0, 1e-6, "周内秒（周四 00:00 UTC，周日起算第 5 天）")
	# 同日 12:00（JD +0.5）：SOW = 5.5 天 × 86400 = 475200 s
	var ws3 := T.gps_week_sow(2460483.0)
	assert_almost_eq(float(ws3["sow_s"]), 475200.0, 1e-6, "同日 12UT 周内秒（Python 构造复核）")

func test_leap_seconds() -> void:
	assert_almost_eq(T.leap_seconds(2444244.5), 0.0, 1e-9, "GPS 纪元时闰秒 0")
	assert_almost_eq(T.leap_seconds(T.utc_to_jd(1981, 7, 1, 0, 0, 0.0)), 1.0, 1e-9, "1981-07-01 起累计 1 s")
	assert_almost_eq(T.leap_seconds(T.utc_to_jd(1990, 6, 1, 0, 0, 0.0)), 6.0, 1e-9, "1990 年为 6 s")
	assert_almost_eq(T.leap_seconds(T.utc_to_jd(2017, 6, 1, 0, 0, 0.0)), 18.0, 1e-9, "2017-01-01 起 18 s（至今未新增）")
	assert_almost_eq(T.leap_seconds(T.utc_to_jd(2024, 6, 21, 0, 0, 0.0)), 18.0, 1e-9, "2024 年仍 18 s")
	assert_almost_eq(T.gps_minus_utc(T.utc_to_jd(2024, 6, 21, 12, 0, 0.0)), 18.0, 1e-9, "GPS−UTC = 18 s")

func test_convert_protocol() -> void:
	var r := T.convert({"year": 2024, "month": 6, "day": 21, "hour": 0, "minute": 0, "second": 0.0})
	assert_true(r["ok"], "convert 协议应成功")
	if bool(r["ok"]):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["jd"]), 2460482.5, 1e-9, "JD")
		assert_almost_eq(float(v["mjd"]), 60482.0, 1e-9, "MJD = JD − 2400000.5")
		assert_int_eq(int(v["doy"]), 173, "年积日")
		assert_int_eq(int(v["week"]), 2319, "GPS 周号")
		assert_almost_eq(float(v["sow_s"]), 432000.0, 1e-6, "周内秒（UTC 口径）")
		assert_int_eq(int(v["week_day"]), 5, "周五（0=周日）")
		assert_almost_eq(float(v["leap_s"]), 18.0, 1e-9, "累计闰秒")
		assert_almost_eq(float(v["sow_gps_s"]), 432018.0, 1e-6, "GPS 时标度周内秒 = 432000 + 18")
		var steps: Array = r["steps"]
		assert_true(steps.size() == 4, "4 个解题步骤")

func test_jd_to_utc_roundtrip() -> void:
	for jd_day: Array in [[2024, 6, 21, 15, 30, 45.0], [1901, 1, 1, 0, 0, 0.0], [2099, 12, 31, 23, 59, 59.0], [2000, 2, 29, 6, 0, 0.0]]:
		var jd := T.utc_to_jd(int(jd_day[0]), int(jd_day[1]), int(jd_day[2]), int(jd_day[3]), int(jd_day[4]), float(jd_day[5]))
		var back := T.jd_to_utc(jd)
		assert_true(bool(back["ok"]), "往返 %s 应成功" % str(jd_day))
		if bool(back["ok"]):
			assert_int_eq(int(back["year"]), int(jd_day[0]), "年")
			assert_int_eq(int(back["month"]), int(jd_day[1]), "月")
			assert_int_eq(int(back["day"]), int(jd_day[2]), "日")
			assert_int_eq(int(back["hour"]), int(jd_day[3]), "时")
			assert_int_eq(int(back["minute"]), int(jd_day[4]), "分")
			assert_almost_eq(float(back["second"]), float(jd_day[5]), 1e-6, "秒")

func test_invalid_inputs() -> void:
	var r1 := T.convert({"year": 2024, "month": 13, "day": 1, "hour": 0, "minute": 0, "second": 0.0})
	assert_false(bool(r1["ok"]), "月份 13 应拒绝")
	var r2 := T.convert({"year": 2024, "month": 2, "day": 30, "hour": 0, "minute": 0, "second": 0.0})
	assert_false(bool(r2["ok"]), "2 月 30 日应拒绝")
	var r3 := T.convert({"year": 2024, "month": 6, "day": 21, "hour": 25, "minute": 0, "second": 0.0})
	assert_false(bool(r3["ok"]), "小时 25 应拒绝")
	var r4 := T.gps_week_sow(2444244.0)
	assert_true((r4 as Dictionary).is_empty(), "GPS 纪元前无周号（返回空字典）")
