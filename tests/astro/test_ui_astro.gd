# tests/astro/test_ui_astro.gd —— GK-M8 astro 域计算器场景冒烟
# 说明：headless 下经 SceneTree.root 挂载触发 _ready（同 tests/cogo/test_cogo_ui.gd 手法）；
#   GKServices 是否装配均不崩（计算器 run() 不依赖服务，渲染用 ready_state 判空）。
# manifest 示例值 = 权威向量（F3-1 / F4 北京），见 test_example_values_match_vectors。
extends "res://tests/test_case_base.gd"

const MANIFEST_PATH := "res://scenes/calculators/astro/manifest.json"
const EXPECTED_IDS := ["f3_solar_az", "f4_sun_events", "f5_mag_decl", "f6_time_sys", "f1_curv_refr"]

func test_manifest_contract() -> void:
	var catalog := GKModuleCatalog.new()
	var entries := catalog.load_manifest_file(MANIFEST_PATH)
	assert_int_eq(entries.size(), EXPECTED_IDS.size(), "manifest 条目数 = 5")
	var seen := {}
	for e: Dictionary in entries:
		var id := String(e["id"])
		seen[id] = true
		assert_true(EXPECTED_IDS.has(id), "条目 id 合法：" + id)
		assert_true(String(e["name"]).length() > 0, "条目有名称：" + id)
		assert_true(String(e["keywords"]).length() > 0, "条目有关键词：" + id)
		assert_true(ResourceLoader.exists(String(e["scene"])), "场景存在：" + id)
		var ex: Dictionary = e["example"]
		assert_true(ex is Dictionary and ex.size() > 0, "示例非空：" + id)
	assert_false(seen.has(""), "无空 id")
	for id: String in EXPECTED_IDS:
		assert_true(seen.has(id), "manifest 含条目：" + id)

func test_catalog_load_all_mounts_astro_domain() -> void:
	var catalog := GKModuleCatalog.new()
	catalog.load_all()
	var by_domain := catalog.by_domain()
	assert_true(by_domain.has("astro"), "load_all 后 astro 域已挂载")
	if by_domain.has("astro"):
		var astro: Dictionary = by_domain["astro"]
		var list: Array = astro["entries"]
		assert_int_eq(list.size(), EXPECTED_IDS.size(), "astro 域条目数 = 5")
	var hits := catalog.search("日出日落")
	var found := false
	for h: Dictionary in hits:
		if String(h["id"]) == "f4_sun_events":
			found = true
	assert_true(found, "搜索「日出日落」命中条目")

func test_all_calculators_instantiate_and_run_example() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	assert_true(tree != null, "SceneTree 可取")
	if tree == null:
		return
	var catalog := GKModuleCatalog.new()
	var entries := catalog.load_manifest_file(MANIFEST_PATH)
	assert_int_eq(entries.size(), EXPECTED_IDS.size(), "条目数（冒烟前置）")
	for e: Dictionary in entries:
		var id := String(e["id"])
		var packed := load(String(e["scene"]))
		assert_true(packed != null, "场景可加载：" + id)
		if packed == null:
			continue
		var inst: Node = packed.instantiate()
		assert_true(inst is GKCalculatorBase, "根脚本继承 GKCalculatorBase：" + id)
		if not (inst is GKCalculatorBase):
			inst.free()
			continue
		var calc := inst as GKCalculatorBase
		assert_eq(calc.get_entry_id(), id, "entry_id 与 manifest 一致：" + id)
		assert_true(calc.get_title().length() > 0, "有标题：" + id)
		calc.set_example(e["example"])
		tree.root.add_child(calc)  # 触发 _ready：建 UI + 填示例
		var res: Dictionary = calc.call("run")
		assert_true(bool(res.get("ok", false)), "示例可算出结果：" + id)
		if not bool(res.get("ok", false)):
			print("示例失败 %s → %s" % [id, String(res.get("error", ""))])
		assert_true(res.has("value") and res.has("steps") and res.has("formula") and res.has("error"), "§5 协议字段：" + id)
		var steps: Array = res.get("steps", [])
		assert_true(steps.size() > 0, "示例有解题步骤：" + id)
		for st: Dictionary in steps:
			assert_true(st.has("title") and st.has("formula") and st.has("substitution") and st.has("result"), "步骤四字段：" + id)
		calc._render_result(res)
		calc._render_result({"ok": false, "value": {}, "steps": [], "formula": "", "error": "冒烟：中文错误渲染"})
		tree.root.remove_child(calc)
		calc.free()

func test_example_values_match_authoritative_vectors() -> void:
	var catalog := GKModuleCatalog.new()
	var entries := catalog.load_manifest_file(MANIFEST_PATH)
	var by_id := {}
	for e: Dictionary in entries:
		by_id[String(e["id"])] = e["example"]
	# F3 权威向量（示例即算例 1）
	var ex: Dictionary = by_id.get("f3_solar_az", {})
	assert_eq(String(ex.get("year", "")), "2024", "F3 示例年份")
	assert_eq(String(ex.get("lon_deg", "")), "-105.25", "F3 示例经度")
	var r := GKSolar.solar_position({
		"year": 2024, "month": 3, "day": 20, "hour": 12, "minute": 0, "second": 0.0,
		"lat_deg": 40.0, "lon_deg": -105.25,
	})
	assert_almost_eq(float(r["value"]["az_deg"]), 78.719, 0.002, "F3 示例即权威向量（方位角）")
	assert_almost_eq(float(r["value"]["zen_deg"]), 102.900, 0.002, "F3 示例即权威向量（天顶距）")
	# F4 权威构造向量（示例即北京 2024-06-21）
	var ex4: Dictionary = by_id.get("f4_sun_events", {})
	assert_eq(String(ex4.get("tz_hours", "")), "8", "F4 示例时区")
	var r4 := GKSunEvents.sun_events({
		"year": 2024, "month": 6, "day": 21,
		"lat_deg": 39.9075, "lon_deg": 116.3913, "tz_hours": 8.0,
	})
	assert_almost_eq(float(r4["value"]["daylen_h"]), 15.0046, 0.005, "F4 示例即权威向量（昼长）")
	# F6 权威常数（2024-06-21 00UT）
	var r6 := GKTimeSys.convert({"year": 2024, "month": 6, "day": 21, "hour": 0, "minute": 0, "second": 0.0})
	assert_int_eq(int(r6["value"]["doy"]), 173, "F6 年积日 173（权威）")
	assert_int_eq(int(r6["value"]["week"]), 2319, "F6 GPS 周号 2319（构造复核）")

func test_invalid_input_gives_chinese_error_not_crash() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		assert_true(false, "SceneTree 可取")
		return
	var packed := load("res://scenes/calculators/astro/f3_solar_az.tscn")
	assert_true(packed != null, "F3 场景可加载")
	if packed == null:
		return
	var calc: GKCalculatorBase = packed.instantiate()
	tree.root.add_child(calc)
	for key: String in calc.get_inputs():
		calc.set_inputs({key: ""})
	var r1: Dictionary = calc.call("run")
	assert_false(bool(r1.get("ok", true)), "空输入失败")
	assert_true(String(r1.get("error", "")).contains("请输入"), "空输入中文提示")
	calc.set_inputs({"year": "2024", "month": "3", "day": "20", "hour": "12", "minute": "0", "second": "0",
			"lat_deg": "abc", "lon_deg": "0"})
	var r2: Dictionary = calc.call("run")
	assert_false(bool(r2.get("ok", true)), "非法数字失败")
	assert_true(String(r2.get("error", "")).contains("不是有效数字"), "非法数字中文提示")
	# 年份超适用范围 → core 中文拒绝
	calc.set_inputs({"year": "1800", "month": "3", "day": "20", "hour": "12", "minute": "0", "second": "0",
			"lat_deg": "40", "lon_deg": "0"})
	var r3: Dictionary = calc.call("run")
	assert_false(bool(r3.get("ok", true)), "年份 1800 应拒绝")
	assert_true(String(r3.get("error", "")).contains("1901"), "适用范围中文提示")
	tree.root.remove_child(calc)
	calc.free()
