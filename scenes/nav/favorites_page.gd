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
	var scroll := ScrollContainer.new()
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
	var empty_shown := ids.is_empty()
	if empty_shown:
		var hint := Label.new()
		hint.theme_type_variation = &"Muted"
		hint.text = "尚未收藏任何计算器。在计算器页点“收藏”后出现在这里。"
		v.add_child(hint)
	for id: String in ids:
		var e: Dictionary = GKServices.catalog.entry(id)
		var b := Button.new()
		if e.is_empty():
			b.text = "%s（条目未加载，可能模块未接入）" % id
			b.disabled = true
		else:
			b.text = String(e["name"])
			b.pressed.connect(func() -> void: open_entry.emit(e))
		b.custom_minimum_size = Vector2(0, 96)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(b)
