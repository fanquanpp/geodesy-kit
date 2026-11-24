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

# ---------- P5 追加：双口径 cut_minus_fill_m3 与棱台公式路径 ----------

## 双口径：net_m3（填−挖）与 cut_minus_fill_m3（挖−填）互为相反数
func test_dual_net_conventions() -> void:
	var res: Dictionary = Sv.forward({"chains_m": [0.0, 20.0, 60.0],
		"fill_areas_m2": [10.0, 0.0, 0.0], "cut_areas_m2": [0.0, 8.0, 12.0]})
	assert_true(bool(res.get("ok", false)), "双口径算例成功")
	if bool(res.get("ok", false)):
		var v: Dictionary = res["value"]
		assert_almost_eq(float(v["net_m3"]), -380.0, 1e-9, "净量 = 填−挖 = −380")
		assert_almost_eq(float(v["cut_minus_fill_m3"]), 380.0, 1e-9, "挖减填 = 380（互为相反数）")
		assert_almost_eq(float(v["net_m3"]) + float(v["cut_minus_fill_m3"]), 0.0, 1e-12, "两口径代数和为 0")

## 棱台公式纯核与权威算例：A₁=100、A_m=144、A₂=100 m²、L=100 m → 12933.333333 m³（1e-6）
## 端面平均 = (100+100)/2×100 = 10000 m³（Python 复核一致）
func test_frustum_formula_authority_vector() -> void:
	assert_almost_eq(Sv.frustum_volume(100.0, 144.0, 100.0, 100.0), 12933.333333, 1e-4, "棱台 12933.333333 m³")
	assert_almost_eq(Sv.frustum_volume(100.0, 144.0, 100.0, 100.0), 12933.333333333334, 1e-6, "棱台全精度")
	# 端面平均对照
	var mean_v := (100.0 + 100.0) / 2.0 * 100.0
	assert_almost_eq(mean_v, 10000.0, 1e-9, "端面平均 10000 m³")
	# 退化输入
	assert_true(is_nan(Sv.frustum_volume(100.0, 144.0, 100.0, -1.0)), "负段长返回 NAN")
	assert_true(is_nan(Sv.frustum_volume(NAN, 144.0, 100.0, 100.0)), "NaN 面积返回 NAN")

## 协议入口棱台路径（prismoidal_segments 显式给 A₁/A_m/A₂/L）
func test_frustum_protocol_path() -> void:
	var res: Dictionary = Sv.forward({
		"chains_m": [0.0, 100.0],
		"fill_areas_m2": [100.0, 100.0],
		"prismoidal_segments": [{"a1_m2": 100.0, "am_m2": 144.0, "a2_m2": 100.0, "l_m": 100.0}],
	})
	assert_true(bool(res.get("ok", false)), "棱台协议路径成功：" + String(res.get("error", "")))
	if bool(res.get("ok", false)):
		var v: Dictionary = res["value"]
		assert_almost_eq(float(v["frustum_m3"]), 12933.333333, 1e-4, "协议棱台体积 12933.333333 m³")
		assert_almost_eq(float(v["fill_m3"]), 10000.0, 1e-9, "平均断面法 10000 m³")
		assert_true(String(v.get("prismoidal_note", "")).contains("1/2 桩号"), "输出含 A_m 口径说明")
	# 非法棱台分段输入
	var bad: Dictionary = Sv.forward({
		"chains_m": [0.0, 100.0],
		"fill_areas_m2": [100.0, 100.0],
		"prismoidal_segments": [{"a1_m2": 100.0, "am_m2": "abc", "a2_m2": 100.0, "l_m": 100.0}],
	})
	assert_false(bool(bad.get("ok", true)), "棱台分段非法输入拒绝")
	assert_true(String(bad.get("error", "")).contains("棱台分段"), "中文错误提示棱台分段")
