# tests/ellipsoid/test_blh_xyz.gd —— A6 BLH↔XYZ 权威向量回归
#
# 向量来源（ARCHITECTURE.md §4 GK-M2 + 本会话 pyproj 复核）：
#   【权威·EPSG GN7-2 §4.1.1】B=53°48′33.820″N, L=2°07′46.380″E, h=73（WGS84）
#     → (3771793.968, 140253.342, 5124304.349)，pyproj EPSG:4937→4978 逐位一致；
#     参考值为毫米舍入，断言容差 0.5 mm。
#   【权威】CGCS2000 天安门 B=39.9075276°, L=116.3912757°, h=43.5
#     → (−2177748.227, 4388723.160, 4070142.752)，pyproj EPSG:4490→4978 复核
#     （输入坐标经本会话反查锁定，与架构师 _scripts/gen_vectors_b.py 的北京点同源）。
# 反算恢复：Bowring 闭式与闭式正算互逆，恢复到 1e-9°/1mm 级。
extends "res://tests/test_case_base.gd"

const BXL := preload("res://core/ellipsoid/blh_xyz.gd")
const EL := preload("res://core/ellipsoid/ellipsoid.gd")

const GN72_B := 53.0 + 48.0 / 60.0 + 33.820 / 3600.0
const GN72_L := 2.0 + 7.0 / 60.0 + 46.380 / 3600.0

func test_gn72_forward_authoritative() -> void:
	var r := BXL.forward({"lat_deg": GN72_B, "lon_deg": GN72_L, "h_m": 73.0, "datum": "WGS84"})
	assert_true(bool(r.get("ok", false)), "GN7-2 正算应成功")
	var v: Dictionary = r.get("value", {})
	assert_almost_eq(float(v.get("x_m", NAN)), 3771793.968, 0.0005, "GN7-2 X")
	assert_almost_eq(float(v.get("y_m", NAN)), 140253.342, 0.0005, "GN7-2 Y")
	assert_almost_eq(float(v.get("z_m", NAN)), 5124304.349, 0.0005, "GN7-2 Z")

func test_gn72_inverse_recovers_point() -> void:
	# 由正算结果闭式反算，应恢复原点（自洽互逆）
	var fw := BXL.blh_to_xyz(GN72_B, GN72_L, 73.0, EL.params("WGS84"))
	assert_false(fw.is_empty(), "正算纯函数应成功")
	var inv := BXL.xyz_to_blh(float(fw["x"]), float(fw["y"]), float(fw["z"]), EL.params("WGS84"))
	assert_false(inv.is_empty(), "反算纯函数应成功")
	assert_almost_eq(float(inv["lat"]), GN72_B, 1e-9, "反算恢复 B")
	assert_almost_eq(float(inv["lon"]), GN72_L, 1e-9, "反算恢复 L")
	assert_almost_eq(float(inv["h"]), 73.0, 0.001, "反算恢复 h")

func test_gn72_inverse_from_mm_reference() -> void:
	# 直接反算参考答案（毫米舍入坐标），坐标扰动 0.5mm 对应纬度扰动 ~1e-8°
	var r := BXL.inverse({"x_m": 3771793.968, "y_m": 140253.342, "z_m": 5124304.349, "datum": "WGS84"})
	assert_true(bool(r.get("ok", false)), "参考答案反算应成功")
	var v: Dictionary = r.get("value", {})
	assert_almost_eq(float(v.get("lat_deg", NAN)), GN72_B, 1e-6, "参考答案反算 B")
	assert_almost_eq(float(v.get("lon_deg", NAN)), GN72_L, 1e-6, "参考答案反算 L")
	assert_almost_eq(float(v.get("h_m", NAN)), 73.0, 0.002, "参考答案反算 h")

func test_tiananmen_cgcs2000_authoritative() -> void:
	var r := BXL.forward({"lat_deg": 39.9075276, "lon_deg": 116.3912757, "h_m": 43.5, "datum": "CGCS2000"})
	assert_true(bool(r.get("ok", false)), "天安门 CGCS2000 正算应成功")
	var v: Dictionary = r.get("value", {})
	assert_almost_eq(float(v.get("x_m", NAN)), -2177748.227, 0.0005, "天安门 X")
	assert_almost_eq(float(v.get("y_m", NAN)), 4388723.160, 0.0005, "天安门 Y")
	assert_almost_eq(float(v.get("z_m", NAN)), 4070142.752, 0.0005, "天安门 Z")
	# 反算恢复同点
	var inv := BXL.inverse({"x_m": float(v["x_m"]), "y_m": float(v["y_m"]), "z_m": float(v["z_m"]), "datum": "CGCS2000"})
	assert_true(bool(inv.get("ok", false)), "天安门反算应成功")
	var iv: Dictionary = inv.get("value", {})
	assert_almost_eq(float(iv.get("lat_deg", NAN)), 39.9075276, 1e-9, "天安门反算 B")
	assert_almost_eq(float(iv.get("lon_deg", NAN)), 116.3912757, 1e-9, "天安门反算 L")
	assert_almost_eq(float(iv.get("h_m", NAN)), 43.5, 0.001, "天安门反算 h")
	assert_false(String(iv.get("lat_dms", "")).is_empty(), "反算应附 DMS 文本")

func test_protocol_shape_and_formula() -> void:
	var r := BXL.forward({"lat_deg": GN72_B, "lon_deg": GN72_L, "h_m": 73.0, "datum": "WGS84"})
	assert_true(r.has("ok") and r.has("value") and r.has("steps") and r.has("formula") and r.has("error"), "§5 协议五键齐全")
	var steps: Array = r.get("steps", [])
	assert_eq(steps.size(), 2, "正算步骤数")
	var s0: Dictionary = steps[0]
	assert_true(s0.has("title") and s0.has("formula") and s0.has("substitution") and s0.has("result"), "步骤四字段")
	var ri := BXL.inverse({"x_m": 3771793.968, "y_m": 140253.342, "z_m": 5124304.349, "datum": "WGS84"})
	var steps_i: Array = ri.get("steps", [])
	assert_eq(steps_i.size(), 4, "反算步骤数（p/L、θ、Bowring B、h）")
	assert_true(String(ri.get("formula", "")).contains("Bowring"), "反算公式标注 Bowring")

func test_validation_chinese_errors() -> void:
	var r1 := BXL.forward({"lat_deg": 95.0, "lon_deg": 0.0, "h_m": 0.0, "datum": "WGS84"})
	assert_false(bool(r1.get("ok", true)), "纬度越界应失败")
	assert_false(String(r1.get("error", "")).is_empty(), "纬度越界应有中文错误")
	var r2 := BXL.forward({"lat_deg": NAN, "lon_deg": 0.0, "h_m": 0.0, "datum": "WGS84"})
	assert_false(bool(r2.get("ok", true)), "NaN 输入应失败")
	var r3 := BXL.forward({"lat_deg": 30.0, "lon_deg": 30.0, "h_m": 0.0, "datum": "不存在的椭球"})
	assert_false(bool(r3.get("ok", true)), "未知 datum 应失败")
	var r4 := BXL.inverse({"x_m": 0.0, "y_m": 0.0, "z_m": 0.0, "datum": "WGS84"})
	assert_false(bool(r4.get("ok", true)), "地心点反算应失败")
	var r5 := BXL.forward({"lat_deg": 30.0, "lon_deg": 30.0, "h_m": 0.0})
	assert_true(bool(r5.get("ok", false)), "缺 datum 时按 a/inv_f 默认（WGS84）可算")

func test_pole_case() -> void:
	# 极点：X=Y=0，Z=b+h（h=100）
	var b := 6356752.3142451793
	var inv := BXL.xyz_to_blh(0.0, 0.0, b + 100.0, EL.params("WGS84"))
	assert_false(inv.is_empty(), "极点反算应成功")
	assert_almost_eq(float(inv["lat"]), 90.0, 1e-9, "极点 B=90°")
	assert_almost_eq(float(inv["h"]), 100.0, 0.001, "极点 h=100")
	assert_almost_eq(float(inv["lon"]), 0.0, 1e-12, "极点 L 取 0")

func test_N_self_consistency() -> void:
	# N = a/√(1−e²·sin²B) 恒等式，即 N·√(1−e²·sin²B) = a
	var el := EL.params("WGS84")
	var r := BXL.forward({"lat_deg": GN72_B, "lon_deg": GN72_L, "h_m": 73.0, "datum": "WGS84"})
	var n := float(r["value"]["N_m"])
	var sl := sin(deg_to_rad(GN72_B))
	assert_almost_eq(n * sqrt(1.0 - float(el["e2"]) * sl * sl), 6378137.0, 1e-6, "N 恒等式")
