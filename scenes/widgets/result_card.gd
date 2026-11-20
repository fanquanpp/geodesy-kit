# scenes/widgets/result_card.gd —— 可复用结果卡控件（标题 + 多行结果文本）
# 独立控件场景（result_card.tscn）：组装方（calculator_base / 自定义面板）调用
# set_result(lines: PackedStringArray) 渲染；空内容显示占位"（尚未计算）"。
class_name GKResultCard
extends PanelContainer

@onready var value_label: Label = get_node("VBox/Value")

## 结果行渲染：每行"键 = 值"；空数组显示占位。
func set_result(lines: PackedStringArray) -> void:
	value_label.text = "\n".join(lines) if not lines.is_empty() else "（尚未计算）"

## 当前文本（复制/导出用）
func get_text() -> String:
	return value_label.text if value_label != null else ""
