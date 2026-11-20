# tests/route/test_segment_link.gd —— D5 断链往返换算 + 超高/加宽线性过渡（构造自洽）
# 断链口径（core/route/segment_link.gd 头注）：断链值 Δ=后桩号−前桩号，
# Δ<0 长链（桩号重复）、Δ>0 短链（桩号跳过）；断链前后桩号指同一物理点；
# 往返换算闭合 + 断点两侧桩号映射到同一实际里程 = 本文件判据。
extends "res://tests/test_case_base.gd"

const Sl := preload("res://core/route/segment_link.gd")

## 短链：前5000 / 后5200（Δ=+200，桩号跳过）
func test_short_chain() -> void:
	var br := [{"before_chain_m": 5000.0, "after_chain_m": 5200.0}]
	var res: Dictionary = Sl.chain_convert({"breaks": br,
		"chains_m": [4900.0, 5000.0, 5200.0, 5300.0, 8000.0], "direction": "d2a"})
	assert_true(bool(res.get("ok", false)), "短链换算成功：" + String(res.get("error", "")))
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	var out: PackedFloat64Array = v["chains_out_m"]
	assert_almost_eq(out[0], 4900.0, 1e-9, "断链前里程不变")
	assert_almost_eq(out[1], 5000.0, 1e-9, "断链前桩号 a → 实际 A=5000")
	assert_almost_eq(out[2], 5000.0, 1e-9, "断链后桩号 b → 同一物理点实际 A=5000")
	assert_almost_eq(out[3], 5100.0, 1e-9, "断链后 5300 → 5100（修正 −200）")
	assert_almost_eq(out[4], 7800.0, 1e-9, "8000 → 7800")
	assert_eq(String(v["breaks"][0]["kind"]), "短链（桩号跳过）", "短链判定")
	# 反向：实际 → 设计
	var back: Dictionary = Sl.chain_convert({"breaks": br,
		"chains_m": [4900.0, 5100.0, 7800.0, 5000.0], "direction": "a2d"})
	var bout: PackedFloat64Array = back["value"]["chains_out_m"]
	assert_almost_eq(bout[0], 4900.0, 1e-9, "a2d 断链前不变")
	assert_almost_eq(bout[1], 5300.0, 1e-9, "实际5100 → 设计5300")
	assert_almost_eq(bout[2], 8000.0, 1e-9, "实际7800 → 设计8000")
	assert_almost_eq(bout[3], 5000.0, 1e-9, "断点实际里程 → 前桩号 a（首次出现约定）")

## 长链：前6000 / 后5800（Δ=−200，桩号重复）
func test_long_chain() -> void:
	var br := [{"before_chain_m": 6000.0, "after_chain_m": 5800.0}]
	var res: Dictionary = Sl.chain_convert({"breaks": br,
		"chains_m": [5900.0, 6000.0, 5800.0, 6100.0], "direction": "d2a"})
	assert_true(bool(res.get("ok", false)), "长链换算成功：" + String(res.get("error", "")))
	if not bool(res.get("ok", false)):
		return
	var out: PackedFloat64Array = res["value"]["chains_out_m"]
	assert_almost_eq(out[0], 5900.0, 1e-9, "重复区首次出现：5900 保持不变")
	assert_almost_eq(out[1], 6000.0, 1e-9, "断链前桩号 6000 → 实际 6000")
	assert_almost_eq(out[2], 6000.0, 1e-9, "断链后桩号 5800 → 同一物理点 6000")
	assert_almost_eq(out[3], 6300.0, 1e-9, "6100 → 6300（长链修正 +200）")
	assert_eq(String(res["value"]["breaks"][0]["kind"]), "长链（桩号重复）", "长链判定")
	var back: Dictionary = Sl.chain_convert({"breaks": br,
		"chains_m": [6300.0, 5900.0, 6000.0], "direction": "a2d"})
	var bout: PackedFloat64Array = back["value"]["chains_out_m"]
	assert_almost_eq(bout[0], 6100.0, 1e-9, "实际6300 → 设计6100")
	assert_almost_eq(bout[1], 5900.0, 1e-9, "实际5900 → 设计5900（重复区）")
	assert_almost_eq(bout[2], 6000.0, 1e-9, "实际6000 → 设计6000")

## 多断链混合（短链+长链）与往返闭合
func test_multi_break_roundtrip() -> void:
	var br := [{"before_chain_m": 5000.0, "after_chain_m": 5200.0},
			{"before_chain_m": 8000.0, "after_chain_m": 7900.0}]
	var chains := [1000.0, 4000.0, 4999.9, 5999.9, 8000.0, 8999.9, 12000.0]
	var fwd: Dictionary = Sl.chain_convert({"breaks": br, "chains_m": chains, "direction": "d2a"})
	assert_true(bool(fwd.get("ok", false)), "多断链 d2a 成功：" + String(fwd.get("error", "")))
	if not bool(fwd.get("ok", false)):
		return
	var out: PackedFloat64Array = fwd["value"]["chains_out_m"]
	assert_almost_eq(out[1], 4000.0, 1e-9, "断链1前不变")
	assert_almost_eq(out[3], 5799.9, 1e-9, "5999.9 → 5799.9（s1=−200）")
	assert_almost_eq(out[4], 7800.0, 1e-9, "8000(断链2前桩号) → A2=7800")
	assert_almost_eq(out[5], 8899.9, 1e-9, "8999.9 → 8899.9（s1+s2=−100）")
	var back: Dictionary = Sl.chain_convert({"breaks": br,
		"chains_m": Array(out), "direction": "a2d"})
	assert_true(bool(back.get("ok", false)), "a2d 成功")
	var bout: PackedFloat64Array = back["value"]["chains_out_m"]
	for i in chains.size():
		assert_almost_eq(float(bout[i]), chains[i], 1e-9, "往返闭合 桩%d" % (i + 1))
	# 断链2后桩号 7900 → 实际 7800（与断链前桩号 8000 同一物理点）
	var hit: Dictionary = Sl.chain_convert({"breaks": br, "chains_m": [8000.0, 7900.0], "direction": "d2a"})
	var hout: PackedFloat64Array = hit["value"]["chains_out_m"]
	assert_almost_eq(hout[0], 7800.0, 1e-9, "8000 → 7800")
	assert_almost_eq(hout[1], 7800.0, 1e-9, "7900 → 同一物理点 7800")

## 超高/加宽线性过渡：权威要素（R=500,l0=60,α=30°，L=R·α(rad)+l0）
func test_superelevation_linear() -> void:
	var l_exact := 500.0 * deg_to_rad(30.0) + 60.0
	var res: Dictionary = Sl.superelevation({"r_m": 500.0, "l0_m": 60.0, "alpha_deg": 30.0,
		"e_max_pct": 6.0, "w_max_m": 1.5,
		"query_m": [0.0, 30.0, 60.0, l_exact / 2.0, l_exact - 60.0, l_exact - 30.0, l_exact]})
	assert_true(bool(res.get("ok", false)), "超高计算成功：" + String(res.get("error", "")))
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	assert_almost_eq(v["l_m"], 321.7994, 1e-3, "L 与 B3 权威向量一致")
	var es: PackedFloat64Array = v["e_pct"]
	assert_almost_eq(es[0], 0.0, 1e-12, "ZH 处超高 0")
	assert_almost_eq(es[1], 3.0, 1e-9, "半缓和段线性中点 3%")
	assert_almost_eq(es[2], 6.0, 1e-9, "HY 处达全超高")
	assert_almost_eq(es[3], 6.0, 1e-9, "全超高端保持 6%")
	assert_almost_eq(es[4], 6.0, 1e-9, "YZ 处仍全超高（L−l0）")
	assert_almost_eq(es[5], 3.0, 1e-9, "出口对称递减（L−30）")
	assert_almost_eq(es[6], 0.0, 1e-12, "HZ 处超高 0")
	var ws: PackedFloat64Array = v["w_m"]
	assert_almost_eq(ws[2], 1.5, 1e-9, "加宽同型线性过渡")

## 错误路径
func test_error_paths() -> void:
	var e1: Dictionary = Sl.chain_convert({"breaks": [], "chains_m": [100.0]})
	assert_false(bool(e1.get("ok", true)), "空断链表拒绝")
	var e2: Dictionary = Sl.chain_convert({"breaks": [{"before_chain_m": 100.0, "after_chain_m": 100.0}],
		"chains_m": [100.0]})
	assert_false(bool(e2.get("ok", true)), "前后桩号相同拒绝")
	var e3: Dictionary = Sl.chain_convert({
		"breaks": [{"before_chain_m": 5000.0, "after_chain_m": 5200.0},
				{"before_chain_m": 5100.0, "after_chain_m": 5300.0}],
		"chains_m": [100.0]})
	assert_false(bool(e3.get("ok", true)), "断链交错拒绝（后一断链前桩号落入前一断链跳过区）")
	var e4: Dictionary = Sl.superelevation({"r_m": 500.0, "l0_m": 60.0, "alpha_deg": 30.0,
		"e_max_pct": 15.0, "query_m": [30.0]})
	assert_false(bool(e4.get("ok", true)), "e_max>12% 拒绝")
	var e5: Dictionary = Sl.superelevation({"r_m": 500.0, "l0_m": 60.0, "alpha_deg": 30.0,
		"e_max_pct": 6.0, "query_m": [400.0]})
	assert_false(bool(e5.get("ok", true)), "弧长超曲线范围拒绝")
