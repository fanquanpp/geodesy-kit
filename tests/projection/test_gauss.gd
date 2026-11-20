# tests/projection/test_gauss.gd —— M3-1 高斯-克吕格正反算回归
#
# 向量来源【权威·pyproj 3.8.0 复核】（本会话以 EPSG:4490→4548 / 4214→21460 / 4610→2384 变换逐条复核）：
#   - CGCS2000 3°带 CM117：(30,117)→(3320113.3978,500000.0000)；(32.5,118.25)→(3597986.6234,617474.9201)；
#     天安门(39.9075,116.3913)→(4419435.7897,447950.5147)；
#   - 北京54 EPSG:21460（6° CM 117E，自然 y）天安门→(4419517.0313,447947.5867)；
#     西安80 EPSG:2384（3° CM 117E，自然 y）→(4419440.9298,447948.4332)。
#     注：这两条向量与 CGCS2000 天安门同点位不同基准，输入坐标经向量反解得到
#     (39.9075275988,116.3912757005)，pyproj 回代残差 0.000000（向量本身数值权威）。
#   - 反算：(3597986.6234,617474.9201)→(32.5°,118.25°)。
#   - 子午线弧长 X(30°)=3320113.3978 m（=中央子午线上正算 x，pyproj 同点）。
# 容差：坐标 0.5 mm（自编级数与 pyproj 实测差 ≤0.015 mm，留足余量）。
extends "res://tests/test_case_base.gd"

const GK := preload("res://core/projection/gauss_kruger.gd")
const EL := preload("res://core/ellipsoid/ellipsoid.gd")

func _v(res: Dictionary) -> Dictionary:
	return res.get("value", {}) if res.get("ok", false) else {}

func test_forward_authoritative_vectors() -> void:
	# (30°,117°) 中央子午线上：x=子午线弧长，y=FE
	var r := GK.forward({"lat_deg": 30.0, "lon_deg": 117.0, "l0_deg": 117.0, "datum": "CGCS2000"})
	assert_true(bool(r.get("ok", false)), "正算 (30,117) 应成功：" + String(r.get("error", "")))
	var v: Dictionary = _v(r)
	assert_almost_eq(float(v.get("x_m", 0.0)), 3320113.3978, 0.0005, "(30,117) x")
	assert_almost_eq(float(v.get("y_m", 0.0)), 500000.0, 0.0005, "(30,117) y")
	# (32.5°,118.25°)
	r = GK.forward({"lat_deg": 32.5, "lon_deg": 118.25, "l0_deg": 117.0, "datum": "CGCS2000"})
	v = _v(r)
	assert_true(bool(r.get("ok", false)), "正算 (32.5,118.25) 应成功")
	assert_almost_eq(float(v.get("x_m", 0.0)), 3597986.6234, 0.0005, "(32.5,118.25) x")
	assert_almost_eq(float(v.get("y_m", 0.0)), 617474.9201, 0.0005, "(32.5,118.25) y")
	# 天安门 (39.9075,116.3913)
	r = GK.forward({"lat_deg": 39.9075, "lon_deg": 116.3913, "l0_deg": 117.0, "datum": "CGCS2000"})
	v = _v(r)
	assert_true(bool(r.get("ok", false)), "正算 天安门(CGCS2000) 应成功")
	assert_almost_eq(float(v.get("x_m", 0.0)), 4419435.7897, 0.0005, "天安门 x")
	assert_almost_eq(float(v.get("y_m", 0.0)), 447950.5147, 0.0005, "天安门 y")

func test_forward_datums_5480_2384() -> void:
	# 北京54 EPSG:21460（6° CM 117E，Krassovsky 椭球）
	var r := GK.forward({"lat_deg": 39.9075275988, "lon_deg": 116.3912757005, "l0_deg": 117.0, "datum": "北京54"})
	assert_true(bool(r.get("ok", false)), "北京54 正算应成功：" + String(r.get("error", "")))
	var v: Dictionary = _v(r)
	assert_almost_eq(float(v.get("x_m", 0.0)), 4419517.0313, 0.0005, "北京54 天安门 x")
	assert_almost_eq(float(v.get("y_m", 0.0)), 447947.5867, 0.0005, "北京54 天安门 y")
	# 西安80 EPSG:2384（3° CM 117E，IUGG75 椭球）
	r = GK.forward({"lat_deg": 39.9075275988, "lon_deg": 116.3912757005, "l0_deg": 117.0, "datum": "西安80"})
	v = _v(r)
	assert_true(bool(r.get("ok", false)), "西安80 正算应成功：" + String(r.get("error", "")))
	assert_almost_eq(float(v.get("x_m", 0.0)), 4419440.9298, 0.0005, "西安80 天安门 x")
	assert_almost_eq(float(v.get("y_m", 0.0)), 447948.4332, 0.0005, "西安80 天安门 y")

func test_inverse_authoritative_vector() -> void:
	var r := GK.inverse({"x_m": 3597986.6234, "y_m": 617474.9201, "l0_deg": 117.0, "datum": "CGCS2000"})
	assert_true(bool(r.get("ok", false)), "反算应成功：" + String(r.get("error", "")))
	var v: Dictionary = _v(r)
	assert_almost_eq(float(v.get("lat_deg", 0.0)), 32.5, 5e-9, "反算 B")
	assert_almost_eq(float(v.get("lon_deg", 0.0)), 118.25, 5e-9, "反算 L")
	# 天安门反算
	r = GK.inverse({"x_m": 4419435.7897, "y_m": 447950.5147, "l0_deg": 117.0, "datum": "CGCS2000"})
	v = _v(r)
	assert_almost_eq(float(v.get("lat_deg", 0.0)), 39.9075, 5e-9, "天安门反算 B")
	assert_almost_eq(float(v.get("lon_deg", 0.0)), 116.3913, 5e-9, "天安门反算 L")
	# 度分秒文本输出
	assert_true(String(v.get("lat_dms", "")).begins_with("39°54′"), "反算带度分秒文本：" + String(v.get("lat_dms", "")))

func test_meridian_arc_matches_on_cm_vector() -> void:
	# 中央子午线上 k0=1 时 x = X(B)：pyproj (30,117) x=3320113.3978
	var ell: Dictionary = EL.params("CGCS2000")
	var x := GK.meridian_arc(30.0 * PI / 180.0, float(ell["a"]), float(ell["e2"]))
	assert_almost_eq(x, 3320113.3978, 0.0005, "子午线弧长 X(30°)")
	var x2 := GK.meridian_arc(32.5 * PI / 180.0, float(ell["a"]), float(ell["e2"]))
	assert_almost_eq(x2, 3597298.0326, 0.0005, "子午线弧长 X(32.5°)")

func test_roundtrip_and_k0_fe_fn() -> void:
	# k0/FE/FN 可配：UTM 参数下的正算（pyproj EPSG:32619 全精度）
	var r := GK.forward({"lat_deg": 43.642556, "lon_deg": -70.252228, "l0_deg": -69.0,
			"datum": "WGS84", "k0": 0.9996, "fe_m": 500000.0, "fn_m": 0.0})
	var v: Dictionary = _v(r)
	assert_true(bool(r.get("ok", false)), "k0=0.9996 正算应成功：" + String(r.get("error", "")))
	assert_almost_eq(float(v.get("x_m", 0.0)), 4832935.3412, 0.0005, "UTM 参数 N")
	assert_almost_eq(float(v.get("y_m", 0.0)), 399002.5708, 0.0005, "UTM 参数 E")
	# 正反往返（多点、含南半球）
	var pts := [[32.5, 118.25, 117.0, "CGCS2000"], [39.9075, 116.3913, 117.0, "CGCS2000"],
			[-33.8678, 151.2073, 153.0, "WGS84"], [5.0, 114.6, 114.0, "CGCS2000"], [80.0, 114.1, 114.0, "CGCS2000"]]
	for pt: Array in pts:
		var lat := float(pt[0])
		var lon := float(pt[1])
		var l0 := float(pt[2])
		var f1 := GK.forward({"lat_deg": lat, "lon_deg": lon, "l0_deg": l0, "datum": String(pt[3])})
		var fv: Dictionary = _v(f1)
		assert_true(bool(f1.get("ok", false)), "往返正算应成功 %s" % str(pt))
		var i1 := GK.inverse({"x_m": fv.get("x_m", 0.0), "y_m": fv.get("y_m", 0.0), "l0_deg": l0,
				"datum": String(pt[3])})
		var iv: Dictionary = _v(i1)
		assert_true(bool(i1.get("ok", false)), "往返反算应成功 %s" % str(pt))
		assert_almost_eq(float(iv.get("lat_deg", 0.0)), lat, 5e-9, "往返恢复 B %s" % str(pt))
		assert_almost_eq(float(iv.get("lon_deg", 0.0)), lon, 5e-9, "往返恢复 L %s" % str(pt))

func test_protocol_shape_and_dms_input() -> void:
	# 步骤协议：{title, formula, substitution, result} 四字段
	var r := GK.forward({"lat_deg": 32.5, "lon_deg": 118.25, "l0_deg": 117.0})
	var steps: Array = r.get("steps", [])
	assert_true(steps.size() >= 3, "正算步骤数")
	for st: Dictionary in steps:
		assert_true(st.has("title") and st.has("formula") and st.has("substitution") and st.has("result"),
				"步骤四字段齐备")
	assert_true(String(r.get("formula", "")).contains("高斯"), "formula 说明算法")
	# 度分秒输入
	var r2 := GK.forward({"lat_dms": "32°30′00″", "lon_dms": "118°15′00″", "l0_deg": 117.0})
	assert_true(bool(r2.get("ok", false)), "度分秒输入应成功：" + String(r2.get("error", "")))
	assert_almost_eq(float(_v(r2).get("x_m", 0.0)), 3597986.6234, 0.0005, "DMS 输入与十进制一致")

func test_error_paths() -> void:
	# 距中央子午线过远（>6°）
	var r := GK.forward({"lat_deg": 32.5, "lon_deg": 125.0, "l0_deg": 117.0})
	assert_false(bool(r.get("ok", true)), "l 超 6° 应失败")
	assert_true(String(r.get("error", "")).length() > 0, "中文错误提示")
	assert_true((r.get("value", {}) as Dictionary).is_empty(), "失败时 value 为空")
	# 非法数字
	r = GK.forward({"lat_deg": "abc", "lon_deg": 117.0, "l0_deg": 117.0})
	assert_false(bool(r.get("ok", true)), "非法纬度应失败")
	r = GK.inverse({"x_m": "xyz", "y_m": 500000.0, "l0_deg": 117.0})
	assert_false(bool(r.get("ok", true)), "非法 x 应失败")
	# 未知基准
	r = GK.forward({"lat_deg": 32.5, "lon_deg": 118.0, "l0_deg": 117.0, "datum": "不存在"})
	assert_false(bool(r.get("ok", true)), "未知基准应失败")
	assert_true(String(r.get("error", "")).contains("椭球"), "未知基准提示可用椭球")
	# 反算 y 过远
	r = GK.inverse({"x_m": 3597986.0, "y_m": 1500000.0, "l0_deg": 117.0})
	assert_false(bool(r.get("ok", true)), "y 偏离过远应失败")
