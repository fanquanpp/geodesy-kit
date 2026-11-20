# tests/route/test_spiral.gd —— B4 缓和曲线（回旋线级数 + Fresnel 数值积分双路径互检）
# 向量来源：ARCHITECTURE.md §4 GK-M7【权威】三组（x0/y0/β0）；双路径互检为架构要求
extends "res://tests/test_case_base.gd"

const Sp := preload("res://core/route/spiral.gd")

## 权威向量：缓和曲线终点坐标 x0/y0 与切线角 β0（三组）
func test_vector_authoritative_endpoints() -> void:
	# R=500, l0=60, α=30° → x0=59.9784, y0=1.1997, β0=3.4377468°
	var s1: PackedFloat64Array = Sp.point_series(60.0, 500.0, 60.0)
	assert_false(s1.is_empty(), "级数路径返回非空")
	assert_almost_eq(s1[0], 59.9784, 1e-3, "x0(R500)")
	assert_almost_eq(s1[1], 1.1997, 1e-3, "y0(R500)")
	var i1: PackedFloat64Array = Sp.point_integral(60.0, 500.0, 60.0)
	assert_almost_eq(i1[0], 59.9784, 1e-4, "x0 数值积分路径")
	assert_almost_eq(i1[1], 1.1997, 1e-4, "y0 数值积分路径")
	assert_almost_eq(rad_to_deg(Sp.tangent_angle_rad(60.0, 500.0, 60.0)), 3.4377468, 1e-6, "β0(R500)")
	# R=1000, l0=100, α=45°
	var s2: PackedFloat64Array = Sp.point_series(100.0, 1000.0, 100.0)
	assert_almost_eq(s2[0], 99.9750, 1e-3, "x0(R1000)")
	assert_almost_eq(s2[1], 1.6664, 1e-3, "y0(R1000)")
	assert_almost_eq(rad_to_deg(Sp.tangent_angle_rad(100.0, 1000.0, 100.0)), 2.8647890, 1e-6, "β0(R1000)")
	# R=600, l0=120, α=25°30′
	var s3: PackedFloat64Array = Sp.point_series(120.0, 600.0, 120.0)
	assert_almost_eq(s3[0], 119.8800, 1e-3, "x0(R600)")
	assert_almost_eq(s3[1], 3.9971, 1e-3, "y0(R600)")
	assert_almost_eq(rad_to_deg(Sp.tangent_angle_rad(120.0, 600.0, 120.0)), 5.7295780, 1e-6, "β0(R600)")

## 双路径互检：级数 vs 数值积分（任意弧长，多组）
func test_dual_path_consistency() -> void:
	var cases := [
		[500.0, 60.0], [1000.0, 100.0], [600.0, 120.0],
		[300.0, 200.0],   # β0 = 200/(2·300) rad ≈ 19.1°，大转角
		[250.0, 150.0],
	]
	for c: Array in cases:
		var r: float = c[0]
		var l0: float = c[1]
		for l in [l0 * 0.25, l0 * 0.5, l0 * 0.75, l0]:
			var sa: PackedFloat64Array = Sp.point_series(l, r, l0)
			var sb: PackedFloat64Array = Sp.point_integral(l, r, l0)
			# 四项级数在 β0≈19° 时截断误差 ≤5e-8 m（本会话 Python 复核），容差 1e-7
			assert_almost_eq(sa[0], sb[0], 1e-7, "x 双路径 (R=%s,l=%s)" % [str(r), str(l)])
			assert_almost_eq(sa[1], sb[1], 1e-7, "y 双路径 (R=%s,l=%s)" % [str(r), str(l)])

## 级数主导项与全项级数一致（x = l − l⁵/(40R²l0²)、y = l³/(6Rl0) 为主导项）
func test_series_leading_terms() -> void:
	var r := 500.0
	var l0 := 60.0
	var l := 60.0
	var x_leading: float = l - pow(l, 5.0) / (40.0 * r * r * l0 * l0)
	var y_leading: float = pow(l, 3.0) / (6.0 * r * l0)
	var sa: PackedFloat64Array = Sp.point_series(l, r, l0)
	# x 三阶项（l⁹）贡献 ≈3.6e-6、y 三阶项（l⁷）贡献 ≈3.1e-4（本会话 Python 复核量级）
	assert_almost_eq(sa[0], x_leading, 1e-5, "x 高阶项贡献 <1e-5")
	assert_almost_eq(sa[1], y_leading, 5e-4, "y 高阶项贡献 <5e-4（1.19969 vs 1.2）")

## B4 协议入口 coords：局部坐标 + 全局归化 + 双路径自检键
func test_coords_protocol() -> void:
	var res: Dictionary = Sp.coords({"r_m": 500.0, "l0_m": 60.0, "l_m": 60.0, "dir": 1})
	assert_true(bool(res.get("ok", false)), "coords 应成功")
	if bool(res.get("ok", false)):
		var v: Dictionary = res["value"]
		assert_almost_eq(v["x_local_m"], 59.9784, 1e-3, "coords x0")
		assert_almost_eq(v["y_local_m"], 1.1997, 1e-3, "coords y0（右转为正）")
		assert_almost_eq(v["tangent_deg"], 3.4377468, 1e-6, "coords 切线角（右转+）")
		assert_almost_eq(v["dual_path_gap_m"], 0.0, 1e-7, "双路径互差")
	# 左转：y 取负
	var rl: Dictionary = Sp.coords({"r_m": 500.0, "l0_m": 60.0, "l_m": 60.0, "dir": -1})
	assert_almost_eq(rl["value"]["y_local_m"], -1.1997, 1e-3, "左转 y 为负")
	assert_almost_eq(rl["value"]["tangent_deg"], -3.4377468, 1e-6, "左转切线角为负")
	# 全局归化：起点方位 0°（向正北行进）：局部 x 沿切线 → 北（Y+），右转弯曲侧为东（X+）
	var g1: Dictionary = Sp.coords({"r_m": 500.0, "l0_m": 60.0, "l_m": 60.0, "dir": 1,
		"start": {"x_m": 1000.0, "y_m": 2000.0, "bearing_deg": 0.0}})
	assert_almost_eq(g1["value"]["x_m"], 1000.0 + 1.1997, 1e-3, "方位0°：右弯侧为东 X+=y_local")
	assert_almost_eq(g1["value"]["y_m"], 2000.0 + 59.9784, 1e-3, "方位0°：沿切线北 Y+=x_local")
	assert_almost_eq(g1["value"]["bearing_deg"], 3.4377468, 1e-6, "全局方位")
	# 起点方位 90°（向东行进）：切线方向为东 → 曲线弯向南（右转）
	var g2: Dictionary = Sp.coords({"r_m": 500.0, "l0_m": 60.0, "l_m": 60.0, "dir": 1,
		"start": {"x_m": 1000.0, "y_m": 2000.0, "bearing_deg": 90.0}})
	assert_almost_eq(g2["value"]["x_m"], 1000.0 + 59.9784, 1e-3, "方位90°：沿东前进 x=X0+x0")
	assert_almost_eq(g2["value"]["y_m"], 2000.0 - 1.1997, 1e-3, "方位90°右转：弯向南 y=Y0−y0")

## 错误路径
func test_error_paths() -> void:
	assert_true(Sp.point_series(-1.0, 500.0, 60.0).is_empty(), "l<0 级数返回空")
	assert_true(Sp.point_series(60.0, 0.0, 60.0).is_empty(), "R=0 级数返回空")
	assert_true(is_nan(Sp.tangent_angle_rad(60.0, -1.0, 60.0)), "R<0 切线角 NAN")
	var e1: Dictionary = Sp.coords({"r_m": 500.0, "l0_m": 60.0, "l_m": 80.0})
	assert_false(bool(e1.get("ok", true)), "l>l0 应拒绝")
	assert_true(String(e1.get("error", "")).contains("超出缓和曲线全长"), "中文提示")
	var e2: Dictionary = Sp.coords({"r_m": 500.0, "l0_m": 60.0, "l_m": 30.0, "dir": 5})
	assert_false(bool(e2.get("ok", true)), "dir 非法应拒绝")
	var e3: Dictionary = Sp.coords({"r_m": 500.0, "l0_m": 60.0, "l_m": 30.0,
		"start": {"x_m": 1000.0, "y_m": 2000.0}})
	assert_false(bool(e3.get("ok", true)), "start 缺 bearing_deg 应拒绝")
