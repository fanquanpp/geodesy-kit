# scenes/widgets/limits_panel.gd —— 可复用限差检核面板控件（§5 规则③）
# 独立控件场景（limits_panel.tscn）：组装方调用 set_limits(ok: bool, detail: PackedStringArray)。
# ok=true → 通过（OkLabel 绿色语义）；false → 超限（ErrorLabel 红色语义）。
# 结论行唯一归属 Verdict（由 ok 参数独立生成，加粗 ResultAccent 语义）；
# detail 若首行含结论（"检核结论：…"前缀），set_limits 内部剥离——明细行不重复结论，
# 兼容组装方仍按旧口径把结论塞进 detail[0] 的调用（calculator_base._render_result）。
class_name GKLimitsPanel
extends PanelContainer

@onready var limits_label: Label = get_node("VBox/Detail")
@onready var verdict_label: Label = get_node_or_null("VBox/Verdict")

func _ready() -> void:
	visible = false

## 渲染限差检核。detail 若首行为结论行则剥离，仅渲染明细；结论由 ok 参数生成。
func set_limits(ok: bool, detail: PackedStringArray) -> void:
	visible = true
	# 语义色挂在 limits_label（既有契约）；结论行唯一归属 Verdict，不进明细
	limits_label.theme_type_variation = &"OkLabel" if ok else &"ErrorLabel"
	var body := PackedStringArray()
	for line in detail:
		var txt := String(line)
		if txt.begins_with("检核结论："):
			continue
		body.append(txt)
	limits_label.text = "\n".join(body)
	if verdict_label != null:
		verdict_label.theme_type_variation = &"ResultAccent"
		verdict_label.text = "检核结论：通过" if ok else "检核结论：超限"

func clear() -> void:
	visible = false
