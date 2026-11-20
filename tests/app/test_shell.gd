# tests/app/test_shell.gd —— 导航壳冒烟：headless 实例化 main.tscn 并验证页面/服务接线
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
	# 页面注册
	var pages: Dictionary = inst.get("_pages")
	assert_int_eq(pages.size(), 4, "四类导航页注册")
	for k: String in ["home", "search", "favorites", "history"]:
		assert_true(pages.has(k), "页面存在：" + k)
		assert_true((pages[k] as Control).get_parent() != null, "页面已入树：" + k)
	# 导航控件
	assert_true(inst.get("_sidebar") != null, "侧边栏已建")
	assert_true(inst.get("_bottom_nav") != null, "底部 TabBar 已建")
	assert_true(inst.get("_drawer") != null, "抽屉已建")
	assert_true(inst.get("_scrim") != null, "抽屉遮罩已建")
	# 页面切换与响应式（窄屏形态）
	inst.call("_show_page", "search")
	assert_true((pages["search"] as Control).visible, "切换到搜索页")
	assert_false((pages["home"] as Control).visible, "首页隐藏")
	inst.call("_apply_wide", false)
	var bottom: TabBar = inst.get("_bottom_nav")
	assert_true(bottom.visible, "窄屏显示底部导航")
	assert_false((inst.get("_sidebar") as VBoxContainer).visible, "窄屏隐藏侧边栏")
	inst.call("_apply_wide", true)
	assert_true((inst.get("_sidebar") as VBoxContainer).visible, "宽屏显示侧边栏")
	assert_false(bottom.visible, "宽屏隐藏底部导航")
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
	assert_eq(base._result_label.text, "x_m = 100.0", "成功渲染（4 位小数口径，整值尾零 1 位）")
	assert_true(base._limits_card.visible, "限差面板出现")
	assert_eq(base._steps_root.get_child_count(), 1, "步骤卡数量")
	tree.root.remove_child(base)
	base.free()
