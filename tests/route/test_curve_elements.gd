# tests/route/test_curve_elements.gd —— B3 圆曲线要素（含缓和曲线对称基本型）
# 向量来源：ARCHITECTURE.md §4 GK-M7【权威·教材通用公式，两公式路径复算一致】三组
extends "res://tests/test_case_base.gd"

const Cur := preload("res://core/route/curve_elements.gd")

## 权威向量组1：R=500, l0=60, α=30°
func test_vector_authoritative_1() -> void:
	var res: Dictionary = Cur.forward({"r_m": 500.0, "l0_m": 60.0, "alpha_deg": 30.0})
	assert_true(bool(res.get("ok", false)), "应计算成功")
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	assert_almost_eq(v["beta0_deg"], 3.4377468, 1e-6, "β0")
	assert_almost_eq(v["m_m"], 29.9964, 1e-3, "m 切线增长值")
	assert_almost_eq(v["p_m"], 0.3000, 1e-3, "p 内移值")
	assert_almost_eq(v["t_m"], 164.0514, 1e-3, "T")
	assert_almost_eq(v["l_m"], 321.7994, 1e-3, "L")
	assert_almost_eq(v["e_m"], 17.9486, 1e-3, "E")
	assert_almost_eq(v["q_m"], 6.3034, 1e-3, "q")
	assert_almost_eq(v["x0_m"], 59.9784, 1e-3, "x0")
	assert_almost_eq(v["y0_m"], 1.1997, 1e-3, "y0")

## 权威向量组2：R=1000, l0=100, α=45°
func test_vector_authoritative_2() -> void:
	var res: Dictionary = Cur.forward({"r_m": 1000.0, "l0_m": 100.0, "alpha_deg": 45.0})
	assert_true(bool(res.get("ok", false)), "应计算成功")
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	assert_almost_eq(v["beta0_deg"], 2.8647890, 1e-6, "β0")
	assert_almost_eq(v["m_m"], 49.9958, 1e-3, "m")
	assert_almost_eq(v["p_m"], 0.4166, 1e-3, "p")
	assert_almost_eq(v["t_m"], 464.3820, 1e-3, "T")
	assert_almost_eq(v["l_m"], 885.3982, 1e-3, "L")
	assert_almost_eq(v["e_m"], 82.8432, 1e-3, "E")
	assert_almost_eq(v["q_m"], 43.3658, 1e-3, "q")
	assert_almost_eq(v["x0_m"], 99.9750, 1e-3, "x0")
	assert_almost_eq(v["y0_m"], 1.6664, 1e-3, "y0")

## 权威向量组3：R=600, l0=120, α=25°30′
func test_vector_authoritative_3() -> void:
	var res: Dictionary = Cur.forward({"r_m": 600.0, "l0_m": 120.0, "alpha_deg": 25.5})
	assert_true(bool(res.get("ok", false)), "应计算成功")
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	assert_almost_eq(v["beta0_deg"], 5.7295780, 1e-6, "β0")
	assert_almost_eq(v["m_m"], 59.9800, 1e-3, "m")
	assert_almost_eq(v["p_m"], 0.9996, 1e-3, "p")
	assert_almost_eq(v["t_m"], 195.9723, 1e-3, "T")
	assert_almost_eq(v["l_m"], 387.0354, 1e-3, "L")
	assert_almost_eq(v["e_m"], 16.1935, 1e-3, "E")
	assert_almost_eq(v["q_m"], 4.9093, 1e-3, "q")
	assert_almost_eq(v["x0_m"], 119.8800, 1e-3, "x0")
	assert_almost_eq(v["y0_m"], 3.9971, 1e-3, "y0")

## l0=0 退化为纯圆曲线：T=R·tan(α/2)，L=R·α，E=R(sec(α/2)−1)，q=2T−L
func test_pure_circular() -> void:
	var res: Dictionary = Cur.forward({"r_m": 500.0, "l0_m": 0.0, "alpha_deg": 40.0})
	assert_true(bool(res.get("ok", false)), "纯圆曲线应成功")
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	var t_expect: float = 500.0 * tan(deg_to_rad(20.0))
	assert_almost_eq(v["t_m"], t_expect, 1e-9, "T=R·tan(α/2)")
	assert_almost_eq(v["l_m"], 500.0 * deg_to_rad(40.0), 1e-9, "L=R·α")
	assert_almost_eq(v["e_m"], 500.0 / cos(deg_to_rad(20.0)) - 500.0, 1e-9, "E=R(sec−1)")
	assert_almost_eq(v["q_m"], 2.0 * t_expect - 500.0 * deg_to_rad(40.0), 1e-9, "q=2T−L")
	assert_false(v.has("x0_m"), "纯圆曲线无 x0/y0")
	# 主点 ZY/QZ/YZ
	var r2: Dictionary = Cur.forward({"r_m": 500.0, "l0_m": 0.0, "alpha_deg": 40.0, "jd_chain_m": 2000.0})
	var v2: Dictionary = r2["value"]
	assert_almost_eq(v2["zy_m"], 2000.0 - t_expect, 1e-9, "ZY=JD−T")
	assert_almost_eq(v2["qz_m"], 2000.0 - t_expect + 0.5 * 500.0 * deg_to_rad(40.0), 1e-9, "QZ")
	assert_almost_eq(v2["yz_m"], 2000.0 - t_expect + 500.0 * deg_to_rad(40.0), 1e-9, "YZ")

## 主点里程（含缓和曲线）：ZH/HY/QZ/YZ/HZ
func test_main_chains_with_spiral() -> void:
	var res: Dictionary = Cur.forward({"r_m": 500.0, "l0_m": 60.0, "alpha_deg": 30.0, "jd_chain_m": 1234.5})
	assert_true(bool(res.get("ok", false)), "应成功")
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	var t: float = v["t_m"]
	var l: float = v["l_m"]
	assert_almost_eq(v["zh_m"], 1234.5 - t, 1e-9, "ZH=JD−T")
	assert_almost_eq(v["hy_m"], 1234.5 - t + 60.0, 1e-9, "HY=ZH+l0")
	assert_almost_eq(v["qz_m"], 1234.5 - t + l / 2.0, 1e-9, "QZ")
	assert_almost_eq(v["yz_m"], 1234.5 - t + l - 60.0, 1e-9, "YZ")
	assert_almost_eq(v["hz_m"], 1234.5 - t + l, 1e-9, "HZ")

## 纯核 elements 与协议 forward 一致
func test_core_elements_matches_forward() -> void:
	var el: Dictionary = Cur.elements(500.0, 60.0, deg_to_rad(30.0))
	assert_false(el.is_empty(), "elements 核应非空")
	assert_almost_eq(el["t_m"], 164.0514, 1e-3, "核心 T 与权威向量一致")
	var ch: PackedFloat64Array = Cur.main_chains(1234.5, el["t_m"], el["l_m"], 60.0)
	assert_int_eq(ch.size(), 5, "5 个主点")

## 错误路径：中文错误、ok=false
func test_error_paths() -> void:
	var r1: Dictionary = Cur.forward({"r_m": 500.0, "l0_m": 60.0, "alpha_deg": 185.0})
	assert_false(bool(r1.get("ok", true)), "α≥180° 应拒绝")
	assert_true(String(r1.get("error", "")).contains("180"), "中文错误提示含角度原因")
	var r2: Dictionary = Cur.forward({"r_m": 500.0, "l0_m": 60.0, "alpha_deg": 3.0})
	assert_false(bool(r2.get("ok", true)), "l0 过长应拒绝")
	assert_true(String(r2.get("error", "")).contains("缓和曲线过长"), "提示 2β0≥α")
	var r3: Dictionary = Cur.forward({"r_m": -5.0, "l0_m": 60.0, "alpha_deg": 30.0})
	assert_false(bool(r3.get("ok", true)), "R≤0 应拒绝")
	var r4: Dictionary = Cur.forward({"r_m": 500.0, "alpha_deg": "abc"})
	assert_false(bool(r4.get("ok", true)), "非数字输入应拒绝")
	var r5: Dictionary = Cur.forward({})
	assert_false(bool(r5.get("ok", true)), "空输入应拒绝")
