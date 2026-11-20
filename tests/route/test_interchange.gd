# tests/route/test_interchange.gd —— D6 匝道复杂线型（C型/S型/卵型/回头 = 线元组合）
# 自洽判据：总转角解析式 == 分段转角和（核心内已检）、接点曲率连续、
# 卵型半径衔接、S/C 型曲率零点衔接、往返闭合、回头曲线总转角>180°
extends "res://tests/test_case_base.gd"

const Ic := preload("res://core/route/interchange.gd")
const El := preload("res://core/route/alignment_el.gd")

const START := {"x_m": 1000.0, "y_m": 2000.0, "bearing_deg": 10.0, "chain_m": 0.0}

## 基本型：与 B3 权威向量闭合（R=500, l0=60, α=30° → L=321.7994）
func test_basic_matches_b3() -> void:
	var res: Dictionary = Ic.basic({"r_m": 500.0, "l0_m": 60.0, "alpha_deg": 30.0, "dir": 1, "start": START})
	assert_true(bool(res.get("ok", false)), "基本型成功：" + String(res.get("error", "")))
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	assert_almost_eq(v["total_len_m"], 321.7994, 1e-3, "全长 = B3 权威 L")
	assert_almost_eq(v["total_turn_deg"], 30.0, 1e-9, "总转角 = α")
	assert_int_eq(int(v["element_count"]), 3, "缓—圆—缓 三线元")
	var els: Array = v["elements"]
	assert_almost_eq(float(els[0]["k1"]), 1.0 / 500.0, 1e-12, "进缓和段曲率终值 1/R")

## S型：反向回旋线曲率零点衔接 + 总转角解析式
func test_s_type() -> void:
	var r1 := 400.0
	var r2 := 300.0
	var l01 := 80.0
	var l02 := 70.0
	var b1 := 40.0
	var b2 := 35.0
	var res: Dictionary = Ic.s_type({"r1_m": r1, "r2_m": r2, "l01_m": l01, "l02_m": l02,
		"arc1_turn_deg": b1, "arc2_turn_deg": b2, "dir": 1, "start": START})
	assert_true(bool(res.get("ok", false)), "S型成功：" + String(res.get("error", "")))
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	var els: Array = v["elements"]
	assert_int_eq(int(v["element_count"]), 4, "圆—缓—缓—圆 四线元")
	# 曲率零点衔接：k(1)=0 → 0；转向相反
	assert_almost_eq(float(els[1]["k1"]), 0.0, 1e-15, "S型回旋1 出口曲率 0")
	assert_almost_eq(float(els[2]["k0"]), 0.0, 1e-15, "S型回旋2 入口曲率 0")
	assert_almost_eq(float(els[2]["k1"]), -1.0 / r2, 1e-12, "回旋2 反向曲率 −1/R2")
	# 总转角解析式：β1 + l01/(2r1) − l02/(2r2) − β2（弧度→度）
	var expect := b1 + rad_to_deg(l01 / (2.0 * r1)) - rad_to_deg(l02 / (2.0 * r2)) - b2
	assert_almost_eq(v["total_turn_deg"], expect, 1e-9, "S型总转角解析式")
	# 往返回收
	var chain := float(v["total_len_m"]) * 0.4
	var pt: Dictionary = El.point_at({"elements": els, "start": START, "chain_m": chain})
	var inv: Dictionary = El.inverse({"elements": els, "start": START,
		"x_m": pt["value"]["x_m"], "y_m": pt["value"]["y_m"]})
	assert_almost_eq(inv["value"]["chain_m"], chain, 1e-5, "S型反算往返")

## 卵型：R1>R2、曲率连续过渡
func test_egg_type() -> void:
	var res: Dictionary = Ic.egg({"r1_m": 500.0, "r2_m": 200.0, "l0_m": 100.0,
		"arc1_turn_deg": 30.0, "arc2_turn_deg": 40.0, "dir": 1, "start": START})
	assert_true(bool(res.get("ok", false)), "卵型成功：" + String(res.get("error", "")))
	if not bool(res.get("ok", false)):
		return
	var els: Array = res["value"]["elements"]
	assert_int_eq(els.size(), 3, "圆—缓—圆 三线元")
	assert_almost_eq(float(els[0]["k0"]), 1.0 / 500.0, 1e-12, "大圆曲率")
	assert_almost_eq(float(els[1]["k0"]), 1.0 / 500.0, 1e-12, "回旋线入口曲率 = 1/R1")
	assert_almost_eq(float(els[1]["k1"]), 1.0 / 200.0, 1e-12, "回旋线出口曲率 = 1/R2")
	assert_almost_eq(float(els[2]["k1"]), 1.0 / 200.0, 1e-12, "小圆曲率")
	var expect := 30.0 + rad_to_deg(100.0 * (0.5 / 500.0 + 0.5 / 200.0)) + 40.0
	assert_almost_eq(res["value"]["total_turn_deg"], expect, 1e-9, "卵型总转角 = β1 + ∫k + β2")
	# R2 ≥ R1 拒绝
	var bad: Dictionary = Ic.egg({"r1_m": 200.0, "r2_m": 500.0, "l0_m": 100.0,
		"arc1_turn_deg": 30.0, "arc2_turn_deg": 40.0, "dir": 1, "start": START})
	assert_false(bool(bad.get("ok", true)), "卵型 R2≥R1 拒绝")
	assert_true(String(bad.get("error", "")).contains("卵型要求大圆半径"), "卵型半径条件中文提示")

## C型：同向回旋线曲率零点衔接（可夹短直线）
func test_c_type() -> void:
	var res: Dictionary = Ic.c_type({"r1_m": 400.0, "r2_m": 350.0, "l01_m": 70.0, "l02_m": 60.0,
		"arc1_turn_deg": 30.0, "arc2_turn_deg": 25.0, "dir": 1, "start": START})
	assert_true(bool(res.get("ok", false)), "C型成功：" + String(res.get("error", "")))
	if bool(res.get("ok", false)):
		var els: Array = res["value"]["elements"]
		assert_int_eq(els.size(), 4, "无夹直线：圆—缓—缓—圆")
		assert_almost_eq(float(els[1]["k1"]), 0.0, 1e-15, "C型回旋1 出口曲率 0")
		assert_almost_eq(float(els[2]["k0"]), 0.0, 1e-15, "C型回旋2 入口曲率 0")
		assert_almost_eq(float(els[2]["k1"]), 1.0 / 350.0, 1e-12, "同向曲率 +1/R2")
	# 带夹短直线
	var res2: Dictionary = Ic.c_type({"r1_m": 400.0, "r2_m": 350.0, "l01_m": 70.0, "l02_m": 60.0,
		"arc1_turn_deg": 30.0, "arc2_turn_deg": 25.0, "straight_m": 30.0, "dir": 1, "start": START})
	assert_true(bool(res2.get("ok", false)), "C型带夹直线成功")
	if bool(res2.get("ok", false)):
		assert_int_eq(int(res2["value"]["element_count"]), 5, "含夹直线 5 线元")
		var expect: float = 30.0 + rad_to_deg(70.0 / 800.0) + rad_to_deg(60.0 / 700.0) + 25.0
		assert_almost_eq(res2["value"]["total_turn_deg"], expect, 1e-9, "C型总转角（夹直线不转角）")

## 回头曲线：转角>180°、总长 = R·α + l0、不输出 T/E
func test_hairpin() -> void:
	var res: Dictionary = Ic.hairpin({"r_m": 100.0, "l0_m": 40.0, "alpha_deg": 210.0, "dir": -1, "start": START})
	assert_true(bool(res.get("ok", false)), "回头曲线成功：" + String(res.get("error", "")))
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	assert_almost_eq(v["total_turn_deg"], -210.0, 1e-9, "左回头总转角 −210°")
	assert_almost_eq(v["total_len_m"], 100.0 * deg_to_rad(210.0) + 40.0, 1e-9, "全长 = R·α + l0")
	assert_false(v.has("t_m"), "回头曲线不输出 T（交点法失效）")
	# 回头终点位于起点"后方"：终点切线方位 = 10° − 210° = −200° ≡ 160°（线元表方位连续累计不规范化）
	var segs: Array = v["segs"]
	assert_almost_eq(GKAngles.normalize_deg(float(segs[segs.size() - 1]["bearing1_deg"])), 160.0, 1e-6, "终点切线方位 160°")
	# 往返回收（大转角反算稳健性）
	var chain := float(v["total_len_m"]) * 0.55
	var pt: Dictionary = El.point_at({"elements": v["elements"], "start": START, "chain_m": chain})
	var inv: Dictionary = El.inverse({"elements": v["elements"], "start": START,
		"x_m": pt["value"]["x_m"], "y_m": pt["value"]["y_m"]})
	assert_almost_eq(inv["value"]["chain_m"], chain, 1e-5, "回头曲线反算往返")
	# 转角不足 180° 拒绝
	var bad: Dictionary = Ic.hairpin({"r_m": 100.0, "l0_m": 40.0, "alpha_deg": 150.0, "dir": 1, "start": START})
	assert_false(bool(bad.get("ok", true)), "回头曲线 |α|≤180° 拒绝")

## 错误路径
func test_error_paths() -> void:
	var e1: Dictionary = Ic.basic({"r_m": 500.0, "l0_m": 60.0, "alpha_deg": 200.0, "dir": 1, "start": START})
	assert_false(bool(e1.get("ok", true)), "基本型 α≥180° 拒绝（应用回头曲线）")
	var e2: Dictionary = Ic.s_type({"r1_m": -400.0, "r2_m": 300.0, "l01_m": 80.0, "l02_m": 70.0,
		"arc1_turn_deg": 40.0, "arc2_turn_deg": 35.0, "dir": 1, "start": START})
	assert_false(bool(e2.get("ok", true)), "负半径拒绝")
	var e3: Dictionary = Ic.basic({"r_m": 500.0, "l0_m": 60.0, "alpha_deg": 30.0})
	assert_false(bool(e3.get("ok", true)), "缺 start 拒绝")
