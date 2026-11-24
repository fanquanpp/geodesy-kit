# tests/adjustment/test_leveling.gd —— GK-M6-3 水准测量回归（C6 单一路线 / C7 水准网双法 / 三角高程）
#
# 向量来源（docs/ARCHITECTURE.md §4 GK-M6）：
#   - C7【权威·numpy 双法互检】HA=100.000；h1=12.513(3km,A→P1)、h2=20.947(4km,A→P2)、
#     h3=8.402(2km,P1→P2)，P=diag(1/3,1/4,1/2) → HP1=112.5237、HP2=120.9328、
#     V=(+0.0107,−0.0142,+0.0071)m、μ=±10.7mm；条件法闭合差 w=−0.032 与间接法逐位一致。
#     本测试按全精度断言（V=(+0.0106666667, −0.0142222222, +0.0071111111)、μ=0.0106666667）。
#   - C6/三角高程【构造·numpy 复核】附合路线 fh=+4mm 按路线长分配；闭合环 fh=−6mm；
#     三角高程 D=2000m、α=2°、i=v=1.5m、k=0.13、R=6371008.7714 → 单向 70.1146511487m、
#     对向均值 69.8415389835m、球气差单项 f=0.27311216519m（对向均值 + f = 单向值，互检）。
extends "res://tests/test_case_base.gd"

const LV := preload("res://core/adjustment/leveling.gd")

const C7_OBS := [
	{"from": "A", "to": "P1", "h": 12.513, "L_km": 3.0},
	{"from": "A", "to": "P2", "h": 20.947, "L_km": 4.0},
	{"from": "P1", "to": "P2", "h": 8.402, "L_km": 2.0},
]
const C7_KNOWN := {"A": 100.000}
const C7_APPROX := {"P1": 112.513, "P2": 120.947}

func test_c7_network_indirect_authoritative() -> void:
	var res := LV.network_indirect({"known": C7_KNOWN, "approx": C7_APPROX, "obs": C7_OBS})
	assert_true(bool(res.get("ok", false)), "C7 间接法应成功")
	if not bool(res.get("ok", false)):
		print("       C7 error: %s" % String(res.get("error", "")))
		return
	var v: Dictionary = res["value"]
	assert_almost_eq(float(v["H_P1_m"]), 112.5236666667, 1e-9, "权威 HP1=112.5237")
	assert_almost_eq(float(v["H_P2_m"]), 120.9327777778, 1e-9, "权威 HP2=120.9328")
	assert_vector_almost_eq(Array(v["v_m"]), [0.0106666666667, -0.0142222222222, 0.00711111111111], 1e-12, "权威 V=(+0.0107,−0.0142,+0.0071)")
	assert_almost_eq(float(v["mu_m"]), 0.0106666666667, 1e-12, "权威 μ=±10.7mm（全精度 0.0106666667）")
	assert_almost_eq(float(v["mu_mm"]), 10.6666666667, 1e-9, "μ 毫米口径")
	assert_eq(int(v["dof"]), 1, "多余观测 r = n−t = 1")
	assert_eq(int(v["n_obs"]), 3, "n=3")

func test_c7_condition_matches_indirect_bitwise() -> void:
	var r_ind := LV.network_indirect({"known": C7_KNOWN, "approx": C7_APPROX, "obs": C7_OBS})
	var r_con := LV.network_condition({"known": C7_KNOWN, "approx": C7_APPROX, "obs": C7_OBS})
	assert_true(bool(r_ind.get("ok", false)), "间接法成功")
	assert_true(bool(r_con.get("ok", false)), "条件法成功")
	if not (bool(r_ind.get("ok", false)) and bool(r_con.get("ok", false))):
		print("       indirect: %s / condition: %s" % [String(r_ind.get("error", "")), String(r_con.get("error", ""))])
		return
	var vi: Dictionary = r_ind["value"]
	var vc: Dictionary = r_con["value"]
	assert_eq(int((vc["w_m"] as PackedFloat64Array).size()), 1, "1 个独立环")
	assert_almost_eq(float((vc["w_m"] as PackedFloat64Array)[0]), -0.032, 1e-12, "条件闭合差 w=−0.032")
	# 双法逐位一致：残差与高程同序对比
	assert_vector_almost_eq(Array(vc["v_m"]), Array(vi["v_m"]), 1e-12, "条件/间接 V 逐位一致")
	assert_almost_eq(float(vc["H_P1_m"]), float(vi["H_P1_m"]), 1e-12, "HP1 双法一致")
	assert_almost_eq(float(vc["H_P2_m"]), float(vi["H_P2_m"]), 1e-12, "HP2 双法一致")
	assert_almost_eq(float(vc["mu_m"]), float(vi["mu_m"]), 1e-12, "μ 双法一致")
	# 条件法高程推算应回到权威值
	assert_almost_eq(float(vc["H_P1_m"]), 112.5236666667, 1e-9, "条件法 HP1 权威值")
	assert_almost_eq(float(vc["H_P2_m"]), 120.9327777778, 1e-9, "条件法 HP2 权威值")

func test_c6_single_route_annex() -> void:
	# 附合路线：HA=100、HB=110，Σh=+10.004 → fh=+4mm，按路线长 2:1:3 分配
	var res := LV.single_route({
		"h_start": 100.000, "h_end": 110.000,
		"segs": [{"h": 4.251, "L_km": 2.0}, {"h": 3.008, "L_km": 1.0}, {"h": 2.745, "L_km": 3.0}],
		"point_names": ["B1", "B2"],
	})
	assert_true(bool(res.get("ok", false)), "C6 附合应成功")
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	assert_almost_eq(float(v["fh_m"]), 0.004, 1e-12, "fh=+4mm")
	assert_vector_almost_eq(Array(v["v_m"]), [-0.00133333333333, -0.000666666666667, -0.002], 1e-12, "按路线长比例分配改正")
	assert_almost_eq(float(v["H_B1_m"]), 104.249666667, 1e-9, "B1 改正后高程")
	assert_almost_eq(float(v["H_B2_m"]), 107.257, 1e-9, "B2 改正后高程")
	assert_almost_eq(float(v["H_B_m"]), 110.000, 1e-9, "终点附合回已知高程")
	# 自输限差两种走向
	var ok_res := LV.single_route({"h_start": 100.000, "h_end": 110.000,
		"segs": [{"h": 4.251, "L_km": 2.0}, {"h": 3.008, "L_km": 1.0}, {"h": 2.745, "L_km": 3.0}],
		"limit_mm": 8.0})
	assert_true(bool(ok_res["value"].get("ok_limit", false)), "fh=4mm ≤ 限差 8mm 应通过")
	var over_res := LV.single_route({"h_start": 100.000, "h_end": 110.000,
		"segs": [{"h": 4.251, "L_km": 2.0}, {"h": 3.008, "L_km": 1.0}, {"h": 2.745, "L_km": 3.0}],
		"limit_mm": 3.0})
	assert_false(bool(over_res["value"].get("ok_limit", true)), "fh=4mm > 限差 3mm 应超限")

func test_c6_single_route_loop() -> void:
	# 闭合环：Σh=−6mm 全部按比例分配，终点=起点
	var res := LV.single_route({
		"h_start": 100.000, "loop": true,
		"segs": [{"h": 2.516, "L_km": 1.0}, {"h": -1.204, "L_km": 2.0}, {"h": -1.318, "L_km": 3.0}],
		"point_names": ["C1", "C2"],
	})
	assert_true(bool(res.get("ok", false)), "C6 闭合环应成功")
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	assert_almost_eq(float(v["fh_m"]), -0.006, 1e-12, "环闭合差 fh=−6mm")
	assert_vector_almost_eq(Array(v["v_m"]), [0.001, 0.002, 0.003], 1e-12, "改正数 +1/+2/+3mm")
	assert_almost_eq(float(v["H_A_m"]), 100.000, 1e-12, "环终点回到起点")

func test_trig_height_constructed() -> void:
	var res := LV.trig_height({
		"D_m": 2000.0, "v_angle_deg": 2.0, "i_m": 1.5, "v_m": 1.5,
		"k": 0.13, "R_m": 6371008.7714,
		"back": {"v_angle_deg": -2.0, "i_m": 1.5, "v_m": 1.5},
	})
	assert_true(bool(res.get("ok", false)), "三角高程应成功")
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	assert_almost_eq(float(v["h_m"]), 70.1146511487, 1e-9, "单向 h=70.1146511487（含球气差）")
	assert_almost_eq(float(v["f_ballistic_m"]), 0.27311216519, 1e-9, "球气差改正 f=0.27311216519")
	assert_almost_eq(float(v["h_two_way_m"]), 69.8415389835, 1e-9, "对向均值=69.8415389835（球气差抵消）")
	# 互检：单向 − 对向均值 = 球气差单项 f
	assert_almost_eq(float(v["h_m"]) - float(v["h_two_way_m"]), float(v["f_ballistic_m"]), 1e-9, "单向−对向=f 球气差自洽")

func test_leveling_error_paths() -> void:
	var r1 := LV.single_route({"h_start": 100.0, "segs": [{"h": 1.0, "L_km": 1.0}]})
	assert_false(bool(r1.get("ok", true)), "附合缺 h_end 应失败")
	var r2 := LV.network_indirect({"known": {"A": 10.0}, "approx": {"P1": 11.0},
		"obs": [{"from": "A", "to": "X", "h": 1.0, "L_km": 1.0}]})
	assert_false(bool(r2.get("ok", true)), "观测引用未定义点应失败")
	var r3 := LV.network_indirect({"approx": {"P1": 11.0}, "obs": C7_OBS})
	assert_false(bool(r3.get("ok", true)), "缺已知点应失败")
	var r4 := LV.network_condition({"known": {"A": 10.0}, "approx": {"P1": 11.0},
		"obs": [{"from": "A", "to": "P1", "h": 1.0, "L_km": 1.0}]})
	assert_false(bool(r4.get("ok", true)), "无多余观测条件法应失败（不崩溃）")
	var r5 := LV.trig_height({"D_m": -5.0, "v_angle_deg": 1.0, "i_m": 1.0, "v_m": 1.0})
	assert_false(bool(r5.get("ok", true)), "非正平距应失败")
	var r6 := LV.trig_height({"D_m": 100.0, "v_angle_deg": 1.0, "i_m": 1.0, "v_m": 1.0, "k": 1.5})
	assert_false(bool(r6.get("ok", true)), "k 越界应失败")

# ---------- 以下为 P3 修正后追加的回归用例（既有用例期望值一律不动） ----------

## 回归 1【双已知点·numpy 全精度复算】：条件法须同时含环条件与已知点附合条件。
## known={A:100.0, B:110.2}、approx={P1:105.0}、obs：A→B h=10.0(4km)、A→P1 h=5.0(3km)、
## P1→B h=5.1(3km)。条件集：环 A1=[1,−1,−1] w1=−0.1；附合 A2=[0,1,1] w2=−0.1。
## 权 P=diag(1/4,1/3,1/3) → V=(+0.2, +0.05, +0.05) m、VᵀPV=7/1200、μ=0.0763762616、dof=2。
## 该算例在修复前失败（旧实现只组环条件，r=1，V 误为 (0.04,−0.03,−0.03)）。
## 注：以任务书复核时给出的 V=(3.2,0.45,0.45) 经代入条件方程不闭合（A1·v=2.3≠0.1），
##     系参考实现误把 A·P·Aᵀ 当法方程所致；本用例断言按条件方程闭合的最小二乘解。
func test_c7_dual_known_annex_condition() -> void:
	var obs := [
		{"from": "A", "to": "B", "h": 10.0, "L_km": 4.0},
		{"from": "A", "to": "P1", "h": 5.0, "L_km": 3.0},
		{"from": "P1", "to": "B", "h": 5.1, "L_km": 3.0},
	]
	var inp := {"known": {"A": 100.0, "B": 110.2}, "approx": {"P1": 105.0}, "obs": obs}
	var r_con := LV.network_condition(inp)
	assert_true(bool(r_con.get("ok", false)), "条件法（双已知点）应成功")
	if not bool(r_con.get("ok", false)):
		print("       condition error: %s" % String(r_con.get("error", "")))
		return
	var vc: Dictionary = r_con["value"]
	# 条件集：1 环 + 1 附合 = 2（附合条件此前缺失，是本回归的核心）
	assert_eq(int(vc["dof"]), 2, "条件数 r = n − t = 2（环+附合）")
	assert_vector_almost_eq(Array(vc["v_m"]), [0.2, 0.05, 0.05], 1e-9, "V=(+0.2,+0.05,+0.05)")
	assert_almost_eq(float(vc["mu_m"]), 0.0763762616, 1e-9, "μ=√(7/1200)=0.0763762616")
	assert_almost_eq(float(vc["H_P1_m"]), 105.05, 1e-9, "H_P1=105.05")
	# 条件方程闭合差（环条件基底取向依生成树，|w1|=0.1；附合条件沿树经不同路径，w2=−0.2 与
	# 任务书 A₂=[0,1,1]、w₂=−0.1 同为合法附合基底，最小二乘解不受基底选择影响）
	var w1 := float((vc["w_m"] as PackedFloat64Array)[0])
	assert_almost_eq(absf(w1), 0.1, 1e-12, "|环闭合差|=0.1")
	# 双法逐位一致
	var r_ind := LV.network_indirect(inp)
	assert_true(bool(r_ind.get("ok", false)), "间接法（双已知点）应成功")
	if bool(r_ind.get("ok", false)):
		var vi: Dictionary = r_ind["value"]
		assert_eq(int(vi["dof"]), 2, "间接法 dof=2")
		assert_vector_almost_eq(Array(vc["v_m"]), Array(vi["v_m"]), 1e-9, "双已知点双法 V 逐位一致")
		assert_almost_eq(float(vc["mu_m"]), float(vi["mu_m"]), 1e-9, "双已知点 μ 双法一致")
		assert_almost_eq(float(vi["H_P1_m"]), 105.05, 1e-9, "间接法 H_P1=105.05")

## 回归 2【对向均值·本侧仪器高/目标高严格配对·numpy 复算】：
## D=2000、α往=+2°、α返=−2°、i_A=1.5、v_B=1.6、i_B=1.4、v_A=1.3、k=0.13、R=6371008.7714
## → h_AB=70.0146511487（含 f）、h_BA=−69.4684268183（含 f）、对向均值=69.7415389835。
## 修复前旧公式错把返测目标高当本侧配对，输出 70.0415（偏差 +0.300 m）。
func test_trig_height_asymmetric_paring() -> void:
	var res := LV.trig_height({
		"D_m": 2000.0, "v_angle_deg": 2.0, "i_m": 1.5, "v_m": 1.6,
		"k": 0.13, "R_m": 6371008.7714,
		"back": {"v_angle_deg": -2.0, "i_m": 1.4, "v_m": 1.3},
	})
	assert_true(bool(res.get("ok", false)), "非对称对向应成功")
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	assert_almost_eq(float(v["h_two_way_m"]), 69.7415389835, 1e-9, "对向均值=69.7415389835（严格本侧配对）")
	assert_almost_eq(float(v["h_m"]), 70.0146511487, 1e-9, "单向 h_AB=70.0146511487")
	# 自洽检核：单向 − 对向均值 = 球气差单项 f（本算例 i_A−v_B = −(i_B−v_A)，tanα 项抵消后成立）
	assert_almost_eq(float(v["h_m"]) - float(v["h_two_way_m"]), float(v["f_ballistic_m"]), 1e-9, "单向−对向=f 球气差自洽")
	# 对向均值显式公式复算：h_均 = ½(h_AB − h_BA)，h_BA = D·tanα返 + i_B − v_A + f
	var f_ball := float(v["f_ballistic_m"])
	var h_ab_exp: float = 2000.0 * tan(deg_to_rad(2.0)) + 1.5 - 1.6 + f_ball
	var h_ba_exp: float = 2000.0 * tan(deg_to_rad(-2.0)) + 1.4 - 1.3 + f_ball
	assert_almost_eq(float(v["h_m"]), h_ab_exp, 1e-12, "单向值显式复算一致")
	assert_almost_eq(0.5 * (h_ab_exp - h_ba_exp), 69.7415389835, 1e-9, "½(h_AB−h_BA) 显式代入复算一致")

## 回归 3【两独立环条件法·numpy 全精度复算】：known={A:100.0}，obs 5 条成两环。
## 环1 A→P1→P2→A：w1=−0.1；环2 P1→P3→P2→P1：w2=−0.2。权 p=diag(1/2,1/2,1/2,1,1)
## → V=(+0.08, −0.06, +0.08, +0.07, +0.07) m、μ=√(VᵀPV/2)=√0.009=0.094868329805051…、dof=2；
##   双法一致 1e-12。（μ 常量须给全精度：截断到 0.0948683298 与真值差 5.05e-12，超出 1e-12 容差）
func test_c7_two_loops_condition_authoritative() -> void:
	var obs := [
		{"from": "A", "to": "P1", "h": 5.0, "L_km": 2.0},
		{"from": "P1", "to": "P2", "h": 3.0, "L_km": 2.0},
		{"from": "P2", "to": "A", "h": -8.1, "L_km": 2.0},
		{"from": "P1", "to": "P3", "h": 4.0, "L_km": 1.0},
		{"from": "P3", "to": "P2", "h": -1.2, "L_km": 1.0},
	]
	var inp := {"known": {"A": 100.0}, "approx": {"P1": 105.0, "P2": 108.0, "P3": 109.0}, "obs": obs}
	var r_con := LV.network_condition(inp)
	assert_true(bool(r_con.get("ok", false)), "两环条件法应成功")
	if not bool(r_con.get("ok", false)):
		print("       condition error: %s" % String(r_con.get("error", "")))
		return
	var vc: Dictionary = r_con["value"]
	assert_eq(int((vc["w_m"] as PackedFloat64Array).size()), 2, "2 个独立环")
	# 环闭合差依生成树基底：环1 恰为 w=−0.1；环2 基底取向沿树不同，得 w=−0.3
	# （与 −0.2 同为合法基底，最小二乘解不变，见下 V 断言）
	assert_vector_almost_eq(Array(vc["w_m"]), [-0.1, -0.3], 1e-12, "环闭合差 w=(−0.1,−0.3)（依树基底）")
	assert_vector_almost_eq(Array(vc["v_m"]), [0.08, -0.06, 0.08, 0.07, 0.07], 1e-12, "权威 V")
	assert_almost_eq(float(vc["mu_m"]), 0.094868329805051, 1e-12, "权威 μ=√0.009=0.094868329805051…")
	assert_eq(int(vc["dof"]), 2, "dof=2")
	var r_ind := LV.network_indirect(inp)
	assert_true(bool(r_ind.get("ok", false)), "两环间接法应成功")
	if bool(r_ind.get("ok", false)):
		var vi: Dictionary = r_ind["value"]
		assert_vector_almost_eq(Array(vc["v_m"]), Array(vi["v_m"]), 1e-12, "两环双法 V 逐位一致")
		assert_almost_eq(float(vc["mu_m"]), float(vi["mu_m"]), 1e-12, "两环 μ 双法一致")

## 回归 4【C6 测站数定权·构造算例】：Σh=6.000、附合差 H终−H起=6.006 → fh=−6mm，
## 按测站数 3:2:1 分配 → v=(+3,+2,+1)mm；weight_mode 注明每站等精度口径；Σv=−fh 检核；
## 超限时报限差判据步骤且不输出改正分配。
func test_c6_ns_weighting_and_limit_chain() -> void:
	var res := LV.single_route({
		"h_start": 100.000, "h_end": 106.006,
		"segs": [{"h": 2.0, "L_km": 1.0, "ns": 3}, {"h": 2.0, "L_km": 1.0, "ns": 2}, {"h": 2.0, "L_km": 1.0, "ns": 1}],
	})
	assert_true(bool(res.get("ok", false)), "测站数定权应成功")
	if bool(res.get("ok", false)):
		var v: Dictionary = res["value"]
		assert_almost_eq(float(v["fh_mm"]), -6.0, 1e-12, "fh=−6mm")
		assert_vector_almost_eq(Array(v["v_mm"]), [3.0, 2.0, 1.0], 1e-12, "按测站数分配 v=(+3,+2,+1)mm")
		assert_true(bool(v.get("sum_v_ok", false)), "Σv=−fh 检核通过")
		assert_true(String(v.get("weight_mode", "")).contains("测站数"), "weight_mode 注明测站数口径")
	# 超限：限差判据步骤在、不做改正分配（steps 只有闭合差与限差判据两步）
	var over := LV.single_route({
		"h_start": 100.000, "h_end": 110.000,
		"segs": [{"h": 4.251, "L_km": 2.0}, {"h": 3.008, "L_km": 1.0}, {"h": 2.745, "L_km": 3.0}],
		"limit_mm": 3.0,
	})
	assert_true(bool(over.get("ok", false)), "超限仍返回成功壳（ok_limit=false）")
	var ov: Dictionary = over["value"]
	assert_false(bool(ov.get("ok_limit", true)), "超限标志为否")
	assert_false(bool(ov.get("sum_v_ok", true)), "超限时未做分配，Σv 检核不通过")
	assert_true(String(ov.get("basis", "")).contains("用户自输"), "basis 为用户自输口径（无内部占位标识）")
	var titles := PackedStringArray()
	for st: Dictionary in over["steps"]:
		titles.append(String(st["title"]))
	assert_true(_any_contains(titles, "限差判据"), "步骤含限差判据")
	assert_true(_any_contains(titles, "返工"), "超限提示返工")
	assert_false(_any_contains(titles, "改正后高程推算"), "超限不输出改正分配步骤")

func _any_contains(arr: PackedStringArray, sub: String) -> bool:
	for t in arr:
		if t.contains(sub):
			return true
	return false
