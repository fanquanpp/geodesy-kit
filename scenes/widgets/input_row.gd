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
## keyboard_type：虚拟键盘类型，缺省数字键盘（与旧行为一致）；文本字段由调用方
## 显式传 LineEdit.KEYBOARD_TYPE_DEFAULT（P6 各域实参经本参数落地）。
## p_suffix：单位后缀（stacked 模式显示在输入框内右缘，如 "°"、"m"；空串无后缀）。
## p_mode："row"（默认）/ "stacked"。
## 返回 edit 供组装方直接登记（register_field）。
## label/edit 是 @onready 变量（入树时才赋值）；未入树调用时经 get_node 兜底，
## 保证 setup 返回的 edit 始终有效（register_field 登记契约）。
func setup(label_text: String, p_key: String, placeholder := "",
		keyboard_type: int = LineEdit.KEYBOARD_TYPE_NUMBER,
		p_suffix := "", p_mode := "row") -> LineEdit:
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
		if p_mode == "stacked":
			_apply_stacked()
	return ed

## stacked 形态：根 HBox 改单列语义——把 Label/Edit 摘出重排为
## HBox{ VBox{ Label, Edit } }，Edit 吃满宽度。
## 引用不变（label/edit @onready 仍指向同一节点），输入快照/回车流转契约不破。
func _apply_stacked() -> void:
	var lab := label
	var ed := edit
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
	ed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(ed)

func get_value() -> String:
	return edit.text if edit != null else ""

func set_value(v: String) -> void:
	if edit != null:
		edit.text = v
