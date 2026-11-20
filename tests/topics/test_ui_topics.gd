# tests/topics/test_ui_topics.gd —— GK-M8 topics 域计算器场景冒烟
# 说明：headless 下经 SceneTree.root 挂载触发 _ready（同 tests/cogo/test_cogo_ui.gd 手法）。
#   示例值 = 权威构造向量（DOP 2.0388 / Haversine 北京→上海 / 走向045→倾向135 /
#   真厚度 50.0 / 天顶像 1:100），见 test_example_values_match_vectors。
extends "res://tests/test_case_base.gd"

const MANIFEST_PATH := "res://scenes/calculators/topics/manifest.json"
const EXPECTED_IDS := [
	"i_gnss_ephemeris", "i_gnss_dop", "i_photo_flight", "i_photo_collinearity",
	"i_photo_remote_index", "i_gis_haversine", "i_gis_buffer_idw_area",
	"i_geo_attitude", "i_geo_borehole", "i_geo_reserve",
]

func test_manifest_contract() -> void:
	var catalog := GKModuleCatalog.new()
	var entries := catalog.load_manifest_file(MANIFEST_PATH)
	assert_int_eq(entries.size(), EXPECTED_IDS.size(), "manifest 条目数 = 10")
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

func test_catalog_load_all_mounts_topics_domain() -> void:
	var catalog := GKModuleCatalog.new()
	catalog.load_all()
	var by_domain := catalog.by_domain()
	assert_true(by_domain.has("topics"), "load_all 后 topics 域已挂载")
	if by_domain.has("topics"):
		var topics: Dictionary = by_domain["topics"]
		var list: Array = topics["entries"]
		assert_int_eq(list.size(), EXPECTED_IDS.size(), "topics 域条目数 = 10")
	var hits := catalog.search("NDVI")
	var found := false
	for h: Dictionary in hits:
		if String(h["id"]) == "i_photo_remote_index":
			found = true
	assert_true(found, "搜索「NDVI」命中条目")

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
		tree.root.add_child(calc)
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
	# I-GNSS DOP 权威构造向量（4 星对称 → PDOP=2.0388）
	var z := sqrt(0.66)
	var rd := GKGnss.dop({"los": [[0.5, 0.3, z], [0.5, -0.3, z], [-0.5, 0.3, z], [-0.5, -0.3, z]]})
	assert_almost_eq(float(rd["value"]["pdop"]), 2.0388, 1e-4, "DOP 示例即权威向量")
	# I-GIS Haversine 权威构造向量（北京→上海 1074470.9 m）
	var rh := GKGisMeasure.haversine({"lat1": 39.9075276, "lon1": 116.3912757, "lat2": 31.1666667, "lon2": 121.4666667})
	assert_almost_eq(float(rh["value"]["dist_m"]), 1074470.9, 0.5, "Haversine 示例即权威向量")
	# I-地质 产状权威构造向量（走向 045° → 倾向 135°；真厚度 50.0 m）
	var ra := GKGeology.attitude({"strike_deg": 45.0, "dip_deg": 30.0})
	assert_almost_eq(float(ra["value"]["dip_dir_deg"]), 135.0, 1e-9, "产状示例即权威向量（倾向）")
	var rt := GKGeology.true_thickness({"width_m": 100.0, "dip_deg": 30.0, "profile_az_deg": 135.0, "strike_deg": 45.0})
	assert_almost_eq(float(rt["value"]["true_thickness_m"]), 50.0, 1e-9, "真厚度示例即权威向量")
	# I-摄影 天顶像构造成像（f=100, H=100 → 比例尺 1:100）
	var ext := {"f": 100.0, "Xs": 0.0, "Ys": 0.0, "Zs": 100.0, "phi_deg": 0.0, "omega_deg": 0.0, "kappa_deg": 180.0}
	var img: Array = GKPhoto.project(ext, [20.0, -15.0, 0.0])
	assert_almost_eq(float(img[0]), -20.0, 1e-9, "天顶像 x = −fX/H（倒像）")
	assert_almost_eq(float(img[1]), 15.0, 1e-9, "天顶像 y = −fY/H")

func test_invalid_input_gives_chinese_error_not_crash() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		assert_true(false, "SceneTree 可取")
		return
	var packed := load("res://scenes/calculators/topics/i_gis_haversine.tscn")
	assert_true(packed != null, "Haversine 场景可加载")
	if packed == null:
		return
	var calc: GKCalculatorBase = packed.instantiate()
	tree.root.add_child(calc)
	for key: String in calc.get_inputs():
		calc.set_inputs({key: ""})
	var r1: Dictionary = calc.call("run")
	assert_false(bool(r1.get("ok", true)), "空输入失败")
	assert_true(String(r1.get("error", "")).contains("请输入"), "空输入中文提示")
	calc.set_inputs({"lat1": "abc", "lon1": "116.4", "lat2": "31.2", "lon2": "121.5"})
	var r2: Dictionary = calc.call("run")
	assert_false(bool(r2.get("ok", true)), "非法数字失败")
	assert_true(String(r2.get("error", "")).contains("不是有效数字"), "非法数字中文提示")
	# 纬度越界 → core 中文拒绝
	calc.set_inputs({"lat1": "95", "lon1": "116.4", "lat2": "31.2", "lon2": "121.5"})
	var r3: Dictionary = calc.call("run")
	assert_false(bool(r3.get("ok", true)), "纬度 95 应拒绝")
	assert_true(String(r3.get("error", "")).contains("纬度"), "纬度越界中文提示")
	tree.root.remove_child(calc)
	calc.free()
