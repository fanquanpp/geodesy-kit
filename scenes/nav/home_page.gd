# scenes/nav/home_page.gd —— 首页：8 个展示组的方块网格（P9 重构）
#
# 用户硬性要求：计算器条目「不要一行一个，改为方块布局，节省空间利用率高」。
# 分组头部 = 组标题行（折叠交互保留：FoldableContainer 只折条目网格）；
# 条目网格 = GridContainer 3 列（窄屏 2 列），方块按钮 min 高 128 设计 px，
# 文字自动换行居中——触控目标大幅高于 96px 下限且信息密度高。
# 分组数据 = GKDisplayGroups（展示层重分类；manifest 域结构不动）。
class_name GKHomePage
extends Control

signal open_entry(entry: Dictionary)

func _ready() -> void:
	# P9 触控：GKTouchScroll 赋能手指拖滚 + 惯性（真机反馈拖滚动条才能滚）
	var scroll := GKTouchScroll.attach(false)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)

	var sub := Label.new()
	sub.theme_type_variation = &"Muted"
	sub.text = "全离线测绘计算器 · 点方块进入计算"
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

	for g: Dictionary in groups:
		var entries: Array = g["entries"]
		var head := Label.new()
		head.text = "%s（%d）" % [String(g["title"]), entries.size()]
		head.theme_type_variation = &"Header"
		v.add_child(head)

		var grid := GridContainer.new()
		grid.columns = cols
		grid.add_theme_constant_override("h_separation", GKThemeConstants.MIN_TOUCH_SPACING / 2)
		grid.add_theme_constant_override("v_separation", GKThemeConstants.MIN_TOUCH_SPACING / 2)
		v.add_child(grid)
		for e: Dictionary in entries:
			var b := Button.new()
			b.text = String(e["name"])
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.custom_minimum_size = Vector2(0, cell_h)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var entry := e
			b.pressed.connect(func() -> void: open_entry.emit(entry))
			grid.add_child(b)
