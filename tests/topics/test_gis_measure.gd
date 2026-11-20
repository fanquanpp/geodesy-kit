# tests/topics/test_gis_measure.gd —— GK-M8-8（I-GIS 量测）
# 向量来源：ARCHITECTURE.md §4 GK-M8【构造·本会话】I-GIS：Haversine 北京→上海
# 1074470.9 m（R₁=6371008.7714 m；坐标 39.9075276,116.3912757 → 31.1666667,121.4666667，
# 即 _scripts/gen_vectors_b.py 所用坐标，本会话 Python 复核 1074470.8798 m）。
# 其余为构造自洽（缓冲范围闭式、IDW 对称与精确命中、球面面积与平面近似互差）。
extends "res://tests/test_case_base.gd"

const G := preload("res://core/topics/gis_measure.gd")

const R1 := 6371008.7714
const BJ := [39.9075276, 116.3912757]
const SH := [31.1666667, 121.4666667]

func test_haversine_authority_vector() -> void:
	var r := G.haversine({"lat1": BJ[0], "lon1": BJ[1], "lat2": SH[0], "lon2": SH[1]})
	assert_true(r["ok"], "Haversine 向量应成功")
	if bool(r["ok"]):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["dist_m"]), 1074470.9, 0.05, "I-GIS Haversine 北京→上海 1074470.9 m")
		assert_almost_eq(float(v["dist_km"]), 1074.4709, 0.001, "千米口径")
		# 对称性
		var r2 := G.haversine({"lat1": SH[0], "lon1": SH[1], "lat2": BJ[0], "lon2": BJ[1]})
		assert_almost_eq(float(r2["value"]["dist_m"]), float(v["dist_m"]), 1e-9, "距离对称")
	# 同点距离为 0
	var r0 := G.haversine({"lat1": BJ[0], "lon1": BJ[1], "lat2": BJ[0], "lon2": BJ[1]})
	assert_almost_eq(float(r0["value"]["dist_m"]), 0.0, 1e-9, "同点距离 0")

func test_haversine_known_arcs() -> void:
	# 赤道上 1° = πR/180 ≈ 111194.93 m（构造常数自洽）
	var r := G.haversine({"lat1": 0.0, "lon1": 0.0, "lat2": 0.0, "lon2": 1.0})
	assert_almost_eq(float(r["value"]["dist_m"]), PI * R1 / 180.0, 1e-6, "赤道 1° 弧长")
	# 对径点距离 = πR
	var r2 := G.haversine({"lat1": 0.0, "lon1": 0.0, "lat2": 0.0, "lon2": 180.0})
	assert_almost_eq(float(r2["value"]["dist_m"]), PI * R1, 1e-3, "对径点 πR")

func test_buffer_bbox() -> void:
	var r := G.buffer_bbox({"lat": BJ[0], "lon": BJ[1], "radius_m": 1000.0})
	assert_true(r["ok"], "缓冲范围应成功")
	if bool(r["ok"]):
		var v: Dictionary = r["value"]
		var dlat := rad_to_deg(1000.0 / R1)
		var dlon := dlat / cos(deg_to_rad(BJ[0]))
		assert_almost_eq(float(v["dlat_deg"]), dlat, 1e-12, "Δφ = r/R（双路径）")
		assert_almost_eq(float(v["dlon_deg"]), dlon, 1e-12, "Δλ = Δφ/cosφ（双路径）")
		assert_almost_eq(float(v["lat_min_deg"]), BJ[0] - dlat, 1e-12, "纬度下界")
		assert_almost_eq(float(v["lon_max_deg"]), BJ[1] + dlon, 1e-12, "经度上界")
	# 近极区：经度覆盖全范围
	var r2 := G.buffer_bbox({"lat": 89.95, "lon": 30.0, "radius_m": 20000.0})
	assert_true(r2["ok"], "近极区应成功")
	if bool(r2["ok"]):
		assert_true((r2["value"] as Dictionary).has("note"), "近极区有说明")
		assert_almost_eq(float(r2["value"]["lon_min_deg"]), -180.0, 1e-12, "经度范围钳制为全经度")

func test_idw() -> void:
	# 对称两点等距 → 均值
	var r := G.idw({"samples": "0,0,10;2,0,30", "target_lat": 1.0, "target_lon": 0.0})
	assert_true(r["ok"], "IDW 对称算例应成功")
	if bool(r["ok"]):
		assert_almost_eq(float(r["value"]["value"]), 20.0, 1e-9, "等距对称 → 均值 20")
	# 精确命中 → 直接返回样本值
	var r2 := G.idw({"samples": "0,0,10;2,0,30", "target_lat": 2.0, "target_lon": 0.0})
	assert_true(r2["ok"], "IDW 精确命中应成功")
	if bool(r2["ok"]):
		assert_true(bool(r2["value"]["exact_hit"]), "标记 exact_hit")
		assert_almost_eq(float(r2["value"]["value"]), 30.0, 1e-12, "精确命中返回 30")
	# 三点算例：模块结果与测试内用 haversine 重算一致（双路径互检）
	var samples := "0,0,10;0,1,30;1,0,50"
	var r3 := G.idw({"samples": samples, "target_lat": 0.0, "target_lon": 0.5, "power": 2.0})
	assert_true(r3["ok"], "三点算例应成功")
	if bool(r3["ok"]):
		var num := 0.0
		var den := 0.0
		for s: Array in [[0.0, 0.0, 10.0], [0.0, 1.0, 30.0], [1.0, 0.0, 50.0]]:
			var d: float = G.haversine({"lat1": s[0], "lon1": s[1], "lat2": 0.0, "lon2": 0.5})["value"]["dist_m"]
			var w := 1.0 / (d * d)
			num += w * s[2]
			den += w
		assert_almost_eq(float(r3["value"]["value"]), num / den, 1e-9, "三点 IDW 双路径一致")

func test_spherical_area() -> void:
	# 1°×1° 赤道方格（Python 复核 12363718034.2 m²，与平面近似比 0.999949）
	var r := G.spherical_area({"ring": "0,0;0,1;1,1;1,0"})
	assert_true(r["ok"], "赤道方格应成功")
	if bool(r["ok"]):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["area_m2"]), 12363718034.2, 12.0, "赤道 1°×1° 球面面积")
		var arc := PI * R1 / 180.0
		var ratio := float(v["area_m2"]) / (arc * arc)
		assert_between(ratio, 0.99994, 1.0, "球面/平面比在 1 附近（小范围）")
	# 39°N 方格（Python 复核 9540512050.7 m²）
	var r2 := G.spherical_area({"ring": "39,116;39,117;40,117;40,116"})
	assert_true(r2["ok"], "39N 方格应成功")
	if bool(r2["ok"]):
		assert_almost_eq(float(r2["value"]["area_m2"]), 9540512050.7, 10.0, "39N 1°×1° 球面面积")
	# 单位换算自洽
	if bool(r["ok"]):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["area_km2"]), float(v["area_m2"]) / 1e6, 1e-9, "km² 换算")
		assert_almost_eq(float(v["area_ha"]), float(v["area_m2"]) / 10000.0, 1e-9, "公顷换算")
		assert_almost_eq(float(v["area_mu"]), float(v["area_ha"]) * 15.0, 1e-9, "亩换算（1 公顷 = 15 亩）")

func test_invalid_inputs() -> void:
	var r1 := G.haversine({"lat1": 95.0, "lon1": 0.0, "lat2": 0.0, "lon2": 0.0})
	assert_false(bool(r1["ok"]), "纬度 95 应拒绝")
	var r2 := G.buffer_bbox({"lat": 39.9, "lon": 116.4, "radius_m": 0.0})
	assert_false(bool(r2["ok"]), "半径 0 应拒绝")
	var r3 := G.idw({"samples": "0,0,10;0,1,30", "target_lat": 1.0, "target_lon": 0.0, "power": -1.0})
	assert_false(bool(r3["ok"]), "负幂应拒绝")
	var r4 := G.idw({"samples": "0,0,abc", "target_lat": 1.0, "target_lon": 0.0})
	assert_false(bool(r4["ok"]), "非数值应拒绝")
	var r5 := G.spherical_area({"ring": "0,0;0,1"})
	assert_false(bool(r5["ok"]), "顶点不足应拒绝")
	var r6 := G.haversine({"lat1": 39.9, "lon1": 200.0, "lat2": 0.0, "lon2": 0.0})
	assert_false(bool(r6["ok"]), "经度 200 应拒绝")
	for r: Dictionary in [r1, r2, r3, r4, r5, r6]:
		assert_true(String(r["error"]).length() > 0, "失败必带中文错误")
		assert_true((r["value"] as Dictionary).is_empty(), "失败时 value 为空")
