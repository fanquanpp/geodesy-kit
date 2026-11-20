# tests/astro/test_magdecl.gd —— GK-M8-3（F5）WMM 磁偏角
# 向量来源：NOAA/NGA 官方 WMM2025_TestValues.txt（随 WMM2025COF.zip 发布，公共领域，
# 本会话从 ncei.noaa.gov 下载）。原架构"SKIP-WMM-DATA"占位在落地补后升级为正式断言：
# 本实现与官方 100 行测试值全部吻合（D/I ≤0.005°，H/F ≤2 nT），此处断言 6 个代表行。
# 系数：data/wmm.json（转录自官方 WMM.COF，已程序化字节级校验）。
extends "res://tests/test_case_base.gd"

const M := preload("res://core/astro/magdecl.gd")

var _coeffs: Dictionary = {}

func _coeffs_loaded() -> bool:
	if not _coeffs.is_empty():
		return true
	if not FileAccess.file_exists("res://data/wmm.json"):
		return false
	var f := FileAccess.open("res://data/wmm.json", FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_coeffs = parsed
		return true
	return false

func _row(decyear: float, alt_km: float, lat: float, lon: float) -> Dictionary:
	return {"coeffs": _coeffs, "decyear": decyear, "alt_km": alt_km, "lat_deg": lat, "lon_deg": lon}

func test_official_rows_2025() -> void:
	assert_true(_coeffs_loaded(), "data/wmm.json 应可加载")
	if not _coeffs_loaded():
		return
	# 官方测试值行（decyear, alt km, lat, lon, D, I, H, F）——WMM2025_TestValues.txt 原文
	var rows := [
		[2025.0, 28.0, 89.0, -121.0, -99.77, 88.47, 1504.298146, 56214.419888],
		[2025.0, 48.0, 80.0, -96.0, -29.91, 87.77, 2164.285547, 55665.134163],
		[2025.0, 54.0, 82.0, 87.0, 54.89, 87.68, 2302.427342, 56787.466800],
		[2025.0, 65.0, 43.0, 93.0, 0.50, 64.10, 24300.764692, 55626.621348],
		[2025.0, 51.0, -33.0, 109.0, -5.49, -67.50, 21838.046477, 57054.752538],
		[2025.0, 3.0, -50.0, -103.0, 27.96, -54.89, 22106.041373, 38431.724126],
	]
	for row: Array in rows:
		var r := M.declination(_row(float(row[0]), float(row[1]), float(row[2]), float(row[3])))
		assert_true(r["ok"], "官方行 (%s) 应成功" % str(row.slice(0, 4)))
		if bool(r["ok"]):
			var v: Dictionary = r["value"]
			assert_almost_eq(float(v["decl_deg"]), float(row[4]), 0.01, "D 磁偏角（官方）")
			assert_almost_eq(float(v["incl_deg"]), float(row[5]), 0.01, "I 磁倾角（官方）")
			assert_almost_eq(float(v["h_nt"]), float(row[6]), 2.0, "H 水平强度（官方）")
			assert_almost_eq(float(v["f_nt"]), float(row[7]), 2.0, "F 总强度（官方）")

func test_official_rows_secular() -> void:
	# 年变率行：2025.5 与 2029.5（SV 内插路径）
	assert_true(_coeffs_loaded(), "系数应可加载")
	if not _coeffs_loaded():
		return
	var rows := [
		[2025.5, 6.0, -36.0, -137.0, 20.28, -52.11, 25353.230658, 41280.516301],
		[2025.5, 63.0, 26.0, 81.0, 0.51, 41.07, 34803.980117, 46166.554053],
		[2026.0, 34.0, -19.0, 43.0, -14.98, -52.33, 20212.447331, 33076.964235],
		[2029.5, 77.0, -18.0, 138.0, 4.45, -47.55, 31847.598742, 47186.017113],
	]
	for row: Array in rows:
		var r := M.declination(_row(float(row[0]), float(row[1]), float(row[2]), float(row[3])))
		assert_true(r["ok"], "SV 行 (%s) 应成功" % str(row.slice(0, 4)))
		if bool(r["ok"]):
			var v: Dictionary = r["value"]
			assert_almost_eq(float(v["decl_deg"]), float(row[4]), 0.01, "D（官方 SV 行）")
			assert_almost_eq(float(v["incl_deg"]), float(row[5]), 0.01, "I（官方 SV 行）")
			assert_almost_eq(float(v["f_nt"]), float(row[7]), 2.0, "F（官方 SV 行）")

func test_beijing_west_declination() -> void:
	# 物理常识：2026 年北京磁偏角约 −7°（西偏）
	assert_true(_coeffs_loaded(), "系数应可加载")
	if not _coeffs_loaded():
		return
	var r := M.declination({"coeffs": _coeffs, "decyear": 2026.0, "alt_km": 0.0,
			"lat_deg": 39.9075276, "lon_deg": 116.3912757})
	assert_true(r["ok"], "北京算例应成功")
	if bool(r["ok"]):
		var d := float(r["value"]["decl_deg"])
		assert_between(d, -9.0, -6.0, "北京磁偏角约 −7°（西偏）")
		assert_true(float(r["value"]["f_nt"]) > 45000.0 and float(r["value"]["f_nt"]) < 60000.0, "总强度量级合理")

func test_date_input_and_warning() -> void:
	assert_true(_coeffs_loaded(), "系数应可加载")
	if not _coeffs_loaded():
		return
	# 年月日输入路径（decyear 换算）
	var r := M.declination({"coeffs": _coeffs, "year": 2025, "month": 7, "day": 2, "lat_deg": 39.9, "lon_deg": 116.4})
	assert_true(r["ok"], "日期输入应成功")
	if bool(r["ok"]):
		assert_almost_eq(float(r["value"]["decyear"]), 2025.0 + 182.0 / 365.0, 1e-6, "十进制年换算（2025 平年，7 月 2 日为年内第 183 天）")
	# 超出有效期 → 警告键
	var r2 := M.declination({"coeffs": _coeffs, "decyear": 2035.0, "lat_deg": 0.0, "lon_deg": 0.0})
	assert_true(r2["ok"], "超期仍可计算（教学口径）")
	if bool(r2["ok"]):
		assert_true(String(r2["value"].get("warning", "")).length() > 0, "超期带中文警告")
	# 有效期内无警告
	var r3 := M.declination({"coeffs": _coeffs, "decyear": 2027.0, "lat_deg": 0.0, "lon_deg": 0.0})
	if bool(r3["ok"]):
		assert_false(r3["value"].has("warning"), "有效期内无警告")

func test_decyear_helper() -> void:
	assert_almost_eq(M.decyear_from_date(2025, 1, 1), 2025.0, 1e-9, "年初")
	assert_almost_eq(M.decyear_from_date(2024, 12, 31), 2024.0 + 365.0 / 366.0, 1e-9, "闰年年末")
	assert_true(is_nan(M.decyear_from_date(2024, 2, 30)), "非法日期返回 NAN")

func test_invalid_inputs() -> void:
	var r1 := M.declination({"lat_deg": 40.0, "lon_deg": 116.0, "decyear": 2025.0})
	assert_false(bool(r1["ok"]), "无系数应拒绝")
	var r2 := M.declination({"coeffs": {"epoch": 2025.0, "n_max": 12}, "lat_deg": 40.0, "lon_deg": 116.0, "decyear": 2025.0})
	assert_false(bool(r2["ok"]), "系数数组缺失应拒绝")
	var r3 := M.declination({"coeffs": _coeffs, "lat_deg": 95.0, "lon_deg": 116.0, "decyear": 2025.0})
	assert_false(bool(r3["ok"]), "纬度 95 应拒绝")
	var r4 := M.declination({"coeffs": _coeffs, "year": 2024, "month": 2, "day": 30, "lat_deg": 40.0, "lon_deg": 116.0})
	assert_false(bool(r4["ok"]), "非法日期应拒绝")
	for r: Dictionary in [r1, r2, r3, r4]:
		assert_true(String(r["error"]).length() > 0, "失败必带中文错误")
		assert_true((r["value"] as Dictionary).is_empty(), "失败时 value 为空")
