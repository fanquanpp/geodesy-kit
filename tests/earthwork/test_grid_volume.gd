# tests/earthwork/test_grid_volume.gd —— E1 方格网法土方
# 权威向量：ARCHITECTURE.md §4 GK-M7【构造·本会话】20×20 格四角 (1.0,2.0,1.5,0.5) → V=500.0 m³
extends "res://tests/test_case_base.gd"

const Gv := preload("res://core/earthwork/grid_volume.gd")

## 权威向量：单格 20×20，四角高程 (1.0,2.0,1.5,0.5)、设计 0 → 挖方 500.0 m³
func test_vector_authoritative_single_cell() -> void:
	var res: Dictionary = Gv.forward({"design_elev_m": 0.0, "cell_size_m": 20.0,
		"grid": [[1.0, 2.0], [1.5, 0.5]]})
	assert_true(bool(res.get("ok", false)), "应计算成功：" + String(res.get("error", "")))
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	assert_almost_eq(v["cut_m3"], 500.0, 1e-9, "权威向量 V=500.0 m³（挖方）")
	assert_almost_eq(v["fill_m3"], 0.0, 1e-9, "无填方")
	assert_almost_eq(v["net_m3"], -500.0, 1e-9, "净值 = 填−挖 = −500")
	assert_int_eq(int(v["cells"]), 1, "1 个方格")
	assert_almost_eq(v["cell_area_m2"], 400.0, 1e-12, "单格面积 400 m²")

## 纯核 cell_volume 与协议一致
func test_cell_volume_core() -> void:
	var cv: PackedFloat64Array = Gv.cell_volume(20.0, 1.0, 2.0, 1.5, 0.5)
	assert_almost_eq(cv[0], 0.0, 1e-12, "核：填 0")
	assert_almost_eq(cv[1], 500.0, 1e-9, "核：挖 500")
	var cv2: PackedFloat64Array = Gv.cell_volume(10.0, -1.0, -2.0, -1.5, -0.5)
	assert_almost_eq(cv2[0], 125.0, 1e-9, "核：全负 → 填 125")
	assert_almost_eq(cv2[1], 0.0, 1e-12, "核：无挖")

## 多格混合符号：与逐格手算一致
func test_multi_cell_mixed() -> void:
	# 2×2 格（3×3 点），a=10，设计 5；地面构造：左半挖、右半填
	var grid := [
		[6.0, 5.0, 4.0],
		[7.0, 5.0, 3.0],
		[8.0, 5.0, 2.0],
	]
	var res: Dictionary = Gv.forward({"design_elev_m": 5.0, "cell_size_m": 10.0, "grid": grid})
	assert_true(bool(res.get("ok", false)), "多格成功")
	if bool(res.get("ok", false)):
		var v: Dictionary = res["value"]
		assert_int_eq(int(v["cells"]), 4, "4 格")
		# 逐格手算：
		# 格(0,0) h=(1,0,2,0)：挖 (1+0+2+0)/4×100=75
		# 格(0,1) h=(0,−1,0,−2)：填 (1+2)/4×100=75
		# 格(1,0) h=(2,0,3,0)：挖 (2+3)/4×100=125
		# 格(1,1) h=(0,−2,0,−3)：填 (2+3)/4×100=125
		assert_almost_eq(v["cut_m3"], 200.0, 1e-9, "挖方 75+125=200")
		assert_almost_eq(v["fill_m3"], 200.0, 1e-9, "填方 75+125=200")
		# 混合格（含 0 与异号）：格(0,0) 无负 → 非混合；格(0,1) 无正 → 非混合
		assert_almost_eq(v["mixed_cells_area_m2"], 0.0, 1e-9, "无非混合格误判")

## 行列数校验与错误路径
func test_error_paths() -> void:
	var e1: Dictionary = Gv.forward({"design_elev_m": 0.0, "cell_size_m": 20.0,
		"grid": [[1.0, 2.0], [1.5]]})
	assert_false(bool(e1.get("ok", true)), "行列不一致拒绝")
	var e2: Dictionary = Gv.forward({"design_elev_m": 0.0, "cell_size_m": 0.0,
		"grid": [[1.0, 2.0], [1.5, 0.5]]})
	assert_false(bool(e2.get("ok", true)), "格网边长 0 拒绝")
	var e3: Dictionary = Gv.forward({"design_elev_m": 0.0, "cell_size_m": 20.0, "grid": []})
	assert_false(bool(e3.get("ok", true)), "空网格拒绝")
	var e4: Dictionary = Gv.forward({"design_elev_m": 0.0, "cell_size_m": 20.0,
		"grid": [[1.0, "abc"], [1.5, 0.5]]})
	assert_false(bool(e4.get("ok", true)), "非数字高程拒绝")
