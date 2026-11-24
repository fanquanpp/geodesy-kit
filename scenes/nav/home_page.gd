# scenes/nav/home_page.gd —— 首页：8 个展示组折叠卡（P9.4 折叠回归）
#
# 用户要求：分类依旧加上折叠（不要把折叠删了），条目保持方块网格。
# 结构：每展示组一个 FoldableContainer（Card 样式），标题 = 组名（条目数）；
# 卡内 = GridContainer 3 列（窄屏 2 列）方块按钮，min 高 128 设计 px，文字换行居中。
# 默认折叠、只展开第一个组（首屏一屏内可见全部分类入口，展开后网格满宽）。
# 分组数据 = GKDisplayGroups（展示层重分类；manifest 域结构不动）。
class_name GKHomePage
extends Control

signal open_entry(entry: Dictionary)

func _ready() -> void:
	# 触屏滚动交引擎原生路径（deadzone 区分拖动/点击）
	var scroll := GKTouchScroll.attach(false)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)

	var sub := Label.new()
	sub.theme_type_variation = &"Muted"
	sub.text = "全离线测绘计算器 · 点分类展开，点方块进入计算"
	v.add_child(sub)

	var catalog := GKServices.ensure_catalog()
	var groups: Array = GKDisplayGroups.group_entries(catalog.entries())
	if groups.is_empty():
		var empty := PanelContainer.new()
		empty.theme_type_variation = &"Card"
		v.add_child(empty)
		var ev := VBoxContainer.new()
		empty.add_child(ev)
		var t := Label.new()
		t.text = "暂无已接入模块"
		t.theme_type_variation = &"Header"
		ev.add_child(t)
		var d := Label.new()
		d.theme_type_variation = &"Muted"
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.text = "新的计算模块接入后，\n本页将自动出现对应的计算器条目。"
		ev.add_child(d)
		return

	# 触屏设备方块更大（128px 高），键鼠 96px；列数按有效宽自适应
	var cell_h := 128.0 if DisplayServer.is_touchscreen_available() else 96.0
	var cols := 3 if get_viewport().get_visible_rect().size.x >= 700.0 else 2
	var first := true
	for g: Dictionary in groups:
		var entries: Array = g["entries"]
		var card := FoldableContainer.new()
		card.theme_type_variation = &"Card"
		card.folded = not first  # 默认只展开第一个分类
		first = false
		card.title = "%s（%d 个计算器）" % [String(g["title"]), entries.size()]
		v.add_child(card)
		var grid := GridContainer.new()
		grid.columns = cols
		grid.add_theme_constant_override("h_separation", GKThemeConstants.MIN_TOUCH_SPACING / 2)
		grid.add_theme_constant_override("v_separation", GKThemeConstants.MIN_TOUCH_SPACING / 2)
		card.add_child(grid)
		for e: Dictionary in entries:
			var b := Button.new()
			b.text = String(e["name"])
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.custom_minimum_size = Vector2(0, cell_h)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var entry := e
			b.pressed.connect(func() -> void: open_entry.emit(entry))
			grid.add_child(b)
