# tests/earthwork/test_profile.gd —— E6 纵断面内插 / 横断面数据（构造自洽）
# 构造向量：纵断面 (0,100)(100,102)(200,101) 桩150→101.5；
# 横断面 o∈[−20,20] 地面平 100、设计 103、i=0 → 填 120.0 m²；i=2% → 填 112.0 m²
extends "res://tests/test_case_base.gd"

const Pf := preload("res://core/earthwork/profile.gd")

static func _points() -> Array:
	return [{"chain_m": 0.0, "elev_m": 100.0}, {"chain_m": 100.0, "elev_m": 102.0},
			{"chain_m": 200.0, "elev_m": 101.0}]

## 纵断面内插构造向量 + 纯核
func test_profile_interp() -> void:
	var res: Dictionary = Pf.interp_forward({"points": _points(), "query_chains_m": [150.0, 50.0, 0.0, 200.0]})
	assert_true(bool(res.get("ok", false)), "纵断面内插成功：" + String(res.get("error", "")))
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	assert_almost_eq(float(v["elevs_m"][0]), 101.5, 1e-12, "桩150 → 101.5（102 与 101 中点）")
	assert_almost_eq(float(v["elevs_m"][1]), 101.0, 1e-12, "桩50 → 101.0")
	assert_almost_eq(float(v["elevs_m"][2]), 100.0, 1e-12, "端点 0 → 100")
	assert_almost_eq(float(v["elevs_m"][3]), 101.0, 1e-12, "端点 200 → 101")
	# 纯核
	var pts := [[0.0, 100.0], [100.0, 102.0], [200.0, 101.0]]
	assert_almost_eq(Pf.interp(pts, 150.0), 101.5, 1e-12, "纯核 101.5")
	assert_true(is_nan(Pf.interp(pts, 250.0)), "纯核越界 NAN")
	assert_true(is_nan(Pf.interp([[0.0, 1.0]], 5.0)), "点数不足 NAN")

## 纵断面越界：默认报错 / clamp 截断
func test_interp_out_of_range() -> void:
	var e1: Dictionary = Pf.interp_forward({"points": _points(), "query_chains_m": [250.0]})
	assert_false(bool(e1.get("ok", true)), "越界默认拒绝")
	assert_true(String(e1.get("error", "")).contains("超出纵断面"), "越界中文提示")
	var ok: Dictionary = Pf.interp_forward({"points": _points(), "query_chains_m": [250.0, -10.0], "clamp": true})
	assert_true(bool(ok.get("ok", false)), "clamp 成功")
	if bool(ok.get("ok", false)):
		assert_almost_eq(float(ok["value"]["elevs_m"][0]), 101.0, 1e-12, "右端截断 101")
		assert_almost_eq(float(ok["value"]["elevs_m"][1]), 100.0, 1e-12, "左端截断 100")

## 横断面构造向量：平地面、平设计 → 填 120 m²
func test_cross_section_flat() -> void:
	var res: Dictionary = Pf.cross_section({"design_elev_m": 103.0, "cross_slope_pct": 0.0,
		"section": [{"offset_m": -20.0, "elev_m": 100.0}, {"offset_m": 0.0, "elev_m": 100.0},
				{"offset_m": 20.0, "elev_m": 100.0}]})
	assert_true(bool(res.get("ok", false)), "横断面成功：" + String(res.get("error", "")))
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	assert_almost_eq(v["fill_area_m2"], 120.0, 1e-9, "填方面积 = 40×3 = 120")
	assert_almost_eq(v["cut_area_m2"], 0.0, 1e-9, "无挖方")
	assert_almost_eq(v["net_area_m2"], 120.0, 1e-9, "净值 120")
	var dhs: PackedFloat64Array = v["dhs_m"]
	assert_almost_eq(dhs[0], -3.0, 1e-12, "首点挖填高 −3（地面−设计）")

## 路拱横坡：i=2% → 边缘设计 102.6 → 填 112 m²
func test_cross_section_crown() -> void:
	var res: Dictionary = Pf.cross_section({"design_elev_m": 103.0, "cross_slope_pct": 2.0,
		"section": [{"offset_m": -20.0, "elev_m": 100.0}, {"offset_m": 0.0, "elev_m": 100.0},
				{"offset_m": 20.0, "elev_m": 100.0}]})
	assert_true(bool(res.get("ok", false)), "带路拱成功")
	if bool(res.get("ok", false)):
		var v: Dictionary = res["value"]
		assert_almost_eq(v["fill_area_m2"], 40.0 * (3.0 + 2.6) / 2.0, 1e-9, "填 112（梯形）")
		var heights: Array = v["heights"]
		assert_almost_eq(float(heights[0]["design_elev_m"]), 102.6, 1e-9, "边缘设计高程 102.6")

## 变号段零点分割（精确）：地面 (−20,100)→(20,106)，设计 103 → 填 30 / 挖 30
func test_cross_section_zero_split() -> void:
	var res: Dictionary = Pf.cross_section({"design_elev_m": 103.0, "cross_slope_pct": 0.0,
		"section": [{"offset_m": -20.0, "elev_m": 100.0}, {"offset_m": 20.0, "elev_m": 106.0}]})
	assert_true(bool(res.get("ok", false)), "变号断面成功")
	if bool(res.get("ok", false)):
		var v: Dictionary = res["value"]
		# h 从 −3 到 +3 线性：零点在中点，两侧三角形各 3×20/2=30
		assert_almost_eq(v["fill_area_m2"], 30.0, 1e-9, "填 30（零点左三角形）")
		assert_almost_eq(v["cut_area_m2"], 30.0, 1e-9, "挖 30（零点右三角形）")
		assert_almost_eq(v["net_area_m2"], 0.0, 1e-9, "净 0")

## 纯核 interval_areas 与错误路径
func test_core_and_errors() -> void:
	var a1: PackedFloat64Array = Pf.interval_areas(-3.0, 3.0, 20.0)
	assert_almost_eq(a1[0], 15.0, 1e-9, "核：填 15（负部三角形 3×10/2）")
	assert_almost_eq(a1[1], 15.0, 1e-9, "核：挖 15（正部三角形）")
	var a2: PackedFloat64Array = Pf.interval_areas(2.0, 4.0, 10.0)
	assert_almost_eq(a2[1], 30.0, 1e-9, "核：同号正部 → 挖方梯形")
	assert_almost_eq(a2[0], 0.0, 1e-9, "核：无填方")
	var a3: PackedFloat64Array = Pf.interval_areas(-2.0, -4.0, 10.0)
	assert_almost_eq(a3[0], 30.0, 1e-9, "核：同号负部 → 填方梯形")
	var e1: Dictionary = Pf.cross_section({"design_elev_m": 103.0,
		"section": [{"offset_m": -20.0, "elev_m": 100.0}]})
	assert_false(bool(e1.get("ok", true)), "单点断面拒绝")
	var e2: Dictionary = Pf.cross_section({"design_elev_m": 103.0,
		"section": [{"offset_m": 20.0, "elev_m": 100.0}, {"offset_m": -20.0, "elev_m": 106.0}]})
	assert_false(bool(e2.get("ok", true)), "偏距倒序拒绝")
	var e3: Dictionary = Pf.interp_forward({"points": _points(), "query_chains_m": []})
	assert_false(bool(e3.get("ok", true)), "空查询拒绝")
