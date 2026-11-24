# tests/earthwork/test_grid_volume_asym.gd —— P4 固化：非对称混合格零线分割锚定
# 数值探针（_p4_checks/probe_asym.py，逐行移植 grid_volume.gd _split_rec/_zero_line_fan）：
#   (2,-2,-2,-2) a=10 → fill=109.667891 / cut=9.646929；
#   对参考半解析积分 fill=109.6574 / cut=9.6574 残差 ≈0.0105/0.0104，
#   属"四分递归 + 零线直线化"固有近似，本测试按实现口径锚定，防止槽位/角点约定回退。
extends "res://tests/test_case_base.gd"

const Gv := preload("res://core/earthwork/grid_volume.gd")

## 权威锚定：非对称 1+3 混合格 (2,-2,-2,-2) a=10，设计 0
## → 填 ≈109.6679 m³、挖 ≈9.6469 m³（容差 5e-3，覆盖实现与参考积分间固有直线化残差）
func test_asymmetric_one_vs_three() -> void:
	var res: Dictionary = Gv.forward({"design_elev_m": 0.0, "cell_size_m": 10.0,
		"grid": [[2.0, -2.0], [-2.0, -2.0]]})
	assert_true(bool(res.get("ok", false)), "非对称混合格应成功：" + String(res.get("error", "")))
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	assert_almost_eq(v["fill_m3"], 109.6679, 5e-3, "非对称格填方锚定 ≈109.6679 m³")
	assert_almost_eq(v["cut_m3"], 9.6469, 5e-3, "非对称格挖方锚定 ≈9.6469 m³")
	# 净值与分量和一致性：净 = 填 − 挖
	assert_almost_eq(v["net_m3"], float(v["fill_m3"]) - float(v["cut_m3"]), 1e-9, "净值 = 填 − 挖")
	assert_int_eq(int(v["mixed_cells"]), 1, "1 个混合格")
	assert_int_eq(int(v["cells"]), 1, "1 个方格")
	# 总填挖应显著偏向填方侧（1 正 3 负）：填 > 挖 × 8
	assert_true(float(v["fill_m3"]) > 8.0 * float(v["cut_m3"]), "填方应远大于挖方（1 正 3 负）")

## 镜像/旋转配对逐位一致：四角重排不改变分割结果（槽位约定回归防线）
func test_asym_mirror_rotation_bitwise() -> void:
	var layouts := {
		"原": [[2.0, -2.0], [-2.0, -2.0]],
		"水平镜像": [[-2.0, 2.0], [-2.0, -2.0]],
		"垂直镜像": [[-2.0, -2.0], [2.0, -2.0]],
		"旋转180°": [[-2.0, -2.0], [-2.0, 2.0]],
	}
	var base_fill := NAN
	var base_cut := NAN
	for name: String in layouts:
		var res: Dictionary = Gv.forward({"design_elev_m": 0.0, "cell_size_m": 10.0,
			"grid": layouts[name]})
		assert_true(bool(res.get("ok", false)), name + " 应成功")
		if not bool(res.get("ok", false)):
			continue
		var v: Dictionary = res["value"]
		if is_nan(base_fill):
			base_fill = float(v["fill_m3"])
			base_cut = float(v["cut_m3"])
		else:
			assert_almost_eq(float(v["fill_m3"]), base_fill, 0.0, name + " 填方与原布局逐位一致")
			assert_almost_eq(float(v["cut_m3"]), base_cut, 0.0, name + " 挖方与原布局逐位一致")

## 纯核 split_cell_volume：非对称混合格分割槽位 [填, 挖, 精确子格, 近似子格]
func test_asym_split_core_slots() -> void:
	var sv: PackedFloat64Array = Gv.split_cell_volume(10.0, 2.0, -2.0, -2.0, -2.0)
	assert_false(sv.is_empty(), "非对称混合格分割非空")
	assert_int_eq(sv.size(), 4, "返回 [填, 挖, 精确子格, 近似子格] 四槽")
	assert_almost_eq(sv[0], 109.6679, 5e-3, "槽位 0 = 填 ≈109.6679")
	assert_almost_eq(sv[1], 9.6469, 5e-3, "槽位 1 = 挖 ≈9.6469")
	assert_between(sv[0] + sv[1], 119.0, 120.0, "填挖合计应接近 a²·|h|均值=120 的直线化口径")
