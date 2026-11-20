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
