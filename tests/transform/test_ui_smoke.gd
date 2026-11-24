# tests/transform/test_ui_smoke.gd —— GK-M4 计算器场景冒烟（headless 实例化 + 示例输入运行）
# 覆盖：manifest 契约（4 条目、场景可加载）、场景根脚本继承 GKCalculatorBase、
# 示例输入 run() 成功、get_inputs/set_inputs 回放、非法输入给中文错误不崩溃、
# height_fit 拟合→预测链路、itrf 参数表缺失方向给中文提示。
# 说明：不依赖 GKServices（bootstrap 未装配，本模块 run() 均只调 core 静态函数）。
extends "res://tests/test_case_base.gd"

const MANIFEST_PATH := "res://scenes/calculators/transform/manifest.json"

func _tree_root() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root
	return null

func _load_entries() -> Array:
	var f := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if f == null:
		_fail("manifest.json 无法读取")
		return []
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Dictionary):
		_fail("manifest.json 不是 JSON 对象")
		return []
	assert_eq(String(data.get("domain", "")), "transform", "manifest domain")
	return data.get("entries", [])

func _open(entry: Dictionary) -> GKCalculatorBase:
	var packed := load(String(entry["scene"]))
	if packed == null:
		_fail("场景加载失败：%s" % entry["scene"])
		return null
	var inst: Node = packed.instantiate()
	if not (inst is GKCalculatorBase):
		_fail("场景根脚本未继承 GKCalculatorBase：%s" % entry["scene"])
		inst.queue_free()
		return null
	var calc := inst as GKCalculatorBase
	calc.set("_entry_id", String(entry.get("id", "")))
	calc.set_example(entry.get("example", {}))
	var root := _tree_root()
	if root == null:
		_fail("无法获取场景树根（runner 时序异常）")
		calc.queue_free()
		return null
	root.add_child(calc)
	return calc

func test_manifest_entries() -> void:
	var entries := _load_entries()
	assert_eq(entries.size(), 5, "transform 域 5 条目（含新增 RTK 参数计算）")
	var ids := {}
	for e: Dictionary in entries:
		ids[String(e["id"])] = e
		assert_true(String(e["scene"]).ends_with(".tscn"), "条目场景为 .tscn")
		assert_true((e.get("keywords", "") as String).length() > 0, "条目有关键词")
		assert_true((e.get("example", {}) as Dictionary).size() > 0, "条目有示例输入")
	for want: String in ["a9_bursa", "a8_four_param", "a10_height_fit", "f7_itrf", "a11_rtk_params"]:
		assert_true(ids.has(want), "条目 id：%s" % want)

func test_bursa_calculator_scene() -> void:
	var entries := _load_entries()
	if entries.is_empty():
		return
	var entry := {}
	for e: Dictionary in entries:
		if String(e["id"]) == "a9_bursa":
			entry = e
	var calc := _open(entry)
	if calc == null:
		return
	# 示例（GN7-2 官方算例）应一次运行成功
	var res := calc.run()
	assert_true(bool(res.get("ok", false)), "示例运行应成功：" + String(res.get("error", "")))
	var v: Dictionary = res.get("value", {})
	assert_almost_eq(float(v.get("x_m", NAN)), 3657660.78, 0.01, "示例输出 x（GN7-2 口径）")
	assert_almost_eq(float(v.get("y_m", NAN)), 255778.43, 0.01, "示例输出 y")
	assert_almost_eq(float(v.get("z_m", NAN)), 5201387.75, 0.01, "示例输出 z")
	# 输入回放
	var inputs := calc.get_inputs()
	assert_eq(String(inputs.get("mode", "")), "fwd", "get_inputs 回显 mode")
	assert_eq(String(inputs.get("convention", "")), "PV", "get_inputs 回显 convention")
	calc.set_inputs({"mode": "solve", "rz_as": "-0.554", "convention": "CF"})
	var inputs2 := calc.get_inputs()
	assert_eq(String(inputs2.get("mode", "")), "solve", "set_inputs 切换 mode")
	assert_eq(String(inputs2.get("convention", "")), "CF", "set_inputs 切换 convention")
	# 求参模式但目标点为空 → 中文错误
	var res_bad := calc.run()
	assert_false(bool(res_bad.get("ok", true)), "目标点为空应失败")
	assert_true(String(res_bad.get("error", "")).length() > 0, "失败应有中文错误")
	calc.set_inputs(entry.get("example", {}))
	calc.queue_free()

func test_four_param_calculator_scene() -> void:
	var entries := _load_entries()
	var entry := {}
	for e: Dictionary in entries:
		if String(e["id"]) == "a8_four_param":
			entry = e
	var calc := _open(entry)
	if calc == null:
		return
	var res := calc.run()
	assert_true(bool(res.get("ok", false)), "示例求参应成功：" + String(res.get("error", "")))
	var v: Dictionary = res.get("value", {})
	assert_almost_eq(float(v.get("dx_m", NAN)), 1000.0, 1e-6, "示例 dx=1000")
	assert_almost_eq(float(v.get("alpha_deg", NAN)), 2.0, 1e-6, "示例 α=2°")
	# 反算回放：先算正算目标，再反算回源点
	calc.set_inputs({"mode": "fwd", "dx_m": "1000", "dy_m": "2000", "scale": "1.0002", "alpha_deg": "2", "src_xy": "2000, 4000"})
	var res_fwd := calc.run()
	assert_true(bool(res_fwd.get("ok", false)), "正算应成功：" + String(res_fwd.get("error", "")))
	assert_true((res_fwd["value"] as Dictionary).has("x_m"), "正算 value 应含 x_m：%s" % str(res_fwd["value"]))
	var xf := float(res_fwd["value"]["x_m"])
	var yf := float(res_fwd["value"]["y_m"])
	calc.set_inputs({"mode": "inv", "dst_xy": "%.9f, %.9f" % [xf, yf]})
	var res_inv := calc.run()
	assert_true(bool(res_inv.get("ok", false)), "反算应成功：" + String(res_inv.get("error", "")))
	assert_almost_eq(float(res_inv["value"]["x_m"]), 2000.0, 1e-6, "反算回 x")
	assert_almost_eq(float(res_inv["value"]["y_m"]), 4000.0, 1e-6, "反算回 y")
	# 非法输入：单点求参 → 中文错误不崩溃
	calc.set_inputs({"mode": "solve", "src_xy": "1000, 1000"})
	var res_bad := calc.run()
	assert_false(bool(res_bad.get("ok", true)), "单点求参应失败")
	assert_true(String(res_bad.get("error", "")).contains("公共点"), "中文错误：公共点")
	calc.set_inputs(entry.get("example", {}))
	calc.queue_free()

func test_height_fit_calculator_scene() -> void:
	var entries := _load_entries()
	var entry := {}
	for e: Dictionary in entries:
		if String(e["id"]) == "a10_height_fit":
			entry = e
	var calc := _open(entry)
	if calc == null:
		return
	var res := calc.run()
	assert_true(bool(res.get("ok", false)), "示例拟合应成功：" + String(res.get("error", "")))
	# 拟合 → 预测链路（同一实例内存模型）
	calc.set_inputs({"mode": "predict", "predict_x": "1500", "predict_y": "500"})
	var res_p := calc.run()
	assert_true(bool(res_p.get("ok", false)), "预测应成功：" + String(res_p.get("error", "")))
	assert_almost_eq(float(res_p["value"]["h_m"]), 12.5, 1e-9, "预测点 (1500,500) H=12.5（示例平面模型）")
	# 未拟合就预测（新实例）→ 中文错误
	var calc2 := _open(entry)
	if calc2 != null:
		calc2.set_inputs({"mode": "predict", "predict_x": "1", "predict_y": "1"})
		var res2 := calc2.run()
		assert_false(bool(res2.get("ok", true)), "未拟合预测应失败")
		assert_true(String(res2.get("error", "")).contains("拟合"), "中文错误：请先拟合")
		calc2.queue_free()
	# 非法点行 → 中文错误（先切回拟合模式）
	calc.set_inputs({"mode": "fit", "points": "1, 2\n3, 4, 5"})
	var res_bad := calc.run()
	assert_false(bool(res_bad.get("ok", true)), "非法点行应失败")
	assert_true(String(res_bad.get("error", "")).contains("3 个数字"), "中文错误：行格式")
	calc.set_inputs(entry.get("example", {}))
	calc.queue_free()

func test_itrf_calculator_scene() -> void:
	var entries := _load_entries()
	var entry := {}
	for e: Dictionary in entries:
		if String(e["id"]) == "f7_itrf":
			entry = e
	var calc := _open(entry)
	if calc == null:
		return
	var res := calc.run()
	assert_true(bool(res.get("ok", false)), "示例转换应成功：" + String(res.get("error", "")))
	var v: Dictionary = res.get("value", {})
	assert_almost_eq(float(v["points_m"][0][0]), 3999999.99692, 1e-6, "ITRF2020→ITRF2014 示例输出 x")
	# 未收录方向 → 中文提示
	calc.set_inputs({"frame_from": "ITRF1996", "frame_to": "ITRF2020"})
	var res_bad := calc.run()
	assert_false(bool(res_bad.get("ok", true)), "未收录方向应失败")
	assert_true(String(res_bad.get("error", "")).contains("参数表"), "中文错误：参数表未收录")
	# 历元传播模式
	calc.set_inputs({
		"mode": "propagate",
		"points": "1000, 2000, 3000, 0.01, 0.02, 0.03",
		"epoch_from": "2015.0", "epoch_to": "2023.0",
	})
	var res_p := calc.run()
	assert_true(bool(res_p.get("ok", false)), "历元传播应成功：" + String(res_p.get("error", "")))
	assert_almost_eq(float(res_p["value"]["points_m"][0][2]), 3000.24, 1e-12, "传播 z(t2)")
	# 非法数字 → 中文错误
	calc.set_inputs({"mode": "transform", "points": "abc"})
	var res_bad2 := calc.run()
	assert_false(bool(res_bad2.get("ok", true)), "非法数字应失败")
	assert_true(String(res_bad2.get("error", "")).contains("数字"), "中文错误：数字格式：%s" % String(res_bad2.get("error", "")))
	calc.set_inputs(entry.get("example", {}))
	calc.queue_free()

func test_rtk_calculator_scene() -> void:
	var entries := _load_entries()
	var entry := {}
	for e: Dictionary in entries:
		if String(e["id"]) == "a11_rtk_params":
			entry = e
	var calc := _open(entry)
	if calc == null:
		return
	# 示例（EPSG:1314 七参数场景：4 公共点 + 1 检核点，限差 0.05 m）应一次运行成功且判合格
	var res := calc.run()
	assert_true(bool(res.get("ok", false)), "示例运行应成功：" + String(res.get("error", "")))
	var v: Dictionary = res.get("value", {})
	assert_true((v as Dictionary).has("params"), "value 应含求参参数")
	assert_almost_eq(float(v.get("max_check_res_m", NAN)), 0.0, 1e-3, "示例检核较差≈0")
	assert_true(bool(v.get("ok_limit", false)), "示例应判合格")
	assert_true(String(v.get("conclusion", "")).contains("合格"), "结论含合格")
	# 输入回放
	var inputs := calc.get_inputs()
	assert_eq(String(inputs.get("mode", "")), "space", "get_inputs 回显 mode")
	# 未填限差 → 中文错误（限差必须由用户输入）
	calc.set_inputs({"limit_m": ""})
	var res_nolim := calc.run()
	assert_false(bool(res_nolim.get("ok", true)), "未填限差应失败")
	assert_true(String(res_nolim.get("error", "")).contains("限差"), "中文错误：限差")
	# 检核点不成对 → 中文错误
	calc.set_inputs({"limit_m": "0.05", "check_src": "4050000, 550000, 4980000", "check_dst": ""})
	var res_pair := calc.run()
	assert_false(bool(res_pair.get("ok", true)), "检核点不成对应失败")
	assert_true(String(res_pair.get("error", "")).contains("成对"), "中文错误：成对")
	# 非法数字 → 中文错误
	calc.set_inputs({"mode": "plane", "common_src": "abc", "limit_m": "0.05"})
	var res_bad := calc.run()
	assert_false(bool(res_bad.get("ok", true)), "非法数字应失败")
	assert_true(String(res_bad.get("error", "")).contains("数字"), "中文错误：数字")
	calc.set_inputs(entry.get("example", {}))
	calc.queue_free()
