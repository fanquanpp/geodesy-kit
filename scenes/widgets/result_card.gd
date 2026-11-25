# scenes/widgets/result_card.gd —— 可复用结果卡控件（标题 + 逐行结果 + 逐行复制）
# 独立控件场景（result_card.tscn）：组装方（calculator_base / 自定义面板）调用
# set_result(lines: PackedStringArray) 渲染；空内容在 value_label 显示占位"（尚未计算）"。
# 有结果时 value_label 隐藏（占位专用），行文本只渲染在行区——修复冷审问题③
# （全文 join + 逐行按钮导致文本显示两遍、卡高翻倍）。
# get_text() 语义保持 tests/app/test_widgets.gd:30-38 既有断言：多行文本 = "\n".join(lines)，
# 空数组回落占位，且不含复制按钮附加内容。
# 逐行「复制」按钮触控目标统一 GKThemeConstants.TOUCH_TARGET（96 设计 px），
# 行间距用 MIN_TOUCH_SPACING（此前按钮 64px 高低于项目统一 96px 触控目标）。
# 行级按钮仅在行数 ≤ COPY_ROW_MAX（5）时渲染：多行结果卡纵向按钮列过密，
# 复制整卡走卡头「复制全部」；单行复制反馈带行摘要（前 24 字符）供状态行确认。
class_name GKResultCard
extends PanelContainer

signal copy_confirmed(line_text: String)  # 复制成功（组装方用于状态行反馈）

const _TC := preload("res://themes/theme_constants.gd")  # GKThemeConstants

## 行级复制按钮的行数上限：超过则只留卡头「复制全部」
const COPY_ROW_MAX := 5
## 复制反馈中的行摘要长度（状态行过长会换行挤压版面）
const COPY_FEEDBACK_CHARS := 24
## 状态色条宽度（设计 px）；高度 = 面板左描边宽（2px）级别的细条，置于内容之前
const STATUS_BAR_WIDTH := 6.0
## 状态色条 Tween 展开时长（秒）
const STATUS_BAR_TWEEN := 0.2

@onready var value_label: Label = get_node("VBox/Value")

var _lines: PackedStringArray = PackedStringArray()
var _status_color := Color()          # 当前状态色（_draw 用；Color() 即不画）
var _status_width := 0.0              # 状态条当前宽度（Tween 驱动，queue_redraw 重绘）

func _ready() -> void:
	(get_node("VBox/CopyAll") as Button).pressed.connect(_on_copy_all)

## 状态色条：三色取主题语义 Label 字色（缺项回退中性色，主题未构建时不崩）。
## P11 修复：此前用 PanelContainer 子 ColorRect 承载——PanelContainer 给所有
## 子节点分配满布局（锚点被容器覆盖），6px 细条变成满宽色块盖住结果内容。
## 改为 _draw 自绘左缘竖条：不受容器布局，宽度 Tween + queue_redraw 过渡。
func _draw() -> void:
	if _status_color != Color() and _status_width > 0.0:
		var h := size.y - 8.0
		draw_rect(Rect2(0.0, 4.0, _status_width, h), _status_color)

func _bar_color(kind: String) -> Color:
	var c := get_theme_color("font_color", kind)
	return c if c != Color() else Color(0.6, 0.6, 0.6)

func _show_status_bar(kind: String) -> void:
	_status_color = _bar_color(kind)
	var tw := create_tween()
	tw.tween_method(_set_bar_width, _status_width, STATUS_BAR_WIDTH, STATUS_BAR_TWEEN) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _set_bar_width(w: float) -> void:
	_status_width = w
	queue_redraw()

## 隐藏状态色条：宽度收回到 0
func _hide_status_bar() -> void:
	if _status_color == Color() and _status_width == 0.0:
		return
	var tw := create_tween()
	tw.tween_method(_set_bar_width, _status_width, 0.0, STATUS_BAR_TWEEN) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

## 结果行渲染：每行一条（行文本 + 行数 ≤ 阈值时的 96px 复制按钮）；空数组显示占位。
## P9.4 修复渲染死区：行数 > COPY_ROW_MAX 时此前既不渲染行（直接 return）又
## 隐藏 value_label（有结果时占位语义）——结果卡一片空白，用户看到"计算是假的"。
## 修复：行多时 value_label 常显承载全部文本（只读结果一览），行级按钮仍受阈值限制。
func set_result(lines: PackedStringArray) -> void:
	_lines = lines
	value_label.text = "\n".join(lines) if not lines.is_empty() else "（尚未计算）"
	# 占位语义：无结果显示占位。行区现在始终渲染双列结构（P11），value_label
	# 只在空态承担占位文本——行多时不再全文重复（P9.4 双显问题的最终收口）。
	value_label.visible = lines.is_empty()
	_rebuild_rows()
	_hide_status_bar()  # 正常态：色条收回，变体回落 Card

## 失败态：卡体换 ErrorCard 变体（错误红描边，主题缺失回退默认不报错），
## 左缘展开红色状态条——与 batch_convert 失败行卡同一视觉语言。
func set_failed() -> void:
	theme_type_variation = &"ErrorCard"
	_show_status_bar("ErrorLabel")

## 成功态：恢复 Card 变体并展开绿色状态条（成功后显式调用）。
func set_succeeded() -> void:
	theme_type_variation = &"Card"
	_show_status_bar("OkLabel")

## 卡头「复制全部」按钮：行多时唯一复制入口；行少时与行级按钮并存
func _on_copy_all() -> void:
	if GKClipboard.copy_text(get_text()):
		copy_confirmed.emit(get_text())

## 当前文本（复制/导出用；语义与改造前一致：仅结果行文本，不含按钮/标题/占位）
func get_text() -> String:
	if _lines.is_empty():
		return "（尚未计算）"
	return "\n".join(_lines)

## 行区：Rows 容器整体同步清空重建（节点名前缀扫描会漏改节点类型，容器清空无此隐患）
## P11 双列对齐（调研落地）：行文本按最后一个 " = " 拆「标签 | 数值」两 Label——
## 标签左对齐、数值右对齐，长短标签/数值天然列对齐（正规计算器惯例），
## 免等宽字体依赖（Noto Sans SC 数字本就等宽，fontTools 实测 advance 一致）。
## 拆不出 " = " 的行（纯文本行）保持单 Label 全文渲染。
func _rebuild_rows() -> void:
	var box: VBoxContainer = get_node("VBox")
	var rows := box.get_node_or_null("Rows") as VBoxContainer
	if rows == null:
		rows = VBoxContainer.new()
		rows.name = "Rows"
		box.add_child(rows)
	# 同步移除旧行（queue_free 延迟释放会让连续渲染出现双份按钮）
	for c in rows.get_children():
		rows.remove_child(c)
		c.free()
	rows.visible = not _lines.is_empty()
	rows.add_theme_constant_override("separation", _TC.MIN_TOUCH_SPACING)
	# P11：双列行结构始终渲染（标签左/数值右对齐），行级复制按钮仅 ≤COPY_ROW_MAX
	# 行时渲染——行多时不再整体退回 value_label 单列全文（无双列对齐），
	# value_label 仍承担 >COPY_ROW_MAX 行的全文展示（滚动流只读一览）。
	for i in _lines.size():
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.custom_minimum_size = Vector2(0, _TC.TOUCH_TARGET if _lines.size() <= COPY_ROW_MAX else 0)
		row.add_theme_constant_override("separation", _TC.MIN_TOUCH_SPACING)
		var lab := Label.new()
		var val := Label.new()
		var sep := _lines[i].rfind(" = ")
		if sep > 0:
			lab.text = _lines[i].substr(0, sep)
			val.text = _lines[i].substr(sep + 3)
			lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lab.size_flags_stretch_ratio = 1.0
			lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			val.custom_minimum_size = Vector2(0, 0)
			val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			val.size_flags_horizontal = Control.SIZE_SHRINK_END
		else:
			lab.text = _lines[i]
			lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for l: Label in [lab, val]:
			l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 文本不拦点击
		row.add_child(lab)
		if sep > 0:
			row.add_child(val)
		if _lines.size() <= COPY_ROW_MAX:
			var btn := Button.new()
			btn.text = "复制"
			btn.tooltip_text = "复制本行到剪贴板"
			btn.custom_minimum_size = Vector2(_TC.TOUCH_TARGET, _TC.TOUCH_TARGET)
			btn.pressed.connect(_on_copy_line.bind(i))
			row.add_child(btn)
		rows.add_child(row)

## 行摘要：前若干字符 + 省略号（反馈行显示用，不含换行）
static func line_digest(line: String) -> String:
	var one := line.replace("\n", " ")
	if one.length() <= COPY_FEEDBACK_CHARS:
		return one
	return one.substr(0, COPY_FEEDBACK_CHARS) + "…"

func _on_copy_line(i: int) -> void:
	if i < 0 or i >= _lines.size():
		return
	if GKClipboard.copy_text(_lines[i]):
		copy_confirmed.emit(line_digest(_lines[i]))
