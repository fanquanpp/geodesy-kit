# tests/ellipsoid/test_ui_calculators.gd —— 椭球域计算器 UI 冒烟
# 覆盖：manifest 装载、场景实例化契约（继承 GKCalculatorBase）、示例可一键算、
# 非法输入给中文错误不崩、BLH↔XYZ 经计算器往返一致、导航壳 _open_entry 挂载。
extends "res://tests/test_case_base.gd"

const MANIFEST := "res://scenes/calculators/ellipsoid/manifest.json"

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

func _cleanup(node: Node) -> void:
	var t := _tree()
	if t != null and node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()

func test_manifest_loads_five_entries() -> void:
	GKServices.bootstrap()
	var cat := GKServices.ensure_catalog()
	var entries: Array = cat.by_domain().get("ellipsoid", {}).get("entries", [])
	assert_int_eq(entries.size(), 5, "椭球域 manifest 应有 5 个条目")
	var ids := {}
	for e: Dictionary in entries:
		ids[String(e["id"])] = e
	for want: String in ["m2_1_ellipsoid_params", "a6_blh_xyz", "a11_geodesic", "a12_rhumb", "f2_geoid_egm2008"]:
		assert_true(ids.has(want), "条目存在：" + want)
	if ids.has("a6_blh_xyz"):
		var e: Dictionary = ids["a6_blh_xyz"]
		assert_true(ResourceLoader.exists(String(e["scene"])), "a6 场景文件存在")
		assert_false(String(e.get("keywords", "")).is_empty(), "a6 关键词非空（搜索可见）")
		assert_true((e.get("example", {}) as Dictionary).size() > 0, "a6 示例输入非空")

func _instantiate_and_run(scene_path: String, example: Dictionary) -> Dictionary:
	var packed = load(scene_path)
	if packed == null:
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "场景加载失败：" + scene_path}
	var inst: Node = packed.instantiate()
	var t := _tree()
	if t != null:
		t.root.add_child(inst)  # 触发 _ready：建 UI + 注册字段
	var calc := inst as GKCalculatorBase
	if calc == null:
		_cleanup(inst)
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "根脚本未继承 GKCalculatorBase"}
	calc.set_example(example)
	calc.set_inputs(example)
	var res := calc.run()
	_cleanup(inst)
	return res

func test_each_calculator_runs_its_example() -> void:
	GKServices.bootstrap()
	var cat := GKServices.ensure_catalog()
	for e: Dictionary in cat.by_domain().get("ellipsoid", {}).get("entries", []):
		var res := _instantiate_and_run(String(e["scene"]), e.get("example", {}) as Dictionary)
		assert_true(bool(res.get("ok", false)), "示例应可算：" + String(e["id"]) + " / " + String(res.get("error", "")))
		if bool(res.get("ok", false)):
			assert_false((res.get("value", {}) as Dictionary).is_empty(), "示例结果非空：" + String(e["id"]))
			var steps: Array = res.get("steps", [])
			assert_true(steps.size() >= 2, "示例步骤数 ≥ 2：" + String(e["id"]))
			var s0: Dictionary = steps[0]
			assert_true(s0.has("title") and s0.has("formula") and s0.has("substitution") and s0.has("result"), "步骤四字段：" + String(e["id"]))

func test_invalid_input_gives_chinese_error() -> void:
	var res := _instantiate_and_run("res://scenes/calculators/ellipsoid/a6_blh_xyz.tscn",
			{"datum": "WGS84", "lat_deg": "abc", "lon_deg": "10", "h_m": "1"})
	assert_false(bool(res.get("ok", true)), "非法纬度应失败")
	assert_true(String(res.get("error", "")).contains("纬度") or String(res.get("error", "")).contains("格式"), "中文错误提示纬度问题")
	var res2 := _instantiate_and_run("res://scenes/calculators/ellipsoid/a11_geodesic.tscn",
			{"lat1_deg": "", "lon1_deg": "", "lat2_deg": "", "lon2_deg": "", "azi1_deg": "", "s12_m": ""})
	assert_false(bool(res2.get("ok", true)), "空输入应失败")
	assert_false(String(res2.get("error", "")).is_empty(), "空输入应有中文提示")
	var res3 := _instantiate_and_run("res://scenes/calculators/ellipsoid/a6_blh_xyz.tscn",
			{"datum": "WGS84", "lat_deg": "30", "lon_deg": "30", "h_m": "0", "x_m": "1", "y_m": "2", "z_m": "3"})
	assert_false(bool(res3.get("ok", true)), "两组输入同时填写应被拒")

func test_blh_xyz_calculator_roundtrip() -> void:
	var fwd := _instantiate_and_run("res://scenes/calculators/ellipsoid/a6_blh_xyz.tscn",
			{"datum": "CGCS2000", "lat_deg": "39.9075276", "lon_deg": "116.3912757", "h_m": "43.5"})
	assert_true(bool(fwd.get("ok", false)), "计算器正算应成功")
	var v: Dictionary = fwd.get("value", {})
	var inv := _instantiate_and_run("res://scenes/calculators/ellipsoid/a6_blh_xyz.tscn",
			{"datum": "CGCS2000", "lat_deg": "", "lon_deg": "", "h_m": "",
			"x_m": String.num(float(v.get("x_m", 0.0)), 6), "y_m": String.num(float(v.get("y_m", 0.0)), 6), "z_m": String.num(float(v.get("z_m", 0.0)), 6)})
	assert_true(bool(inv.get("ok", false)), "计算器反算应成功")
	var iv: Dictionary = inv.get("value", {})
	assert_almost_eq(float(iv.get("lat_deg", NAN)), 39.9075276, 1e-6, "计算器往返恢复 B")
	assert_almost_eq(float(iv.get("lon_deg", NAN)), 116.3912757, 1e-6, "计算器往返恢复 L")
	assert_almost_eq(float(iv.get("h_m", NAN)), 43.5, 0.002, "计算器往返恢复 h")

func test_geoid_calculator_beijing() -> void:
	var res := _instantiate_and_run("res://scenes/calculators/ellipsoid/f2_geoid_egm2008.tscn",
			{"lat_deg": "39.9075", "lon_deg": "116.3913"})
	assert_true(bool(res.get("ok", false)), "高程异常查询应成功：" + String(res.get("error", "")))
	if bool(res.get("ok", false)):
		var v: Dictionary = res.get("value", {})
		# 与格网忠实值一致（本文件向量口径详见 test_geoid.gd 头注）
		assert_almost_eq(float(v.get("undulation_m", NAN)), -9.103042, 0.01, "北京高程异常（格网忠实值口径）")

func test_main_shell_mounts_ellipsoid_entries() -> void:
	var scene = load("res://scenes/main.tscn")
	assert_true(scene != null, "main.tscn 可加载")
	if scene == null:
		return
	var t := _tree()
	if t == null:
		return
	GKServices.bootstrap()
	GKServices.ensure_catalog()
	var inst: Node = scene.instantiate()
	t.root.add_child(inst)
	var entries: Array = GKServices.catalog.by_domain().get("ellipsoid", {}).get("entries", [])
	assert_int_eq(entries.size(), 5, "导航壳装配后椭球域 5 条目可见")
	if entries.size() > 0:
		inst.call("_open_entry", entries[0])
		var holder: Control = inst.get("_calc_holder")
		assert_true(holder != null, "椭球计算器经导航壳挂载成功")
		assert_true(holder is GKCalculatorBase, "挂载对象继承计算器基类")
	inst.call("_close_calculator")
	_cleanup(inst)
