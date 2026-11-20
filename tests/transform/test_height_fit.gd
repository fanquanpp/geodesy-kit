# tests/transform/test_height_fit.gd —— GK-M4-3（A10）GNSS 高程拟合（平面/曲面/带状分段）+ 预测
# 向量来源：
#   【构造·本任务分配向量】已知系数 + 噪声恢复：
#     平面真值 H = 10 + 0.002x − 0.001y，4×4 格网 16 点精确恢复（系数、残差、预测）；
#     加确定性噪声后与 numpy lstsq（独立实现）逐位对照；
#     曲面真值 H = 10 + 0.002x − 0.001y − 2e-7x² + 1e-7y² + 3e-8xy（20 点精确恢复）；
#     带状分段两段线性真值（每段中点/端点/外插行为）；
#     粗差：精确平面数据 + 第 6 点 +0.8 m → 3σ 检核应提示（行为先经 numpy 预演确认）。
extends "res://tests/test_case_base.gd"

const HF := preload("res://core/transform/height_fit.gd")

func _grid16() -> Array:
	var pts := []
	for y in [0, 1000, 2000, 3000]:
		for x in [0, 1000, 2000, 3000]:
			pts.append([float(x), float(y)])
	return pts

func _grid20() -> Array:
	var pts := []
	for y in [0, 1500, 3000, 4500]:
		for x in [0, 1000, 2000, 3000, 4000]:
			pts.append([float(x), float(y)])
	return pts

func _arr(p: Array) -> Array:
	# h 数组直接给 Array[float]
	return p

func test_plane_exact_recovery() -> void:
	# 真值 H = 10 + 0.002x − 0.001y（16 点，无噪声）
	var xy := _grid16()
	var h := []
	for q: Array in xy:
		h.append(10.0 + 0.002 * q[0] - 0.001 * q[1])
	var res := HF.fit({"xy": xy, "h": h, "model": "plane"})
	assert_true(res["ok"], "平面拟合应成功：" + String(res.get("error", "")))
	var v: Dictionary = res["value"]
	var ca: Array = v["coeffs_abs"]
	assert_almost_eq(ca[0], 10.0, 1e-12, "绝对形式 A0=10")
	assert_almost_eq(ca[1], 0.002, 1e-15, "绝对形式 A1=0.002")
	assert_almost_eq(ca[2], -0.001, 1e-15, "绝对形式 A2=−0.001")
	var cc: Array = v["coeffs_center"]
	assert_eq(cc.size(), 3, "中心化系数 3 个")
	assert_almost_eq(v["sigma0_m"], 0.0, 1e-12, "精确数据 σ0=0")
	assert_almost_eq(v["rms_m"], 0.0, 1e-12, "精确数据 RMS=0")
	assert_eq(int(v["redundancy"]), 13, "自由度 16−3")
	# 预测（重心 x0=y0=1500，模型字典回传 predict）
	var pred := HF.predict({"model": v["model"], "x": 1500.0, "y": 2500.0})
	assert_true(pred["ok"], "预测应成功：" + String(pred.get("error", "")))
	assert_almost_eq(pred["value"]["h_m"], 10.0 + 3.0 - 2.5, 1e-12, "预测点 (1500,2500) H=10.5")
	assert_false(bool(pred["value"]["extrapolated"]), "范围内预测不外插")

func test_plane_with_noise_matches_numpy() -> void:
	# 确定性噪声（本会话生成），期望系数与 σ0 经 numpy lstsq 独立复核
	var xy := _grid16()
	var h := []
	var noise := [0.005, -0.004, 0.003, -0.002, 0.001, -0.005, 0.004, -0.003, 0.002, -0.001, 0.005, -0.004, 0.003, -0.002, 0.001, -0.005]
	for i in xy.size():
		var q: Array = xy[i]
		h.append(10.0 + 0.002 * q[0] - 0.001 * q[1] + noise[i])
	var res := HF.fit({"xy": xy, "h": h, "model": "plane"})
	assert_true(res["ok"], "含噪拟合应成功")
	var v: Dictionary = res["value"]
	var ca: Array = v["coeffs_abs"]
	# numpy: [10.002125, 0.00199875, −0.00100025]，σ0=0.0034779525365011455
	assert_almost_eq(ca[0], 10.002125, 1e-9, "A0（numpy 复核）")
	assert_almost_eq(ca[1], 0.00199875, 1e-12, "A1（numpy 复核）")
	assert_almost_eq(ca[2], -0.00100025, 1e-12, "A2（numpy 复核）")
	assert_almost_eq(v["sigma0_m"], 0.0034779525365011455, 1e-10, "σ0（numpy 复核）")
	assert_false(bool(v["outliers"].has(0)), "该噪声水平不应误报粗差")

func test_surface_exact_recovery() -> void:
	# 真值 H = 10 + 0.002x − 0.001y − 2e-7·x² + 1e-7·y² + 3e-8·xy（20 点）
	var xy := _grid20()
	var h := []
	for q: Array in xy:
		var x: float = q[0]
		var y: float = q[1]
		h.append(10.0 + 0.002 * x - 0.001 * y - 2e-7 * x * x + 1e-7 * y * y + 3e-8 * x * y)
	var res := HF.fit({"xy": xy, "h": h, "model": "surface"})
	assert_true(res["ok"], "曲面拟合应成功：" + String(res.get("error", "")))
	var v: Dictionary = res["value"]
	var ca: Array = v["coeffs_abs"]
	assert_eq(ca.size(), 6, "曲面系数 6 个")
	assert_almost_eq(ca[0], 10.0, 1e-9, "曲面 A0")
	assert_almost_eq(ca[1], 0.002, 1e-12, "曲面 A1")
	assert_almost_eq(ca[2], -0.001, 1e-12, "曲面 A2")
	assert_almost_eq(ca[3], -2e-7, 1e-18, "曲面 A3（x²）")
	assert_almost_eq(ca[4], 1e-7, 1e-18, "曲面 A4（y²）")
	assert_almost_eq(ca[5], 3e-8, 1e-18, "曲面 A5（xy）")
	assert_almost_eq(v["sigma0_m"], 0.0, 1e-12, "精确数据 σ0=0")
	# 预测：曲面代入
	var pred := HF.predict({"model": v["model"], "x": 2000.0, "y": 3000.0})
	var expect := 10.0 + 4.0 - 3.0 - 2e-7 * 4e6 + 1e-7 * 9e6 + 3e-8 * 6e6
	assert_almost_eq(pred["value"]["h_m"], expect, 1e-12, "曲面预测代入")

func test_strip_two_segments_exact() -> void:
	# 真值：seg0（u<2000）H = 10 + 0.002·(u−1000)；seg1（u≥2000）H = 14 − 0.001·(u−3000)
	var xy := []
	var h := []
	for u in [0.0, 500.0, 1000.0, 1500.0, 2000.0, 2500.0, 3000.0, 3500.0, 4000.0]:
		xy.append([u, 1000.0])  # axis=x，y 不参与
		if u < 2000.0:
			h.append(10.0 + 0.002 * (u - 1000.0))
		else:
			h.append(14.0 - 0.001 * (u - 3000.0))
	var res := HF.fit({"xy": xy, "h": h, "model": "strip", "segments": 2, "order": 1, "axis": "x"})
	assert_true(res["ok"], "带状分段拟合应成功：" + String(res.get("error", "")))
	var v: Dictionary = res["value"]
	var segs: Array = v["model"]["segments"]
	assert_eq(segs.size(), 2, "两段")
	var c0: Array = segs[0]["coeffs_center"]
	var c1: Array = segs[1]["coeffs_center"]
	assert_almost_eq(c0[0], 10.0, 1e-12, "seg0 c0=10")
	assert_almost_eq(c0[1], 0.002, 1e-15, "seg0 c1=0.002")
	assert_almost_eq(c1[0], 14.0, 1e-12, "seg1 c0=14")
	assert_almost_eq(c1[1], -0.001, 1e-15, "seg1 c1=−0.001")
	assert_almost_eq(v["sigma0_m"], 0.0, 1e-12, "精确数据 σ0=0")
	# 预测：各段中点、段尾归属、外插
	var p0 := HF.predict({"model": v["model"], "x": 1000.0, "y": 0.0})
	assert_almost_eq(p0["value"]["h_m"], 10.0, 1e-12, "seg0 中点 H=10")
	var p1 := HF.predict({"model": v["model"], "x": 3000.0, "y": 0.0})
	assert_almost_eq(p1["value"]["h_m"], 14.0, 1e-12, "seg1 中点 H=14")
	var p2 := HF.predict({"model": v["model"], "x": 4000.0, "y": 0.0})
	assert_almost_eq(p2["value"]["h_m"], 13.0, 1e-12, "u=4000 落 seg1 尾（ξ=1000）→ 13")
	var p3 := HF.predict({"model": v["model"], "x": 5000.0, "y": 0.0})
	assert_true(bool(p3["value"]["extrapolated"]), "u=5000 应判外插")
	assert_true((p3["value"]["warnings"] as Array).size() > 0, "外插应给中文提示")
	var a1: Array = segs[1]["coeffs_abs"]
	# seg1 绝对形式：H = 14 − 0.001·(u−3000) = 17 − 0.001u
	assert_almost_eq(a1[0], 17.0, 1e-12, "seg1 绝对 d0=17")
	assert_almost_eq(a1[1], -0.001, 1e-15, "seg1 绝对 d1=−0.001")

func test_blunder_flagged_with_3sigma() -> void:
	# 精确平面 + 第 6 点 +0.8 m 粗差（numpy 预演：σ0=0.212，v=−0.73 > 3σ=0.636 → 触发）
	var xy := _grid16()
	var h := []
	for i in xy.size():
		var q: Array = xy[i]
		var val: float = 10.0 + 0.002 * q[0] - 0.001 * q[1]
		if i == 5:
			val += 0.8
		h.append(val)
	var res := HF.fit({"xy": xy, "h": h, "model": "plane"})
	assert_true(res["ok"], "含粗差拟合应成功")
	var v: Dictionary = res["value"]
	assert_true((v["outliers"] as Array).has(6), "第 6 点应判粗差，实际 outliers=%s" % str(v["outliers"]))
	assert_true((v["warnings"] as Array).size() > 0, "应输出中文粗差提示")
	var w0: String = String((v["warnings"] as Array)[0])
	assert_true(w0.contains("粗差") and w0.contains("3σ"), "提示含“粗差”与“3σ”：%s" % w0)

func test_input_validation_chinese_errors() -> void:
	# 点数不足
	var res1 := HF.fit({"xy": [[1.0, 1.0]], "h": [10.0], "model": "plane"})
	assert_false(bool(res1["ok"]), "点数不足应失败")
	assert_true(String(res1["error"]).contains("点"), "中文错误：点数")
	# 点数/高程数不一致
	var res2 := HF.fit({"xy": [[1.0, 1.0], [2.0, 2.0]], "h": [10.0], "model": "plane"})
	assert_false(bool(res2["ok"]), "数量不一致应失败")
	assert_true(String(res2["error"]).contains("不一致"), "中文错误：不一致")
	# 未知模型
	var res3 := HF.fit({"xy": _grid16(), "h": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], "model": "cubic"})
	assert_false(bool(res3["ok"]), "未知模型应失败")
	assert_true(String(res3["error"]).contains("模型"), "中文错误：模型")
	# 非法数字
	var res4 := HF.fit({"xy": [[1.0, 1.0], [2.0, 2.0], ["abc", 3.0]], "h": [1.0, 2.0, 3.0], "model": "plane"})
	assert_false(bool(res4["ok"]), "非法坐标应失败")
	assert_true(String(res4["error"]).contains("有效数字"), "中文错误：数字")
	# 共线退化
	var col := [[0.0, 0.0], [1.0, 1.0], [2.0, 2.0]]
	var res5 := HF.fit({"xy": col, "h": [1.0, 2.0, 3.0], "model": "plane"})
	assert_false(bool(res5["ok"]), "共线退化应失败")
	assert_true(String(res5["error"]).contains("奇异"), "中文错误：奇异")
	# 带状分段：点数不足
	var res6 := HF.fit({"xy": [[0.0, 0.0], [1000.0, 0.0]], "h": [1.0, 2.0], "model": "strip", "segments": 2, "order": 1})
	assert_false(bool(res6["ok"]), "分段点数不足应失败")
	# 带状分段：轴向非法
	var res7 := HF.fit({"xy": [[0.0, 0.0], [1000.0, 0.0], [2000.0, 0.0], [3000.0, 0.0]], "h": [1.0, 2.0, 3.0, 4.0], "model": "strip", "axis": "z"})
	assert_false(bool(res7["ok"]), "非法轴应失败")
	# predict：缺模型
	var res8 := HF.predict({"x": 1.0, "y": 1.0})
	assert_false(bool(res8["ok"]), "缺模型应失败")
	assert_true(String(res8["error"]).contains("模型"), "中文错误：缺模型")
	# predict：坏模型字典
	var res9 := HF.predict({"model": {"kind": "unknown"}, "x": 1.0, "y": 1.0})
	assert_false(bool(res9["ok"]), "未知 kind 应失败")

func test_protocol_shape() -> void:
	var xy := _grid16()
	var h := []
	for q: Array in xy:
		h.append(10.0 + 0.002 * q[0])
	var res := HF.fit({"xy": xy, "h": h, "model": "plane"})
	assert_true((res["steps"] as Array).size() >= 4, "拟合步骤 ≥4")
	for st: Dictionary in res["steps"]:
		assert_true(st.has_all(["title", "formula", "substitution", "result"]), "步骤四字段")
	assert_true(String(res["formula"]).contains("平面拟合"), "formula 说明模型")
	assert_true((res["value"] as Dictionary).has("model"), "value 应含模型字典供预测复用")
