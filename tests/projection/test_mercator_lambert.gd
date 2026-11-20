# tests/projection/test_mercator_lambert.gd —— M3-5 Web 墨卡托（A14）与兰勃特等角圆锥（A14）回归
#
# 向量来源【权威·pyproj】：
#   - EPSG:3857 天安门 (39.9075276,116.3912757)→(12956617.544,4852513.528)
#     （输入坐标按 EPSG:3857 定义自向量反解，pyproj 回代逐位一致）；
#   - EPSG:2154 Lambert-93 巴黎 (48.85,2.35)→(652301.565,6861302.726)；
#   - EPSG 9801（1SP）+proj=lcc lat_0=lat_1=30 lon_0=105 GRS80：(35,110)→(458061.2645,565185.4693)。
extends "res://tests/test_case_base.gd"

const MC := preload("res://core/projection/mercator.gd")
const LB := preload("res://core/projection/lambert.gd")

func _v(res: Dictionary) -> Dictionary:
	return res.get("value", {}) if res.get("ok", false) else {}

func test_web_mercator_forward_vector() -> void:
	var r := MC.forward({"lat_deg": 39.9075276, "lon_deg": 116.3912757})
	assert_true(bool(r.get("ok", false)), "Web 墨卡托正算：" + String(r.get("error", "")))
	var v: Dictionary = _v(r)
	assert_almost_eq(float(v["x_m"]), 12956617.544, 0.0005, "3857 x")
	assert_almost_eq(float(v["y_m"]), 4852513.528, 0.0005, "3857 y")
	assert_int_eq(int(v["epsg"]), 3857, "EPSG 码")

func test_web_mercator_inverse_and_roundtrip() -> void:
	var r := MC.inverse({"x_m": 12956617.544, "y_m": 4852513.528})
	assert_true(bool(r.get("ok", false)), "Web 墨卡托反算：" + String(r.get("error", "")))
	var v: Dictionary = _v(r)
	assert_almost_eq(float(v["lat_deg"]), 39.9075276, 1e-8, "反算 B")
	assert_almost_eq(float(v["lon_deg"]), 116.3912757, 1e-8, "反算 L")
	# 赤道点：x=a·rad(L)，y=0
	r = MC.forward({"lat_deg": 0.0, "lon_deg": 90.0})
	v = _v(r)
	assert_almost_eq(float(v["x_m"]), 6378137.0 * PI / 2.0, 1e-6, "赤道 90E x=a·π/2")
	assert_almost_eq(float(v["y_m"]), 0.0, 1e-6, "赤道 y=0")

func test_web_mercator_domain_error() -> void:
	var r := MC.forward({"lat_deg": 85.2, "lon_deg": 100.0})
	assert_false(bool(r.get("ok", true)), "B 超 85.06° 应失败")
	assert_true(String(r.get("error", "")).contains("适用域"), "中文域提示")
	assert_false(bool(MC.forward({"lat_deg": "abc", "lon_deg": 0.0}).get("ok", true)), "非法输入")

func test_lambert_93_vector() -> void:
	var r := LB.forward({"lat_deg": 48.85, "lon_deg": 2.35, "phi1_deg": 49.0, "phi2_deg": 44.0,
			"phi0_deg": 46.5, "lon0_deg": 3.0, "fe_m": 700000.0, "fn_m": 6600000.0, "datum": "GRS80"})
	assert_true(bool(r.get("ok", false)), "Lambert-93 正算：" + String(r.get("error", "")))
	var v: Dictionary = _v(r)
	assert_almost_eq(float(v["x_m"]), 652301.565, 0.0005, "Lambert-93 x")
	assert_almost_eq(float(v["y_m"]), 6861302.726, 0.0005, "Lambert-93 y")
	assert_eq(String(v["mode"]), "2SP", "2SP 模式")
	# 用预设一键计算（EPSG:2154 官方参数）
	var r2 := LB.forward({"lat_deg": 48.85, "lon_deg": 2.35, "preset": "Lambert-93"})
	assert_true(bool(r2.get("ok", false)), "预设正算：" + String(r2.get("error", "")))
	var v2: Dictionary = _v(r2)
	assert_almost_eq(float(v2["x_m"]), 652301.565, 0.0005, "预设 x")
	assert_almost_eq(float(v2["y_m"]), 6861302.726, 0.0005, "预设 y")

func test_lambert_1sp_vector() -> void:
	# pyproj "+proj=lcc +lat_0=30 +lat_1=30 +lon_0=105 +ellps=GRS80"（n=sin30°）
	var r := LB.forward({"lat_deg": 35.0, "lon_deg": 110.0, "phi1_deg": 30.0,
			"phi0_deg": 30.0, "lon0_deg": 105.0, "fe_m": 0.0, "fn_m": 0.0, "datum": "GRS80"})
	assert_true(bool(r.get("ok", false)), "Lambert 1SP 正算：" + String(r.get("error", "")))
	var v: Dictionary = _v(r)
	assert_almost_eq(float(v["x_m"]), 458061.2645, 0.0005, "1SP x")
	assert_almost_eq(float(v["y_m"]), 565185.4693, 0.0005, "1SP y")
	assert_eq(String(v["mode"]), "1SP", "1SP 模式")

func test_lambert_inverse_and_roundtrip() -> void:
	var r := LB.inverse({"x_m": 652301.565, "y_m": 6861302.726, "phi1_deg": 49.0, "phi2_deg": 44.0,
			"phi0_deg": 46.5, "lon0_deg": 3.0, "fe_m": 700000.0, "fn_m": 6600000.0, "datum": "GRS80"})
	assert_true(bool(r.get("ok", false)), "Lambert 反算：" + String(r.get("error", "")))
	var v: Dictionary = _v(r)
	assert_almost_eq(float(v["lat_deg"]), 48.85, 1e-9, "反算 B")
	assert_almost_eq(float(v["lon_deg"]), 2.35, 5e-9, "反算 L")
	# 随机往返
	var pts := [[44.0, 1.0], [50.5, 8.5], [41.5, -4.0], [46.5, 3.0]]
	for pt: Array in pts:
		var f := LB.forward({"lat_deg": float(pt[0]), "lon_deg": float(pt[1]),
				"phi1_deg": 49.0, "phi2_deg": 44.0, "phi0_deg": 46.5, "lon0_deg": 3.0,
				"fe_m": 700000.0, "fn_m": 6600000.0, "datum": "GRS80"})
		var fv: Dictionary = _v(f)
		assert_true(bool(f.get("ok", false)), "往返正算 %s" % str(pt))
		var i := LB.inverse({"x_m": fv["x_m"], "y_m": fv["y_m"], "phi1_deg": 49.0, "phi2_deg": 44.0,
				"phi0_deg": 46.5, "lon0_deg": 3.0, "fe_m": 700000.0, "fn_m": 6600000.0, "datum": "GRS80"})
		var iv: Dictionary = _v(i)
		assert_almost_eq(float(iv["lat_deg"]), float(pt[0]), 1e-9, "往返 B %s" % str(pt))
		assert_almost_eq(float(iv["lon_deg"]), float(pt[1]), 1e-9, "往返 L %s" % str(pt))

func test_lambert_errors() -> void:
	# 2SP 两标准纬线相同 → 非法
	assert_false(bool(LB.forward({"lat_deg": 45.0, "lon_deg": 2.0, "phi1_deg": 44.0, "phi2_deg": 44.0,
			"phi0_deg": 46.5, "lon0_deg": 3.0, "fe_m": 700000.0, "fn_m": 6600000.0}).get("ok", true)),
			"φ1=φ2 应失败")
	# 缺参数
	assert_false(bool(LB.forward({"lat_deg": 45.0, "lon_deg": 2.0}).get("ok", true)), "缺标准纬线应失败")
	# 非法纬度
	assert_false(bool(LB.forward({"lat_deg": 95.0, "lon_deg": 2.0, "phi1_deg": 49.0, "phi2_deg": 44.0,
			"phi0_deg": 46.5, "lon0_deg": 3.0, "fe_m": 0.0, "fn_m": 0.0}).get("ok", true)), "|B|≥90 应失败")
	# 预设列表
	assert_true(LB.list_presets().has("Lambert-93"), "预设含 Lambert-93")
