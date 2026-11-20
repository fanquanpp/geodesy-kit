# tests/ellipsoid/test_rhumb.gd —— A12 恒向线（等角航线）向量回归
#
# 向量来源【构造·_scripts/gen_vectors_b.py:79-91，本会话逐字复跑一致】：
#   北京(39.9075276°,116.3912757°) → 上海(31.1666667°,121.4666667°)：
#   d = 1074590.1 m，az = 154.7528°（R1 = 6371008.7714 m = (2a+b)/3）。
# 口径（与向量生成器一致）：ψ = ln tan(π/4+φ/2)；az = atan2(Δλ, Δψ)；
# d = |Δφ|·R/|cos az|（球面严格式）；等纬退化 d = R·|Δλ|·cos φ。
# 反解为正解的精确逆：Δφ = δ·cos az；Δλ = Δψ·tan az（等纬时 Δλ = δ·sin az/cos φ₁）。
extends "res://tests/test_case_base.gd"

const RH := preload("res://core/ellipsoid/rhumb.gd")

const BJ := [39.9075276, 116.3912757]
const SH := [31.1666667, 121.4666667]

func test_bj_sh_authoritative() -> void:
	var r := RH.forward({"lat1_deg": BJ[0], "lon1_deg": BJ[1], "lat2_deg": SH[0], "lon2_deg": SH[1], "datum": "WGS84"})
	assert_true(bool(r.get("ok", false)), "恒向线正解应成功")
	var v: Dictionary = r.get("value", {})
	assert_almost_eq(float(v.get("distance_m", NAN)), 1074590.1, 0.05, "北京→上海恒向线距离")
	assert_almost_eq(float(v.get("azimuth_deg", NAN)), 154.7528, 5e-5, "北京→上海恒向线方位角")
	assert_almost_eq(float(v.get("radius_m", NAN)), 6371008.7714, 1e-3, "默认 R1=(2a+b)/3")

func test_forward_inverse_exact_recovery() -> void:
	# 反解是正解的精确逆（同一 R）
	var fwd := RH.forward({"lat1_deg": BJ[0], "lon1_deg": BJ[1], "lat2_deg": SH[0], "lon2_deg": SH[1], "datum": "WGS84"})
	var v: Dictionary = fwd["value"]
	var inv := RH.inverse({"lat1_deg": BJ[0], "lon1_deg": BJ[1],
			"az_deg": float(v["azimuth_deg"]), "distance_m": float(v["distance_m"]), "datum": "WGS84"})
	assert_true(bool(inv.get("ok", false)), "反解应成功")
	var iv: Dictionary = inv.get("value", {})
	assert_almost_eq(float(iv.get("lat2_deg", NAN)), SH[0], 1e-9, "反解恢复 B₂")
	assert_almost_eq(float(iv.get("lon2_deg", NAN)), SH[1], 1e-9, "反解恢复 L₂")

func test_due_east_parallel_sailing() -> void:
	# 赤道正东 10°：az=90°，d = R·Δλ
	var r := RH.forward({"lat1_deg": 0.0, "lon1_deg": 0.0, "lat2_deg": 0.0, "lon2_deg": 10.0, "datum": "WGS84"})
	var v: Dictionary = r["value"]
	assert_almost_eq(float(v["azimuth_deg"]), 90.0, 1e-9, "正东方位 90°")
	assert_almost_eq(float(v["distance_m"]), 6371008.77141506 * 10.0 * PI / 180.0, 0.1, "赤道正东 10° 距离")
	var inv := RH.inverse({"lat1_deg": 0.0, "lon1_deg": 0.0, "az_deg": 90.0, "distance_m": float(v["distance_m"]), "datum": "WGS84"})
	assert_almost_eq(float(inv["value"]["lon2_deg"]), 10.0, 1e-9, "正东反解恢复经度")
	# 40°N 平行圈正东：d = R·Δλ·cos(40°)
	var r2 := RH.forward({"lat1_deg": 40.0, "lon1_deg": 0.0, "lat2_deg": 40.0, "lon2_deg": 10.0, "datum": "WGS84"})
	assert_almost_eq(float(r2["value"]["distance_m"]), 6371008.77141506 * 10.0 * PI / 180.0 * cos(deg_to_rad(40.0)), 0.1, "40°N 平行圈正东距离")
	assert_almost_eq(float(r2["value"]["azimuth_deg"]), 90.0, 1e-9, "平行圈方位 90°")

func test_meridional_sailing() -> void:
	var r := RH.forward({"lat1_deg": 0.0, "lon1_deg": 0.0, "lat2_deg": 30.0, "lon2_deg": 0.0, "datum": "WGS84"})
	var v: Dictionary = r["value"]
	assert_almost_eq(float(v["azimuth_deg"]), 0.0, 1e-9, "正北方位 0°")
	assert_almost_eq(float(v["distance_m"]), 6371008.77141506 * 30.0 * PI / 180.0, 0.1, "正北 30° 距离 = R·Δφ")
	var inv := RH.inverse({"lat1_deg": 0.0, "lon1_deg": 0.0, "az_deg": 0.0, "distance_m": float(v["distance_m"]), "datum": "WGS84"})
	assert_almost_eq(float(inv["value"]["lat2_deg"]), 30.0, 1e-9, "正北反解恢复纬度")
	assert_almost_eq(float(inv["value"]["lon2_deg"]), 0.0, 1e-12, "正北反解经度不变")

func test_crossing_antimeridian() -> void:
	# 跨 180° 经线：170°E → 170°W 应走 +20° 而不是 −340°
	var r := RH.forward({"lat1_deg": 10.0, "lon1_deg": 170.0, "lat2_deg": 10.0, "lon2_deg": -170.0, "datum": "WGS84"})
	assert_almost_eq(float(r["value"]["azimuth_deg"]), 90.0, 1e-9, "跨 180° 走向正东")
	assert_almost_eq(float(r["value"]["distance_m"]), 6371008.77141506 * 20.0 * PI / 180.0 * cos(deg_to_rad(10.0)), 0.2, "跨 180° 距离按 +20°")

func test_same_point_degenerate() -> void:
	var r := RH.forward({"lat1_deg": 30.0, "lon1_deg": 120.0, "lat2_deg": 30.0, "lon2_deg": 120.0, "datum": "WGS84"})
	assert_almost_eq(float(r["value"]["distance_m"]), 0.0, 1e-9, "同点距离 0")

func test_protocol_shape_and_errors() -> void:
	var r := RH.forward({"lat1_deg": BJ[0], "lon1_deg": BJ[1], "lat2_deg": SH[0], "lon2_deg": SH[1], "datum": "WGS84"})
	assert_true(r.has("ok") and r.has("value") and r.has("steps") and r.has("formula") and r.has("error"), "§5 协议五键")
	assert_true(String(r.get("formula", "")).contains("Mercator"), "公式注明 Mercator 参数法")
	var e1 := RH.forward({"lat1_deg": 95.0, "lon1_deg": 0.0, "lat2_deg": 0.0, "lon2_deg": 0.0})
	assert_false(bool(e1.get("ok", true)), "纬度越界应失败")
	assert_false(String(e1.get("error", "")).is_empty(), "纬度越界中文错误")
	var e2 := RH.inverse({"lat1_deg": 0.0, "lon1_deg": 0.0, "az_deg": 0.0, "distance_m": -1.0})
	assert_false(bool(e2.get("ok", true)), "负距离应失败")
	var e3 := RH.inverse({"lat1_deg": 85.0, "lon1_deg": 0.0, "az_deg": 0.0, "distance_m": 1e9})
	assert_false(bool(e3.get("ok", true)), "到达极点外应失败并提示")
	var e4 := RH.forward({"lat1_deg": 0.0, "lon1_deg": 0.0, "lat2_deg": 1.0, "lon2_deg": 1.0, "datum": "不存在"})
	assert_false(bool(e4.get("ok", true)), "未知 datum 应失败")

func test_custom_radius_and_datum_params() -> void:
	# 自定义半径（球 R=1）便于人工核值：Δφ=30°，az=0 → d = 30π/180
	var r := RH.forward({"lat1_deg": 0.0, "lon1_deg": 0.0, "lat2_deg": 30.0, "lon2_deg": 0.0, "radius_m": 1.0})
	assert_almost_eq(float(r["value"]["distance_m"]), 30.0 * PI / 180.0, 1e-12, "单位球正北 30° 距离")
	# a/inv_f 传参
	var r2 := RH.forward({"lat1_deg": 0.0, "lon1_deg": 0.0, "lat2_deg": 0.0, "lon2_deg": 10.0, "a": 6378137.0, "inv_f": 298.257223563})
	assert_almost_eq(float(r2["value"]["radius_m"]), 6371008.77141506, 1e-3, "a/inv_f 传参取 R1")
