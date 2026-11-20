# tests/earthwork/test_section_volume.gd —— E2 断面法（平均断面法）
# 构造向量（自洽检核）：断面积 [10,20,30] m²、间距 50/50 → V=2000.0 m³
extends "res://tests/test_case_base.gd"

const Sv := preload("res://core/earthwork/section_volume.gd")

## 构造向量：填方面积 [10,20,30]、桩号 [0,50,100] → 填方 2000 m³
func test_vector_construction() -> void:
	var res: Dictionary = Sv.forward({"chains_m": [0.0, 50.0, 100.0],
		"fill_areas_m2": [10.0, 20.0, 30.0]})
	assert_true(bool(res.get("ok", false)), "应计算成功：" + String(res.get("error", "")))
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	assert_almost_eq(v["fill_m3"], 2000.0, 1e-9, "(10+20)/2×50 + (20+30)/2×50 = 2000")
	assert_almost_eq(v["cut_m3"], 0.0, 1e-9, "无挖方")
	assert_almost_eq(v["net_m3"], 2000.0, 1e-9, "净值 = 填 − 挖")
	assert_int_eq(int(v["segments"]), 2, "2 段")
	assert_almost_eq(v["total_dist_m"], 100.0, 1e-9, "总长 100 m")

## 纯核 seg_volumes
func test_core_seg_volumes() -> void:
	var v: PackedFloat64Array = Sv.seg_volumes(PackedFloat64Array([10.0, 20.0, 30.0]),
			PackedFloat64Array([50.0, 50.0]))
	assert_int_eq(v.size(), 2, "2 段")
	assert_almost_eq(v[0], 750.0, 1e-9, "段1 = 750")
	assert_almost_eq(v[1], 1250.0, 1e-9, "段2 = 1250")
	assert_true(Sv.seg_volumes(PackedFloat64Array([10.0]), PackedFloat64Array()).is_empty(), "单断面返回空")

## 填挖分列与不等间距
func test_fill_cut_separate() -> void:
	var res: Dictionary = Sv.forward({"chains_m": [0.0, 20.0, 60.0],
		"fill_areas_m2": [10.0, 0.0, 0.0], "cut_areas_m2": [0.0, 8.0, 12.0]})
	assert_true(bool(res.get("ok", false)), "填挖分列成功")
	if bool(res.get("ok", false)):
		var v: Dictionary = res["value"]
		assert_almost_eq(v["fill_m3"], (10.0 + 0.0) / 2.0 * 20.0, 1e-9, "填方 100")
		assert_almost_eq(v["cut_m3"], (0.0 + 8.0) / 2.0 * 20.0 + (8.0 + 12.0) / 2.0 * 40.0, 1e-9, "挖方 80+400=480")
		assert_almost_eq(v["net_m3"], 100.0 - 480.0, 1e-9, "净值 = 填−挖 = −380（净挖）")

## 错误路径
func test_error_paths() -> void:
	var e1: Dictionary = Sv.forward({"chains_m": [0.0, 50.0], "fill_areas_m2": [10.0]})
	assert_false(bool(e1.get("ok", true)), "面积与桩号不等长拒绝")
	var e2: Dictionary = Sv.forward({"chains_m": [50.0, 0.0], "fill_areas_m2": [10.0, 20.0]})
	assert_false(bool(e2.get("ok", true)), "桩号递减拒绝")
	var e3: Dictionary = Sv.forward({"chains_m": [0.0, 50.0, 50.0], "fill_areas_m2": [10.0, 20.0, 30.0]})
	assert_false(bool(e3.get("ok", true)), "桩号重复拒绝")
	var e4: Dictionary = Sv.forward({"chains_m": [0.0, 50.0], "fill_areas_m2": [-1.0, 20.0]})
	assert_false(bool(e4.get("ok", true)), "负面积拒绝")
