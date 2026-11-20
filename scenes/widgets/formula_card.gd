# scenes/widgets/formula_card.gd —— 可复用公式卡控件（FoldableContainer 折叠"公式与依据"）
# 独立控件场景（formula_card.tscn）：组装方调用 set_formula(text) / set_folded()。
class_name GKFormulaCard
extends FoldableContainer

@onready var formula_label: Label = get_node("Text")

func _ready() -> void:
	title = "公式与依据"
	folded = true

## 设置公式/依据文本（空串时隐藏折叠面板）
func set_formula(text: String) -> void:
	formula_label.text = text
	visible = not text.is_empty()

## 只按"是否有内容"控制显隐（渲染流程已另行写入 formula_label）
func set_visible_by_formula(has_text: bool) -> void:
	visible = has_text
