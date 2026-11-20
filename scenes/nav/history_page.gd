# scenes/nav/history_page.gd —— 历史页（最新在前；点条目回放输入重算，§3.3/DEVELOPMENT_PLAN §3.13）
class_name GKHistoryPage
extends Control

signal open_entry(entry: Dictionary)
signal replay_entry(entry_id: String, inputs: Dictionary)

func _ready() -> void:
	refresh()

func refresh() -> void:
	# 同步移除旧内容再重建（理由同 favorites_page.refresh）
	for c in get_children():
		remove_child(c)
		c.free()
	var scroll := ScrollContainer.new()
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
	var clear_btn := Button.new()
	clear_btn.text = "清空"
	clear_btn.custom_minimum_size = Vector2(120, 96)
	clear_btn.pressed.connect(func() -> void:
		GKServices.history.clear()
		refresh()
	)
	head.add_child(clear_btn)

	var rows: Array = GKServices.history.list(200)
	if rows.is_empty():
		var hint := Label.new()
		hint.theme_type_variation = &"Muted"
		hint.text = "暂无历史记录。任意计算器点击“计算”后自动记录（含输入快照，可回放）。"
		v.add_child(hint)
	for row: Dictionary in rows:
		var card := PanelContainer.new()
		card.theme_type_variation = &"Card"
		v.add_child(card)
		var cv := VBoxContainer.new()
		card.add_child(cv)
		var meta := Label.new()
		meta.theme_type_variation = &"Muted"
		var eid := String(row.get("entry_id", ""))
		var e: Dictionary = GKServices.catalog.entry(eid) if not eid.is_empty() else {}
		var name := String(e.get("name", eid)) if not e.is_empty() else (eid if not eid.is_empty() else "未知条目")
		meta.text = "%s · %s" % [String(row.get("ts_text", "")), name]
		cv.add_child(meta)
		var go := Button.new()
		go.text = "打开该计算器并回放输入"
		go.custom_minimum_size = Vector2(0, 96)
		go.pressed.connect(func() -> void:
			if e.is_empty():
				return
			open_entry.emit(e)
			replay_entry.emit(eid, row.get("inputs", {}))
		)
		cv.add_child(go)
