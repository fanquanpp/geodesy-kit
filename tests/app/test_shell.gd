# tests/app/test_shell.gd —— 导航壳冒烟：headless 实例化 main.tscn 并验证页面/服务接线
# P9 重构后形态：顶部导航（四页）+ 常驻搜索框 + 计算器全屏覆盖
extends "res://tests/test_case_base.gd"

func test_main_scene_instantiates_and_wires() -> void:
	var scene := load("res://scenes/main.tscn")
	assert_true(scene != null, "main.tscn 可加载")
	if scene == null:
		return
	var tree := Engine.get_main_loop() as SceneTree
	assert_true(tree != null, "SceneTree 可取（headless 下）")
	if tree == null:
		return
	GKServices.bootstrap()  # 幂等
	var inst: Node = scene.instantiate()
	tree.root.add_child(inst)  # 触发 _ready：服务装配 + UI 构建 + 主题应用
	# 页面注册（P9：搜索并入顶栏；懒加载——启动只建首页，切到才实例化）
	var pages: Dictionary = inst.get("_pages")
	assert_int_eq(pages.size(), 1, "懒加载：启动只实例化首页")
	assert_true(pages.has("home"), "首页已建")
	assert_true((pages["home"] as Control).get_parent() != null, "首页已入树")
	# 顶部导航控件
	assert_true(inst.get("_back_btn") != null, "返回按钮已建")
	assert_true(inst.get("_theme_btn") != null, "主题按钮已建")
	assert_true(inst.get("_search_box") != null, "常驻搜索框已建")
	assert_true(inst.get("_search_popup") != null, "搜索结果浮层已建")
	# 首启定位（P8 修复回归：_build_ui 全隐藏后必须显式 _show_page）
	assert_true((pages["home"] as Control).visible, "首启显示首页")
	# 页面切换（懒加载触发：history 首访实例化）
	inst.call("_show_page", "history")
	assert_int_eq(pages.size(), 2, "切换后懒加载 history 页")
	assert_true((pages["history"] as Control).visible, "切换到历史页")
	assert_false((pages["home"] as Control).visible, "首页隐藏")
	# 计算器挂载协议：无 manifest 场景下直接打开应安全拒绝
	inst.call("_open_entry", {"id": "不存在的条目", "scene": "res://不存在的场景.tscn"})
	assert_true(inst.get("_calc_holder") == null, "加载失败安全返回（不崩）")
	# 清理（free 同步释放，不依赖帧）
	tree.root.remove_child(inst)
	inst.free()

func test_calculator_base_contract() -> void:
	# 契约基类可实例化（入树触发 _ready 建 UI）；默认 run() 返回 §5 协议失败结构
	var tree := Engine.get_main_loop() as SceneTree
	assert_true(tree != null, "SceneTree 可取")
	if tree == null:
		return
	var base: GKCalculatorBase = preload("res://scenes/widgets/calculator_base.gd").new()
	tree.root.add_child(base)
	assert_true(base is Control, "基类为 Control")
	var res: Dictionary = base.call("run")
	assert_false(bool(res.get("ok", false)), "默认 run() 未实现应失败")
	assert_true(String(res.get("error", "")).length() > 0, "error 为人类可读中文")
	assert_true(res.has("value") and res.has("steps") and res.has("formula"), "协议字段齐备")
	# 协议渲染：ok=false 时不崩；成功路径与限差面板渲染
	base._render_result(res)
	assert_eq(base._result_label.text, "计算未完成", "失败渲染")
	base._render_result({
		"ok": true, "value": {"x_m": 100.0, "ok_limit": true, "limit_s": 40.0, "f_beta_s": 2.0},
		"steps": [{"title": "步骤1", "formula": "y=x", "substitution": "x=100", "result": "100"}],
		"formula": "演示公式", "error": "",
	})
	# 冷审问题①：渲染层键名经 GKUiLabels 映射为中文标签（value_label 为占位专用，
	# 有结果时隐藏，行文本经 get_text() 语义保持 "\n".join(lines)——tests/app/test_widgets.gd）
	assert_eq(base._result_card.get_text(), "X 坐标（m） = 100.0", "成功渲染（键名 → 中文标签，4 位小数口径）")
	assert_false(base._result_label.visible, "有结果时占位 label 隐藏（行文本只在复制按钮行渲染）")
	assert_true(base._limits_card.visible, "限差面板出现")
	assert_eq(base._steps_root.get_child_count(), 1, "步骤卡数量")
	tree.root.remove_child(base)
	base.free()

func test_display_groups() -> void:
	# P9 展示分组：65 条目全量归组、组序稳定、无遗漏（fallback 兜底）
	var GKServices_catalog := GKServices.ensure_catalog()
	var groups: Array = GKDisplayGroups.group_entries(GKServices_catalog.entries())
	var total := 0
	var seen := {}
	for g: Dictionary in groups:
		assert_true(not (g["entries"] as Array).is_empty(), "组非空：" + String(g["key"]))
		for e: Dictionary in g["entries"]:
			seen[String(e["id"])] = true
			total += 1
	assert_int_eq(total, GKServices_catalog.count(), "分组无遗漏（全条目覆盖）")
	# 组数 ≤ 定义组数且关键组在位
	assert_true(groups.size() <= GKDisplayGroups.GROUPS.size(), "组数不超定义")
	var keys := {}
	for g: Dictionary in groups:
		keys[String(g["key"])] = true
	for must: String in ["coords", "proj", "datum", "control", "route"]:
		assert_true(keys.has(must), "关键组在位：" + must)
