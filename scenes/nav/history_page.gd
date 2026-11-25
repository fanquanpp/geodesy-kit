# scenes/nav/history_page.gd —— 历史页（最新在前；点条目回放输入重算，§3.3/DEVELOPMENT_PLAN §3.13）
class_name GKHistoryPage
extends Control

signal open_entry(entry: Dictionary)
signal replay_entry(entry_id: String, inputs: Dictionary)

var _clear_dialog: ConfirmationDialog  # 清空历史二次确认（误触即丢全部回放原料）
var _remove_dialog: ConfirmationDialog  # 单条删除二次确认（含输入快照，同样不可恢复）

func _ready() -> void:
	refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for dlg: Node in [_clear_dialog, _remove_dialog]:
			if dlg != null and is_instance_valid(dlg):
				dlg.queue_free()

func refresh() -> void:
	# 同步移除旧内容再重建（理由同 favorites_page.refresh）
	for c in get_children():
		remove_child(c)
		c.free()
	var scroll := GKTouchScroll.attach(false)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)

	var head := HBoxContainer.new()
	v.add_child(head)
	var title := Label.new()
	title.text = "历史"
	title.theme_type_variation = &"Header"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var rows: Array = GKServices.history.list(200)
	var clear_btn := Button.new()
	clear_btn.text = "清空"
	clear_btn.custom_minimum_size = Vector2(120, 96)
	clear_btn.disabled = rows.is_empty()  # 无历史时禁用，避免无效误触
	clear_btn.pressed.connect(_confirm_clear.bind(rows.size()))
	head.add_child(clear_btn)

	if rows.is_empty():
		var hint := Label.new()
		hint.theme_type_variation = &"Muted"
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.text = "暂无历史记录。任意计算器点击「计算」后自动记录（含输入快照，可回放）。"
		v.add_child(hint)
	# P9.4 卡片化：每条历史一张 Card——计算器名（可点回放）为主体，时间戳弱化为 Caption
	for row: Dictionary in rows:
		var card := PanelContainer.new()
		card.theme_type_variation = &"Card"
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(card)
		var cv := VBoxContainer.new()
		card.add_child(cv)
		var eid := String(row.get("entry_id", ""))
		var e: Dictionary = GKServices.catalog.entry(eid) if not eid.is_empty() else {}
		var missing := e.is_empty() and not eid.is_empty()  # 原计算器已随域移除（历史只读展示）
		var name := String(e.get("name", eid)) if not e.is_empty() else (eid if not eid.is_empty() else "未知条目")
		var go := Button.new()
		go.text = name
		go.alignment = HORIZONTAL_ALIGNMENT_LEFT
		go.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		go.custom_minimum_size = Vector2(0, 72)
		go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		go.disabled = missing  # 计算器已下线：无场景可打开，按钮留死链不如禁用
		go.pressed.connect(func() -> void:
			if e.is_empty():
				return
			open_entry.emit(e)
			replay_entry.emit(eid, row.get("inputs", {}))
		)
		cv.add_child(go)
		var meta := Label.new()
		meta.theme_type_variation = &"Caption"
		meta.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 文本不拦卡片点击（同 result_card）
		meta.text = "%s%s" % [String(row.get("ts_text", "")),
			" · 原计算器已移除，仅存历史记录" if missing else ""]
		cv.add_child(meta)
		# 细粒度操作：「…」按钮弹菜单——单条删除走 ConfirmationDialog（与清空同口径：
		# 含输入快照不可恢复），删除接 app/history.gd remove(rid)
		var more := Button.new()
		more.text = "…"
		more.custom_minimum_size = Vector2(0, 48)
		more.size_flags_horizontal = Control.SIZE_SHRINK_END
		more.pressed.connect(_show_row_menu.bind(more, int(row.get("rid", -1)), name))
		cv.add_child(more)

## 清空前二次确认（ConfirmationDialog 挂根窗口；历史含输入快照是回放功能的原料，
## 冷审问题⑨：一点即全部清空无确认，误触不可恢复）。
func _confirm_clear(count: int) -> void:
	if _clear_dialog != null and is_instance_valid(_clear_dialog):
		_clear_dialog.queue_free()
	_clear_dialog = ConfirmationDialog.new()
	_clear_dialog.dialog_text = "确定清空全部 %d 条历史？（含输入快照，清空后不可恢复）" % count
	_clear_dialog.ok_button_text = "清空"
	_clear_dialog.cancel_button_text = "取消"
	_clear_dialog.get_ok_button().pressed.connect(func() -> void:
		GKServices.history.clear()
		refresh()
	)
	# 挂到根窗口（本页可能被移出树重建，对话框生命周期独立管理）
	get_tree().root.add_child(_clear_dialog)
	_clear_dialog.popup_centered()

## 单条删除：弹出锚定在「…」按钮下的 PopupMenu（每次新建，随 refresh 一并释放）
func _show_row_menu(anchor: Button, rid: int, title_text: String) -> void:
	if rid < 0:
		return
	var menu := PopupMenu.new()
	menu.add_item("删除该条记录", 0)
	menu.id_pressed.connect(func(id: int) -> void:
		if id == 0:
			_confirm_remove(rid, title_text)
	)
	get_tree().root.add_child(menu)
	menu.popup_hide.connect(menu.queue_free)  # 选完/点外即释放，不悬挂
	var bl := anchor.get_global_rect()
	menu.popup(Rect2i(Vector2i(bl.position + Vector2(bl.size.x - 160, bl.size.y)), Vector2i(160, 0)))

## 单条删除二次确认（接 app/history.gd remove(rid)；快照删除后该条回放能力随失）
func _confirm_remove(rid: int, title_text: String) -> void:
	if _remove_dialog != null and is_instance_valid(_remove_dialog):
		_remove_dialog.queue_free()
	_remove_dialog = ConfirmationDialog.new()
	_remove_dialog.dialog_text = "删除「%s」的这条历史记录？（含输入快照，删除后不可恢复）" % title_text
	_remove_dialog.ok_button_text = "删除"
	_remove_dialog.cancel_button_text = "取消"
	_remove_dialog.get_ok_button().pressed.connect(func() -> void:
		GKServices.history.remove(rid)
		refresh()
	)
	get_tree().root.add_child(_remove_dialog)
	_remove_dialog.popup_centered()
