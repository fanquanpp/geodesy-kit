# scenes/widgets/calculator_base.gd —— 计算器场景契约基类（M0 提供，施工者只继承不改）
#
# 契约（ARCHITECTURE.md §3.3）：
#   - 每个计算器场景根脚本 extends "res://scenes/widgets/calculator_base.gd"；
#   - 覆写 run() -> Dictionary（调 core，遵守 §5 forward 协议）、
#           get_inputs()/set_inputs()（历史回放与示例填充）、
#           get_title()/get_description()、可选 get_entry_id()；
#   - 输入行用 register_field(key, line_edit) 登记 → get/set_inputs 自动生效；
#   - 输入区/结果卡/步骤列表/公式折叠/限差面板/复制导出收藏骨架由本类内置；
#   - §5 协议渲染：ok=true → 结果+步骤四行卡片（title/formula/substitution/result）
#     + 公式折叠 + 限差检核；ok=false → 清空 value、红字中文 error。
class_name GKCalculatorBase
extends Control

signal favorite_changed(entry_id: String, fav: bool)

const _Report := preload("res://app/report.gd")  # G3 报告导出（app/report.gd，GKReport）

var _entry_id := ""
var _example_inputs := {}
var _fields: Dictionary = {}  # key -> LineEdit
var _last_result_text := ""
var _last_result: Dictionary = {}  # 供报告导出（G3）与子类读取的最近一次 §5 结果

var _title_label: Label
var _desc_label: Label
var _inputs_root: VBoxContainer
var _status_label: Label
var _result_card: PanelContainer
var _result_label: Label
# —— 组件化控件（scenes/widgets/ 独立场景实例）与兼容别名 ——
var _steps_widget: Control          # step_list.tscn（GKStepList）
var _steps_root: VBoxContainer      # 兼容别名 = _steps_widget 的卡片根
var _formula_widget: Control        # formula_card.tscn（GKFormulaCard）
var _formula_text: Label            # 兼容别名 = _formula_widget 的文本 Label
var _limits_widget: Control         # limits_panel.tscn（GKLimitsPanel）
var _limits_card: PanelContainer    # 兼容别名 = _limits_widget
var _limits_label: Label            # 兼容别名 = _limits_widget 的文本 Label
var _fav_button: Button

func _ready() -> void:
	_build_ui()
	_title_label.text = get_title()
	_desc_label.text = get_description()
	_desc_label.visible = get_description() != ""
	set_inputs(_example_inputs)
	# 收藏按钮初态与 favorites 表同步（进入已收藏条目时按钮应显示"已收藏"）
	var id := get_entry_id()
	if not id.is_empty() and GKServices.ready_state() and GKServices.favorites.is_favorite(id):
		_fav_button.text = "已收藏"

# ---------- 供子类覆写的契约方法 ----------

## 核心计算入口：调 core 模块，返回 §5 协议结果
func run() -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "",
			"error": "计算器未实现 run()（契约见 scenes/widgets/calculator_base.gd 头注）"}

## 输入快照（历史回放用）
func get_inputs() -> Dictionary:
	var out := {}
	for key: String in _fields:
		out[key] = _fields[key].text
	return out

## 填充输入（示例/历史回放）
func set_inputs(_inputs: Dictionary) -> void:
	pass

func get_title() -> String:
	return "未命名计算器"

func get_description() -> String:
	return ""

## manifest 的功能编号 id（收藏/历史/报告命名用）
func get_entry_id() -> String:
	return _entry_id

## 示例输入由 manifest 注入（catalog 加载时设置），子类也可覆写
func set_example(inputs: Dictionary) -> void:
	_example_inputs = inputs

# ---------- 输入行注册 ----------

func register_field(key: String, edit: LineEdit) -> void:
	_fields[key] = edit

## 便捷建行：标签 + LineEdit（组装 input_row.tscn 独立控件；触控目标 96px 由控件保证）
func add_input_row(label_text: String, key: String, placeholder := "") -> LineEdit:
	var row: HBoxContainer = preload("res://scenes/widgets/input_row.tscn").instantiate()
	row.get_node("Label").text = label_text
	var edit: LineEdit = row.get_node("Edit")
	edit.placeholder_text = placeholder
	row.set("key", key)
	_inputs_root.add_child(row)
	register_field(key, edit)
	return edit

# ---------- UI 骨架 ----------

func _build_ui() -> void:
	# 外层 ScrollContainer：720×1280 竖屏基准下，多输入行计算器（如 C 组网形 +
	# 20 参数行）总高必然超出视口，必须可滚动才能触达底部操作区/结果区；
	# 桌面宽窗内容完整时滚动条不出现（ScrollContainer 自动让位）。
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED  # 窄屏只纵滚，横滚破坏布局
	add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)

	_title_label = Label.new()
	_title_label.theme_type_variation = &"Header"
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_title_label)

	_desc_label = Label.new()
	_desc_label.theme_type_variation = &"Muted"
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_desc_label)

	_status_label = Label.new()
	_status_label.theme_type_variation = &"ErrorLabel"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.visible = false
	v.add_child(_status_label)

	_inputs_root = VBoxContainer.new()
	v.add_child(_inputs_root)
	var inputs_head := Label.new()
	inputs_head.text = "输入"
	inputs_head.theme_type_variation = &"Header"
	_inputs_root.add_child(inputs_head)

	var buttons := HBoxContainer.new()
	v.add_child(buttons)
	var run_btn := Button.new()
	run_btn.text = "计算"
	run_btn.theme_type_variation = &"PrimaryButton"
	run_btn.custom_minimum_size = Vector2(0, 96)
	run_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	run_btn.pressed.connect(_on_run)
	buttons.add_child(run_btn)
	var reset_btn := Button.new()
	reset_btn.text = "重置"
	reset_btn.custom_minimum_size = Vector2(0, 96)
	reset_btn.pressed.connect(_on_reset)
	buttons.add_child(reset_btn)
	var example_btn := Button.new()
	example_btn.text = "示例"
	example_btn.custom_minimum_size = Vector2(0, 96)
	example_btn.pressed.connect(_on_example)
	buttons.add_child(example_btn)

	# 组件化组装（用户硬性要求 §5）：结果卡/步骤列表/公式卡/限差面板为 scenes/widgets/
	# 独立控件场景实例；本基类只做组装与协议分流，不再内联建这些构件。
	_result_card = preload("res://scenes/widgets/result_card.tscn").instantiate()
	_result_card.custom_minimum_size = Vector2(0, 148)  # 结果卡兜底高度：占位时视觉重心与输入区平衡
	v.add_child(_result_card)
	_result_label = _result_card.get("value_label")  # 兼容别名（tests/app/test_shell.gd 断言文本）
	_steps_widget = preload("res://scenes/widgets/step_list.tscn").instantiate()
	_steps_widget.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_steps_widget.custom_minimum_size = Vector2(0, 220)  # 步骤滚动区最小高度：宽屏下不至于压成一条缝
	v.add_child(_steps_widget)
	_steps_root = _steps_widget.get("_root")  # 兼容别名：历史测试断言步骤卡数量用

	_formula_widget = preload("res://scenes/widgets/formula_card.tscn").instantiate()
	v.add_child(_formula_widget)
	_formula_text = _formula_widget.get("formula_label")  # 兼容别名

	_limits_widget = preload("res://scenes/widgets/limits_panel.tscn").instantiate()
	v.add_child(_limits_widget)
	_limits_card = _limits_widget  # 兼容别名（tests/app/test_shell.gd 断言 visible）

	var actions := HBoxContainer.new()
	v.add_child(actions)
	var copy_btn := Button.new()
	copy_btn.text = "复制结果"
	copy_btn.custom_minimum_size = Vector2(0, 96)
	copy_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy_btn.pressed.connect(_on_copy)
	actions.add_child(copy_btn)
	_fav_button = Button.new()
	_fav_button.text = "收藏"
	_fav_button.custom_minimum_size = Vector2(0, 96)
	_fav_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fav_button.pressed.connect(_on_favorite)
	actions.add_child(_fav_button)
	var export_btn := Button.new()
	export_btn.text = "导出报告"
	export_btn.custom_minimum_size = Vector2(0, 96)
	export_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	export_btn.pressed.connect(_on_export_report)
	actions.add_child(export_btn)

# ---------- 按钮行为 ----------

func _on_run() -> void:
	var res := run()
	_last_result = res
	_render_result(res)
	if res.get("ok", false) and GKServices.ready_state():
		GKServices.history.add(get_entry_id(), get_title(), get_inputs(), res)

## G3 报告导出（app/report.gd）：把最近一次计算的 §5 协议（含输入回显、
## 步骤四列表、限差检核）渲染为 Markdown 报告写入 user://reports/。
## 未计算过时给中文提示；失败的计算同样可导出（含错误原因，可追溯）。
func _on_export_report() -> void:
	_status_label.theme_type_variation = &"Muted"
	if _last_result.is_empty():
		_status_label.text = "请先点击「计算」，再导出报告。"
		_status_label.visible = true
		return
	var res := _Report.save(get_title(), get_entry_id(), get_inputs(), _last_result)
	if bool(res.get("ok", false)):
		_status_label.text = "报告已保存：%s" % String(res.get("path", ""))
		var txt := _Report.save_text(get_title(), get_entry_id(), get_inputs(), _last_result)
		if bool(txt.get("ok", false)):
			_status_label.text = "报告已保存：%s（纯文本版：%s）" % [String(res.get("path", "")), String(txt.get("path", ""))]
	else:
		_status_label.theme_type_variation = &"ErrorLabel"
		_status_label.text = String(res.get("error", "报告导出失败"))
	_status_label.visible = true

func _on_reset() -> void:
	for key: String in _fields:
		_fields[key].text = ""
	_last_result = {}
	_render_result({})

func _on_example() -> void:
	set_inputs(_example_inputs)

func _on_copy() -> void:
	if _last_result_text.is_empty():
		return
	if GKClipboard.copy_text(_last_result_text):
		_status_label.theme_type_variation = &"Muted"
		_status_label.text = "结果已复制到剪贴板"
		_status_label.visible = true

func _on_favorite() -> void:
	if not GKServices.ready_state():
		return
	var id := get_entry_id()
	if id.is_empty():
		return
	var fav := GKServices.favorites.toggle(id)
	_fav_button.text = "已收藏" if fav else "收藏"
	favorite_changed.emit(id, fav)

# ---------- §5 协议渲染 ----------

func _render_result(res: Dictionary) -> void:
	_last_result_text = ""

	if res.is_empty():
		_steps_widget.call("clear")
		_result_label.text = "（尚未计算）"
		_formula_text.text = ""
		_limits_card.visible = false
		_status_label.visible = false
		return

	if not bool(res.get("ok", false)):
		# 失败：value 必空、error 必中文可读（§5 规则①）
		_result_label.text = "计算未完成"
		var err := String(res.get("error", "未知错误"))
		_status_label.theme_type_variation = &"ErrorLabel"
		_status_label.text = err
		_status_label.visible = true
		_formula_text.text = String(res.get("formula", ""))
		_limits_card.visible = false
		return

	_status_label.visible = false
	var value: Dictionary = res.get("value", {})
	var decimals := 4
	if GKServices.ready_state():
		decimals = GKServices.settings.get_decimals()
	# 限差键归限差面板，不重复进结果卡（§5 规则③）
	var is_limit_key := func(k: String) -> bool:
		return k == "ok_limit" or k == "basis" or k.begins_with("f_") or k.begins_with("limit_") or k.begins_with("rel_")
	var lines := PackedStringArray()
	for k: String in value.keys():
		if value.has("ok_limit") and is_limit_key.call(k):
			continue
		lines.append("%s = %s" % [k, _format_num(value[k], decimals)])
	_result_label.text = "\n".join(lines)

	# 步骤四行卡片：空字段跳过（§5 规则②）——经 step_list 组件渲染（内含同步清空）
	var steps: Array = res.get("steps", [])
	_steps_widget.call("set_steps", steps)
	_steps_root.get_parent().visible = not steps.is_empty()

	_formula_text.text = String(res.get("formula", ""))
	_formula_widget.call("set_visible_by_formula", _formula_text.text != "")

	# 限差检核：ok_limit 键存在即渲染（§5 规则③）——经 limits_panel 组件渲染
	if value.has("ok_limit"):
		var ok := bool(value["ok_limit"])
		var detail := PackedStringArray()
		detail.append("检核结论：" + ("通过" if ok else "超限"))
		for k: String in value.keys():
			if k.begins_with("f_") or k.begins_with("limit_") or k.begins_with("rel_") or k == "basis":
				detail.append("%s = %s" % [k, _format_num(value[k], decimals)])
		_limits_widget.call("set_limits", ok, detail)
		_limits_label = _limits_widget.get("limits_label")
	else:
		_limits_card.visible = false

	_last_result_text = _result_label.text

func _format_num(v: Variant, decimals: int) -> String:
	if v is float or v is int:
		var f := float(v)
		if is_finite(f):
			return String.num(f, decimals)
	return str(v)
