# tests/cogo/test_cogo_ui.gd —— GK-M5 计算器场景冒烟（manifest 契约 + 挂载协议 + 示例可算）
# 说明：headless 下经 SceneTree.root 挂载触发 _ready（同 tests/app/test_shell.gd 手法）；
#   GKServices 是否装配均不崩（计算器 run() 不依赖服务，渲染用 ready_state 判空）。
extends "res://tests/test_case_base.gd"

const MANIFEST_PATH := "res://scenes/calculators/cogo/manifest.json"
const EXPECTED_IDS := [
	"a1_polar_fwd", "a2_polar_inv", "a1_fwd_3d", "a2_inv_3d",
	"b1_fwd_az", "b1_fwd_ang", "b1_side", "b1_resection",
	"b2_az_az", "b2_az_dist", "b2_dist_dist",
	"b5_convert", "b5_propagate", "b6_area", "b7_affine",
	"b8_point_line", "b9_circle_3p", "b9_arc", "b9_arc_3p",
]

func test_manifest_contract() -> void:
	var catalog := GKModuleCatalog.new()
	var entries := catalog.load_manifest_file(MANIFEST_PATH)
	assert_int_eq(entries.size(), EXPECTED_IDS.size(), "manifest 条目数 = 19")
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
	assert_false(seen.has("") , "无空 id")
	for id: String in EXPECTED_IDS:
		assert_true(seen.has(id), "manifest 含条目：" + id)

func test_catalog_load_all_mounts_cogo_domain() -> void:
	# 挂载协议：manifest 就位后 load_all 应把 cogo 域整域注册（首页/搜索/收藏自动可见）
	var catalog := GKModuleCatalog.new()
	catalog.load_all()
	var by_domain := catalog.by_domain()
	assert_true(by_domain.has("cogo"), "load_all 后 cogo 域已挂载")
	if by_domain.has("cogo"):
		var cogo: Dictionary = by_domain["cogo"]
		assert_eq(String(cogo["title"]), "坐标几何与交会", "域标题来自 manifest")
		var list: Array = cogo["entries"]
		assert_int_eq(list.size(), EXPECTED_IDS.size(), "cogo 域条目数 = 19")
	# 搜索冒烟：中文关键词命中
	var hits := catalog.search("后方交会")
	var found := false
	for h: Dictionary in hits:
		if String(h["id"]) == "b1_resection":
			found = true
	assert_true(found, "搜索「后方交会」命中条目")

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
		# 协议渲染冒烟（成功 + 失败两条路径都不崩）
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
	# A1 权威向量
	var ex: Dictionary = by_id.get("a1_polar_fwd", {})
	assert_eq(String(ex.get("x0_m", "")), "1000", "A1 示例 x0")
	assert_eq(String(ex.get("az_deg", "")), "45", "A1 示例方位角")
	var r := GKCogo.forward({"x0_m": 1000.0, "y0_m": 1000.0, "az_deg": 45.0, "dist_m": 500.0})
	assert_almost_eq(float(r["value"]["x_m"]), 1353.553390593, 1e-9, "A1 示例即权威向量")
	# B2 权威向量（示例 side=右 → P₊）
	var r2 := GKIntersections.b2_dist_dist({
		"x_a_m": 1000.0, "y_a_m": 1000.0, "d_a_m": 700.0,
		"x_b_m": 1800.0, "y_b_m": 1050.0, "d_b_m": 600.0, "side": 1,
	})
	assert_almost_eq(float(r2["value"]["x_m"]), 1512.6058, 5e-4, "B2 示例即权威向量 P₊")

func test_invalid_input_gives_chinese_error_not_crash() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		assert_true(false, "SceneTree 可取")
		return
	var packed := load("res://scenes/calculators/cogo/a1_polar_fwd.tscn")
	assert_true(packed != null, "A1 场景可加载")
	if packed == null:
		return
	var calc: GKCalculatorBase = packed.instantiate()
	tree.root.add_child(calc)
	# 清空输入 → 中文错误
	for key: String in calc.get_inputs():
		calc.set_inputs({key: ""})
	var r1: Dictionary = calc.call("run")
	assert_false(bool(r1.get("ok", true)), "空输入失败")
	assert_true(String(r1.get("error", "")).contains("请输入"), "空输入中文提示")
	# 非法数字 → 中文错误
	calc.set_inputs({"x0_m": "abc", "y0_m": "1", "az_deg": "45", "dist_m": "100"})
	var r2: Dictionary = calc.call("run")
	assert_false(bool(r2.get("ok", true)), "非法数字失败")
	assert_true(String(r2.get("error", "")).contains("不是有效数字"), "非法数字中文提示")
	# 角度字段接受度分秒
	calc.set_inputs({"x0_m": "0", "y0_m": "0", "az_deg": "30 30 00", "dist_m": "100"})
	var r3: Dictionary = calc.call("run")
	assert_true(bool(r3.get("ok", false)), "度分秒输入可算")
	tree.root.remove_child(calc)
	calc.free()
