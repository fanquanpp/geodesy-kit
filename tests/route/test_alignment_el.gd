# tests/route/test_alignment_el.gd —— D2 线元法（D 组地基）：装配/正算/反算/采样
# 双路径互检（解析/级数公式链 vs 辛普森数值积分）为架构 §4 GK-M7 要求
extends "res://tests/test_case_base.gd"

const El := preload("res://core/route/alignment_el.gd")
const Sp := preload("res://core/route/spiral.gd")

const START := {"x_m": 1000.0, "y_m": 2000.0, "bearing_deg": 30.0, "chain_m": 0.0}

## 直线线元：正算坐标与方位
func test_line_element() -> void:
	var els := [El.make_line(200.0)]
	var res: Dictionary = El.point_at({"elements": els, "start": START, "chain_m": 100.0})
	assert_true(bool(res.get("ok", false)), "直线正算成功")
	if bool(res.get("ok", false)):
		var v: Dictionary = res["value"]
		assert_almost_eq(v["x_m"], 1000.0 + 100.0 * sin(deg_to_rad(30.0)), 1e-9, "直线 X=东")
		assert_almost_eq(v["y_m"], 2000.0 + 100.0 * cos(deg_to_rad(30.0)), 1e-9, "直线 Y=北")
		assert_almost_eq(v["bearing_deg"], 30.0, 1e-12, "直线方位不变")
	# 反算回收
	var inv: Dictionary = El.inverse({"elements": els, "start": START,
		"x_m": res["value"]["x_m"], "y_m": res["value"]["y_m"]})
	assert_almost_eq(inv["value"]["chain_m"], 100.0, 1e-6, "直线反算桩号回收")
	assert_almost_eq(inv["value"]["offset_m"], 0.0, 1e-9, "中桩偏距 0")

## 圆曲线线元：解析闭式与几何一致（终点半径矢量垂直于切线）
func test_arc_element() -> void:
	var els := [El.make_arc(500.0, 90.0)]
	assert_almost_eq(els[0]["len"], 500.0 * PI / 2.0, 1e-9, "弧长=R·α")
	var res: Dictionary = El.point_at({"elements": els, "start": START, "chain_m": 500.0 * PI / 2.0})
	assert_true(bool(res.get("ok", false)), "圆曲线终点定位成功")
	if bool(res.get("ok", false)):
		var v: Dictionary = res["value"]
		# 终点几何（x=东取 cos 差、y=北取 sin 差）：终点方位 120°
		# ΔE = (cosθ0 − cosθe)/k；ΔN = (sinθe − sinθ0)/k
		var x_expect := 1000.0 + 500.0 * (cos(deg_to_rad(30.0)) - cos(deg_to_rad(120.0)))
		var y_expect := 2000.0 + 500.0 * (sin(deg_to_rad(120.0)) - sin(deg_to_rad(30.0)))
		assert_almost_eq(v["x_m"], x_expect, 1e-9, "圆曲线终点 X（解析闭式）")
		assert_almost_eq(v["y_m"], y_expect, 1e-9, "圆曲线终点 Y")
		assert_almost_eq(v["bearing_deg"], 120.0, 1e-9, "终点方位 = 起点+90°")
		# 圆心距校验：|终点 − 圆心| = R；圆心 = 起点 + R·右法线
		var cx := 1000.0 + 500.0 * cos(deg_to_rad(30.0))
		var cy := 2000.0 - 500.0 * sin(deg_to_rad(30.0))
		var dd := sqrt(pow(float(v["x_m"]) - cx, 2.0) + pow(float(v["y_m"]) - cy, 2.0))
		assert_almost_eq(dd, 500.0, 1e-9, "|终点−圆心| = R")

## 广义缓和段：辛普森（生产）vs 级数公式链 双路径互检
func test_spiral_element_dual_path() -> void:
	var cases := [
		[0.0, 1.0 / 500.0, 60.0],   # 完整缓和曲线（0→1/R）
		[0.0, 1.0 / 300.0, 200.0],  # 大转角
		[1.0 / 400.0, 1.0 / 250.0, 80.0],  # 卵型段
		[1.0 / 200.0, 0.0, 60.0],   # 出口缓和段
	]
	for c: Array in cases:
		var k0: float = c[0]
		var k1: float = c[1]
		var ln: float = c[2]
		for frac in [0.3, 0.7, 1.0]:
			var s := ln * float(frac)
			var a: PackedFloat64Array = El.local_delta(deg_to_rad(30.0), k0, k1, ln, s)
			var b: PackedFloat64Array = El.local_delta_series(deg_to_rad(30.0), k0, k1, ln, s)
			assert_almost_eq(a[0], b[0], 1e-6, "Δn 双路径 k0=%s" % str(k0))
			assert_almost_eq(a[1], b[1], 1e-6, "Δe 双路径 k0=%s" % str(k0))

## D2 缓和段终点 == B4 回旋线内核终点（跨内核一致性）
func test_spiral_element_matches_spiral_kernel() -> void:
	var r := 500.0
	var l0 := 60.0
	var els := [El.make_spiral(0.0, r, l0, 1)]
	var res: Dictionary = El.point_at({"elements": els, "start": START, "chain_m": l0})
	var ker: PackedFloat64Array = Sp.point_integral(l0, r, l0)
	# 起点方位 30°：局部 (x', y') → 全局 = start + x'·(sin30, cos30) + y'·(cos30, −sin30)
	var th := deg_to_rad(30.0)
	var x_expect: float = 1000.0 + ker[0] * sin(th) + ker[1] * cos(th)
	var y_expect: float = 2000.0 + ker[0] * cos(th) - ker[1] * sin(th)
	assert_almost_eq(res["value"]["x_m"], x_expect, 1e-8, "D2 与 B4 内核 x 一致")
	assert_almost_eq(res["value"]["y_m"], y_expect, 1e-8, "D2 与 B4 内核 y 一致")
	assert_almost_eq(res["value"]["bearing_deg"], 30.0 + rad_to_deg(l0 / (2.0 * r)), 1e-9, "切线角 β0")

## 组合线元（直—缓—圆—缓）：接点连续 + 全长
func test_basic_type_assembly() -> void:
	var r := 500.0
	var l0 := 60.0
	var els := [
		El.make_line(100.0),
		El.make_spiral(0.0, r, l0, 1),
		El.make_arc(r, 30.0 - rad_to_deg(l0 / r)),
		El.make_spiral(r, 0.0, l0, 1),
	]
	var res: Dictionary = El.build({"elements": els, "start": START})
	assert_true(bool(res.get("ok", false)), "组合装配成功")
	if bool(res.get("ok", false)):
		var segs: Array = res["value"]["segs"]
		assert_int_eq(segs.size(), 4, "4 个线元")
		assert_almost_eq(res["value"]["total_len_m"], 100.0 + 500.0 * deg_to_rad(30.0) + l0, 1e-9, "全长 = 直线 + R·α + l0")
		for i in range(1, segs.size()):
			var p: Dictionary = segs[i - 1]
			var q: Dictionary = segs[i]
			assert_almost_eq(p["x1_m"], q["x0_m"], 1e-9, "接点 X 连续 (%d)" % i)
			assert_almost_eq(p["y1_m"], q["y0_m"], 1e-9, "接点 Y 连续 (%d)" % i)
			assert_almost_eq(p["bearing1_deg"], q["bearing0_deg"], 1e-9, "接点方位连续 (%d)" % i)

## 反算：偏距与桩号回收（右正左负）
func test_inverse_offset_and_chain() -> void:
	var els := [
		El.make_line(100.0),
		El.make_arc(500.0, 30.0),
	]
	var chain := 200.0
	var pt: Dictionary = El.point_at({"elements": els, "start": START, "chain_m": chain})
	var th := deg_to_rad(float(pt["value"]["bearing_deg"]))
	# 右偏 5m：右法线 = (cosθ, −sinθ)
	var pxr: float = pt["value"]["x_m"] + 5.0 * cos(th)
	var pyr: float = pt["value"]["y_m"] - 5.0 * sin(th)
	var invr: Dictionary = El.inverse({"elements": els, "start": START, "x_m": pxr, "y_m": pyr})
	assert_almost_eq(invr["value"]["chain_m"], chain, 1e-4, "右偏点桩号回收")
	assert_almost_eq(invr["value"]["offset_m"], 5.0, 1e-4, "右偏 +5")
	assert_eq(invr["value"]["offset_side"], "右侧", "右侧判定")
	# 左偏 8m
	var pxl: float = pt["value"]["x_m"] - 8.0 * cos(th)
	var pyl: float = pt["value"]["y_m"] + 8.0 * sin(th)
	var invl: Dictionary = El.inverse({"elements": els, "start": START, "x_m": pxl, "y_m": pyl})
	assert_almost_eq(invl["value"]["offset_m"], -8.0, 1e-4, "左偏 −8")
	assert_eq(invl["value"]["offset_side"], "左侧", "左侧判定")

## 大转角圆曲线反算（粗扫+黄金分割的稳健性）：转向 270°
func test_inverse_large_turn_arc() -> void:
	var els := [El.make_arc(80.0, 270.0)]
	var pt: Dictionary = El.point_at({"elements": els, "start": START, "chain_m": 80.0 * deg_to_rad(270.0) * 0.5})
	var inv: Dictionary = El.inverse({"elements": els, "start": START,
		"x_m": pt["value"]["x_m"], "y_m": pt["value"]["y_m"]})
	assert_almost_eq(inv["value"]["chain_m"], 80.0 * deg_to_rad(270.0) * 0.5, 1e-5, "270°圆曲线中点反算回收")

## 采样：首尾必含、步距正确
func test_sample() -> void:
	var els := [El.make_line(100.0), El.make_arc(500.0, 10.0)]
	var res: Dictionary = El.sample({"elements": els, "start": START, "step_m": 20.0})
	assert_true(bool(res.get("ok", false)), "采样成功")
	if bool(res.get("ok", false)):
		var v: Dictionary = res["value"]
		assert_int_eq(int(v["chains_m"][0]), 0, "首桩 0")
		var total: float = v["total_len_m"]
		assert_almost_eq(float(v["chains_m"][v["chains_m"].size() - 1]), total, 1e-9, "末桩=全长")
		assert_int_eq(int(v["count"]), int(floor(total / 20.0)) + 1, "点数 = floor(L/step)+1")

## 里程越界与非法输入的中文错误
func test_error_paths() -> void:
	var els := [El.make_line(100.0)]
	var e1: Dictionary = El.point_at({"elements": els, "start": START, "chain_m": 150.0})
	assert_false(bool(e1.get("ok", true)), "越界里程拒绝")
	assert_true(String(e1.get("error", "")).contains("超出路线范围"), "越界中文提示")
	var e2: Dictionary = El.build({"elements": [], "start": START})
	assert_false(bool(e2.get("ok", true)), "空线元拒绝")
	var e3: Dictionary = El.build({"elements": els, "start": {"x_m": 1.0, "y_m": 2.0}})
	assert_false(bool(e3.get("ok", true)), "start 缺方位拒绝")
	var e4: Dictionary = El.build({"elements": [{"type": "line", "len": -5.0, "k0": 0.0, "k1": 0.0}], "start": START})
	assert_false(bool(e4.get("ok", true)), "负长度线元拒绝")
	var e5: Dictionary = El.build({"elements": [{"type": "arc", "len": 50.0}], "start": START})
	assert_false(bool(e5.get("ok", true)), "arc 缺曲率拒绝")
	assert_almost_eq(El.turn_total_rad(els), 0.0, 1e-12, "直线总转角 0")
	assert_almost_eq(El.turn_total_rad([El.make_arc(500.0, 30.0)]), deg_to_rad(30.0), 1e-12, "圆曲线总转角")
