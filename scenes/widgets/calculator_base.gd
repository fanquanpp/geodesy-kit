# scenes/widgets/calculator_base.gd —— 计算器场景契约基类（M0 提供，P6 改造）
#
# 契约（ARCHITECTURE.md §3.3）：
#   - 每个计算器场景根脚本 extends "res://scenes/widgets/calculator_base.gd"；
#   - 覆写 run() -> Dictionary（调 core，遵守 §5 forward 协议）、
#           get_inputs()/set_inputs()（历史回放与示例填充）、
#           get_title()/get_description()、可选 get_entry_id()；
#   - 输入行用 register_field(key, line_edit) 登记 → get/set_inputs 自动生效；
#   - 输入区/结果卡/步骤列表/公式折叠/限差面板/复制导出收藏骨架由本类内置；
#   - §5 协议渲染：ok=true → 结果+步骤四行卡片（title/formula/substitution/result）
#     + 公式折叠 + 限差检核；ok=false → 清空 value、步骤卡与公式折叠、红字中文 error。
#
# P6 改造要点：
#   - 结果键名经 ui_labels.gd 映射为中文标签（未知键回退 + 告警）；
#   - 失败分支清理：步骤卡清空、公式折叠隐藏、限差面板隐藏；
#   - focus_field(key)：校验失败定位（grab_focus + 红描边，输入变化即清除）；
#   - register_field 串联回车流转：text_submitted → 下一字段聚焦，末字段触发计算；
#   - 数值行数字键盘（virtual_keyboard_type）；
#   - 版面次序：结果卡 → 限差面板（紧随结果卡）→ 步骤区 → 公式折叠 → 操作行。
class_name GKCalculatorBase
extends Control

signal favorite_changed(entry_id: String, fav: bool)

const _Report := preload("res://app/report.gd")  # G3 报告导出（app/report.gd，GKReport）
const _Labels := preload("res://scenes/widgets/ui_labels.gd")  # GKUiLabels：键名 → 中文标签

var _entry_id := ""
var _example_inputs := {}
var _pending_inputs := {}  # 未入树时的 set_inputs 快照（字段未建，register_field 时回填）
var _fields: Dictionary = {}  # key -> LineEdit
var _field_order: Array = []  # key 顺序（回车流转用）
var _last_result_text := ""
var _last_result: Dictionary = {}  # 供报告导出（G3）与子类读取的最近一次 §5 结果
var _focused_field: LineEdit = null  # 校验失败定位中的输入框（红描边态）

var _title_label: Label
var _desc_label: Label
var _inputs_root: VBoxContainer
var _status_label: Label
var _result_card: PanelContainer
var _result_label: Label
# —— 组件化控件（scenes/widgets/ 独立场景实例）与兼容别名 ——
var _steps_widget: Control          # step_list.tscn（GKStepList）
var _steps_root: VBoxContainer      # 兼容别名 = _steps_widget（P6 起自身即卡根）
var _formula_widget: Control        # formula_card.tscn（GKFormulaCard）
var _formula_text: Label            # 兼容别名 = _formula_widget 的文本 Label
var _limits_widget: Control         # limits_panel.tscn（GKLimitsPanel）
var _limits_card: PanelContainer    # 兼容别名 = _limits_widget
var _limits_label: Label            # 兼容别名 = _limits_widget 的结论 Label
var _scroll: ScrollContainer        # 左列滚动容器（输入区；结果定位/回车流转用）
var _result_scroll: ScrollContainer  # 右列滚动容器（结果区；宽视口左右布局）
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
			"error": "本计算器尚未接入计算逻辑，请检查模块安装。"}

## 输入快照（历史回放用）
func get_inputs() -> Dictionary:
	var out := {}
	for key: String in _fields:
		out[key] = _fields[key].text
	return out

## 填充输入（示例/历史回放）。字段未建（未入树，或 _ready 前半段行还没建）时
## 快照进 _pending_inputs，register_field 逐键回填后清空；字段已就绪则直接丢弃
## 缓存（正常路径由子类覆写完成填充）。pending 已有内容时新快照不再覆盖——
## 首次显式 set_inputs 是用户意图，_ready 尾部对空 example 的注入须退让。
func set_inputs(_inputs: Dictionary) -> void:
	if _fields.is_empty():
		if _pending_inputs.is_empty():
			_pending_inputs = _inputs.duplicate(true)
	elif not _pending_inputs.is_empty():
		_pending_inputs.clear()

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

## 标签域：非空时渲染经 GKUiLabels.label_for(k, domain) 优先命中该域子表
## （如 utm 域 n_m=「北坐标（m）」覆盖通用表 n_m=「卯酉圈曲率半径」）。
## 默认空串走通用表；子类按需覆写。
func get_label_domain() -> String:
	return ""

# ---------- 机器键与限差键契约（渲染/报告侧共用谓词） ----------

## §5 value 中的机器键（P3 meta 契约）：不进结果卡/报告结果表——rows 由 G2
## 面板专用表格渲染，n_ok/n_err/pipeline/label/in_cols/out_cols 走摘要或 CSV。
## P2 report.gd 复用本谓词跳过机器键，tests/tools/test_tools.gd 无需改动。
static func is_meta_key(k: String) -> bool:
	return k == "rows" or k == "n_ok" or k == "n_err" or k == "pipeline" \
			or k == "label" or k == "in_cols" or k == "out_cols"

## 限差键谓词（§5 规则③键集合的唯一收口）：ok_limit/basis 与 f_/limit_/rel_ 前缀。
## f_ballistic_m 是球气差改正量（观测量改正，非限差），显式排除——
## 原 calculator_base 两处与 app/report.gd 一处的字面实现统一收口到本谓词。
static func is_limit_key(k: String) -> bool:
	if k == "f_ballistic_m":
		return false
	return k == "ok_limit" or k == "basis" or k.begins_with("f_") \
			or k.begins_with("limit_") or k.begins_with("rel_")

## 示意图挂载钩子：子面板需要点线图（纵断面线/导线点位连线）时覆写，
## 用 add_child 建 GKSketchPanel（scenes/widgets/sketch_panel.tscn）并保存引用；
## 在 _render_result 里按最近结果调用其 set_points()。默认不建（多数计算器无图）。
func _build_sketch() -> void:
	pass

# ---------- 输入行注册与校验定位 ----------

## 输入行注册与校验定位：入树前收到的 set_inputs 快照（_pending_inputs）
## 在此逐键回填——字段是随 _build_ui 动态建的，未入树时 _fields 为空，
## 子类 set_inputs 的遍历循环会静默丢值（示例/历史回放契约要求不丢）。
func register_field(key: String, edit: LineEdit) -> void:
	_fields[key] = edit
	if not _field_order.has(key):
		_field_order.append(key)
	if _pending_inputs.has(key):
		edit.text = String(_pending_inputs[key])
		if _fields.size() == _pending_inputs.size():
			_pending_inputs.clear()  # 全部键已回填，缓存使命完成
	# 回车流转：当前字段回车 → 聚焦下一字段；末字段回车 → 触发计算
	var idx := _field_order.size() - 1
	edit.text_submitted.connect(_on_field_submitted.bind(idx))
	# 校验失败红描边：输入变化即清除（与 focus_field 注释承诺对齐；
	# 仅当当前正处于该字段的红描边态时清除，不干扰其他字段的定位态）
	edit.text_changed.connect(_on_field_text_changed.bind(edit))
	# 移动端虚拟键盘：焦点进入字段即滚动定位（键盘弹出遮住下半屏，
	# ensure_control_visible 把该字段带到可视区上半段）
	edit.focus_entered.connect(_on_field_focus_entered.bind(edit))

## 虚拟键盘弹出避让：字段获焦时延迟一帧滚动定位——Android 键盘弹出后窗口
## 可视高度变化（viewport size_changed）晚于 focus 事件，直接滚会被键盘再遮住；
## call_deferred 让滚动发生在本帧布局与键盘 inset 生效之后。
func _on_field_focus_entered(edit: LineEdit) -> void:
	if _scroll == null or not is_instance_valid(_scroll):
		return
	var row := edit.get_parent() as Control
	if row == null:
		return
	_scroll.call_deferred("ensure_control_visible", row)

func _on_field_text_changed(_new_text: String, edit: LineEdit) -> void:
	if _focused_field == edit:
		_clear_field_highlight()

## 校验失败定位：聚焦出错字段并加红描边；输入变化即清除（fail_input 携带 key 时由子类调用）
func focus_field(key: String) -> void:
	var edit: LineEdit = _fields.get(key, null)
	if edit == null:
		return
	_clear_field_highlight()
	_focused_field = edit
	edit.add_theme_stylebox_override("normal", _error_field_style())
	edit.grab_focus()

## 便捷建行：标签 + LineEdit（组装 input_row.tscn 独立控件；触控目标 96px 由控件保证）
## keyboard_type：虚拟键盘类型，默认数字键盘（数值行）；多行/含分隔符的文本字段
## 应显式传 LineEdit.KEYBOARD_TYPE_DEFAULT（Android 数字键盘无「;」「,」与换行）。
func add_input_row(label_text: String, key: String, placeholder := "",
		keyboard_type: int = LineEdit.KEYBOARD_TYPE_NUMBER) -> LineEdit:
	var row: HBoxContainer = preload("res://scenes/widgets/input_row.tscn").instantiate()
	_inputs_root.add_child(row)
	# setup 必须在入树后调用：input_row 的 label/edit 是 @onready 变量，
	# 入树前为 null，setup 返回的 edit 才是有效的 LineEdit（供 register_field 登记）
	var edit: LineEdit = row.call("setup", label_text, key, placeholder, keyboard_type)
	register_field(key, edit)
	return edit

func _on_field_submitted(_text: String, idx: int) -> void:
	# 回车流转：末字段提交触发计算，否则聚焦下一字段
	if idx >= _field_order.size() - 1:
		_on_run()
	else:
		var next: LineEdit = _fields.get(_field_order[idx + 1], null)
		if next != null:
			next.grab_focus()

func _error_field_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.92, 0.92, 1.0)
	sb.set_border_width_all(3)
	sb.border_color = Color("#C62828")
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 26
	sb.content_margin_bottom = 26
	return sb

func _clear_field_highlight() -> void:
	if _focused_field != null and is_instance_valid(_focused_field):
		_focused_field.remove_theme_stylebox_override("normal")
	_focused_field = null

# ---------- UI 骨架 ----------

func _build_ui() -> void:
	# P9.2 左右布局（用户要求「采取左右布局」）：
	#   竖屏窄视口（<700 设计 px）维持单列纵排；宽视口/横屏左右两列——
	#   左列 = 输入区（可滚动），右列 = 结果区（结果/限差/步骤/公式，可滚动）。
	#   操作栏（计算/重置/示例/复制/收藏/导出）固定底部不随滚动（M3 表单惯例：
	#   主操作常驻可达，不再沉底需要滚到底才能按）。
	# 页面根 = VBox{ 主体(Expand 分栏) + 操作栏固定底 }；主体各列独立滚动。
	var page_v := VBoxContainer.new()
	page_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(page_v)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", GKThemeConstants.MIN_TOUCH_SPACING)
	page_v.add_child(body)

	# —— 左列：标题/描述/状态/输入区（整列滚动）——
	_scroll = GKTouchScroll.attach(false)
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_stretch_ratio = 0.42
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(v)

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

	# —— 右列：结果区（结果卡/限差/步骤/公式/示意图，整列独立滚动）——
	_result_scroll = GKTouchScroll.attach(false)
	_result_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result_scroll.size_flags_stretch_ratio = 0.58
	_result_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# 窄竖屏（<700）收起右列：单列纵排时结果区并入左列滚动流（走 _apply_result_layout）
	body.add_child(_result_scroll)
	var rv := VBoxContainer.new()
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result_scroll.add_child(rv)

	_result_card = preload("res://scenes/widgets/result_card.tscn").instantiate()
	_result_card.custom_minimum_size = Vector2(0, 148)  # 结果卡兜底高度：占位时视觉重心与输入区平衡
	rv.add_child(_result_card)
	_result_label = _result_card.get("value_label")  # 兼容别名（tests/app/test_shell.gd 断言文本）
	var result_widget := _result_card as GKResultCard
	result_widget.copy_confirmed.connect(_on_line_copied)

	# 限差面板紧随结果卡（P6：结论一目了然，明细在步骤区之前）
	_limits_widget = preload("res://scenes/widgets/limits_panel.tscn").instantiate()
	rv.add_child(_limits_widget)
	_limits_card = _limits_widget  # 兼容别名（tests/app/test_shell.gd 断言 visible）

	_steps_widget = preload("res://scenes/widgets/step_list.tscn").instantiate()
	_steps_widget.visible = false  # 无步骤时隐藏（P6：自适应高度，不占空卡位）
	rv.add_child(_steps_widget)
	_steps_root = _steps_widget  # 兼容别名：P6 起步骤卡直接挂在控件自身，get_child_count() 语义不变

	_formula_widget = preload("res://scenes/widgets/formula_card.tscn").instantiate()
	rv.add_child(_formula_widget)
	_formula_text = _formula_widget.get("formula_label")  # 兼容别名
	_build_sketch()

	# —— 操作栏：固定底部（不随滚动），主操作常驻可达 ——
	var actions := HBoxContainer.new()
	actions.name = "ActionBar"
	actions.add_theme_constant_override("separation", GKThemeConstants.MIN_TOUCH_SPACING / 2)
	page_v.add_child(actions)
	var run_btn := Button.new()
	run_btn.text = "计算"
	run_btn.theme_type_variation = &"PrimaryButton"
	run_btn.custom_minimum_size = Vector2(0, 96)
	run_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	run_btn.size_flags_stretch_ratio = 2.0
	run_btn.pressed.connect(_on_run)
	actions.add_child(run_btn)
	var reset_btn := Button.new()
	reset_btn.text = "重置"
	reset_btn.custom_minimum_size = Vector2(0, 96)
	actions.add_child(reset_btn)
	var example_btn := Button.new()
	example_btn.text = "示例"
	example_btn.custom_minimum_size = Vector2(0, 96)
	actions.add_child(example_btn)
	var copy_btn := Button.new()
	copy_btn.text = "复制"
	copy_btn.custom_minimum_size = Vector2(0, 96)
	copy_btn.pressed.connect(_on_copy)
	actions.add_child(copy_btn)
	_fav_button = Button.new()
	_fav_button.text = "收藏"
	_fav_button.custom_minimum_size = Vector2(0, 96)
	_fav_button.pressed.connect(_on_favorite)
	actions.add_child(_fav_button)
	var export_btn := Button.new()
	export_btn.text = "报告"
	export_btn.custom_minimum_size = Vector2(0, 96)
	export_btn.pressed.connect(_on_export_report)
	actions.add_child(export_btn)

	# 竖屏窄视口：右列并入左列（单列纵排），左右布局只在宽视口/横屏生效
	if get_viewport().get_visible_rect().size.x < 700.0:
		_result_scroll.visible = false
		# 结果构件整体搬到左列滚动流尾部（输入之后）
		var rv_children: Array = rv.get_children().duplicate()
		for c: Control in rv_children:
			rv.remove_child(c)
			v.add_child(c)

# ---------- 按钮行为 ----------

func _on_run() -> void:
	var res := run()
	_last_result = res
	_render_result(res)
	if res.get("ok", false) and GKServices.ready_state():
		GKServices.history.add(get_entry_id(), get_title(), get_inputs(), res)

## G3 报告导出（app/report.gd）：把最近一次计算的 §5 协议（含输入回显、
## 步骤四列表、限差检核）渲染为 Markdown 报告写入用户文档目录。
## 未计算过时给中文提示；失败的计算同样可导出（含错误原因，可追溯）。
func _on_export_report() -> void:
	_status_label.theme_type_variation = &"Muted"
	if _last_result.is_empty():
		_status_label.text = "请先点击「计算」，再导出报告。"
		_status_label.visible = true
		return
	var res := _Report.save(get_title(), get_entry_id(), get_inputs(), _last_result)
	if bool(res.get("ok", false)):
		_status_label.text = "报告已保存到应用文档目录，可在文件管理器查看。"
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
	# P6：填充后给状态行反馈（避免用户不知道是否生效）
	_clear_field_highlight()
	_status_label.theme_type_variation = &"Muted"
	_status_label.text = "已填入示例数据"
	_status_label.visible = true

func _on_copy() -> void:
	if _last_result_text.is_empty():
		return
	if GKClipboard.copy_text(_last_result_text):
		_status_label.theme_type_variation = &"Muted"
		_status_label.text = "结果已复制到剪贴板"
		_status_label.visible = true

func _on_line_copied(line_digest: String) -> void:
	_status_label.theme_type_variation = &"Muted"
	# 反馈带行摘要（result_card 传前 24 字），多行卡里确认复制的是哪一行
	if line_digest.is_empty():
		_status_label.text = "该行已复制到剪贴板"
	else:
		_status_label.text = "已复制：%s" % line_digest
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
	_clear_field_highlight()

	if res.is_empty():
		_steps_widget.call("clear")
		_steps_widget.visible = false
		_result_card.call("set_result", PackedStringArray())
		_result_label.visible = true  # 占位专用：重置态重新显示
		_result_label.text = "（尚未计算）"
		_formula_text.text = ""
		_formula_widget.call("set_visible_by_formula", false)
		_limits_card.visible = false
		_status_label.visible = false
		return

	if not bool(res.get("ok", false)):
		# 失败：value 必空、error 必中文可读（§5 规则①）；步骤卡清空、公式折叠隐藏（P6）
		_result_card.call("set_result", PackedStringArray())
		_result_label.visible = true  # 失败态经占位 label 提示（行区为空）
		_result_label.text = "计算未完成"
		_steps_widget.call("clear")
		_steps_widget.visible = false
		_formula_text.text = ""
		_formula_widget.call("set_visible_by_formula", false)
		_limits_card.visible = false
		_status_label.theme_type_variation = &"ErrorLabel"
		_status_label.text = String(res.get("error", "未知错误"))
		_status_label.visible = true
		return

	_status_label.visible = false
	var value: Dictionary = res.get("value", {})
	var decimals := 4
	if GKServices.ready_state():
		decimals = GKServices.settings.get_decimals()
	var domain := get_label_domain()
	var lines := PackedStringArray()
	for k: String in value.keys():
		# 限差键归限差面板、机器键由专用构件渲染，均不进结果卡（§5 规则③/meta 契约）
		if value.has("ok_limit") and is_limit_key(k):
			continue
		if is_meta_key(k):
			continue
		# 键名经 GKUiLabels 映射为中文标签（域子表优先，动态键如 x_P1_m /
		# ell_P1_A_mm 走前缀模板；未收录键回退原文 + push_warning 一次，
		# tests/cogo/test_cogo_ui.gd 断言全量 value 键无「未收录」回退）。
		# 键名原文保留在报告导出（app/report.gd）。
		lines.append("%s = %s" % [_Labels.label_for(k, domain), _format_num(value[k], decimals)])
	_result_card.call("set_result", lines)

	# 步骤四行卡片：空字段跳过（§5 规则②）——经 step_list 组件渲染（内含同步清空）
	var steps: Array = res.get("steps", [])
	_steps_widget.call("set_steps", steps)
	_steps_widget.visible = not steps.is_empty()

	_formula_text.text = String(res.get("formula", ""))
	_formula_widget.call("set_visible_by_formula", _formula_text.text != "")

	# 限差检核：ok_limit 键存在即渲染（§5 规则③）——经 limits_panel 组件渲染
	if value.has("ok_limit"):
		var ok := bool(value["ok_limit"])
		var detail := PackedStringArray()
		detail.append("检核结论：" + ("通过" if ok else "超限"))
		for k: String in value.keys():
			# ok_limit 已单独作结论行，明细只收 f_/limit_/rel_/basis（与原字面行为一致）
			if is_limit_key(k) and k != "ok_limit":
				detail.append("%s = %s" % [_Labels.label_for(k, domain), _format_num(value[k], decimals)])
		_limits_widget.call("set_limits", ok, detail)
		# 兼容别名指向结论 Label（Verdict）：P6 起结论唯一归属 Verdict，
		# Detail 只放明细——旧消费方读 _limits_label.text 取「通过/超限」结论
		_limits_label = _limits_widget.get("verdict_label")
		if _limits_label == null:
			_limits_label = _limits_widget.get("limits_label")
	else:
		_limits_card.visible = false

	# 成功后滚动定位到结果卡（P6：用户点「计算」即见结果，不必手动翻找）
	if _scroll != null and is_instance_valid(_scroll):
		_scroll.call_deferred("ensure_control_visible", _result_card)

	_last_result_text = _result_card.call("get_text")

## 数值 → 定点小数；容器（数组/矩阵）→ 摘要展示：逐元素逗号分隔，超过 4 个元素
## 截断加省略号（完整值在步骤区/导出报告，避免结果卡被 GDScript 原生表示撑爆）；
## 嵌套容器（矩阵行/残差表行）递归摘要；其余类型回退 str()。
func _format_num(v: Variant, decimals: int) -> String:
	if v is float or v is int:
		var f := float(v)
		if is_finite(f):
			return String.num(f, decimals)
		return "—"
	if v is PackedFloat64Array or v is PackedInt32Array or v is PackedInt64Array or v is Array:
		return _format_seq(v, decimals)
	if v is PackedStringArray or v is Array[String] or v is Dictionary:
		return _format_seq(v, decimals)
	if v is bool:
		return "是" if v else "否"
	return str(v)

const _SEQ_PREVIEW := 4  # 容器摘要：最多展示 4 个元素，其余以省略号代替

func _format_seq(v: Variant, decimals: int) -> String:
	var items: Array = []
	if v is PackedFloat64Array or v is PackedInt32Array or v is PackedInt64Array or v is PackedStringArray:
		items = Array(v)
	elif v is Array:
		items = v
	elif v is Dictionary:
		for k: Variant in v.keys():
			items.append("%s=%s" % [str(k), _format_num(v[k], decimals)])
	var parts := PackedStringArray()
	var truncated := false
	for i in mini(items.size(), _SEQ_PREVIEW):
		parts.append(_format_num(items[i], decimals))
	if items.size() > _SEQ_PREVIEW:
		truncated = true
	if parts.is_empty():
		return "（空）"
	return "，".join(parts) + ("，…（共 %d 项，完整值见导出报告）" % items.size() if truncated else "")
