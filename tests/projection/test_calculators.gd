# tests/projection/test_calculators.gd —— M3 计算器场景冒烟（manifest → 场景挂载 → §5 协议渲染链路）
# 沿用 tests/app/test_shell.gd 的挂载协议口径：实例化 → set_example → 入树 → run()。
extends "res://tests/test_case_base.gd"

const _DIR := "res://scenes/calculators/projection"

func _catalog_entries() -> Array:
	GKServices.bootstrap()
	var catalog := GKServices.ensure_catalog()
	return catalog.by_domain().get("projection", {}).get("entries", [])

func test_manifest_loads_into_catalog() -> void:
	var entries := _catalog_entries()
	assert_int_eq(entries.size(), 17, "projection 域 17 个计算器条目")
	var ids := {}
	for e: Dictionary in entries:
		assert_true(String(e["id"]).length() > 0, "条目有 id")
		assert_true(String(e["scene"]).ends_with(".tscn"), "条目有场景路径")
		ids[String(e["id"])] = true
	assert_int_eq(ids.size(), 17, "id 无重复")
	# manifest 直接解析核验
	var f := FileAccess.open(_DIR + "/manifest.json", FileAccess.READ)
	assert_true(f != null, "manifest.json 可读")
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		assert_true(parsed is Dictionary, "manifest 是 JSON 对象")
		if parsed is Dictionary:
			assert_eq(String(parsed.get("domain", "")), "projection", "manifest domain")
			assert_int_eq((parsed.get("entries", []) as Array).size(), 17, "manifest 17 条")

func test_all_calculators_mount_and_run_examples() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	assert_true(tree != null, "SceneTree 可取")
	if tree == null:
		return
	for e: Dictionary in _catalog_entries():
		var packed = load(String(e["scene"]))
		assert_true(packed != null, "场景可加载：" + String(e["scene"]))
		if packed == null:
			continue
		var inst: Node = packed.instantiate()
		assert_true(inst is GKCalculatorBase, "根脚本继承 GKCalculatorBase：" + String(e["scene"]))
		if not (inst is GKCalculatorBase):
			inst.free()
			continue
		var calc := inst as GKCalculatorBase
		calc.set_example(e.get("example", {}))
		tree.root.add_child(calc)  # 触发 _ready：骨架 + 输入行 + 示例填充
		# 输入回放链路
		var snap := calc.get_inputs()
		assert_true(snap.size() > 0, "输入行已登记：" + String(e["id"]))
		var res: Dictionary = calc.run()
		assert_true(res.has("ok") and res.has("value") and res.has("steps") and res.has("formula") and res.has("error"),
				"§5 协议字段齐备：" + String(e["id"]))
		assert_true(bool(res.get("ok", false)), "示例输入应计算成功：" + String(e["id"]) + " → " + String(res.get("error", "")))
		var steps: Array = res.get("steps", [])
		for st: Dictionary in steps:
			assert_true(st.has("title") and st.has("formula") and st.has("substitution") and st.has("result"),
					"步骤四字段齐备：" + String(e["id"]))
		tree.root.remove_child(calc)
		calc.free()

func test_calculator_rejects_garbage_input() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	# 高斯正算：乱码输入 → ok=false + 中文错误（不崩）
	var packed = load(_DIR + "/gauss_forward.tscn")
	assert_true(packed != null, "gauss_forward 可加载")
	if packed == null:
		return
	var calc := (packed.instantiate() as GKCalculatorBase)
	tree.root.add_child(calc)
	calc.set_inputs({"lat_deg": "abc", "lon_deg": "118", "l0_deg": "117", "datum": "CGCS2000"})
	var res: Dictionary = calc.run()
	assert_false(bool(res.get("ok", true)), "乱码纬度应失败")
	assert_true(String(res.get("error", "")).length() > 0, "中文错误提示")
	assert_true((res.get("value", {}) as Dictionary).is_empty(), "失败时 value 为空")
	# 必填缺失 → 中文提示
	calc._on_reset()  # 清空全部输入（set_inputs 为合并语义）
	calc.set_inputs({"lat_deg": "32.5"})
	res = calc.run()
	assert_false(bool(res.get("ok", true)), "必填缺失应失败")
	assert_true(String(res.get("error", "")).contains("请先填写"), "必填中文提示：" + String(res.get("error", "")))
	tree.root.remove_child(calc)
	calc.free()
	# MGRS 解码：非法串
	var pk2 = load(_DIR + "/mgrs_inverse.tscn")
	if pk2 != null:
		var c2 := (pk2.instantiate() as GKCalculatorBase)
		tree.root.add_child(c2)
		c2.set_inputs({"mgrs": "bad_string!!"})
		var r2: Dictionary = c2.run()
		assert_false(bool(r2.get("ok", true)), "非法 MGRS 应失败")
		assert_true(String(r2.get("error", "")).length() > 0, "非法 MGRS 中文提示")
		tree.root.remove_child(c2)
		c2.free()
