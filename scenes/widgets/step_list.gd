# scenes/widgets/step_list.gd —— 可复用步骤列表控件（§5 四段式步骤卡片流）
# 独立控件场景（step_list.tscn）：VBoxContainer（P6：去内嵌 ScrollContainer，
# 滚动权交给外层整页滚动，避免滚动嵌套；根节点 SIZE_FILL，纵向不抢高）。
# 组装方调用 set_steps(steps: Array) 渲染 title/formula/substitution/result 四行
# 折叠卡片（FoldableContainer，与 formula_card 同控件：折叠头触控口径一致），
# 空字段跳过（§5 规则②）；默认全部折叠、只展开最后一步（结果就近可读）。
# clear() 清空。set_visible_by_steps 已删（无人调用，越界操作 get_parent 的接口）。
class_name GKStepList
extends VBoxContainer

var _root: VBoxContainer

func _ready() -> void:
	if _root == null:
		_root = self

## 渲染步骤数组（元素 {title, formula, substitution, result}）；
## 手风琴策略（P11 调研②落地，对标 WA 分步可展开）：关键步骤（闭合差/限差/
## 检核/改正/精度/判据/超限/分配——学生最需要看的过程）默认展开，机械代入
## 步骤默认折叠；无关键步骤时回退旧行为（只展开最后一步，结果就近可读）。
const _KEY_STEP_PATTERNS := ["闭合差", "限差", "检核", "改正", "精度", "判据", "超限", "分配"]

## 是否关键步骤：标题命中关键词即视为关键（core 的 title 字段直接决定）。
static func is_key_step(title_txt: String) -> bool:
	for p in _KEY_STEP_PATTERNS:
		if title_txt.contains(String(p)):
			return true
	return false

func set_steps(steps: Array) -> void:
	_ensure_root()
	clear()
	var n := steps.size()
	var any_key := false
	for st: Dictionary in steps:
		if is_key_step(String(st.get("title", ""))):
			any_key = true
			break
	for i in n:
		var st: Dictionary = steps[i]
		var card := FoldableContainer.new()
		# 关键步骤展开；无关键步骤时回退旧行为（只展开最后一步）
		if any_key:
			card.folded = not is_key_step(String(st.get("title", "")))
		else:
			card.folded = i != n - 1
		var title_txt := String(st.get("title", ""))
		card.title = "步骤 %d/%d　%s" % [i + 1, n, _strip_existing_index(title_txt)]
		var cv := VBoxContainer.new()
		card.add_child(cv)
		# 四行层级：formula 弱化（Muted）、substitution 正常、result 强调（ResultAccent）
		for pair: Array in [["formula", "Muted"], ["substitution", ""], ["result", "ResultAccent"]]:
			var txt := String(st.get(pair[0], ""))
			if txt.is_empty():
				continue
			var lab := Label.new()
			lab.text = txt
			lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			if pair[1] != "":
				lab.theme_type_variation = StringName(pair[1])
			cv.add_child(lab)
		add_child(card)

## 标题里已有的「1. 」式序号去掉，避免与「步骤 i/n」重复编号
func _strip_existing_index(t: String) -> String:
	var regex := RegEx.new()
	# 匹配形如 "1. " / "12、" / "3．" 的前缀
	regex.compile("^\\s*\\d+\\s*[.、．]\\s*")
	return regex.sub(t, "", true)

func clear() -> void:
	_ensure_root()
	# 立即移除旧卡（queue_free 延迟到帧尾，连续两次 run() 时旧卡仍会计入 step_count，
	# 且 calculator_base 连续渲染会瞬时翻倍——这里用同步 remove_child+free 保证幂等）
	for c in get_children():
		remove_child(c)
		c.free()

func step_count() -> int:
	_ensure_root()
	return get_child_count()

func _ensure_root() -> void:
	if _root == null:
		_ready()
