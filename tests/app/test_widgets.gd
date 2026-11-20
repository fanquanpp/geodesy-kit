# tests/app/test_widgets.gd —— scenes/widgets 独立控件场景回归（组件化封装验收）
# 覆盖：input_row / result_card / step_list / formula_card / limits_panel 五个
# 控件场景可实例化、API 可用，且 calculator_base 组装后别名指向正确。
extends "res://tests/test_case_base.gd"

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

func _mount(path: String) -> Node:
	var inst: Node = load(path).instantiate()
	_tree().root.add_child(inst)
	return inst

func _unmount(inst: Node) -> void:
	_tree().root.remove_child(inst)
	inst.free()

func test_input_row_widget() -> void:
	var w := _mount("res://scenes/widgets/input_row.tscn")
	var row: Node = w
	assert_true(row.has_method("get_value"), "input_row 根脚本挂 input_row.gd")
	row.setup("纬度 B（度）", "lat_deg", "30 或 30°00′00″")
	assert_eq(row.get_node("Label").text, "纬度 B（度）", "setup 写标签")
	assert_eq((row.get_node("Edit") as LineEdit).placeholder_text, "30 或 30°00′00″", "setup 写占位")
	row.set_value("30.5")
	assert_eq(row.get_value(), "30.5", "set/get_value 往返")
	assert_eq(row.key, "lat_deg", "key 属性")
	_unmount(w)

func test_result_card_widget() -> void:
	var w := _mount("res://scenes/widgets/result_card.tscn")
	var card: Node = w
	assert_true(card.has_method("set_result"), "result_card 根脚本挂 result_card.gd")
	assert_eq(card.get_text(), "（尚未计算）", "初始占位")
	card.set_result(PackedStringArray(["x_m = 100", "y_m = 200"]))
	assert_eq(card.get_text(), "x_m = 100\ny_m = 200", "多行结果渲染")
	card.set_result(PackedStringArray())
	assert_eq(card.get_text(), "（尚未计算）", "空数组回落占位")
	_unmount(w)

func test_step_list_widget() -> void:
	var w := _mount("res://scenes/widgets/step_list.tscn")
	var sl: Node = w
	assert_true(sl.has_method("set_steps"), "step_list 根脚本挂 step_list.gd")
	sl.set_steps([
		{"title": "1. 弧长", "formula": "X=…", "substitution": "B=…", "result": "3320113 m"},
		{"title": "2. 纵坐标", "formula": "", "substitution": "", "result": "3597986 m"},
	])
	assert_int_eq(sl.step_count(), 2, "两步两卡")
	sl.clear()
	assert_int_eq(sl.step_count(), 0, "清空")
	_unmount(w)

func test_formula_card_widget() -> void:
	var w := _mount("res://scenes/widgets/formula_card.tscn")
	var fc: Node = w
	assert_true(fc.has_method("set_formula"), "formula_card 根脚本挂 formula_card.gd")
	assert_eq(fc.title, "公式与依据", "折叠面板标题")
	assert_true(fc.folded, "默认折叠")
	fc.set_formula("高斯-克吕格正算（Krüger 6 阶）")
	assert_eq(fc.formula_label.text, "高斯-克吕格正算（Krüger 6 阶）", "公式文本")
	assert_true(fc.visible, "有内容可见")
	fc.set_formula("")
	assert_false(fc.visible, "空内容隐藏")
	fc.set_visible_by_formula(true)
	assert_true(fc.visible, "set_visible_by_formula(true)")
	_unmount(w)

func test_limits_panel_widget() -> void:
	var w := _mount("res://scenes/widgets/limits_panel.tscn")
	var lp: Node = w
	assert_true(lp.has_method("set_limits"), "limits_panel 根脚本挂 limits_panel.gd")
	assert_false(lp.visible, "初始隐藏")
	lp.set_limits(false, PackedStringArray(["检核结论：超限", "f_beta_s = 12.5"]))
	assert_true(lp.visible, "渲染后可见")
	assert_true(lp.limits_label.text.contains("超限"), "超限文案")
	assert_eq(lp.limits_label.theme_type_variation, &"ErrorLabel", "超限红色语义")
	lp.clear()
	assert_false(lp.visible, "clear 隐藏")
	_unmount(w)

func test_calculator_base_assembles_widgets() -> void:
	# 基类组装后：兼容别名（_steps_root/_formula_text/_limits_card/_limits_label）
	# 指向组件实例的内部节点（历史测试与子面板依赖这些别名）。
	var base: GKCalculatorBase = load("res://scenes/widgets/calculator_base.gd").new()
	_tree().root.add_child(base)
	assert_true(base._steps_widget != null, "step_list 组件已组装")
	assert_true(base._formula_widget != null, "formula_card 组件已组装")
	assert_true(base._limits_widget != null, "limits_panel 组件已组装")
	assert_true(base._steps_root != null, "步骤根别名")
	assert_true(base._formula_text != null, "公式文本别名")
	assert_true(base._limits_card == base._limits_widget, "限差面板别名指向组件")
	base._render_result({
		"ok": true, "value": {"x_m": 1.0, "ok_limit": true, "limit_s": 40.0},
		"steps": [{"title": "s1", "formula": "f", "substitution": "sub", "result": "1"}],
		"formula": "F", "error": "",
	})
	assert_true(base._limits_card.visible, "限差组件渲染可见")
	assert_true(String(base._limits_label.text).contains("通过"), "限差文案经组件")
	assert_eq(base._steps_root.get_child_count(), 1, "步骤卡经组件渲染")
	_tree().root.remove_child(base)
	base.free()
