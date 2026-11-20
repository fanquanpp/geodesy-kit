# tests/transform/test_four_param.gd —— GK-M4-2（A8）平面四参数求参 + 正反算
# 向量来源：
#   【构造·本任务分配权威向量】四参数恢复：公共点 (1000,1000),(3000,2000)，真值
#     dx=1000, dy=2000, m=1.0002, α=2° → 解出 (1000.0000, 2000.0000, 1.000200, 2.000000°)；
#     检核点 (2000,4000) 残差 0。目标点坐标在测试内用独立显式三角公式生成（不经被测模块），
#     并经 numpy lstsq（独立实现）复核。
extends "res://tests/test_case_base.gd"

const F := preload("res://core/transform/four_param.gd")

# 真值参数生成的公共点目标坐标（测试内独立显式三角公式 + python 复核）
const SRC2 := [[1000.0, 1000.0], [3000.0, 2000.0]]
const DST2 := [
	[1964.684228582658, 3034.4971817863407],
	[3928.959162349816, 4103.900840174523],
]
# 检核点 (2000,4000) 的正算目标（真值参数，显式三角独立计算）
const CHECK_IN := [2000.0, 4000.0]
const CHECK_OUT := [2859.5555039616333, 6068.175773941681]

func _truth_dst(pts: Array) -> Array:
	# 独立实现：X = dx + m(x·cosα − y·sinα)，Y = dy + m(x·sinα + y·cosα)
	var al := 2.0 * PI / 180.0
	var out := []
	for q: Array in pts:
		out.append([
			1000.0 + 1.0002 * (q[0] * cos(al) - q[1] * sin(al)),
			2000.0 + 1.0002 * (q[0] * sin(al) + q[1] * cos(al)),
		])
	return out

func test_solve_recovers_assigned_vector() -> void:
	var res := F.solve({"src_xy": SRC2, "dst_xy": DST2})
	assert_true(res["ok"], "两点求参应成功：" + String(res.get("error", "")))
	var v: Dictionary = res["value"]
	assert_almost_eq(v["dx_m"], 1000.0, 1e-9, "dx 应恢复 1000.0000")
	assert_almost_eq(v["dy_m"], 2000.0, 1e-9, "dy 应恢复 2000.0000")
	assert_almost_eq(v["scale"], 1.0002, 1e-12, "m 应恢复 1.000200")
	assert_almost_eq(v["alpha_deg"], 2.0, 1e-9, "α 应恢复 2.000000°")
	# 两点求参无多余观测：σ0=0、无 3σ 检核能力（如实提示）
	assert_almost_eq(v["sigma0_m"], 0.0, 1e-15, "无多余观测 σ0=0")
	assert_eq(int(v["redundancy"]), 0, "自由度 0")
	assert_true((v["warnings"] as Array).is_empty(), "无多余观测无粗差提示")
	# 残差表
	var residuals: Array = v["residuals_m"]
	assert_eq(residuals.size(), 2, "残差表行数")
	for r: Array in residuals:
		assert_almost_eq(r[1], 0.0, 1e-9, "残差 vx≈0")
		assert_almost_eq(r[2], 0.0, 1e-9, "残差 vy≈0")
	# alpha_dms 文本
	assert_eq(String(v["alpha_dms"]), "2°00′00.00″", "角文本")

func test_solve_target_from_independent_trig() -> void:
	# 目标坐标由测试内独立三角公式再生成一遍（与常量互为双路径）
	var dst := _truth_dst(SRC2)
	assert_vector_almost_eq(dst[0], DST2[0], 1e-9, "独立生成 dst[0] 与常量一致")
	assert_vector_almost_eq(dst[1], DST2[1], 1e-9, "独立生成 dst[1] 与常量一致")
	var res := F.solve({"src_xy": SRC2, "dst_xy": dst})
	var v: Dictionary = res["value"]
	assert_almost_eq(v["dx_m"], 1000.0, 1e-9, "dx")
	assert_almost_eq(v["scale"], 1.0002, 1e-12, "m")
	assert_almost_eq(v["alpha_deg"], 2.0, 1e-9, "α")

func test_forward_check_point_residual_zero() -> void:
	# 求参 → 用解出的参数正算检核点 (2000,4000) → 与真值目标一致（残差 0）
	var res_solve := F.solve({"src_xy": SRC2, "dst_xy": DST2})
	var v: Dictionary = res_solve["value"]
	var res_fwd := F.apply({
		"mode": "fwd",
		"dx_m": v["dx_m"], "dy_m": v["dy_m"],
		"scale": v["scale"], "alpha_deg": v["alpha_deg"],
		"src_xy": [CHECK_IN],
	})
	assert_true(res_fwd["ok"], "正算应成功：" + String(res_fwd.get("error", "")))
	var out: Array = res_fwd["value"]["points_m"][0]
	for i in 2:
		assert_almost_eq(out[i], CHECK_OUT[i], 1e-9, "检核点分量 %d（残差应为 0）" % i)

func test_inverse_roundtrip() -> void:
	var res_fwd := F.apply({
		"mode": "fwd", "dx_m": 1000.0, "dy_m": 2000.0, "scale": 1.0002, "alpha_deg": 2.0,
		"src_xy": [CHECK_IN, [3500.0, 1250.0]],
	})
	var fwd_pts: Array = res_fwd["value"]["points_m"]
	var res_inv := F.apply({
		"mode": "inv", "dx_m": 1000.0, "dy_m": 2000.0, "scale": 1.0002, "alpha_deg": 2.0,
		"dst_xy": fwd_pts,
	})
	var inv_pts: Array = res_inv["value"]["points_m"]
	assert_almost_eq(inv_pts[0][0], 2000.0, 1e-12, "反算回 x")
	assert_almost_eq(inv_pts[0][1], 4000.0, 1e-12, "反算回 y")
	assert_almost_eq(inv_pts[1][0], 3500.0, 1e-12, "反算回第二点 x")
	assert_almost_eq(inv_pts[1][1], 1250.0, 1e-12, "反算回第二点 y")

func test_solve_multi_point_with_redundancy() -> void:
	# 9 公共点（真值生成）+ 第 5 点注入 2.0 m 粗差 → 3σ 提示
	# （网形与粗差量级经 numpy 预演：|v|/σ0=3.36，可靠触发；小网形单粗差受杠杆限制
	#   可能低于 3σ，属测量可靠性理论现象，测试用足够冗余的网形。）
	var src := [
		[1000.0, 1000.0], [3000.0, 2000.0], [1500.0, 3500.0], [4000.0, 4000.0],
		[2500.0, 800.0], [2000.0, 1500.0], [3500.0, 1000.0], [800.0, 2000.0], [1200.0, 3000.0],
	]
	var dst := _truth_dst(src)
	dst[4][0] += 2.0
	var res := F.solve({"src_xy": src, "dst_xy": dst})
	assert_true(res["ok"], "多点求参应成功：" + String(res.get("error", "")))
	var v: Dictionary = res["value"]
	assert_eq(int(v["redundancy"]), 14, "自由度 2n−4=14")
	var outliers: Array = v["outliers"]
	assert_true(outliers.has(5), "第 5 点应判粗差，实际 outliers=%s" % str(outliers))
	assert_true((v["warnings"] as Array).size() > 0, "应输出中文粗差提示")
	# 去掉粗差后参数应精确恢复且无提示
	dst[4][0] -= 2.0
	var res2 := F.solve({"src_xy": src, "dst_xy": dst})
	var v2: Dictionary = res2["value"]
	assert_almost_eq(v2["dx_m"], 1000.0, 1e-9, "多点无粗差 dx")
	assert_almost_eq(v2["scale"], 1.0002, 1e-12, "多点无粗差 m")
	assert_eq((v2["warnings"] as Array).size(), 0, "无粗差提示")

func test_input_validation_chinese_errors() -> void:
	var cases := [
		{"src_xy": [], "dst_xy": [[1.0, 1.0]], "_expect": "点集为空"},
		{"src_xy": [[1.0, 1.0]], "dst_xy": [[1.0, 1.0]], "_expect": "至少需要 2 个公共点"},
		{"src_xy": [[1.0, 1.0], [2.0, 2.0]], "dst_xy": [[1.0, 1.0]], "_expect": "数量不一致"},
		{"src_xy": [[1.0, 1.0], ["abc", 2.0]], "dst_xy": [[1.0, 1.0], [2.0, 2.0]], "_expect": "有效数字"},
		{"src_xy": [[1.0, 1.0], [NAN, 2.0]], "dst_xy": [[1.0, 1.0], [2.0, 2.0]], "_expect": "有限"},
		{"src_xy": [[1.0], [2.0, 2.0]], "dst_xy": [[1.0, 1.0], [2.0, 2.0]], "_expect": "分量"},
	]
	for c: Dictionary in cases:
		var res := F.solve(c)
		assert_false(bool(res["ok"]), "非法输入应失败：%s" % str(c["_expect"]))
		assert_true(String(res["error"]).contains(String(c["_expect"])), "中文错误：%s → %s" % [str(c["_expect"]), String(res["error"])])
	# apply 模式校验
	var bad_mode := F.apply({"mode": "xyz", "dx_m": 0.0, "dy_m": 0.0, "scale": 1.0, "alpha_deg": 0.0, "src_xy": [[1.0, 1.0]]})
	assert_false(bool(bad_mode["ok"]), "未知模式应失败")
	assert_true(String(bad_mode["error"]).contains("模式"), "中文错误：模式")
	var bad_param := F.apply({"mode": "fwd", "dx_m": "abc", "dy_m": 0.0, "scale": 1.0, "alpha_deg": 0.0, "src_xy": [[1.0, 1.0]]})
	assert_false(bool(bad_param["ok"]), "非法参数应失败")
	assert_true(String(bad_param["error"]).contains("有效数字"), "中文错误：参数数字")
	var zero_scale := F.apply({"mode": "fwd", "dx_m": 0.0, "dy_m": 0.0, "scale": 0.0, "alpha_deg": 0.0, "src_xy": [[1.0, 1.0]]})
	assert_false(bool(zero_scale["ok"]), "尺度为 0 应失败")

func test_protocol_shape() -> void:
	var res := F.solve({"src_xy": SRC2, "dst_xy": DST2})
	assert_true((res["steps"] as Array).size() >= 5, "求参步骤 ≥5")
	for st: Dictionary in res["steps"]:
		assert_true(st.has_all(["title", "formula", "substitution", "result"]), "步骤四字段")
	assert_true(String(res["formula"]).contains("四参数"), "formula 说明四参数")
	var res2 := F.apply({"mode": "fwd", "dx_m": 1.0, "dy_m": 2.0, "scale": 1.0, "alpha_deg": 0.0, "src_xy": [[1.0, 1.0]]})
	assert_true((res2["steps"] as Array).size() >= 2, "正算步骤 ≥2")
	assert_eq(res2["value"]["x_m"], 2.0, "单点 value 附 x_m")
