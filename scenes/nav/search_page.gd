# scenes/nav/search_page.gd —— 全局搜索：name 包含 OR keywords 分词命中（catalog.search）
class_name GKSearchPage
extends Control

signal open_entry(entry: Dictionary)

var _box: LineEdit
var _result_root: VBoxContainer
var _hint: Label
var _debounce: SceneTreeTimer  # 输入防抖：停顿 0.25s 才真正检索（manifest 全量列表较大）

func _ready() -> void:
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(v)

	_box = LineEdit.new()
	_box.placeholder_text = "搜索计算器：名称或关键词（如 高斯 / UTM / 水准）"
	_box.custom_minimum_size = Vector2(0, 96)
	_box.text_changed.connect(_on_query_changed)
	_box.text_submitted.connect(func(_t: String) -> void: _open_first_result())
	v.add_child(_box)

	_hint = Label.new()
	_hint.theme_type_variation = &"Muted"
	_hint.text = "搜索范围为全部已加载模块的 name + keywords；回车打开第一条结果"
	v.add_child(_hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	_result_root = VBoxContainer.new()
	_result_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_result_root)

	_on_query_changed("")

## 回车直达：第一条命中即打开（常用计算可达性；无命中时不动）
func _open_first_result() -> void:
	var q := _box.text.strip_edges()
	if q.is_empty():
		return
	var results: Array = GKServices.ensure_catalog().search(q)
	if not results.is_empty():
		open_entry.emit(results[0])

func _on_query_changed(_q: String) -> void:
	# 防抖：每次按键重置计时器，停顿后统一走 _do_search（避免全量列表逐键重建闪烁）
	_debounce = get_tree().create_timer(0.25)
	_debounce.timeout.connect(_do_search, CONNECT_ONE_SHOT)

func _do_search() -> void:
	var q := _box.text.strip_edges()
	# 同步移除旧结果行再重建（queue_free 延迟释放会让本帧出现双份卡片）
	for c in _result_root.get_children():
		_result_root.remove_child(c)
		c.free()
	var results: Array = GKServices.ensure_catalog().search(q)
	if q.is_empty():
		_hint.text = "共 %d 个计算器（输入关键词过滤；回车打开第一条）" % results.size()
	else:
		_hint.text = "“%s” 命中 %d 项" % [q, results.size()]
	for e: Dictionary in results:
		_add_row(e)
	if not q.is_empty() and results.is_empty():
		var none := Label.new()
		none.theme_type_variation = &"Muted"
		none.text = "无匹配项：换个关键词试试（支持 name + keywords 分词）"
		_result_root.add_child(none)

func _add_row(e: Dictionary) -> void:
	var b := Button.new()
	b.text = "%s（%s）" % [e["name"], GKModuleIndex.DOMAIN_TITLES.get(e.get("domain", ""), e.get("domain", ""))]
	b.custom_minimum_size = Vector2(0, 96)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func() -> void: open_entry.emit(e))
	_result_root.add_child(b)
