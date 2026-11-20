# tests/transform/test_bursa.gd —— GK-M4-1（A9）布尔莎七参数 PV/CF + 三参数 + 公共点求参
# 向量来源：
#   【权威·EPSG GN7-2 §4.2.3 官方算例（本任务分配向量）】WGS72→WGS84 PV：t=(0,0,+4.5 m)，
#     rZ=+0.554″，dS=+0.219 ppm，入 (3657660.66,255768.55,5201382.11) → 出
#     (3657660.78,255778.43,5201387.75)；CF 约定 rZ=−0.554″ 输出完全相同（双约定互为反号）。
#   【外部核读】pyproj 3.8（PROJ helmert，position_vector/coordinate_frame，本会话实跑）
#     对 GN7-2 算例与通用参数组合逐位复核（期望值与容差见各断言）。
#   【构造】求参恢复：5 公共点 + 已知七参数（目标点由 GKBursa.transform 精确三角生成），
#     期望参数经 numpy lstsq 独立实现复核（ARCHITECTURE.md §7.3 双法互检口径）。
extends "res://tests/test_case_base.gd"

const B := preload("res://core/transform/bursa.gd")

const GN72_IN := [3657660.66, 255768.55, 5201382.11]
const GN72_OUT_AUTH := [3657660.78, 255778.43, 5201387.75]      # GN7-2 官方（0.01 m 口径）
const GN72_OUT_PYPROJ := [3657660.774067023, 255778.43000842957, 5201387.749102682]  # pyproj 复核
const GEN_P2 := [4000000.0, 500000.0, 4933000.0]
const GEN_PV_OUT := [3999997.0047910223, 500004.7715172163, 4933010.072232273]       # pyproj PV
const GEN_CF_OUT := [4000008.995208978, 499999.7284827838, 4933000.860767728]        # pyproj CF 同角
const SRC5 := [
	[3657660.66, 255768.55, 5201382.11],
	[4000000.0, 500000.0, 4933000.0],
	[4200000.0, 300000.0, 4800000.0],
	[3800000.0, 700000.0, 5100000.0],
	[4100000.0, 600000.0, 4950000.0],
]

func _pt(x, y, z) -> Array:
	return [x, y, z]

func _first(res: Dictionary) -> Array:
	var pts: Array = res["value"]["points_m"]
	return pts[0]

func test_gn72_official_example_pv() -> void:
	var res := B.transform({
		"src_xyz": [_pt(3657660.66, 255768.55, 5201382.11)],
		"tx_m": 0.0, "ty_m": 0.0, "tz_m": 4.5,
		"rx_as": 0.0, "ry_as": 0.0, "rz_as": 0.554,
		"scale_ppm": 0.219, "convention": "PV",
	})
	assert_true(res["ok"], "PV 正算应成功")
	var out: Array = _first(res)
	for i in 3:
		assert_almost_eq(out[i], GN72_OUT_AUTH[i], 0.01, "GN7-2 官方分量 %d" % i)
		# pyproj/PROJ helmert 默认为一阶小角近似（本会话 10° 实测证实），与本实现的精确三角
		# 差异为 O(ε²)·X ≤ 1.4e-5 m（0.554″），故互检容差取 1e-4 m（远小于 GN7-2 的 0.01 m 口径）
		assert_almost_eq(out[i], GN72_OUT_PYPROJ[i], 1e-4, "pyproj 复核分量 %d" % i)
	assert_eq(res["value"]["convention"], "PV", "约定回显")
	# 协议完整性
	assert_true((res["steps"] as Array).size() >= 3, "步骤数")
	for st: Dictionary in res["steps"]:
		assert_true(st.has_all(["title", "formula", "substitution", "result"]), "步骤四字段")
	assert_true(String(res["formula"]).length() > 0, "formula 非空")
	assert_eq(res["error"], "", "error 为空")

func test_pv_cf_dual_convention() -> void:
	# CF 约定 rZ=−0.554″ 必须与 PV rZ=+0.554″ 输出完全相同（本任务要求双约定同测）
	var res_cf := B.transform({
		"src_xyz": [_pt(3657660.66, 255768.55, 5201382.11)],
		"tx_m": 0.0, "ty_m": 0.0, "tz_m": 4.5,
		"rx_as": 0.0, "ry_as": 0.0, "rz_as": -0.554,
		"scale_ppm": 0.219, "convention": "CF",
	})
	assert_true(res_cf["ok"], "CF 正算应成功")
	var out_cf: Array = _first(res_cf)
	# 与本实现 PV 路径（同参数、PV 约定）逐位一致——双约定互为反号的模块级自检
	var res_pv_self := B.transform({
		"src_xyz": [_pt(3657660.66, 255768.55, 5201382.11)],
		"tx_m": 0.0, "ty_m": 0.0, "tz_m": 4.5,
		"rx_as": 0.0, "ry_as": 0.0, "rz_as": 0.554,
		"scale_ppm": 0.219, "convention": "PV",
	})
	var out_pv: Array = _first(res_pv_self)
	for i in 3:
		assert_almost_eq(out_cf[i], out_pv[i], 1e-12, "CF(−ε)=PV(+ε) 分量 %d" % i)
	# 通用参数组合：PV(+ε) vs pyproj；CF(+ε) vs pyproj；CF(−ε)=PV(+ε)
	var base := {
		"src_xyz": [_pt(4000000.0, 500000.0, 4933000.0)],
		"tx_m": 1.0, "ty_m": 2.0, "tz_m": 3.0,
		"rx_as": 0.3, "ry_as": -0.2, "rz_as": 0.5,
		"scale_ppm": 0.5,
	}
	var pv := base.duplicate(); pv["convention"] = "PV"
	var res_pv := B.transform(pv)
	assert_true(res_pv["ok"], "通用 PV 应成功")
	var o_pv: Array = _first(res_pv)
	for i in 3:
		assert_almost_eq(o_pv[i], GEN_PV_OUT[i], 1e-4, "通用 PV vs pyproj 分量 %d（PROJ 一阶小角口径）" % i)
	var cf := base.duplicate(); cf["convention"] = "CF"
	var res_cf2 := B.transform(cf)
	var o_cf: Array = _first(res_cf2)
	for i in 3:
		assert_almost_eq(o_cf[i], GEN_CF_OUT[i], 1e-4, "通用 CF(同角) vs pyproj 分量 %d（PROJ 一阶小角口径）" % i)
	var cfneg := base.duplicate()
	cfneg["rx_as"] = -0.3; cfneg["ry_as"] = 0.2; cfneg["rz_as"] = -0.5
	cfneg["convention"] = "CF"
	var res_cfneg := B.transform(cfneg)
	var o_cfneg: Array = _first(res_cfneg)
	for i in 3:
		assert_almost_eq(o_cfneg[i], o_pv[i], 1e-12, "通用 CF(反角)=PV 分量 %d（模块内自检）" % i)
		assert_almost_eq(o_cfneg[i], GEN_PV_OUT[i], 1e-4, "通用 CF(反角) vs pyproj 分量 %d" % i)

func test_three_param_translation_only() -> void:
	# 三参数（仅平移）：无旋转无尺度时直接加平移
	var res := B.transform({
		"src_xyz": [_pt(3657660.66, 255768.55, 5201382.11)],
		"tx_m": 0.0, "ty_m": 0.0, "tz_m": 4.5,
		"rx_as": 0.0, "ry_as": 0.0, "rz_as": 0.0,
		"scale_ppm": 0.0, "convention": "PV",
	})
	var out: Array = _first(res)
	assert_almost_eq(out[0], 3657660.66, 1e-12, "三参数 x 不变")
	assert_almost_eq(out[1], 255768.55, 1e-12, "三参数 y 不变")
	assert_almost_eq(out[2], 5201386.61, 1e-12, "三参数 z 加 4.5")

func test_solve_recovers_known_7param() -> void:
	# 【构造】已知参数生成目标点（精确三角），LS 求参应恢复；期望值经 numpy lstsq 复核
	var known := {
		"src_xyz": SRC5,
		"tx_m": 1.0, "ty_m": 2.0, "tz_m": 3.0,
		"rx_as": 0.3, "ry_as": -0.2, "rz_as": 0.5,
		"scale_ppm": 0.5, "convention": "PV",
	}
	var fwd := B.transform(known)
	assert_true(fwd["ok"], "生成目标点应成功")
	var dst: Array = fwd["value"]["points_m"]
	var res := B.solve({"src_xyz": SRC5, "dst_xyz": dst, "convention": "PV"})
	assert_true(res["ok"], "七参数求参应成功：" + String(res.get("error", "")))
	var v: Dictionary = res["value"]
	assert_almost_eq(v["tx_m"], 1.0000110, 1e-4, "tx（numpy 复核 1.0000110）")
	assert_almost_eq(v["ty_m"], 1.9999844, 1e-4, "ty（numpy 复核 1.9999844）")
	assert_almost_eq(v["tz_m"], 3.0000219, 1e-4, "tz（numpy 复核 3.0000219）")
	assert_almost_eq(v["rx_as"], 0.3, 1e-5, "rx 应恢复 0.3″")
	assert_almost_eq(v["ry_as"], -0.2, 1e-5, "ry 应恢复 −0.2″")
	assert_almost_eq(v["rz_as"], 0.5, 1e-5, "rz 应恢复 0.5″")
	assert_almost_eq(v["scale_ppm"], 0.5, 1e-4, "scale 应恢复 0.5 ppm")
	assert_eq(int(v["redundancy"]), 8, "自由度 15−7")
	assert_almost_eq(v["sigma0_m"], 9.31e-8, 1e-9, "σ0（线性化残差，numpy 复核 9.309e-8）")

func test_solve_cf_convention_and_protocol() -> void:
	var known := {
		"src_xyz": SRC5,
		"tx_m": 1.0, "ty_m": 2.0, "tz_m": 3.0,
		"rx_as": 0.3, "ry_as": -0.2, "rz_as": 0.5,
		"scale_ppm": 0.5, "convention": "CF",
	}
	var fwd := B.transform(known)
	var dst: Array = fwd["value"]["points_m"]
	var res := B.solve({"src_xyz": SRC5, "dst_xyz": dst, "convention": "CF"})
	assert_true(res["ok"], "CF 求参应成功：" + String(res.get("error", "")))
	var v: Dictionary = res["value"]
	assert_eq(v["convention"], "CF", "约定回显")
	assert_almost_eq(v["rx_as"], 0.3, 1e-5, "CF 约定 rx 恢复")
	assert_almost_eq(v["rz_as"], 0.5, 1e-5, "CF 约定 rz 恢复")
	# 残差表逐点 3 分量
	var residuals: Array = v["residuals_m"]
	assert_eq(residuals.size(), 5, "残差表行数=点数")
	var row0: Array = residuals[0]
	assert_eq(row0.size(), 4, "残差行 [点号, vx, vy, vz]")
	for r: Array in residuals:
		for k in 3:
			assert_almost_eq(r[k + 1], 0.0, 1e-6, "第 %d 点残差分量 %d 应≈0" % [int(r[0]), k])

func test_solve_outlier_flagged() -> void:
	# 【构造】8 点精确线性数据 + 第 4 点 ΔX 注入 +3.0 m 粗差 → 3σ 检核应给出中文提示
	# （网形与粗差量级经 numpy 预演：|v|/σ0=3.82，可靠触发）
	var src := [
		_pt(4200000.0, 300000.0, 4800000.0),
		_pt(4100000.0, 500000.0, 4850000.0),
		_pt(4000000.0, 700000.0, 4900000.0),
		_pt(3900000.0, 900000.0, 4950000.0),
		_pt(3800000.0, 1100000.0, 5000000.0),
		_pt(3700000.0, 1300000.0, 5050000.0),
		_pt(4300000.0, 800000.0, 4820000.0),
		_pt(3650000.0, 600000.0, 5100000.0),
	]
	var tx := 1.5
	var ty := -2.0
	var tz := 3.7
	var rx := 0.4 * PI / 648000.0
	var ry := -0.3 * PI / 648000.0
	var rz := 0.6 * PI / 648000.0
	var ds := 0.7e-6
	var dst := []
	for q: Array in src:
		dst.append([
			q[0] + tx + ds * q[0] - rz * q[1] + ry * q[2],
			q[1] + ty + ds * q[1] - rx * q[2] + rz * q[0],
			q[2] + tz + ds * q[2] + rx * q[1] - ry * q[0],
		])
	dst[3][0] += 3.0  # 注入粗差
	var res := B.solve({"src_xyz": src, "dst_xyz": dst, "convention": "PV"})
	assert_true(res["ok"], "含粗差求参仍应成功：" + String(res.get("error", "")))
	var v: Dictionary = res["value"]
	var outliers: Array = v["outliers"]
	assert_true(outliers.has(4), "第 4 点应被判为粗差，实际 outliers=%s" % str(outliers))
	var warnings: Array = v["warnings"]
	assert_true(warnings.size() > 0, "应输出中文粗差提示")
	if warnings.size() > 0:
		assert_true(String(warnings[0]).contains("粗差"), "提示应含“粗差”字样：%s" % str(warnings[0]))
	assert_almost_eq(v["max_res_m"], 2.574, 0.2, "最大点残差量级（numpy 预演 2.574）")
	# 无粗差对照：同一套数据去掉粗差 → 无提示
	dst[3][0] -= 3.0
	var res2 := B.solve({"src_xyz": src, "dst_xyz": dst, "convention": "PV"})
	var w2: Array = res2["value"]["warnings"]
	assert_eq(w2.size(), 0, "无粗差数据不应有提示")

func test_solve_three_param() -> void:
	# 三参数求参：目标 = 源 + (1,2,3)，单点即可
	var src := [_pt(1000.0, 2000.0, 3000.0)]
	var dst := [_pt(1001.0, 2002.0, 3003.0)]
	var res := B.solve({"src_xyz": src, "dst_xyz": dst, "three_param": true})
	assert_true(res["ok"], "三参数求参应成功：" + String(res.get("error", "")))
	var v: Dictionary = res["value"]
	assert_almost_eq(v["tx_m"], 1.0, 1e-12, "tx")
	assert_almost_eq(v["ty_m"], 2.0, 1e-12, "ty")
	assert_almost_eq(v["tz_m"], 3.0, 1e-12, "tz")
	assert_false(v.has("rx_as"), "三参数不应输出旋转角")
	var res7 := B.solve({"src_xyz": src, "dst_xyz": dst})
	assert_false(bool(res7["ok"]), "七参数求参单点应失败")
	assert_true(String(res7["error"]).contains("公共点"), "错误应提示公共点数量")

func test_input_validation_chinese_errors() -> void:
	var ok_params := {
		"src_xyz": [_pt(1.0, 2.0, 3.0)],
		"tx_m": 0.0, "ty_m": 0.0, "tz_m": 0.0, "convention": "PV",
	}
	var cases := [
		{"src_xyz": [], "_expect": "点集为空"},
		{"src_xyz": [[1.0, 2.0]], "_expect": "分量"},
		{"src_xyz": [[1.0, 2.0, "abc"]], "_expect": "有效数字"},
		{"src_xyz": [_pt(1.0, 2.0, NAN)], "_expect": "有限"},
		{"src_xyz": [_pt(1.0, 2.0, 3.0)], "convention": "XX", "_expect": "约定"},
		{"src_xyz": [_pt(1.0, 2.0, 3.0)], "tx_m": "abc", "_expect": "有效数字"},
	]
	for c: Dictionary in cases:
		var p := ok_params.duplicate()
		p.merge(c, true)
		var res := B.transform(p)
		assert_false(bool(res["ok"]), "非法输入应失败：%s" % str(c["_expect"]))
		assert_true(String(res["error"]).contains(String(c["_expect"])), "中文错误应含关键字：%s → %s" % [str(c["_expect"]), String(res["error"])])
		assert_true((res["value"] as Dictionary).is_empty(), "失败时 value 应为空")
	# 求参：点数不一致
	var res2 := B.solve({"src_xyz": [_pt(1, 2, 3), _pt(4, 5, 6)], "dst_xyz": [_pt(1, 2, 3)]})
	assert_false(bool(res2["ok"]), "求参点数不一致应失败")
	assert_true(String(res2["error"]).contains("数量不一致"), "中文错误：数量不一致")
