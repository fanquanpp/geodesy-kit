# tests/adjustment/test_traverse.gd —— GK-M6-1 导线计算回归（C1 支/C2 闭合/C3 附合/C4 无定向）
#
# 向量来源（docs/ARCHITECTURE.md §4 GK-M6）：
#   - C3【权威·教材规则】A(5000,5000)、α起=95.5°、β1=178°15′02″(真+2″)、β2=236°14′58.5″(真−1.5″)、
#     边 950.004/1100.003/200.002、α终=150° → fβ=+0.50″、fx=+0.0074、fy=−0.0116、ΣD=2250.009、
#     相对闭合 1/163506、平差后 P1=(5945.627,4908.951)、P2=(7043.271,4837.004)。
#     ⚠ 权威向量未给出终点 B 坐标，本测试按权威 fx/fy 反推：
#       B = A + ΣΔ(改正后方位的坐标增量) − (fx, fy)，反推值 B=(7143.2712, 4663.7980)
#       （本会话 numpy 独立复核一致；fx/fy 为反推自洽值，P1/P2 与权威值毫米位吻合）。
#       相对闭合差权威 1/163506 对应未取整 fx≈0.007403；反推 fx=0.0074 给 1/163526——
#       两者差 0.012%，源于权威 fx/fy 四位小数取整，断言用区间容差覆盖。
#   - C1/C2/C4【构造·判据明确】真坐标生成观测（测试侧独立计算，不经过被测模块），
#     无误差 → 精确恢复真值；注入已知误差 → 闭合差/分配量可手算核对。
extends "res://tests/test_case_base.gd"

const TR := preload("res://core/adjustment/traverse.gd")
const AK := preload("res://core/math/angles.gd")

const B1_DMS := 178.0 + 15.0 / 60.0 + 2.0 / 3600.0        # 178°15′02″（真误差 +2″）
const B2_DMS := 236.0 + 14.0 / 60.0 + 58.5 / 3600.0       # 236°14′58.5″（真误差 −1.5″）
const FX_AUTH := 0.0074
const FY_AUTH := -0.0116

## 测试侧独立工具：由两点坐标求方位角（不经过被测模块）
func _az(a: Array, b: Array) -> float:
	return AK.azimuth(float(b[0]) - float(a[0]), float(b[1]) - float(a[1]))

## 测试侧独立工具：由坐标链生成 左角串 + 边长串（闭合环闭合用 %4 处理）
func _chain_obs(pts: Dictionary, chain: Array, closed: bool) -> Dictionary:
	var azs := PackedFloat64Array()
	var ds := PackedFloat64Array()
	for i in chain.size() - 1:
		var dx: float = float(pts[chain[i + 1]][0]) - float(pts[chain[i]][0])
		var dy: float = float(pts[chain[i + 1]][1]) - float(pts[chain[i]][1])
		azs.append(AK.azimuth(dx, dy))
		ds.append(sqrt(dx * dx + dy * dy))
	var angs := PackedFloat64Array()
	var n_ang := azs.size() if closed else azs.size() - 1
	for i in n_ang:
		var az_next: float = azs[(i + 1) % azs.size()] if closed else azs[i + 1]
		angs.append(AK.normalize_deg(az_next - azs[i] + 180.0))
	return {"az": azs, "d": ds, "angles": angs}

func test_c3_connect_authoritative() -> void:
	var A := [5000.0, 5000.0]
	var D := PackedFloat64Array([950.004, 1100.003, 200.002])
	var angles := PackedFloat64Array([B1_DMS, B2_DMS])
	# —— 测试侧独立反推 B（与被测模块同一手簿规则，但不经 traverse.gd 代码）——
	var f_beta_deg := (95.5 + B1_DMS + B2_DMS - 2.0 * 180.0) - 150.0
	assert_almost_eq(f_beta_deg * 3600.0, 0.5, 1e-6, "权威 fβ 应为 +0.50″")
	var corr := -f_beta_deg / 2.0
	var az := [95.5, 95.5 + B1_DMS + corr - 180.0, 0.0]
	az[2] = az[1] + B2_DMS + corr - 180.0
	assert_almost_eq(AK.normalize_deg(az[2]), 150.0, 1e-9, "改正后终边方位应闭合于 150°")
	var sum_e := 0.0
	var sum_n := 0.0
	for i in 3:
		sum_e += D[i] * sin(deg_to_rad(az[i]))
		sum_n += D[i] * cos(deg_to_rad(az[i]))
	var B_pt := [5000.0 + sum_e - FX_AUTH, 5000.0 + sum_n - FY_AUTH]
	# —— 被测模块 ——
	var res := TR.connect_traverse({
		"start": A, "end": B_pt,
		"az_start_deg": 95.5, "az_end_deg": 150.0,
		"angles_deg": [B1_DMS, B2_DMS], "sides_m": [950.004, 1100.003, 200.002],
		"point_names": ["P1", "P2"],
	})
	assert_true(bool(res.get("ok", false)), "C3 应计算成功")
	if not bool(res.get("ok", false)):
		print("       C3 error: %s" % String(res.get("error", "")))
		return
	var v: Dictionary = res["value"]
	assert_almost_eq(float(v["f_beta_s"]), 0.5, 1e-6, "fβ=+0.50″")
	assert_almost_eq(float(v["sum_d_m"]), 2250.009, 1e-9, "ΣD=2250.009")
	assert_almost_eq(float(v["fx_m"]), FX_AUTH, 1e-9, "fx=+0.0074（B 反推自洽）")
	assert_almost_eq(float(v["fy_m"]), FY_AUTH, 1e-9, "fy=−0.0116（B 反推自洽）")
	# 相对闭合差：权威 1/163506 与反推取整口径 1/163526 差 0.012%，用区间覆盖
	assert_between(float(v["rel_k"]), 163300.0, 163700.0, "相对闭合差 1/k 应在权威取整范围内")
	# 平差后坐标：全精度（本会话 numpy 独立复核值）与权威毫米取整值双重断言
	assert_almost_eq(float(v["x_P1_m"]), 5945.62724559, 1e-6, "P1.x 全精度")
	assert_almost_eq(float(v["y_P1_m"]), 4908.95104950, 1e-6, "P1.y 全精度")
	assert_almost_eq(float(v["x_P2_m"]), 7043.27082653, 1e-6, "P2.x 全精度")
	assert_almost_eq(float(v["y_P2_m"]), 4837.00376954, 1e-6, "P2.y 全精度")
	assert_almost_eq(float(v["x_P1_m"]), 5945.627, 5e-4, "P1.x 权威毫米值 5945.627")
	assert_almost_eq(float(v["y_P1_m"]), 4908.951, 5e-4, "P1.y 权威毫米值 4908.951")
	assert_almost_eq(float(v["x_P2_m"]), 7043.271, 5e-4, "P2.x 权威毫米值 7043.271")
	assert_almost_eq(float(v["y_P2_m"]), 4837.004, 5e-4, "P2.y 权威毫米值 4837.004")
	# 步骤协议：四字段齐全
	assert_true(res["steps"].size() >= 4, "C3 应产出解题步骤")
	for st: Dictionary in res["steps"]:
		assert_true(st.has_all(["title", "formula", "substitution", "result"]), "步骤四字段齐全")

func test_c3_limit_user_input() -> void:
	var A := [5000.0, 5000.0]
	var D := [950.004, 1100.003, 200.002]
	var angles := [B1_DMS, B2_DMS]
	var f_beta_deg := (95.5 + B1_DMS + B2_DMS - 360.0) - 150.0
	var corr := -f_beta_deg / 2.0
	var az := [95.5, 95.5 + angles[0] + corr - 180.0, 0.0]
	az[2] = az[1] + angles[1] + corr - 180.0
	var sum_e := 0.0
	var sum_n := 0.0
	for i in 3:
		sum_e += D[i] * sin(deg_to_rad(az[i]))
		sum_n += D[i] * cos(deg_to_rad(az[i]))
	var B_pt := [5000.0 + sum_e - FX_AUTH, 5000.0 + sum_n - FY_AUTH]
	var base := {
		"start": A, "end": B_pt, "az_start_deg": 95.5, "az_end_deg": 150.0,
		"angles_deg": angles, "sides_m": D,
	}
	var ok_in := base.duplicate()
	ok_in["limit_fb_s"] = 8.0
	ok_in["limit_rel_k"] = 4000.0
	var ok_res := TR.connect_traverse(ok_in)
	assert_true(bool(ok_res.get("ok", false)), "限差检核路径应成功")
	if not bool(ok_res.get("ok", false)):
		return
	assert_true(bool(ok_res["value"].get("ok_limit", false)), "fβ=0.5″<8″ 且 1/163526 优于 1/4000 应通过")
	assert_eq(String(ok_res["value"].get("basis", "")), "用户输入限差（未核读 GB 50026 等规范限差表，data/tolerance.json 为占位）", "依据应如实标注自输限差")
	var over_in := base.duplicate()
	over_in["limit_fb_s"] = 0.3
	var over_res := TR.connect_traverse(over_in)
	assert_true(bool(over_res.get("ok", false)), "超限仍是计算成功")
	if not bool(over_res.get("ok", false)):
		return
	assert_false(bool(over_res["value"].get("ok_limit", true)), "fβ=0.5″>0.3″ 应判超限")

func test_c1_open_traverse_constructed() -> void:
	var res := TR.open_traverse({
		"start": [1000.0, 2000.0], "az_start_deg": 45.0,
		"angles_deg": [90.0], "sides_m": [200.0, 300.0],
		"point_names": ["P1", "P2"],
	})
	assert_true(bool(res.get("ok", false)), "C1 应成功")
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	# 权威向量（numpy 手算）：45° 边 200 → (141.42135624, 141.42135624)；左角 90° → 方位 315°，边 300 → (−212.13203440, +212.13203440)
	assert_almost_eq(float(v["x_P1_m"]), 1141.42135624, 1e-6, "P1.x=1141.42135624")
	assert_almost_eq(float(v["y_P1_m"]), 2141.42135624, 1e-6, "P1.y=2141.42135624")
	assert_almost_eq(float(v["x_P2_m"]), 929.289321881, 1e-6, "P2.x=929.289321881")
	assert_almost_eq(float(v["y_P2_m"]), 2353.55339059, 1e-6, "P2.y=2353.55339059")
	# 非法输入
	var bad := TR.open_traverse({"start": [1.0, 2.0], "az_start_deg": 45.0, "angles_deg": [90.0, 90.0], "sides_m": [100.0, 100.0]})
	assert_false(bool(bad.get("ok", true)), "角数≠边数−1 应失败")
	assert_true(String(bad.get("error", "")).length() > 0, "失败须有中文 error")

func test_c2_closed_noise_free_recovers_truth() -> void:
	var pts := {"A": [1000.0, 1000.0], "P1": [1300.0, 1050.0], "P2": [1350.0, 1350.0], "P3": [1050.0, 1300.0]}
	var chain := ["A", "P1", "P2", "P3", "A"]
	var obs := _chain_obs(pts, chain, true)
	var res := TR.closed_traverse({
		"start": pts["A"], "az_start_deg": obs["az"][0],
		"angles_deg": Array(obs["angles"]), "sides_m": Array(obs["d"]),
		"point_names": ["P1", "P2", "P3"],
	})
	assert_true(bool(res.get("ok", false)), "C2 无误差构造应成功")
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	assert_almost_eq(float(v["f_beta_s"]), 0.0, 1e-6, "无误差时 fβ≈0")
	assert_almost_eq(float(v["fx_m"]), 0.0, 1e-9, "无误差时 fx≈0")
	assert_almost_eq(float(v["fy_m"]), 0.0, 1e-9, "无误差时 fy≈0")
	assert_almost_eq(float(v["x_P1_m"]), 1300.0, 1e-9, "恢复 P1.x")
	assert_almost_eq(float(v["y_P1_m"]), 1050.0, 1e-9, "恢复 P1.y")
	assert_almost_eq(float(v["x_P2_m"]), 1350.0, 1e-9, "恢复 P2.x")
	assert_almost_eq(float(v["y_P2_m"]), 1350.0, 1e-9, "恢复 P2.y")
	assert_almost_eq(float(v["x_P3_m"]), 1050.0, 1e-9, "恢复 P3.x")
	assert_almost_eq(float(v["y_P3_m"]), 1300.0, 1e-9, "恢复 P3.y")
	# 终点（键名与起点同名 A）应闭合回起点
	assert_almost_eq(float(v["x_A_m"]), 1000.0, 1e-9, "闭合环终点回到 A.x")

func test_c2_closed_with_known_angle_error() -> void:
	# 注入 β2(P2 处) +10″：fβ=+10″、每角改正 −2.5″、闭合环终点仍精确闭合
	var pts := {"A": [1000.0, 1000.0], "P1": [1300.0, 1050.0], "P2": [1350.0, 1350.0], "P3": [1050.0, 1300.0]}
	var chain := ["A", "P1", "P2", "P3", "A"]
	var obs := _chain_obs(pts, chain, true)
	var angs: Array = Array(obs["angles"])
	angs[1] += 10.0 / 3600.0
	var res := TR.closed_traverse({
		"start": pts["A"], "az_start_deg": obs["az"][0],
		"angles_deg": angs, "sides_m": Array(obs["d"]),
		"point_names": ["P1", "P2", "P3"],
	})
	assert_true(bool(res.get("ok", false)), "C2 注入误差应成功")
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	assert_almost_eq(float(v["f_beta_s"]), 10.0, 1e-6, "注入 +10″ 后 fβ=+10″")
	assert_almost_eq(float(v["f_beta_per_angle_s"]), -2.5, 1e-6, "各角均分改正 −2.5″")
	assert_almost_eq(float(v["x_A_m"]), 1000.0, 1e-9, "分配后闭合环精确闭合（终点=A）")
	assert_almost_eq(float(v["y_A_m"]), 1000.0, 1e-9, "分配后闭合环精确闭合（终点=A）")

func test_c4_no_orient_noise_free_recovers_truth() -> void:
	# 真图形（numpy 复核）：A(2000,3000)→P1(2500,3400)→P2(3100,3200)→B(3600,2800)
	var pts := {"A": [2000.0, 3000.0], "P1": [2500.0, 3400.0], "P2": [3100.0, 3200.0], "B": [3600.0, 2800.0]}
	var chain := ["A", "P1", "P2", "B"]
	var obs := _chain_obs(pts, chain, false)
	var res := TR.no_orient_traverse({
		"start": pts["A"], "end": pts["B"],
		"angles_deg": Array(obs["angles"]), "sides_m": Array(obs["d"]),
		"point_names": ["P1", "P2"],
	})
	assert_true(bool(res.get("ok", false)), "C4 无误差构造应成功")
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	# 假定 α'1=0° 时旋转角 δ 应恰为真起始方位角 51.3401917459°
	assert_almost_eq(float(v["rotation_deg"]), 51.3401917459, 1e-6, "旋转角 δ=真起始方位")
	assert_almost_eq(float(v["fx_m"]), 0.0, 1e-9, "无误差时 fx≈0")
	assert_almost_eq(float(v["fy_m"]), 0.0, 1e-9, "无误差时 fy≈0")
	assert_almost_eq(float(v["x_P1_m"]), 2500.0, 1e-6, "恢复 P1.x")
	assert_almost_eq(float(v["y_P1_m"]), 3400.0, 1e-6, "恢复 P1.y")
	assert_almost_eq(float(v["x_P2_m"]), 3100.0, 1e-6, "恢复 P2.x")
	assert_almost_eq(float(v["y_P2_m"]), 3200.0, 1e-6, "恢复 P2.y")

func test_c4_no_orient_with_side_noise_closes_on_end() -> void:
	var pts := {"A": [2000.0, 3000.0], "P1": [2500.0, 3400.0], "P2": [3100.0, 3200.0], "B": [3600.0, 2800.0]}
	var chain := ["A", "P1", "P2", "B"]
	var obs := _chain_obs(pts, chain, false)
	var ds: Array = Array(obs["d"])
	ds[0] += 0.05  # 首边注入 5cm 边长误差
	var res := TR.no_orient_traverse({
		"start": pts["A"], "end": pts["B"],
		"angles_deg": Array(obs["angles"]), "sides_m": ds,
		"point_names": ["P1", "P2"],
	})
	assert_true(bool(res.get("ok", false)), "C4 注入边长误差应成功")
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	assert_almost_eq(float(v["x_B_m"]), 3600.0, 1e-9, "终点精确附合于 B.x")
	assert_almost_eq(float(v["y_B_m"]), 2800.0, 1e-9, "终点精确附合于 B.y")
	# 5cm 误差按边长比例分配，P1 偏离真值应在 0.1 m 内
	assert_between(float(v["x_P1_m"]), 2499.9, 2500.1, "P1.x 偏离真值 <0.1 m")
	assert_between(float(v["y_P1_m"]), 3399.9, 3400.1, "P1.y 偏离真值 <0.1 m")

func test_traverse_error_paths() -> void:
	var r1 := TR.connect_traverse({"start": [0.0, 0.0], "az_start_deg": 10.0, "angles_deg": [30.0], "sides_m": [100.0, 100.0]})
	assert_false(bool(r1.get("ok", true)), "缺 end/az_end 应失败")
	var r2 := TR.connect_traverse({"start": [0.0, 0.0], "end": [100.0, 100.0], "az_start_deg": 10.0,
		"angles_deg": [30.0], "sides_m": [100.0, 100.0]})
	assert_false(bool(r2.get("ok", true)), "缺 az_end_deg 应失败")
	var r3 := TR.connect_traverse({"start": [0.0, 0.0], "end": [100.0, 100.0], "az_start_deg": 10.0,
		"az_end_deg": 80.0, "angles_deg": [30.0], "sides_m": [100.0, 100.0, 100.0]})
	assert_false(bool(r3.get("ok", true)), "角数≠边数−1 应失败")
	var r4 := TR.open_traverse({"start": [0.0, 0.0], "az_start_deg": 10.0, "angles_deg": ["abc"], "sides_m": [100.0, 100.0]})
	assert_false(bool(r4.get("ok", true)), "非法角度文本应失败（不崩溃）")
	var r5 := TR.closed_traverse({"start": [0.0, 0.0], "az_start_deg": 10.0, "angles_deg": [30.0, 30.0], "sides_m": [100.0, 100.0, 100.0]})
	assert_false(bool(r5.get("ok", true)), "闭合导线角数≠边数应失败")
