# tests/transform/test_itrf.gd —— GK-M4-4（F7）ITRF 历元传播 / 14 参数框架转换
# 向量来源：
#   【落地补·官方参数】ITRF2020→ITRF2014（历元 2015.0）14 参数取自 Altamimi et al. (2023)
#     《ITRF2020》论文 Table 6 / Eq.(6)（开放获取 PDF，本会话转录），并经 PROJ 注册表
#     EPSG:9991（pyproj 3.8 实查）逐项互证；测试将 data/itrf_params.json 中的数值
#     与论文 Table 6 逐项钉死，防止数据文件被无意改动。
#   【自洽·本任务分配向量】"无速率参数退化为普通七参数"：速率清零后与七参数公式
#     （测试内独立显式实现 T + D·X + ω×X）逐位一致；时变项 T(t)/D(t)/R(t) 与速度变换
#     Ẋ_to = Ẋ_from + Ṫ + Ḋ·X + Ṙ×X 用测试内独立算式复核（手算路径，python 复核）。
#   【外部核读】带旋转的 14 参数路径用 EPSG:10587 的 helmert 参数（pyproj 实跑）复核 ω×X 符号。
extends "res://tests/test_case_base.gd"

const I := preload("res://core/transform/itrf.gd")

const P2 := [4000000.0, 500000.0, 4933000.0]
# 论文 Table 6（ITRF2020→ITRF2014，2015.0）期望输出：python 手算（E 组）
const E_2015 := [3999999.99692, 499999.99889, 4932999.99932814]
const E_2023 := [3999999.99692, 499999.99808999995, 4933000.000928139]
# 速度变换期望（Ṫ=(0,−0.1,0.2)mm/年，Ḋ=0，Ṙ=0）
const E_VEL := [0.01, 0.0199, 0.030199999999999998]
# EPSG:10587 helmert（带旋转）pyproj 实跑期望（P2 输入）
const E_10587 := [4000000.375632197, 499999.55779715616, 4932999.736951824]

func _load_json() -> Dictionary:
	var f := FileAccess.open("res://data/itrf_params.json", FileAccess.READ)
	if f == null:
		_fail("data/itrf_params.json 无法读取")
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Dictionary):
		_fail("data/itrf_params.json 不是 JSON 对象")
		return {}
	return data

func _row2020_2014() -> Dictionary:
	var data := _load_json()
	if data.is_empty():
		return {}
	for row: Variant in data.get("transforms", []):
		if row is Dictionary and String(row.get("from", "")) == "ITRF2020" and String(row.get("to", "")) == "ITRF2014":
			return row
	_fail("参数表缺少 ITRF2020→ITRF2014 官方行")
	return {}

func test_json_matches_paper_table6() -> void:
	var row := _row2020_2014()
	assert_false(row.is_empty(), "官方行存在")
	if row.is_empty():
		return
	assert_almost_eq(float(row["t_epoch"]), 2015.0, 1e-12, "t_epoch=2015.0")
	var t: Array = row["t_mm"]
	assert_almost_eq(t[0], -1.4, 1e-12, "Tx=−1.4 mm")
	assert_almost_eq(t[1], -0.9, 1e-12, "Ty=−0.9 mm")
	assert_almost_eq(t[2], 1.4, 1e-12, "Tz=+1.4 mm")
	var tr: Array = row["t_rate_mm_y"]
	assert_almost_eq(tr[0], 0.0, 1e-12, "Ṫx=0.0")
	assert_almost_eq(tr[1], -0.1, 1e-12, "Ṫy=−0.1")
	assert_almost_eq(tr[2], 0.2, 1e-12, "Ṫz=+0.2")
	assert_almost_eq(float(row["d_ppb"]), -0.42, 1e-12, "D=−0.42 ppb")
	assert_almost_eq(float(row["d_rate_ppb_y"]), 0.0, 1e-12, "Ḋ=0")
	var r: Array = row["r_mas"]
	assert_almost_eq(r[0], 0.0, 1e-12, "Rx=0")
	assert_almost_eq(r[1], 0.0, 1e-12, "Ry=0")
	assert_almost_eq(r[2], 0.0, 1e-12, "Rz=0（定向与定向速率对齐条件）")
	var rr: Array = row["r_rate_mas_y"]
	assert_almost_eq(rr[0], 0.0, 1e-12, "Ṙx=0")
	assert_almost_eq(rr[1], 0.0, 1e-12, "Ṙy=0")
	assert_almost_eq(rr[2], 0.0, 1e-12, "Ṙz=0")

func test_reversed_row_matches_official_negation() -> void:
	var data := _load_json()
	if data.is_empty():
		return
	var row_fwd := {}
	var row_rev := {}
	for row: Variant in data.get("transforms", []):
		if row is Dictionary:
			if String(row.get("from", "")) == "ITRF2020" and String(row.get("to", "")) == "ITRF2014":
				row_fwd = row
			if String(row.get("from", "")) == "ITRF2014" and String(row.get("to", "")) == "ITRF2020":
				row_rev = row
	assert_false(row_fwd.is_empty() or row_rev.is_empty(), "双向行都应存在")
	var neg: Dictionary = I.negate_row(row_fwd)
	assert_vector_almost_eq(neg["t_mm"], [1.4, 0.9, -1.4], 1e-12, "反号 Tx")
	assert_vector_almost_eq(neg["t_rate_mm_y"], [0.0, 0.1, -0.2], 1e-12, "反号 Ṫ（速率同反号）")
	assert_almost_eq(neg["d_ppb"], 0.42, 1e-12, "反号 D")
	assert_vector_almost_eq(neg["r_mas"], [0.0, 0.0, 0.0], 1e-12, "反号 R")
	var stored: Array = row_rev["t_mm"]
	assert_vector_almost_eq(stored, neg["t_mm"], 1e-12, "表中反向行 = 官方反号规则")
	assert_vector_almost_eq(row_rev["t_rate_mm_y"], neg["t_rate_mm_y"], 1e-12, "表中反向行速率")

func test_lookup_both_directions_and_missing() -> void:
	var data := _load_json()
	if data.is_empty():
		return
	var a := I.lookup(data, "ITRF2020", "ITRF2014")
	assert_false(a.is_empty(), "正向 lookup")
	assert_false(bool(a["_reversed"]), "正向不标记反号")
	var b := I.lookup(data, "itrf2014", "ITRF2020")  # 大小写不敏感
	assert_false(b.is_empty(), "反向 lookup（大小写不敏感）")
	assert_true(bool(b["_reversed"]), "反向行应标记 _reversed")
	var c := I.lookup(data, "ITRF1996", "ITRF2020")
	assert_true(c.is_empty(), "未收录方向返回空")
	# 反向 lookup 的数值应与 negate(正向) 一致
	assert_vector_almost_eq(b["t_mm"], I.negate_row(a)["t_mm"], 1e-12, "lookup 反向行数值")

func test_rates_zero_degrades_to_7param() -> void:
	# 【本任务分配自洽向量】速率全零 → 退化为普通七参数；期望值由测试内独立算式复核
	var row := _row2020_2014()
	if row.is_empty():
		return
	var zero := row.duplicate(true)
	zero["t_rate_mm_y"] = [0.0, 0.0, 0.0]
	zero["r_rate_mas_y"] = [0.0, 0.0, 0.0]
	zero["d_rate_ppb_y"] = 0.0
	var res := I.transform({"src_xyz": [P2], "params_row": zero, "epoch": 2015.0})
	assert_true(res["ok"], "七参数退化正算应成功：" + String(res.get("error", "")))
	var out: Array = res["value"]["points_m"][0]
	# 独立算式：X2 = X + T + D·X（D=−0.42e-9，T=（−1.4,−0.9,1.4）mm）
	var D := -0.42e-9
	var T := [-1.4e-3, -0.9e-3, 1.4e-3]
	for i in 3:
		var expect: float = P2[i] + T[i] + D * P2[i]
		assert_almost_eq(out[i], expect, 1e-9, "退化七参数独立算式分量 %d" % i)
		assert_almost_eq(out[i], E_2015[i], 1e-9, "python 手算复核分量 %d" % i)
	# 与完整 14 参数行在 t_epoch 处逐位一致（Δt=0 时速率项不生效）
	var res_full := I.transform({"src_xyz": [P2], "params_row": row, "epoch": 2015.0})
	var out_full: Array = res_full["value"]["points_m"][0]
	for i in 3:
		assert_almost_eq(out_full[i], out[i], 1e-15, "t_epoch 处 14 参数与退化七参数一致分量 %d" % i)

func test_time_dependent_rates_epoch_2023() -> void:
	var row := _row2020_2014()
	if row.is_empty():
		return
	var res := I.transform({"src_xyz": [P2], "params_row": row, "epoch": 2023.0})
	assert_true(res["ok"], "2023.0 历元正算应成功")
	var out: Array = res["value"]["points_m"][0]
	# 独立算式：Δt=8；T(t)=T+ṪΔt=(−1.4,−1.7,3.0)mm；D(t)=−0.42ppb；R=0
	var dt := 8.0
	var T0 := [-1.4e-3, -0.9e-3, 1.4e-3]
	var Tr0 := [0.0, -0.1e-3, 0.2e-3]
	for i in 3:
		var expect: float = P2[i] + (T0[i] + Tr0[i] * dt) + (-0.42e-9) * P2[i]
		assert_almost_eq(out[i], expect, 1e-9, "时变 T(t) 独立算式分量 %d" % i)
		assert_almost_eq(out[i], E_2023[i], 1e-9, "python 手算复核分量 %d" % i)
	# epoch 也可传字符串（UI 口径）
	var res_s := I.transform({"src_xyz": [P2], "params_row": row, "epoch": "2023.0"})
	var out_s: Array = res_s["value"]["points_m"][0]
	assert_almost_eq(out_s[1], E_2023[1], 1e-9, "字符串历元解析")

func test_velocity_transform() -> void:
	var row := _row2020_2014()
	if row.is_empty():
		return
	var res := I.transform({
		"src_xyz": [P2],
		"vel": [[0.01, 0.02, 0.03]],
		"params_row": row,
		"epoch": 2015.0,
	})
	assert_true(res["ok"], "速度变换应成功：" + String(res.get("error", "")))
	var vel_out: Array = res["value"]["vel_out_m_per_y"][0]
	# 独立算式：Ṫ=(0,−0.0001,0.0002) m/年，Ḋ=0，Ṙ=0 → V_out = V + Ṫ
	for i in 3:
		assert_almost_eq(vel_out[i], E_VEL[i], 1e-12, "速度变换分量 %d" % i)

func test_rotation_sign_convention_vs_epsg10587() -> void:
	# 【外部核读】EPSG:10587（ITRF2020→ETRF2014，带旋转，position_vector）pyproj 实跑值。
	# 该行验证 ω×X 的符号排布与 PROJ 一致（本行参数仅用于符号核读，不属于 ITRF-ITRF 表）。
	var row := {
		"t_epoch": 2015.0,
		"t_mm": [-1.4, -0.9, 1.4],
		"t_rate_mm_y": [0.0, 0.0, 0.0],
		"d_ppb": -0.42,
		"d_rate_ppb_y": 0.0,
		"r_mas": [2.21, 13.806, -20.02],
		"r_rate_mas_y": [0.0, 0.0, 0.0],
	}
	var res := I.transform({"src_xyz": [P2], "params_row": row, "epoch": 2015.0})
	assert_true(res["ok"], "带旋转转换应成功")
	var out: Array = res["value"]["points_m"][0]
	for i in 3:
		assert_almost_eq(out[i], E_10587[i], 1e-6, "EPSG:10587 pyproj 复核分量 %d" % i)

func test_epoch_propagation() -> void:
	var res := I.propagate({
		"src_xyz": [[1000.0, 2000.0, 3000.0]],
		"vel": [[0.01, 0.02, 0.03]],
		"epoch_from": 2015.0,
		"epoch_to": 2023.0,
	})
	assert_true(res["ok"], "历元传播应成功：" + String(res.get("error", "")))
	var out: Array = res["value"]["points_m"][0]
	assert_almost_eq(out[0], 1000.08, 1e-12, "x(t2)")
	assert_almost_eq(out[1], 2000.16, 1e-12, "y(t2)")
	assert_almost_eq(out[2], 3000.24, 1e-12, "z(t2)")
	# 零速度 → 坐标不变
	var res0 := I.propagate({
		"src_xyz": [[1000.0, 2000.0, 3000.0]],
		"vel": [[0.0, 0.0, 0.0]],
		"epoch_from": 2015.0,
		"epoch_to": 2035.0,
	})
	var out0: Array = res0["value"]["points_m"][0]
	assert_almost_eq(out0[0], 1000.0, 1e-15, "零速度传播坐标不变")
	# 缺速度 → 中文错误
	var res_bad := I.propagate({"src_xyz": [[1.0, 2.0, 3.0]], "epoch_from": 2015.0, "epoch_to": 2020.0})
	assert_false(bool(res_bad["ok"]), "缺速度应失败")
	assert_true(String(res_bad["error"]).contains("速度"), "中文错误：速度")
	# 速度点数不一致
	var res_bad2 := I.propagate({"src_xyz": [[1.0, 2.0, 3.0]], "vel": [[1.0, 1.0, 1.0], [2.0, 2.0, 2.0]], "epoch_from": 2015.0, "epoch_to": 2020.0})
	assert_false(bool(res_bad2["ok"]), "速度点数不一致应失败")

func test_errors_and_protocol() -> void:
	# 缺参数行
	var res := I.transform({"src_xyz": [P2]})
	assert_false(bool(res["ok"]), "缺 params_row 应失败")
	assert_true(String(res["error"]).contains("参数"), "中文错误：参数行")
	# 缺 t_epoch
	var res2 := I.transform({"src_xyz": [P2], "params_row": {"t_mm": [1, 2, 3]}})
	assert_false(bool(res2["ok"]), "缺 t_epoch 应失败")
	assert_true(String(res2["error"]).contains("t_epoch"), "中文错误：t_epoch")
	# lookup 空输入
	assert_true(I.lookup({}, "ITRF2020", "ITRF2014").is_empty(), "空表 lookup 返回空")
	# 协议完整性
	var row := _row2020_2014()
	if not row.is_empty():
		var res3 := I.transform({"src_xyz": [P2], "params_row": row, "epoch": 2015.0})
		assert_true((res3["steps"] as Array).size() >= 2, "转换步骤 ≥2")
		for st: Dictionary in res3["steps"]:
			assert_true(st.has_all(["title", "formula", "substitution", "result"]), "步骤四字段")
		assert_true(String(res3["formula"]).contains("ITRF"), "formula 说明 ITRF")
		assert_eq(res3["error"], "", "成功时 error 为空")
		var res4 := I.propagate({
			"src_xyz": [[1000.0, 2000.0, 3000.0]], "vel": [[0.01, 0.02, 0.03]],
			"epoch_from": 2015.0, "epoch_to": 2016.0,
		})
		for st: Dictionary in res4["steps"]:
			assert_true(st.has_all(["title", "formula", "substitution", "result"]), "传播步骤四字段")

# ---------- 本包追加：验收算例与历元链路警示（只追加，不改既有断言） ----------

# 【验收算例】ITRF 14 参数时变（反号路径）：T=(1.4, 0.9, −1.4) mm、Ṫ=(0, 0.1, −0.2) mm/年、
# D=+0.42 ppb、Ḋ=0、R=0、t_epoch=2015.0（即 ITRF2014→ITRF2020 方向，表中反向行/negate 生成），
# 输入 (4000000, 500000, 4933000)；期望值本会话 Python 独立复核。
const A_P := [4000000.0, 500000.0, 4933000.0]
const A_2015 := [4000000.003080, 500000.001110, 4933000.000672]
const A_2023 := [4000000.003080, 500000.001910, 4932999.999072]

func _row2014_2020() -> Dictionary:
	var data := _load_json()
	if data.is_empty():
		return {}
	for row: Variant in data.get("transforms", []):
		if row is Dictionary and String(row.get("from", "")) == "ITRF2014" and String(row.get("to", "")) == "ITRF2020":
			return row
	return {}

func test_acceptance_time_dependent_reverse_path() -> void:
	var row := _row2014_2020()
	assert_false(row.is_empty(), "表中应有 ITRF2014→ITRF2020 反向行")
	if row.is_empty():
		return
	# t=2015.0（Δt=0，速率项不生效）
	var res1 := I.transform({"src_xyz": [A_P], "params_row": row, "epoch": 2015.0})
	assert_true(res1["ok"], "反号路径 t=2015 应成功：" + String(res1.get("error", "")))
	var out1: Array = res1["value"]["points_m"][0]
	for i in 3:
		assert_almost_eq(out1[i], A_2015[i], 1e-6, "t=2015 反号路径分量 %d（钉死反号）" % i)
	# t=2023.0（Δt=8，速率项生效：Ṫ 反号后 (0, +0.1, −0.2) mm/年）
	var res2 := I.transform({"src_xyz": [A_P], "params_row": row, "epoch": 2023.0})
	assert_true(res2["ok"], "反号路径 t=2023 应成功")
	var out2: Array = res2["value"]["points_m"][0]
	for i in 3:
		assert_almost_eq(out2[i], A_2023[i], 1e-6, "t=2023 反号路径分量 %d（钉死速率项）" % i)

func test_epoch_chain_warning_step() -> void:
	# Δt≠0 时 steps 应有历元链路警示（先传播到基准历元 → 转换 → 再传播到用户历元）
	var row := _row2020_2014()
	if row.is_empty():
		return
	var res := I.transform({"src_xyz": [P2], "params_row": row, "epoch": 2023.0})
	assert_true(res["ok"], "时变转换应成功")
	var found := false
	for st: Dictionary in res["steps"]:
		if String(st["title"]).contains("历元链路警示"):
			found = true
			assert_true(String(st["formula"]).contains("先传播到参数基准历元"), "警示含正确链路顺序")
			assert_true(String(st["result"]).contains("确认输入坐标历元"), "警示提示确认坐标历元")
	assert_true(found, "Δt≠0 应有历元链路警示步骤")
	# Δt=0 无警示
	var res0 := I.transform({"src_xyz": [P2], "params_row": row, "epoch": 2015.0})
	var found0 := false
	for st: Dictionary in res0["steps"]:
		if String(st["title"]).contains("历元链路警示"):
			found0 = true
	assert_false(found0, "Δt=0 不应出现链路警示")

func test_error_message_no_internal_names() -> void:
	# error 文案不暴露类名/文件名/函数名（口径：规范中文测绘术语）
	var res := I.transform({"src_xyz": [P2]})
	assert_false(bool(res["ok"]), "缺参数行应失败")
	var msg := String(res["error"])
	for bad in ["GKITRF", "lookup", "itrf_params", "params_row", ".gd", ".json"]:
		assert_false(msg.contains(bad), "error 不应含内部名“%s”：%s" % [bad, msg])
	assert_true(msg.contains("参数"), "error 应为规范中文术语")
