# scenes/nav/favorites_page.gd —— 收藏页（favorites 表按 entry id 关联，ARCHITECTURE.md §3.3）
class_name GKFavoritesPage
extends Control

signal open_entry(entry: Dictionary)

func _ready() -> void:
	refresh()

func refresh() -> void:
	# 同步移除旧内容再重建：queue_free 延迟到帧尾，快速连续 refresh 时旧卡片
	# 仍在本帧计入（同一陷阱 scenes/widgets/step_list.gd clear() 已实测并修复）
	for c in get_children():
		remove_child(c)
		c.free()
	var scroll := GKTouchScroll.attach(false)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)

	var title := Label.new()
	title.text = "收藏"
	title.theme_type_variation = &"Header"
	v.add_child(title)

	var ids: Array = GKServices.favorites.list()
	if ids.is_empty():
		var hint := Label.new()
		hint.theme_type_variation = &"Muted"
		hint.text = "尚未收藏任何计算器。在计算器页点「收藏」后出现在这里。"
		v.add_child(hint)
	# P9：收藏条目方块网格化（与首页一致，触屏 128px 高、2–3 列自适应）
	var cell_h := 128.0 if DisplayServer.is_touchscreen_available() else 96.0
	var cols := 3 if get_viewport().get_visible_rect().size.x >= 700.0 else 2
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", GKThemeConstants.MIN_TOUCH_SPACING / 2)
	grid.add_theme_constant_override("v_separation", GKThemeConstants.MIN_TOUCH_SPACING / 2)
	v.add_child(grid)
	for id: String in ids:
		var e: Dictionary = GKServices.catalog.entry(id)
		var b := Button.new()
		if e.is_empty():
			b.text = "该计算器尚未加载（对应模块未接入）"
			b.disabled = true
		else:
			b.text = String(e["name"])
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.pressed.connect(func() -> void: open_entry.emit(e))
		b.custom_minimum_size = Vector2(0, cell_h)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)
