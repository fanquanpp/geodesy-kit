# tests/projection/test_utm_ups.gd —— M3-3 UTM（A7）与 M3-4 UPS 回归
#
# 向量来源：
#   -【权威·DMA TM 8358.2 Table 2-11 ID1】UTM zone38 International 椭球 73°N/45°E→E=500000.00,
#     N=8100702.90（表列 2 位小数；本会话 pyproj 复核 =8100702.8967，容差 5mm 覆盖表尾舍入）；
#   -【权威·pyproj 全精度】19N (43.642556,-70.252228)→(399002.5708,4832935.3412)；
#   -【权威·pyproj】56S 悉尼 (−33.8678,151.2073)→(334181.6857,6251056.0164)；
#   -【权威·pyproj EPSG:5041/5042】UPS 北 (85,30)→(2277728.6957,1518959.7883)；
#     UPS 南 (−85,30)→(2277728.6957,2481040.2117)。
extends "res://tests/test_case_base.gd"

const UT := preload("res://core/projection/utm.gd")
const UP := preload("res://core/projection/ups.gd")

func _v(res: Dictionary) -> Dictionary:
	return res.get("value", {}) if res.get("ok", false) else {}

func test_utm_forward_19n_full_precision() -> void:
	var r := UT.forward({"lat_deg": 43.642556, "lon_deg": -70.252228, "datum": "WGS84"})
	assert_true(bool(r.get("ok", false)), "UTM 19N 正算：" + String(r.get("error", "")))
	var v: Dictionary = _v(r)
	assert_int_eq(int(v["zone"]), 19, "自动带号 19")
	assert_almost_eq(float(v["e_m"]), 399002.5708, 0.0005, "E")
	assert_almost_eq(float(v["n_m"]), 4832935.3412, 0.0005, "N")
	assert_eq(String(v["hemisphere"]), "N", "北半球")

func test_utm_forward_56s_sydney() -> void:
	var r := UT.forward({"lat_deg": -33.8678, "lon_deg": 151.2073, "datum": "WGS84"})
	var v: Dictionary = _v(r)
	assert_true(bool(r.get("ok", false)), "UTM 56S 正算：" + String(r.get("error", "")))
	assert_int_eq(int(v["zone"]), 56, "自动带号 56")
	assert_almost_eq(float(v["e_m"]), 334181.6857, 0.0005, "悉尼 E")
	assert_almost_eq(float(v["n_m"]), 6251056.0164, 0.0005, "悉尼 N（含 FN=10^7）")
	assert_eq(String(v["hemisphere"]), "S", "南半球")
	assert_almost_eq(float(v["fn_m"]), 10000000.0, 1e-6, "南半球 FN=10,000,000")

func test_utm_dma_table_2_11_id1() -> void:
	# International 1924 椭球，zone 38：73°N/45°E 在中央子午线上
	var r := UT.forward({"lat_deg": 73.0, "lon_deg": 45.0, "zone": 38, "datum": "INTERNATIONAL1924"})
	assert_true(bool(r.get("ok", false)), "TM8358.2 ID1 正算：" + String(r.get("error", "")))
	var v: Dictionary = _v(r)
	assert_almost_eq(float(v["e_m"]), 500000.0, 0.005, "ID1 E=500000.00")
	# DMA 表列 N=8100702.90（2 位小数）；pyproj=8100702.8967
	assert_almost_eq(float(v["n_m"]), 8100702.90, 0.005, "ID1 N（表值 2 位小数）")
	assert_almost_eq(float(v["l0_deg"]), 45.0, 1e-12, "zone38 CM=45")

func test_utm_zone_rules_and_exceptions() -> void:
	assert_int_eq(UT.zone_from_lon(117.0), 50, "117E→50")
	assert_int_eq(UT.zone_from_lon(-70.252228), 19, "70.25W→19")
	assert_int_eq(UT.zone_from_lon(-180.0), 1, "180W→1")
	assert_int_eq(UT.zone_from_lon(180.0), 60, "180E→60")
	# 挪威 32V
	assert_int_eq(UT.standard_zone(60.0, 5.0), 32, "挪威 (60,5)→32")
	assert_int_eq(UT.standard_zone(56.0, 3.0), 32, "挪威边界 (56,3)→32")
	assert_int_eq(UT.standard_zone(56.0, 2.999), 31, "挪威西界 (56,2.999)→31")
	assert_int_eq(UT.standard_zone(64.0, 12.0), 33, "挪威东界 (64,12)→33")
	# 斯瓦尔巴
	assert_int_eq(UT.standard_zone(72.0, 0.001), 31, "斯瓦尔巴 (72,0)→31")
	assert_int_eq(UT.standard_zone(78.0, 15.0), 33, "斯瓦尔巴 (78,15)→33")
	assert_int_eq(UT.standard_zone(72.0, 21.0), 35, "斯瓦尔巴 (72,21)→35")
	assert_int_eq(UT.standard_zone(72.0, 33.0), 37, "斯瓦尔巴 (72,33)→37")
	assert_int_eq(UT.standard_zone(83.9, 15.0), 33, "斯瓦尔巴上界内 (83.9,15)→33")
	assert_int_eq(UT.standard_zone(73.0, 45.0), 38, "非例外区 (73,45)→38")

func test_utm_inverse() -> void:
	var r := UT.inverse({"zone": 19, "hemisphere": "N", "e_m": 399002.5708, "n_m": 4832935.3412, "datum": "WGS84"})
	assert_true(bool(r.get("ok", false)), "UTM 反算：" + String(r.get("error", "")))
	var v: Dictionary = _v(r)
	assert_almost_eq(float(v["lat_deg"]), 43.642556, 5e-9, "反算 B")
	assert_almost_eq(float(v["lon_deg"]), -70.252228, 5e-9, "反算 L")
	# 南半球反算
	r = UT.inverse({"zone": 56, "hemisphere": "南", "e_m": 334181.6857, "n_m": 6251056.0164, "datum": "WGS84"})
	v = _v(r)
	assert_true(bool(r.get("ok", false)), "南半球反算：" + String(r.get("error", "")))
	assert_almost_eq(float(v["lat_deg"]), -33.8678, 5e-9, "反算 B（南）")
	assert_almost_eq(float(v["lon_deg"]), 151.2073, 5e-9, "反算 L（南）")

func test_utm_errors() -> void:
	assert_false(bool(UT.forward({"lat_deg": 85.0, "lon_deg": 30.0}).get("ok", true)), "B≥84 应提示改 UPS")
	assert_true(String(UT.forward({"lat_deg": 85.0, "lon_deg": 30.0}).get("error", "")).contains("UPS"), "提示改用 UPS")
	assert_false(bool(UT.forward({"lat_deg": 40.0, "lon_deg": 100.0, "zone": 61}).get("ok", true)), "带号 61 非法")
	assert_false(bool(UT.inverse({"zone": 19, "e_m": 500000.0, "n_m": 5000000.0}).get("ok", true)), "缺半球应失败")
	assert_false(bool(UT.forward({"lat_deg": "abc", "lon_deg": 100.0}).get("ok", true)), "非法纬度")

func test_ups_authoritative_vectors() -> void:
	var r := UP.forward({"lat_deg": 85.0, "lon_deg": 30.0, "datum": "WGS84"})
	assert_true(bool(r.get("ok", false)), "UPS 北正算：" + String(r.get("error", "")))
	var v: Dictionary = _v(r)
	assert_almost_eq(float(v["e_m"]), 2277728.6957, 0.0005, "UPS 北 E（EPSG:5041）")
	assert_almost_eq(float(v["n_m"]), 1518959.7883, 0.0005, "UPS 北 N")
	assert_eq(String(v["hemisphere"]), "N", "自动判北")
	r = UP.forward({"lat_deg": -85.0, "lon_deg": 30.0, "datum": "WGS84"})
	v = _v(r)
	assert_true(bool(r.get("ok", false)), "UPS 南正算：" + String(r.get("error", "")))
	assert_almost_eq(float(v["e_m"]), 2277728.6957, 0.0005, "UPS 南 E（EPSG:5042）")
	assert_almost_eq(float(v["n_m"]), 2481040.2117, 0.0005, "UPS 南 N")
	assert_eq(String(v["hemisphere"]), "S", "自动判南")

func test_ups_inverse_and_pole() -> void:
	var r := UP.inverse({"e_m": 2277728.6957, "n_m": 1518959.7883, "datum": "WGS84"})
	assert_true(bool(r.get("ok", false)), "UPS 北反算：" + String(r.get("error", "")))
	var v: Dictionary = _v(r)
	assert_almost_eq(float(v["lat_deg"]), 85.0, 1e-9, "UPS 反算 B")
	assert_almost_eq(float(v["lon_deg"]), 30.0, 1e-7, "UPS 反算 L（向量 4 位小数舍入）")
	# 南极点：E=N=2,000,000 → (-90, 0)（经度约定 0）
	r = UP.inverse({"e_m": 2000000.0, "n_m": 2000000.0, "hemisphere": "S", "datum": "WGS84"})
	v = _v(r)
	assert_true(bool(r.get("ok", false)), "极点反算：" + String(r.get("error", "")))
	assert_almost_eq(float(v["lat_deg"]), -90.0, 1e-9, "南极点 B")
	# 极点正算
	r = UP.forward({"lat_deg": 90.0, "lon_deg": 0.0, "datum": "WGS84"})
	v = _v(r)
	assert_true(bool(r.get("ok", false)), "北极点正算：" + String(r.get("error", "")))
	assert_almost_eq(float(v["e_m"]), 2000000.0, 1e-6, "北极点 E=FE")
	assert_almost_eq(float(v["n_m"]), 2000000.0, 1e-6, "北极点 N=FN")

func test_ups_domain_errors() -> void:
	assert_false(bool(UP.forward({"lat_deg": 83.0, "lon_deg": 30.0}).get("ok", true)), "B<84 北域外应失败")
	assert_false(bool(UP.forward({"lat_deg": -79.0, "lon_deg": 30.0}).get("ok", true)), "B>-80 南域外应失败")
	assert_false(bool(UP.forward({"lat_deg": "abc", "lon_deg": 30.0}).get("ok", true)), "非法输入")
	# 域内正反往返
	for pt: Array in [[86.0, 120.0], [89.0, -170.0], [-85.0, -60.0], [-89.5, 170.0]]:
		var f := UP.forward({"lat_deg": float(pt[0]), "lon_deg": float(pt[1]), "datum": "WGS84"})
		var fv: Dictionary = _v(f)
		assert_true(bool(f.get("ok", false)), "UPS 往返正算 %s" % str(pt))
		var hemi := "N" if float(pt[0]) > 0.0 else "S"
		var i := UP.inverse({"e_m": fv["e_m"], "n_m": fv["n_m"], "hemisphere": hemi, "datum": "WGS84"})
		var iv: Dictionary = _v(i)
		assert_almost_eq(float(iv["lat_deg"]), float(pt[0]), 1e-9, "UPS 往返 B %s" % str(pt))
		assert_almost_eq(float(iv["lon_deg"]), float(pt[1]), 1e-9, "UPS 往返 L %s" % str(pt))
