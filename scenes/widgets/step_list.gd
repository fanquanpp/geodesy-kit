# scenes/widgets/step_list.gd —— 可复用步骤列表控件（§5 四段式步骤卡片流）
# 独立控件场景（step_list.tscn）：ScrollContainer + VBox；组装方调用
# set_steps(steps: Array) 渲染 title/formula/substitution/result 四行卡片，
# 空字段跳过（§5 规则②）。clear() 清空。
class_name GKStepList
extends ScrollContainer

var _root: VBoxContainer

func _ready() -> void:
	if _root == null:
		_root = VBoxContainer.new()
		_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(_root)

## 渲染步骤数组（元素 {title, formula, substitution, result}）
func set_steps(steps: Array) -> void:
	_ensure_root()
	clear()
	for st: Dictionary in steps:
		var card := PanelContainer.new()
		card.theme_type_variation = &"Card"
		var cv := VBoxContainer.new()
		card.add_child(cv)
		for pair: Array in [["title", "Header"], ["formula", ""], ["substitution", "Muted"], ["result", ""]]:
			var txt := String(st.get(pair[0], ""))
			if txt.is_empty():
				continue
			var lab := Label.new()
			lab.text = txt
			lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			if pair[1] != "":
				lab.theme_type_variation = StringName(pair[1])
			cv.add_child(lab)
		_root.add_child(card)

func set_visible_by_steps(steps: Array) -> void:
	_ensure_root()
	get_parent().visible = not steps.is_empty()

func clear() -> void:
	_ensure_root()
	# 立即移除旧卡（queue_free 延迟到帧尾，连续两次 run() 时旧卡仍会计入 step_count，
	# 且 calculator_base 连续渲染会瞬时翻倍——这里用同步 remove_child+free 保证幂等）
	for c in _root.get_children():
		_root.remove_child(c)
		c.free()

func step_count() -> int:
	_ensure_root()
	return _root.get_child_count()

func _ensure_root() -> void:
	if _root == null:
		_ready()
