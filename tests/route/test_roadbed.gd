# tests/route/test_roadbed.gd —— D7 路基开挖口/坡脚（构造自洽：解析断面精确交点）
# 期望值来源：本会话 Python 解析解（坡线与地面折线联立求解），见交付说明
extends "res://tests/test_case_base.gd"

const Rd := preload("res://core/route/roadbed.gd")

## 平地填方：地面50、设计55、b=10、1:1.5 → 坡脚距 = 10+1.5×5 = 17.5
func test_flat_fill() -> void:
	var res: Dictionary = Rd.forward({"design_elev_m": 55.0, "half_width_m": 10.0,
		"cross_slope_pct": 0.0, "fill_slope_ratio": 1.5, "cut_slope_ratio": 0.75,
		"ground": [{"offset_m": -40.0, "elev_m": 50.0}, {"offset_m": 0.0, "elev_m": 50.0},
				{"offset_m": 40.0, "elev_m": 50.0}]})
	assert_true(bool(res.get("ok", false)), "平地填方成功：" + String(res.get("error", "")))
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	assert_almost_eq(v["foot_right_dist_m"], 17.5, 1e-9, "右侧坡脚距 17.5")
	assert_almost_eq(v["foot_left_dist_m"], 17.5, 1e-9, "左侧坡脚距 17.5")
	assert_almost_eq(v["foot_right_elev_m"], 50.0, 1e-9, "坡脚地面高程 50")
	assert_eq(v["mode_right"], "路堤填方", "右侧填方")
	assert_eq(v["mode_left"], "路堤填方", "左侧填方")
	assert_eq(v["center_mode"], "路堤填方", "中心填方")
	assert_almost_eq(v["edge_diff_right_m"], 5.0, 1e-9, "边缘填挖高 +5")

## 平地挖方：地面50、设计47、b=10、1:0.75 → 开挖口距 = 10+0.75×3 = 12.25
func test_flat_cut() -> void:
	var res: Dictionary = Rd.forward({"design_elev_m": 47.0, "half_width_m": 10.0,
		"cross_slope_pct": 0.0, "fill_slope_ratio": 1.5, "cut_slope_ratio": 0.75,
		"ground": [{"offset_m": -40.0, "elev_m": 50.0}, {"offset_m": 0.0, "elev_m": 50.0},
				{"offset_m": 40.0, "elev_m": 50.0}]})
	assert_true(bool(res.get("ok", false)), "平地挖方成功：" + String(res.get("error", "")))
	if bool(res.get("ok", false)):
		var v: Dictionary = res["value"]
		assert_almost_eq(v["foot_right_dist_m"], 12.25, 1e-9, "右侧开挖口距 12.25")
		assert_almost_eq(v["foot_left_dist_m"], 12.25, 1e-9, "左侧开挖口距 12.25")
		assert_eq(v["mode_right"], "路堑挖方", "右侧挖方")
		assert_eq(v["center_mode"], "路堑挖方", "中心挖方")

## 横坡路拱：i=2%、b=10 → 边缘高程 = 中心 − 0.2；平地填方坡脚距 = 10 + m×(55−0.2−50)
func test_cross_slope_crown() -> void:
	var res: Dictionary = Rd.forward({"design_elev_m": 55.0, "half_width_m": 10.0,
		"cross_slope_pct": 2.0, "fill_slope_ratio": 1.5, "cut_slope_ratio": 0.75,
		"ground": [{"offset_m": -40.0, "elev_m": 50.0}, {"offset_m": 0.0, "elev_m": 50.0},
				{"offset_m": 40.0, "elev_m": 50.0}]})
	assert_true(bool(res.get("ok", false)), "带横坡填方成功")
	if bool(res.get("ok", false)):
		var v: Dictionary = res["value"]
		assert_almost_eq(v["edge_elev_m"], 54.8, 1e-9, "路槽边缘高程 54.8")
		assert_almost_eq(v["foot_right_dist_m"], 10.0 + 1.5 * 4.8, 1e-9, "坡脚距含横坡修正")

## 斜坡地面（右坡上升）：解析交点 x右=17.674419、x左=20.540541（Python 解析解）
func test_sloped_ground() -> void:
	var res: Dictionary = Rd.forward({"design_elev_m": 55.0, "half_width_m": 10.0,
		"cross_slope_pct": 0.0, "fill_slope_ratio": 1.5, "cut_slope_ratio": 0.75,
		"ground": [{"offset_m": -40.0, "elev_m": 47.0}, {"offset_m": 0.0, "elev_m": 49.0},
				{"offset_m": 40.0, "elev_m": 51.0}, {"offset_m": 80.0, "elev_m": 53.0}]})
	assert_true(bool(res.get("ok", false)), "斜坡断面成功：" + String(res.get("error", "")))
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	assert_almost_eq(v["foot_right_dist_m"], 17.67441860465116, 1e-6, "右坡坡脚解析解")
	assert_almost_eq(v["foot_left_dist_m"], 20.54054054054054, 1e-6, "左坡坡脚解析解")
	# 坡脚地面高程 = 49+0.05x
	assert_almost_eq(v["foot_right_elev_m"], 49.0 + 0.05 * 17.67441860465116, 1e-6, "坡脚地面高程自洽")
	# 坡脚点在坡线上：z_edge − (x−b)/m == foot_ground
	var z_edge: float = v["edge_elev_m"]
	assert_almost_eq(z_edge - (v["foot_right_dist_m"] - 10.0) / 1.5, v["foot_right_elev_m"], 1e-6, "坡线方程自洽")

## 一侧填一侧挖（斜坡穿过设计线）：左填 12.112676 / 右挖 10.198675（Python 解析解）
func test_mixed_fill_cut() -> void:
	var res: Dictionary = Rd.forward({"design_elev_m": 50.5, "half_width_m": 10.0,
		"cross_slope_pct": 0.0, "fill_slope_ratio": 1.5, "cut_slope_ratio": 0.75,
		"ground": [{"offset_m": -40.0, "elev_m": 47.0}, {"offset_m": 0.0, "elev_m": 50.0},
				{"offset_m": 40.0, "elev_m": 53.0}]})
	assert_true(bool(res.get("ok", false)), "混合断面成功：" + String(res.get("error", "")))
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	assert_eq(v["mode_left"], "路堤填方", "左侧填方")
	assert_eq(v["mode_right"], "路堑挖方", "右侧挖方")
	assert_almost_eq(v["foot_left_dist_m"], 12.112676056338024, 1e-6, "左侧填方坡脚解析解")
	assert_almost_eq(v["foot_right_dist_m"], 10.198675496688743, 1e-6, "右侧挖方开挖口解析解")

## 错误路径：地面线不覆盖边坡范围
func test_error_paths() -> void:
	var e1: Dictionary = Rd.forward({"design_elev_m": 55.0, "half_width_m": 10.0,
		"fill_slope_ratio": 1.5, "cut_slope_ratio": 0.75,
		"ground": [{"offset_m": -12.0, "elev_m": 50.0}, {"offset_m": 12.0, "elev_m": 50.0}]})
	assert_false(bool(e1.get("ok", true)), "地面线不足应拒绝")
	assert_true(String(e1.get("error", "")).contains("坡脚解算失败"), "中文失败提示")
	var e2: Dictionary = Rd.forward({"design_elev_m": 55.0, "half_width_m": 10.0,
		"fill_slope_ratio": -1.5, "cut_slope_ratio": 0.75,
		"ground": [{"offset_m": -40.0, "elev_m": 50.0}, {"offset_m": 40.0, "elev_m": 50.0}]})
	assert_false(bool(e2.get("ok", true)), "坡率非法拒绝")
	var e3: Dictionary = Rd.forward({"design_elev_m": 55.0, "half_width_m": 10.0,
		"fill_slope_ratio": 1.5, "cut_slope_ratio": 0.75,
		"ground": [{"offset_m": 40.0, "elev_m": 50.0}, {"offset_m": -40.0, "elev_m": 50.0}]})
	assert_false(bool(e3.get("ok", true)), "地面线倒序拒绝")
