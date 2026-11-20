# tests/route/test_stakeout.gd —— D4 中边桩坐标与极坐标放样（构造自洽）
# 自洽口径：中桩坐标与 D2 正算一致、边桩距中桩=偏距且沿右法线方向、
# 极坐标放样角 = 方位(测站→点) − 后视方位（解析可验）
extends "res://tests/test_case_base.gd"

const So := preload("res://core/route/stakeout.gd")
const El := preload("res://core/route/alignment_el.gd")

const START := {"x_m": 1000.0, "y_m": 2000.0, "bearing_deg": 0.0, "chain_m": 0.0}
# 路线：直线 100 + 右转圆曲线 R=400 转 60°
static func _els() -> Array:
	return [El.make_line(100.0), El.make_arc(400.0, 60.0)]

## 中桩坐标：与线元正算一致
func test_center_stake_matches_point_at() -> void:
	var res: Dictionary = So.forward({"elements": _els(), "start": START,
		"stakes": [{"chain_m": 50.0}, {"chain_m": 150.0}]})
	assert_true(bool(res.get("ok", false)), "放样计算成功：" + String(res.get("error", "")))
	if not bool(res.get("ok", false)):
		return
	var stakes: Array = res["value"]["stakes"]
	assert_int_eq(stakes.size(), 2, "两个中桩")
	var p50: Dictionary = El.point_at({"elements": _els(), "start": START, "chain_m": 50.0})
	assert_almost_eq(stakes[0]["x_m"], p50["value"]["x_m"], 1e-9, "中桩50 坐标一致 X")
	assert_almost_eq(stakes[0]["y_m"], p50["value"]["y_m"], 1e-9, "中桩50 坐标一致 Y")
	assert_almost_eq(stakes[0]["offset_m"], 0.0, 1e-12, "中桩偏距 0")
	# 直线段中桩：起点方位 0°（向北）→ X 不变、Y 增
	assert_almost_eq(stakes[0]["x_m"], 1000.0, 1e-9, "向北直线 X 不变")
	assert_almost_eq(stakes[0]["y_m"], 2050.0, 1e-9, "向北直线 Y=2050")

## 边桩：距中桩=偏距、位于右/左法线方向
func test_side_stakes() -> void:
	var chain := 150.0
	var res: Dictionary = So.forward({"elements": _els(), "start": START,
		"stakes": [{"chain_m": chain, "offset_m": 8.0}, {"chain_m": chain, "offset_m": -5.0}]})
	assert_true(bool(res.get("ok", false)), "边桩计算成功")
	if bool(res.get("ok", false)):
		var stakes: Array = res["value"]["stakes"]
		var pc: Dictionary = El.point_at({"elements": _els(), "start": START, "chain_m": chain})
		var th := deg_to_rad(float(pc["value"]["bearing_deg"]))
		# 右偏 +8
		assert_almost_eq(stakes[0]["x_m"], float(pc["value"]["x_m"]) + 8.0 * cos(th), 1e-9, "右边桩 X = 中桩+8·cosθ")
		assert_almost_eq(stakes[0]["y_m"], float(pc["value"]["y_m"]) - 8.0 * sin(th), 1e-9, "右边桩 Y = 中桩−8·sinθ")
		# 距离校验
		var dd := sqrt(pow(stakes[0]["x_m"] - float(pc["value"]["x_m"]), 2.0) + pow(stakes[0]["y_m"] - float(pc["value"]["y_m"]), 2.0))
		assert_almost_eq(dd, 8.0, 1e-9, "边桩距中桩 8 m")
		# 左偏 −5
		assert_almost_eq(stakes[1]["x_m"], float(pc["value"]["x_m"]) - 5.0 * cos(th), 1e-9, "左边桩 X")
		assert_almost_eq(stakes[1]["y_m"], float(pc["value"]["y_m"]) + 5.0 * sin(th), 1e-9, "左边桩 Y")

## 极坐标放样：平距与放样角解析可验
func test_polar_stakeout() -> void:
	var st := {"x_m": 1100.0, "y_m": 2100.0}
	var backsight_bearing := 270.0
	var res: Dictionary = So.forward({"elements": _els(), "start": START,
		"stakes": [{"chain_m": 50.0}], "station": st, "backsight_bearing_deg": backsight_bearing})
	assert_true(bool(res.get("ok", false)), "极坐标放样成功：" + String(res.get("error", "")))
	if bool(res.get("ok", false)):
		var s: Dictionary = res["value"]["stakes"][0]
		var px: float = s["x_m"]
		var py: float = s["y_m"]
		var dist_expect := sqrt(pow(px - 1100.0, 2.0) + pow(py - 2100.0, 2.0))
		assert_almost_eq(s["dist_m"], dist_expect, 1e-9, "平距 = |测站−点|")
		var az := GKAngles.azimuth(px - 1100.0, py - 2100.0)
		var beta_expect: float = GKAngles.normalize_deg(az - backsight_bearing)
		assert_almost_eq(s["beta_deg"], beta_expect, 1e-9, "放样角 = 方位差")
		assert_almost_eq(res["value"]["backsight_bearing_deg"], 270.0, 1e-12, "后视方位回显")

## 后视点形式（坐标后视）
func test_backsight_point_form() -> void:
	var st := {"x_m": 1100.0, "y_m": 2100.0}
	var bs := {"x_m": 1100.0, "y_m": 2200.0}  # 正北 → 后视方位 0°
	var res: Dictionary = So.forward({"elements": _els(), "start": START,
		"stakes": [{"chain_m": 50.0}], "station": st, "backsight": bs})
	assert_true(bool(res.get("ok", false)), "坐标后视成功")
	if bool(res.get("ok", false)):
		assert_almost_eq(res["value"]["backsight_bearing_deg"], 0.0, 1e-12, "正北后视方位 0°")

## 错误路径
func test_error_paths() -> void:
	var e1: Dictionary = So.forward({"elements": _els(), "start": START, "stakes": []})
	assert_false(bool(e1.get("ok", true)), "空桩列表拒绝")
	var e2: Dictionary = So.forward({"elements": _els(), "start": START,
		"stakes": [{"chain_m": 9999.0}]})
	assert_false(bool(e2.get("ok", true)), "桩号越界拒绝")
	var e3: Dictionary = So.forward({"elements": _els(), "start": START,
		"stakes": [{"chain_m": 50.0}], "station": {"x_m": 1100.0, "y_m": 2100.0}})
	assert_false(bool(e3.get("ok", true)), "测站无后视拒绝")
	assert_true(String(e3.get("error", "")).contains("后视"), "缺后视中文提示")
