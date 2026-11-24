# scenes/widgets/input_row.gd —— 可复用输入行控件（标签 + LineEdit，触控行高 96px）
# 独立控件场景（input_row.tscn）：面板/计算器基类只做组装，不重复建行逻辑。
# 读写经 get_value()/set_value()/edit；key 供输入快照契约（get_inputs/set_inputs）使用。
class_name GKInputRow
extends HBoxContainer

var key := ""
@onready var label: Label = get_node("Label")
@onready var edit: LineEdit = get_node("Edit")

## 动态配置（场景实例化后、入树前调用即可生效）。
## keyboard_type：虚拟键盘类型，缺省数字键盘（与旧行为一致）；文本字段由调用方
## 显式传 LineEdit.KEYBOARD_TYPE_DEFAULT（P6 各域实参经本参数落地）。
## 返回 edit 供组装方直接登记（register_field）。
## label/edit 是 @onready 变量（入树时才赋值）；未入树调用时经 get_node 兜底，
## 保证 setup 返回的 edit 始终有效（register_field 登记契约）。
func setup(label_text: String, p_key: String, placeholder := "",
		keyboard_type: int = LineEdit.KEYBOARD_TYPE_NUMBER) -> LineEdit:
	key = p_key
	var lab: Label = label if label != null else get_node_or_null("Label")
	var ed: LineEdit = edit if edit != null else get_node_or_null("Edit")
	if lab != null:
		lab.text = label_text
	if ed != null:
		ed.placeholder_text = placeholder
		ed.virtual_keyboard_type = keyboard_type
	return ed

func get_value() -> String:
	return edit.text if edit != null else ""

func set_value(v: String) -> void:
	if edit != null:
		edit.text = v
