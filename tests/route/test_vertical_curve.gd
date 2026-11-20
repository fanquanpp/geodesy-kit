# tests/route/test_vertical_curve.gd —— D3 竖曲线
# 向量来源：ARCHITECTURE.md §4 GK-M7【构造·本会话】
# g1=+3%、g2=−2%、L=400、PVI(1000,100)→BVC(800,94.000)、EVC 96.000、
# 中点 97.5000、E=−2.500、桩900=96.3750
extends "res://tests/test_case_base.gd"

const Vc := preload("res://core/route/vertical_curve.gd")

## 权威向量
func test_vector_authoritative() -> void:
	var res: Dictionary = Vc.forward({"g1_pct": 3.0, "g2_pct": -2.0, "l_m": 400.0,
		"pvi_chain_m": 1000.0, "pvi_elev_m": 100.0, "stakes_m": [900.0]})
	assert_true(bool(res.get("ok", false)), "应计算成功：" + String(res.get("error", "")))
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	assert_almost_eq(v["bvc_chain_m"], 800.0, 1e-9, "BVC 桩号 800")
	assert_almost_eq(v["bvc_elev_m"], 94.000, 1e-9, "BVC 高程 94.000")
	assert_almost_eq(v["evc_chain_m"], 1200.0, 1e-9, "EVC 桩号 1200")
	assert_almost_eq(v["evc_elev_m"], 96.000, 1e-9, "EVC 高程 96.000")
	assert_almost_eq(v["mid_elev_m"], 97.5000, 1e-9, "中点 97.5000")
	assert_almost_eq(v["e_m"], -2.500, 1e-9, "外距 E=−2.500（凸为负）")
	assert_almost_eq(float(v["elevs_m"][0]), 96.3750, 1e-9, "桩900 高程 96.3750")
	assert_eq(v["shape"], "凸形", "g2<g1 → 凸形")
	# K 值：L/|Δg(%)| = 400/5 = 80
	assert_almost_eq(v["k_m_per_pct"], 80.0, 1e-9, "K = L/|Δg%| = 80")

## 纯核 elev_at 与协议一致；切线对照
func test_core_elev_at() -> void:
	var y0: float = Vc.elev_at(0.0, 94.0, 0.03, -0.02, 400.0)
	assert_almost_eq(y0, 94.0, 1e-12, "x=0 → BVC 高程")
	var yend: float = Vc.elev_at(400.0, 94.0, 0.03, -0.02, 400.0)
	assert_almost_eq(yend, 96.0, 1e-12, "x=L → EVC 高程")
	# 竖曲线起点/终点处斜率：1m 步长的解析值（含曲率项）
	# e(x+1)−e(x) = g1 + (g2−g1)(2x+1)/(2L)：x=0 → 0.03 − 0.05/800；x=399 → 0.03 − 0.05·799/800
	var e0 := Vc.elev_at(0.0, 94.0, 0.03, -0.02, 400.0)
	var e1 := Vc.elev_at(1.0, 94.0, 0.03, -0.02, 400.0)
	assert_almost_eq(e1 - e0, 0.03 + (-0.05) / 800.0, 1e-12, "起点 1m 割线斜率（解析）")
	var e399 := Vc.elev_at(399.0, 94.0, 0.03, -0.02, 400.0)
	var e400 := Vc.elev_at(400.0, 94.0, 0.03, -0.02, 400.0)
	assert_almost_eq(e400 - e399, 0.03 + (-0.05) * 799.0 / 800.0, 1e-12, "终点 1m 割线斜率（解析）")

## 凹形竖曲线：E 为正
func test_sag_curve() -> void:
	var res: Dictionary = Vc.forward({"g1_pct": -2.0, "g2_pct": 3.0, "l_m": 300.0,
		"pvi_chain_m": 500.0, "pvi_elev_m": 50.0})
	assert_true(bool(res.get("ok", false)), "凹形计算成功")
	if bool(res.get("ok", false)):
		var v: Dictionary = res["value"]
		assert_almost_eq(v["e_m"], 300.0 * 0.05 / 8.0, 1e-12, "凹形 E=+1.875")
		assert_eq(v["shape"], "凹形", "凹形判定")
		assert_almost_eq(v["bvc_elev_m"], 50.0 + 0.02 * 150.0, 1e-12, "凹形 BVC 高程")

## 多桩号查询
func test_multiple_stakes() -> void:
	var res: Dictionary = Vc.forward({"g1_pct": 3.0, "g2_pct": -2.0, "l_m": 400.0,
		"pvi_chain_m": 1000.0, "pvi_elev_m": 100.0, "stakes_m": [800.0, 1000.0, 1200.0]})
	var v: Dictionary = res["value"]
	assert_almost_eq(float(v["elevs_m"][0]), 94.0, 1e-9, "BVC 处 = 切线")
	# PVI 桩号处曲线高程 = 100 − 2.5 = 97.5（E 的定义）
	assert_almost_eq(float(v["elevs_m"][1]), 97.5, 1e-9, "PVI 桩号曲线高程 = PVI+E")
	assert_almost_eq(float(v["elevs_m"][2]), 96.0, 1e-9, "EVC 处 = 切线")

## 错误路径
func test_error_paths() -> void:
	var e1: Dictionary = Vc.forward({"g1_pct": 3.0, "g2_pct": -2.0, "l_m": 0.0,
		"pvi_chain_m": 1000.0, "pvi_elev_m": 100.0})
	assert_false(bool(e1.get("ok", true)), "L=0 拒绝")
	var e2: Dictionary = Vc.forward({"g1_pct": 3.0, "g2_pct": -2.0, "l_m": 400.0,
		"pvi_chain_m": 1000.0, "pvi_elev_m": 100.0, "stakes_m": [500.0]})
	assert_false(bool(e2.get("ok", true)), "桩号超范围拒绝")
	assert_true(String(e2.get("error", "")).contains("超出竖曲线范围"), "越界中文提示")
	var e3: Dictionary = Vc.forward({"g1_pct": "x", "g2_pct": -2.0, "l_m": 400.0,
		"pvi_chain_m": 1000.0, "pvi_elev_m": 100.0})
	assert_false(bool(e3.get("ok", true)), "非数字坡度拒绝")
