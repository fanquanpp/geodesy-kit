# tests/transform/test_rtk.gd —— RTK 参数计算（公共点求参 + 检核点回代残差检核 + 合格结论）
# 向量来源：
#   【权威·EPSG:1314 场景（本任务分配向量）】EPSG:1314（WGS84→NTF，官方 helmert 参数）：
#     T=(446.448, −125.157, 542.06) m，r=(0.15, 0.247, 0.842)″，dS=−20.489 ppm，
#     该参数不在 data/crs_presets.json，参数在测试内自备；
#     4 公共点（精确三角 PV 正算生成目标坐标，不经被测模块）+ 1 检核点，
#     检核点回代较差应≈0（1e-4 m 口径，线性化求参模型误差 O(ε²)·X）。
#   【自洽】平面四参数 RTK 场景：真值 dx=100、dy=200、m=1.0001、α=0.5°，
#     4 公共点 + 1 检核点，检核点回代较差 0。
extends "res://tests/test_case_base.gd"

const RK := preload("res://core/transform/rtk_params.gd")
const FP := preload("res://core/transform/four_param.gd")

# EPSG:1314 场景公共点源坐标（本会话构造的空间直角控制点网形）
const COMMON_SRC := [
	[4000000.0, 500000.0, 4933000.0],
	[4200000.0, 300000.0, 4800000.0],
	[3800000.0, 700000.0, 5100000.0],
	[4100000.0, 600000.0, 4950000.0],
]
const CHECK_SRC := [4050000.0, 550000.0, 4980000.0]
# 检核点已知目标坐标（真值参数精确三角 PV 正算，Python 独立复核）
const CHECK_DST := [4050367.185779, 549876.484878, 4980435.575004]

func _truth_dst_space(pts: Array) -> Array:
	# 独立实现：精确三角 PV：X2 = T + (1+dS)·R·X1（R = Rz·Ry·Rx）
	var t := [446.448, -125.157, 542.06]
	var r := [0.15 * PI / 648000.0, 0.247 * PI / 648000.0, 0.842 * PI / 648000.0]
	var ds := -20.489e-6
	var cx := cos(r[0]); var sx := sin(r[0])
	var cy := cos(r[1]); var sy := sin(r[1])
	var cz := cos(r[2]); var sz := sin(r[2])
	var Rx := [[1.0, 0.0, 0.0], [0.0, cx, -sx], [0.0, sx, cx]]
	var Ry := [[cy, 0.0, sy], [0.0, 1.0, 0.0], [-sy, 0.0, cy]]
	var Rz := [[cz, -sz, 0.0], [sz, cz, 0.0], [0.0, 0.0, 1.0]]
	var M := []
	for i in 3:
		var row := []
		for j in 3:
			var s := 0.0
			for k in 3:
				s += Rz[i][k] * Ry[k][j]
			row.append(s)
		M.append(row)
	var R := []
	for i in 3:
		var row2 := []
		for j in 3:
			var s2 := 0.0
			for k in 3:
				s2 += M[i][k] * Rx[k][j]
			row2.append(s2)
		R.append(row2)
	var out := []
	for q: Array in pts:
		var res := []
		for i in 3:
			var s3 := 0.0
			for j in 3:
				s3 += R[i][j] * float(q[j])
			res.append(t[i] + (1.0 + ds) * s3)
		out.append(res)
	return out

func test_space_scenario_full_pass() -> void:
	var dst := _truth_dst_space(COMMON_SRC)
	var ck_dst: Array = _truth_dst_space([CHECK_SRC])[0]
	var res := RK.compute({
		"mode": "space",
		"convention": "PV",
		"common_src": COMMON_SRC,
		"common_dst": dst,
		"check_src": [CHECK_SRC],
		"check_dst": [ck_dst],
		"limit_m": "0.05",
	})
	assert_true(res["ok"], "空间场景应成功：" + String(res.get("error", "")))
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	# 参数恢复（1e-5 口径，线性化 LS 模型误差 + 数值噪声）
	var params: Dictionary = v["params"]
	assert_almost_eq(float(params["tx_m"]), 446.448, 1e-4, "tx 恢复")
	assert_almost_eq(float(params["ty_m"]), -125.157, 1e-4, "ty 恢复")
	assert_almost_eq(float(params["tz_m"]), 542.06, 1e-4, "tz 恢复")
	assert_almost_eq(float(params["rx_as"]), 0.15, 1e-4, "rx 恢复")
	assert_almost_eq(float(params["ry_as"]), 0.247, 1e-4, "ry 恢复")
	assert_almost_eq(float(params["rz_as"]), 0.842, 1e-4, "rz 恢复")
	assert_almost_eq(float(params["scale_ppm"]), -20.489, 1e-4, "scale 恢复")
	# 检核点回代残差表与结论
	var rows: Array = v["check_residuals"]
	assert_eq(rows.size(), 1, "检核残差表 1 行")
	var row0: Dictionary = rows[0]
	assert_almost_eq(float(row0["ds_m"]), 0.0, 1e-3, "检核点回代较差≈0（1e-3 m 口径）")
	assert_true(bool(v["ok_limit"]), "限差 0.05 m 内应判合格")
	assert_true(String(v["conclusion"]).contains("合格"), "结论应含“合格”：%s" % str(v["conclusion"]))
	assert_eq(String(v["basis"]).contains("用户输入"), true, "basis 注明限差由用户输入")
	# 协议完整性
	assert_true((res["steps"] as Array).size() >= 4, "步骤数 ≥4")
	for st: Dictionary in res["steps"]:
		assert_true(st.has_all(["title", "formula", "substitution", "result"]), "步骤四字段")
	assert_true(String(res["formula"]).contains("RTK"), "formula 说明 RTK")
	# 结论步骤应含"合格"
	var last: Dictionary = res["steps"][res["steps"].size() - 1]
	assert_true(String(last["result"]).contains("合格"), "结论步骤结果含合格")

func test_space_scenario_exceeds_limit() -> void:
	# 同一场景但限差收紧到 1e-9 m：回代较差（约 3e-4 m 线性化模型误差）必超限 → 结论"超限"
	var dst := _truth_dst_space(COMMON_SRC)
	var ck_dst: Array = _truth_dst_space([CHECK_SRC])[0]
	var res := RK.compute({
		"mode": "space",
		"common_src": COMMON_SRC,
		"common_dst": dst,
		"check_src": [CHECK_SRC],
		"check_dst": [ck_dst],
		"limit_m": 1e-9,
	})
	assert_true(res["ok"], "收紧限差场景应成功")
	var v: Dictionary = res["value"]
	assert_false(bool(v["ok_limit"]), "限差 1e-9 m 应判超限")
	assert_true(String(v["conclusion"]).contains("超限"), "结论应含“超限”：%s" % str(v["conclusion"]))

func test_plane_scenario_full_pass() -> void:
	# 平面四参数 RTK：真值 dx=100, dy=200, m=1.0001, α=0.5°，4 公共点 + 1 检核点
	var al := 0.5 * PI / 180.0
	var m := 1.0001
	var src := [[1000.0, 1000.0], [3000.0, 2000.0], [2000.0, 3500.0], [4500.0, 1500.0]]
	var dst := []
	for q: Array in src:
		dst.append([
			100.0 + m * (q[0] * cos(al) - q[1] * sin(al)),
			200.0 + m * (q[0] * sin(al) + q[1] * cos(al)),
		])
	var ck_in := [2000.0, 3000.0]
	var ck_out := [
		100.0 + m * (ck_in[0] * cos(al) - ck_in[1] * sin(al)),
		200.0 + m * (ck_in[0] * sin(al) + ck_in[1] * cos(al)),
	]
	var res := RK.compute({
		"mode": "plane",
		"common_src": src,
		"common_dst": dst,
		"check_src": [ck_in],
		"check_dst": [ck_out],
		"limit_m": "0.05",
	})
	assert_true(res["ok"], "平面场景应成功：" + String(res.get("error", "")))
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	var params: Dictionary = v["params"]
	assert_almost_eq(float(params["dx_m"]), 100.0, 1e-9, "dx 恢复")
	assert_almost_eq(float(params["dy_m"]), 200.0, 1e-9, "dy 恢复")
	assert_almost_eq(float(params["scale"]), 1.0001, 1e-12, "m 恢复")
	assert_almost_eq(float(params["alpha_deg"]), 0.5, 1e-9, "α 恢复")
	var rows: Array = v["check_residuals"]
	assert_eq(rows.size(), 1, "检核残差表 1 行")
	assert_almost_eq(float(rows[0]["ds_m"]), 0.0, 1e-9, "检核较差 0")
	assert_true(bool(v["ok_limit"]), "应判合格")
	assert_true(String(v["conclusion"]).contains("合格"), "结论含合格")

func test_no_check_points_gives_clear_conclusion() -> void:
	var dst := _truth_dst_space(COMMON_SRC)
	var res := RK.compute({
		"mode": "space",
		"common_src": COMMON_SRC,
		"common_dst": dst,
		"limit_m": "0.05",
	})
	assert_true(res["ok"], "无检核点仍应成功求参")
	var v: Dictionary = res["value"]
	assert_false(bool(v["ok_limit"]), "无检核点不能判合格")
	assert_true(String(v["conclusion"]).contains("无检核点"), "结论应提示无检核点：%s" % str(v["conclusion"]))
	assert_eq((v["check_residuals"] as Array).size(), 0, "检核残差表为空")

func test_limit_required_from_user() -> void:
	# 限差是协议必填：未输入给中文错误，basis 要求注明由用户输入
	var src2 := [[1000.0, 1000.0], [3000.0, 2000.0]]
	var dst2 := [[1964.684228582658, 3034.4971817863407], [3928.959162349816, 4103.900840174523]]
	var res := RK.compute({"mode": "plane", "common_src": src2, "common_dst": dst2})
	assert_false(bool(res["ok"]), "缺限差应失败")
	assert_true(String(res["error"]).contains("限差"), "中文错误：限差")
	var res_bad := RK.compute({"mode": "plane", "common_src": src2, "common_dst": dst2, "limit_m": "abc"})
	assert_false(bool(res_bad["ok"]), "非法限差应失败")
	var res_neg := RK.compute({"mode": "plane", "common_src": src2, "common_dst": dst2, "limit_m": "-1"})
	assert_false(bool(res_neg["ok"]), "负限差应失败")

func test_input_validation_chinese_errors() -> void:
	var ok := {"mode": "plane", "common_src": [[1.0, 1.0]], "common_dst": [[1.0, 1.0]], "limit_m": "0.05"}
	var cases := [
		{"mode": "xyz", "_expect": "场景"},
		{"common_src": [], "_expect": "为空"},
		{"common_src": [[1.0, 1.0]], "common_dst": [[1.0, 1.0], [2.0, 2.0]], "_expect": "数量不一致"},
		{"common_src": [[1.0, 1.0]], "common_dst": [[1.0, 1.0]], "_expect": "至少需要 2 个公共点"},
		{"convention": "XX", "mode": "space", "common_src": [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0], [7.0, 8.0, 9.0], [10.0, 11.0, 12.0]],
			"common_dst": [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0], [7.0, 8.0, 9.0], [10.0, 11.0, 12.0]], "_expect": "约定"},
	]
	for c: Dictionary in cases:
		var p := ok.duplicate()
		p.merge(c, true)
		var res := RK.compute(p)
		assert_false(bool(res["ok"]), "非法输入应失败：%s" % str(c["_expect"]))
		assert_true(String(res["error"]).contains(String(c["_expect"])), "中文错误：%s → %s" % [str(c["_expect"]), String(res["error"])])
	# 检核点不成对
	var res_pair := RK.compute({"mode": "plane", "common_src": [[1000.0, 1000.0], [3000.0, 2000.0]],
		"common_dst": [[1964.684228582658, 3034.4971817863407], [3928.959162349816, 4103.900840174523]],
		"check_src": [[2000.0, 3000.0]], "limit_m": "0.05"})
	assert_false(bool(res_pair["ok"]), "检核点只有源坐标应失败")
	assert_true(String(res_pair["error"]).contains("成对"), "中文错误：成对输入")
