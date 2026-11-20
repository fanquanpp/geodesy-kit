# tests/ellipsoid/test_geodesic.gd —— A11 大地线正反解权威向量回归
#
# 向量来源【权威·GeodTest.dat，_research/GeodTest.dat（86,558,916 B，50 万行）本会话
# 0.0mm 复核；geographiclib C++ Geod 生成】：
#   行 12346：P1(3.881801761024°,0°) → P2(54.681996010438946554°,10.214487662352205081°)
#     azi1=7.571318148093° azi2=13.113872139673233629° s12=5707892.515197m
#     a12=51.400248712716941882°
#   行 168（近对跖）：(71.606214176302°,0°) → (−80.240756380896471977°,170.591260542729673958°)
#     azi1=169.717716110676° azi2=19.402427357239077616° s12=19009997.0303785m
#   行 150001（短边 76m）：(19.707097385334°,0°) → (19.707739582810256591°,.000260256428101053°)
#     azi1=20.996796804557° azi2=20.996884567489087848° s12=76.1478894m（文件仅 4 位小数，
#     故 s12 断言容差放宽到参考舍入 ±5e-5；m12 列全精度 76.1478893981816 按 1e-9 相对断言）
# 验收容差（任务口径）：s12 相对 1e-9、方位角绝对 1e-8°。
#
# 关于"近对跖收敛失败返回中文提示"：协议层已实现（inverse() 检查 converged/NaN，
# 失败返回中文 error）。本会话实测：Karney Newton+区间套在 WGS84 与极端扁率
# （f=±0.1~±0.99）下对近对跖用例均收敛（geographiclib 设计保证），无法构造确定性的
# 收敛失败用例；该守卫以行 168 的 converged=true 正向验证 + 越界输入负向验证。
extends "res://tests/test_case_base.gd"

const GEO := preload("res://core/ellipsoid/geodesic.gd")

## 角度差规范化到 (−180,180]（比较方位角用，容忍 359.9999999 vs −0.0000001）
func _ang_delta(a: float, b: float) -> float:
	var d := GKAngles.normalize_deg(a - b)
	if d > 180.0:
		d -= 360.0
	return d

func test_authoritative_row_12346() -> void:
	var g := GEO.wgs84()
	var v := g.inverse_v(3.881801761024, 0.0, 54.681996010438946554, 10.214487662352205081)
	assert_false(v.is_empty(), "行 12346 反解应有结果")
	assert_almost_eq(_ang_delta(float(v["azi1"]), 7.571318148093), 0.0, 1e-8, "行12346 azi1")
	assert_almost_eq(_ang_delta(float(v["azi2"]), 13.113872139673233629), 0.0, 1e-8, "行12346 azi2")
	assert_almost_eq(float(v["s12"]), 5707892.515197, 5707892.515197 * 1e-9, "行12346 s12（相对 1e-9）")
	assert_almost_eq(float(v["a12"]), 51.400248712716941882, 1e-8, "行12346 a12")
	assert_almost_eq(float(v["m12"]), 4973671.3709173875414, 4973671.3709173875414 * 1e-9, "行12346 m12")

func test_authoritative_row_168_near_antipodal() -> void:
	var g := GEO.wgs84()
	var v := g.inverse_v(71.606214176302, 0.0, -80.240756380896471977, 170.591260542729673958)
	assert_false(v.is_empty(), "行 168 反解应有结果")
	assert_true(bool(v["converged"]), "近对跖应收敛")
	assert_true(int(v["numit"]) >= 1, "近对跖应经过 Newton 迭代")
	assert_almost_eq(_ang_delta(float(v["azi1"]), 169.717716110676), 0.0, 1e-8, "行168 azi1")
	assert_almost_eq(_ang_delta(float(v["azi2"]), 19.402427357239077616), 0.0, 1e-8, "行168 azi2")
	assert_almost_eq(float(v["s12"]), 19009997.0303785, 19009997.0303785 * 1e-9, "行168 s12（相对 1e-9）")

func test_authoritative_row_150001_short_line() -> void:
	var g := GEO.wgs84()
	var v := g.inverse_v(19.707097385334, 0.0, 19.707739582810256591, 0.000260256428101053)
	assert_false(v.is_empty(), "行 150001 反解应有结果")
	assert_almost_eq(_ang_delta(float(v["azi1"]), 20.996796804557), 0.0, 1e-8, "行150001 azi1")
	assert_almost_eq(_ang_delta(float(v["azi2"]), 20.996884567489087848), 0.0, 1e-8, "行150001 azi2")
	# s12 参考值仅 4 位小数（76.1478894），容差放宽到参考舍入 ±5e-5
	assert_almost_eq(float(v["s12"]), 76.1478894, 5e-5, "行150001 s12（参考舍入口径）")
	# m12 列全精度：76.1478893981816（相对 1e-9）
	assert_almost_eq(float(v["m12"]), 76.1478893981816, 76.1478893981816 * 1e-9 + 1e-9, "行150001 m12（相对 1e-9）")

func test_direct_roundtrip_row_12346() -> void:
	var g := GEO.wgs84()
	var d := g.direct_v(3.881801761024, 0.0, 7.571318148093, 5707892.515197)
	assert_false(d.is_empty(), "行 12346 正解应有结果")
	assert_almost_eq(float(d["lat2"]), 54.681996010438946554, 1e-8, "正解 lat2")
	assert_almost_eq(_ang_delta(float(d["lon2"]), 10.214487662352205081), 0.0, 1e-8, "正解 lon2")
	assert_almost_eq(_ang_delta(float(d["azi2"]), 13.113872139673233629), 0.0, 1e-8, "正解 azi2")

func test_arcdirect_roundtrip_row_12346() -> void:
	var g := GEO.wgs84()
	var d := g.arcdirect_v(3.881801761024, 0.0, 7.571318148093, 51.400248712716941882)
	assert_almost_eq(float(d["s12"]), 5707892.515197, 5707892.515197 * 1e-9, "弧长模式正解 s12")
	assert_almost_eq(float(d["lat2"]), 54.681996010438946554, 1e-8, "弧长模式正解 lat2")

func test_inverse_direct_self_consistency() -> void:
	# 一般边：反解→正解→再反解应闭合
	var g := GEO.wgs84()
	var v := g.inverse_v(39.9075276, 116.3912757, 31.1666667, 121.4666667)
	var d := g.direct_v(39.9075276, 116.3912757, float(v["azi1"]), float(v["s12"]))
	assert_almost_eq(float(d["lat2"]), 31.1666667, 1e-9, "自洽 lat2")
	assert_almost_eq(_ang_delta(float(d["lon2"]), 121.4666667), 0.0, 1e-9, "自洽 lon2")
	assert_almost_eq(_ang_delta(float(d["azi2"]), float(v["azi2"])), 0.0, 1e-9, "自洽 azi2")
	var v2 := g.inverse_v(float(d["lat2"]), float(d["lon2"]), 39.9075276, 116.3912757)
	assert_almost_eq(_ang_delta(float(v2["azi1"]), float(v["azi2"]) + 180.0), 0.0, 1e-9, "反方位角闭合")
	assert_almost_eq(float(v2["s12"]), float(v["s12"]), float(v["s12"]) * 1e-12, "反解对称 s12")

func test_symmetry_antisymmetry() -> void:
	var g := GEO.wgs84()
	var ab := g.inverse_v(39.9075276, 116.3912757, 31.1666667, 121.4666667)
	var ba := g.inverse_v(31.1666667, 121.4666667, 39.9075276, 116.3912757)
	assert_almost_eq(float(ba["s12"]), float(ab["s12"]), float(ab["s12"]) * 1e-12, "s12 对称")
	# 注：GeographicLib 的 Inverse 在换点后 m12 同号（Python geographiclib 2.1 实测裁决：
	# m12(AB)=m12(BA)=+1067918.44），反对称的是 S12；M12/M21 互换
	assert_almost_eq(float(ba["m12"]), float(ab["m12"]), absf(float(ab["m12"])) * 1e-9 + 1e-9, "m12 换点同号（底本约定）")
	assert_almost_eq(float(ba["S12"]), -float(ab["S12"]), absf(float(ab["S12"])) * 1e-9 + 1e-3, "S12 反对称")
	assert_almost_eq(float(ba["M12"]), float(ab["M21"]), 1e-9, "M12/M21 互换")
	assert_almost_eq(float(ba["M21"]), float(ab["M12"]), 1e-9, "M21/M12 互换")
	assert_almost_eq(_ang_delta(float(ba["azi1"]), float(ab["azi2"]) + 180.0), 0.0, 1e-9, "反解 azi1 = azi2+180")
	assert_almost_eq(_ang_delta(float(ba["azi2"]), float(ab["azi1"]) + 180.0), 0.0, 1e-9, "反解 azi2 = azi1+180")

func test_line_and_position_service() -> void:
	var g := GEO.wgs84()
	var st := g.line(3.881801761024, 0.0, 7.571318148093)
	assert_false(st.is_empty(), "line 状态应建立")
	var p := GEO.geodesic_position(st, 5707892.515197)
	assert_almost_eq(float(p["lat2"]), 54.681996010438946554, 1e-8, "沿线位置 lat2")
	var p0 := GEO.geodesic_position(st, 0.0)
	assert_almost_eq(float(p0["lat2"]), 3.881801761024, 1e-12, "s12=0 仍在起点")

func test_protocol_inverse_and_direct() -> void:
	var r := GEO.inverse({"lat1_deg": 3.881801761024, "lon1_deg": 0.0,
			"lat2_deg": 54.681996010438946554, "lon2_deg": 10.214487662352205081, "datum": "WGS84"})
	assert_true(bool(r.get("ok", false)), "协议反解应成功")
	var v: Dictionary = r.get("value", {})
	assert_true(v.has("azi1_deg") and v.has("azi2_deg") and v.has("s12_m") and v.has("a12_deg") and v.has("m12_m") and v.has("S12_m2"), "反解 value 键齐全")
	assert_eq((r.get("steps", []) as Array).size(), 3, "反解步骤数")
	assert_true(String(r.get("formula", "")).contains("geographiclib-js"), "公式注明移植底本")
	var d := GEO.direct({"lat1_deg": 3.881801761024, "lon1_deg": 0.0, "azi1_deg": 7.571318148093, "s12_m": 5707892.515197})
	assert_true(bool(d.get("ok", false)), "协议正解应成功")
	var dv: Dictionary = d.get("value", {})
	assert_true(dv.has("lat2_deg") and dv.has("lon2_deg") and dv.has("azi2_deg"), "正解 value 键齐全")

func test_protocol_error_messages_chinese() -> void:
	var r1 := GEO.inverse({"lat1_deg": 95.0, "lon1_deg": 0.0, "lat2_deg": 0.0, "lon2_deg": 0.0})
	assert_false(bool(r1.get("ok", true)), "纬度越界应失败")
	assert_true(String(r1.get("error", "")).contains("纬度"), "纬度越界错误应中文提及纬度")
	var r2 := GEO.inverse({"lat1_deg": NAN, "lon1_deg": 0.0, "lat2_deg": 0.0, "lon2_deg": 0.0})
	assert_false(bool(r2.get("ok", true)), "NaN 应失败")
	assert_false(String(r2.get("error", "")).is_empty(), "NaN 应有中文错误")
	var r3 := GEO.direct({"lat1_deg": 0.0, "lon1_deg": 0.0, "azi1_deg": 45.0, "s12_m": NAN})
	assert_false(bool(r3.get("ok", true)), "距离 NaN 应失败")
	var r4 := GEO.inverse({"lat1_deg": 0.0, "lon1_deg": 0.0, "lat2_deg": 1.0, "lon2_deg": 1.0, "datum": "不存在的椭球"})
	assert_false(bool(r4.get("ok", true)), "未知 datum 应失败")
	assert_false(String(r4.get("error", "")).is_empty(), "未知 datum 应有中文错误")

func test_cgcs2000_datum_accepted() -> void:
	var r := GEO.inverse({"lat1_deg": 39.9075276, "lon1_deg": 116.3912757,
			"lat2_deg": 31.1666667, "lon2_deg": 121.4666667, "datum": "CGCS2000"})
	assert_true(bool(r.get("ok", false)), "CGCS2000 反解应成功")
	var rw := GEO.inverse({"lat1_deg": 39.9075276, "lon1_deg": 116.3912757,
			"lat2_deg": 31.1666667, "lon2_deg": 121.4666667, "datum": "WGS84"})
	assert_true(bool(rw.get("ok", false)), "WGS84 反解应成功")
	assert_true(absf(float(r["value"]["s12_m"]) - float(rw["value"]["s12_m"])) >= 0.0, "两椭球均可出值（差异量级不做断言）")
