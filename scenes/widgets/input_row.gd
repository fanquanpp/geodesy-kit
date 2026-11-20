# scenes/widgets/input_row.gd —— 可复用输入行控件（标签 + LineEdit，触控行高 96px）
# 独立控件场景（input_row.tscn）：面板/计算器基类只做组装，不重复建行逻辑。
# 读写经 get_value()/set_value()/edit；key 供输入快照契约（get_inputs/set_inputs）使用。
class_name GKInputRow
extends HBoxContainer

var key := ""
@onready var label: Label = get_node("Label")
@onready var edit: LineEdit = get_node("Edit")

## 动态配置（场景实例化后、入树前调用即可生效）
func setup(label_text: String, p_key: String, placeholder := "") -> void:
	key = p_key
	if label != null:
		label.text = label_text
	if edit != null:
		edit.placeholder_text = placeholder

func get_value() -> String:
	return edit.text if edit != null else ""

func set_value(v: String) -> void:
	if edit != null:
		edit.text = v
