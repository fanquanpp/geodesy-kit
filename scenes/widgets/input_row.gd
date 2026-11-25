# scenes/widgets/input_row.gd —— 可复用输入行控件（P9.4 坐标友好双形态）
#
# 形态由 mode 决定（用户反馈：坐标计算应以坐标输入形式呈现，而非一长行）：
#   - "row"（默认，兼容旧契约）：HBox = [Label | Edit]，标签行内右对齐；
#   - "stacked"：VBox = [Label（上）, Edit（下）]，标签在字段上方（M3 表单惯例，
#     永不消失、可扫描性好），Edit 带单位后缀（suffix，如 ° / m）。
# 数值字段 suffix 由组装方传入（setup 的 p_suffix）；触控行高 96px 不变。
# 独立控件场景（input_row.tscn）：根节点 HBox（row 模式），stacked 模式经
# _set_mode 动态重排子节点（Label/Edit 引用保持不变，setup/register_field 契约不变）。
# 读写经 get_value()/set_value()/edit；key 供输入快照契约（get_inputs/set_inputs）使用。
class_name GKInputRow
extends HBoxContainer

var key := ""
@onready var label: Label = get_node("Label")
@onready var edit: LineEdit = get_node("Edit")

## 动态配置（场景实例化后、入树前调用即可生效）。
## keyboard_type：虚拟键盘类型，缺省带小数点数字键盘 KEYBOARD_TYPE_NUMBER_DECIMAL
## （勘误：4.7.2 无 KEYBOARD_TYPE_DECIMAL 简称，旧默认 NUMBER 无「.」输入不了小数）；
## 文本字段由调用方显式传 LineEdit.KEYBOARD_TYPE_DEFAULT（P6 各域实参经本参数落地）；
## 角度/度分秒字段同样显式传 DEFAULT（组装方约定：suffix 含 °/′/″ 的行传 DEFAULT）。
## p_suffix：单位后缀（stacked 模式显示在输入框内右缘，如 "°"、"m"；空串无后缀）。
## p_mode："row"（默认）/ "stacked"。
## p_pm：负值字段 opt-in 的「±」快捷按钮（stacked/row 两形态都在 Edit 尾部；
## 按一次在文本前补 −，再按移除——竖直角/纬度南半球等负值输入免找符号键盘）。
## 返回 edit 供组装方直接登记（register_field）。
## label/edit 是 @onready 变量（入树时才赋值）；未入树调用时经 get_node 兜底，
## 保证 setup 返回的 edit 始终有效（register_field 登记契约）。
func setup(label_text: String, p_key: String, placeholder := "",
		keyboard_type: int = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL,
		p_suffix := "", p_mode := "row", p_pm := false) -> LineEdit:
	key = p_key
	var lab: Label = label if label != null else get_node_or_null("Label")
	var ed: LineEdit = edit if edit != null else get_node_or_null("Edit")
	# 单位并入标签（LineEdit 无 suffix 属性——单位后缀随 stacked 标签展示：
	# "纬度 B（°）"，用户不须重复输入单位，与 NN/g「单位常显」口径一致）
	if lab != null:
		lab.text = label_text + ("（%s）" % p_suffix if not p_suffix.is_empty() else "")
	if ed != null:
		ed.placeholder_text = placeholder
		ed.virtual_keyboard_type = keyboard_type
		if p_pm:
			_apply_pm_button(ed)
		if p_mode == "stacked":
			_apply_stacked(ed)
	return ed

## stacked 形态：根 HBox 改单列语义——把 Label/Edit 摘出重排为
## HBox{ VBox{ Label, Edit(±钮同行) } }，Edit 吃满宽度。
## 引用不变（label/edit @onready 仍指向同一节点），输入快照/回车流转契约不破。
func _apply_stacked(ed: LineEdit) -> void:
	var lab := label
	if lab == null or ed == null:
		return
	remove_child(lab)
	remove_child(ed)
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", 4)
	var col := VBoxContainer.new()
	col.name = "StackCol"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(col)
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.theme_type_variation = &"Caption"
	col.add_child(lab)
	# Edit 与 ± 钮同行（± 钮仅在 opt-in 时存在）：Edit Expand 吃满剩余宽
	var er := HBoxContainer.new()
	er.name = "EditRow"
	er.add_theme_constant_override("separation", 4)
	er.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(er)
	ed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	er.add_child(ed)

## ± 快捷按钮（负值字段 opt-in）：窄方块按钮贴在 Edit 之后（row/stacked 两形态
## 统一走本函数，都在 Edit 尾部）。点击切换文本的负号前缀——空文本补「-」，
## 已有「-」前缀则移除，其余原样保留（不重排用户已输入的内容）。
func _apply_pm_button(ed: LineEdit) -> void:
	if get_node_or_null("PmBtn") != null:
		return  # 幂等：重复 setup 不重复插钮
	var btn := Button.new()
	btn.name = "PmBtn"
	btn.text = "±"
	btn.tooltip_text = "正/负切换"
	btn.custom_minimum_size = Vector2(72, 0)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(func() -> void:
		if ed.text.begins_with("-"):
			ed.text = ed.text.substr(1)
		else:
			ed.text = "-" + ed.text)
	add_child(btn)

func get_value() -> String:
	return edit.text if edit != null else ""

func set_value(v: String) -> void:
	if edit != null:
		edit.text = v
