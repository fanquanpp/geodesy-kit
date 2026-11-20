# scenes/widgets/limits_panel.gd —— 可复用限差检核面板控件（§5 规则③）
# 独立控件场景（limits_panel.tscn）：组装方调用 set_limits(ok: bool, detail: PackedStringArray)。
# ok=true → 通过（OkLabel 绿色语义）；false → 超限（ErrorLabel 红色语义）。
class_name GKLimitsPanel
extends PanelContainer

@onready var limits_label: Label = get_node("VBox/Detail")

func _ready() -> void:
	visible = false

## 渲染限差检核。detail 首行应为"检核结论：通过/超限"。
func set_limits(ok: bool, detail: PackedStringArray) -> void:
	visible = true
	limits_label.theme_type_variation = &"OkLabel" if ok else &"ErrorLabel"
	limits_label.text = "\n".join(detail)

func clear() -> void:
	visible = false
