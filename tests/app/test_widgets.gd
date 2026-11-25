# tests/app/test_widgets.gd —— scenes/widgets 独立控件场景回归（组件化封装验收）
# 覆盖：input_row / result_card / step_list / formula_card / limits_panel /
# sketch_panel 六个控件场景可实例化、API 可用，主题变体定义，以及
# calculator_base 组装后别名指向正确。
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
	# 行级复制按钮：行数 ≤ 5 才渲染；卡头「复制全部」独立存在（不受行数影响）
	var rows_node: Node = card.get_node("VBox/Rows")
	assert_int_eq(rows_node.get_child_count(), 2, "两行两行级复制按钮（行数 ≤ 5）")
	var copy_all: Button = card.get_node("VBox/CopyAll")
	assert_true(copy_all.visible, "卡头「复制全部」按钮存在")
	copy_all.pressed.emit()
	card.set_result(PackedStringArray())
	assert_int_eq((card.get_node("VBox/Rows") as Node).get_child_count(), 0, "空结果行区清空")
	# 行数超阈值：行级按钮不渲染，但双列行结构始终渲染（P11 口径：
	# 行多时不再整体退回 value_label 单列全文，行区保持标签/数值对齐结构）
	var many := PackedStringArray()
	for i in 8:
		many.append("第 %d 行 = %d" % [i, i])
	card.set_result(many)
	assert_int_eq((card.get_node("VBox/Rows") as Node).get_child_count(), 8, "行数 > 5 行结构仍渲染（无按钮行）")
	assert_false((card.get_node("VBox/Rows") as Node).get_child(0).get_child_count() == 3, "行多时行级按钮不渲染（行内仅标签/数值）")
	assert_false((card.get_node("VBox/Value") as Node).visible, "行多时 value_label 隐藏（不与行区双显）")
	card.set_result(PackedStringArray())
	assert_eq(card.get_text(), "（尚未计算）", "空数组回落占位")
	_unmount(w)

func test_step_list_widget() -> void:
	var w := _mount("res://scenes/widgets/step_list.tscn")
	var sl: Node = w
	assert_true(sl.has_method("set_steps"), "step_list 根脚本挂 step_list.gd")
	# 越界接口已删：step_list 不再提供 set_visible_by_steps（改由组装方控制 visible）
	assert_false(sl.has_method("set_visible_by_steps"), "set_visible_by_steps 已删除")
	sl.set_steps([
		{"title": "1. 弧长", "formula": "X=…", "substitution": "B=…", "result": "3320113 m"},
		{"title": "2. 纵坐标", "formula": "", "substitution": "", "result": "3597986 m"},
	])
	assert_int_eq(sl.step_count(), 2, "两步两卡")
	# 折叠默认态：全部 FoldableContainer 卡默认折叠，仅最后一步展开
	var last_card: FoldableContainer = sl.get_child(1)
	var first_card: FoldableContainer = sl.get_child(0)
	assert_true(last_card is FoldableContainer, "步骤卡为 FoldableContainer")
	assert_false(first_card.folded == false and last_card.folded == false, "非全部展开（默认折叠）")
	assert_true(first_card.folded, "第一步默认折叠")
	assert_false(last_card.folded, "最后一步默认展开")
	assert_true(String(last_card.title).contains("步骤 2/2"), "折叠头含「步骤 i/n」编号")
	assert_true(String(last_card.title).contains("纵坐标"), "折叠头含原标题（去旧序号）")
	# ResultAccent 结果行：展开的最后一步内结果行使用强调变体
	var res_lab: Label = last_card.get_child(0).get_child(last_card.get_child(0).get_child_count() - 1)
	assert_eq(res_lab.theme_type_variation, &"ResultAccent", "结果行 ResultAccent 强调变体")
	assert_eq(res_lab.text, "3597986 m", "结果行文本")
	sl.clear()
	assert_int_eq(sl.step_count(), 0, "清空")
	_unmount(w)

func test_sketch_panel_widget() -> void:
	var w := _mount("res://scenes/widgets/sketch_panel.tscn")
	var sk: Control = w
	assert_true(sk.has_method("set_points"), "sketch_panel 根脚本挂 sketch_panel.gd")
	assert_int_eq(sk.get_points().size(), 0, "初始无点位")
	# 验收探针：数据 setter 触发 queue_redraw 至少一次（挂钩计数）
	var redraws := [0]
	sk.draw.connect(func() -> void: redraws[0] += 1)
	sk.set_points(PackedVector2Array([Vector2(0, 100), Vector2(100, 102), Vector2(200, 101)]))
	assert_int_eq(sk.get_points().size(), 3, "点位写入")
	assert_true(redraws[0] >= 1, "set_points 触发 _draw 至少一次")
	sk.clear()
	assert_int_eq(sk.get_points().size(), 0, "清空点位")
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
	# 结论唯一归属 Verdict（由 ok 参数生成）；detail[0] 结论行剥离后不再出现于明细
	assert_eq(lp.verdict_label.text, "检核结论：超限", "Verdict 独立结论行")
	assert_eq(lp.verdict_label.theme_type_variation, &"ResultAccent", "Verdict 强调变体")
	assert_false(lp.limits_label.text.contains("检核结论：超限"), "明细行不再逐字重复结论")
	assert_true(lp.limits_label.text.contains("f_beta_s = 12.5"), "明细行保留")
	assert_eq(lp.limits_label.theme_type_variation, &"ErrorLabel", "超限红色语义")
	# 兼容组装方新口径：结论不进 detail，Verdict 仍由 ok 生成
	lp.set_limits(true, PackedStringArray(["f_beta_s = 8.2"]))
	assert_eq(lp.verdict_label.text, "检核结论：通过", "ok 参数独立生成结论")
	assert_eq(lp.limits_label.theme_type_variation, &"OkLabel", "通过绿色语义")
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

func test_theme_variants_defined() -> void:
	var th: Theme = load("res://themes/main.tres")
	assert_eq(th.get_type_variation_base("ResultAccent"), &"Label", "ResultAccent 变体已定义")
	assert_eq(th.get_type_variation_base("ErrorCard"), &"PanelContainer", "失败态卡片变体已定义")
	assert_true(th.has_constant("line_spacing", "Label"), "Label 行距常量已定义")
	assert_int_eq(th.get_constant("line_spacing", "Label"), 4, "行距 4px")
