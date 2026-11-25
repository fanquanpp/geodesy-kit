# scenes/nav/favorites_page.gd —— 收藏页（favorites 表按 entry id 关联，ARCHITECTURE.md §3.3）
# P9.4：条目卡片化（Card 面板包裹方块网格，与首页视觉一致），触屏拖滚原生路径。
class_name GKFavoritesPage
extends Control

signal open_entry(entry: Dictionary)

var _remove_dialog: ConfirmationDialog  # 取消收藏二次确认（防误触）
var _grid: GridContainer  # 收藏网格（视口 resize 时重算列数）

func _ready() -> void:
	refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _grid != null and is_instance_valid(_grid):
		var cols := 3 if GKResponsive.breakpoint_now(self) != GKResponsive.Breakpoint.COMPACT else 2
		if _grid.columns != cols:
			_grid.columns = cols
	elif what == NOTIFICATION_PREDELETE and _remove_dialog != null and is_instance_valid(_remove_dialog):
		_remove_dialog.queue_free()

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
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.text = "尚未收藏任何计算器。在计算器页点「收藏」后出现在这里。"
		v.add_child(hint)
		return
	# 卡片化：单张 Card 面板承载网格（条目多时整卡随页滚动，卡内不再嵌滚动）
	var card := PanelContainer.new()
	card.theme_type_variation = &"Card"
	v.add_child(card)
	var card_v := VBoxContainer.new()
	card.add_child(card_v)
	var grid := GridContainer.new()
	_grid = grid  # NOTIFICATION_RESIZED 重算列数用
	# 列数走 GKResponsive（窄 COMPACT 2 列 / MEDIUM+WIDE 3 列），视口 resize 重算
	grid.columns = 3 if GKResponsive.breakpoint_now(self) != GKResponsive.Breakpoint.COMPACT else 2
	grid.add_theme_constant_override("h_separation", GKThemeConstants.MIN_TOUCH_SPACING / 2)
	grid.add_theme_constant_override("v_separation", GKThemeConstants.MIN_TOUCH_SPACING / 2)
	card_v.add_child(grid)
	var cell_h := 128.0 if DisplayServer.is_touchscreen_available() else 96.0
	for id: String in ids:
		var e: Dictionary = GKServices.catalog.entry(id)
		var cell := VBoxContainer.new()
		grid.add_child(cell)
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
		cell.add_child(b)
		# 细粒度操作：单元格下方「取消收藏」文字按钮——取消接 favorites.toggle(id)
		# （toggle 内部自会移除已收藏项；不走私有 _remove_entry），二次确认防误触
		var rm := Button.new()
		rm.text = "取消收藏"
		rm.theme_type_variation = &"Caption"
		rm.custom_minimum_size = Vector2(0, 40)
		rm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rm.pressed.connect(_confirm_remove.bind(id, String(e.get("name", id))))
		cell.add_child(rm)

## 取消收藏二次确认（app/favorites.gd toggle：已收藏再 toggle 即移除并返回 false）
func _confirm_remove(id: String, name_text: String) -> void:
	if _remove_dialog != null and is_instance_valid(_remove_dialog):
		_remove_dialog.queue_free()
	_remove_dialog = ConfirmationDialog.new()
	_remove_dialog.dialog_text = "取消收藏「%s」？" % name_text
	_remove_dialog.ok_button_text = "取消收藏"
	_remove_dialog.cancel_button_text = "保留"
	_remove_dialog.get_ok_button().pressed.connect(func() -> void:
		GKServices.favorites.toggle(id)
		refresh()
	)
	# 挂到根窗口（本页可能被移出树重建，对话框生命周期独立管理）
	get_tree().root.add_child(_remove_dialog)
	_remove_dialog.popup_centered()
