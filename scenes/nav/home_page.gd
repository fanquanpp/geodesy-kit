# scenes/nav/home_page.gd —— 首页：域分类网格（manifest 驱动，ARCHITECTURE.md §3）
# 施工域未提供 manifest 时显示占位提示，不阻断导航。
class_name GKHomePage
extends Control

signal open_entry(entry: Dictionary)

func _ready() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)

	var title := Label.new()
	title.text = "GeodesyKit"
	title.theme_type_variation = &"Header"
	v.add_child(title)
	var sub := Label.new()
	sub.theme_type_variation = &"Muted"
	sub.text = "全离线测绘计算器 · 模块自描述加载（manifest.json）"
	v.add_child(sub)

	var domains: Dictionary = GKServices.ensure_catalog().by_domain()
	if domains.is_empty():
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
		d.text = "各施工域在自己的 scenes/calculators/<域>/manifest.json 就位后，\n本页将自动出现该域的计算器条目（无需改任何共享文件）。"
		ev.add_child(d)
		return

	for domain: String in domains.keys():
		var info: Dictionary = domains[domain]
		var card := PanelContainer.new()
		card.theme_type_variation = &"Card"
		v.add_child(card)
		var cv := VBoxContainer.new()
		card.add_child(cv)
		# 域标题行：模块图标（manifest icon）+ 标题；缺图标退化为标题首字方块
		var head := HBoxContainer.new()
		cv.add_child(head)
		var icon_path := String(GKServices.catalog.domain_icon(domain))
		var tex: Texture2D = load(icon_path) if not icon_path.is_empty() else null
		if tex != null:
			var icon := TextureRect.new()
			icon.texture = tex
			icon.custom_minimum_size = Vector2(64, 64)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			head.add_child(icon)
		else:
			# 缺图标兜底：首字圆形色块（主题主色），可点击性弱化但保留域识别
			var fallback := PanelContainer.new()
			fallback.custom_minimum_size = Vector2(64, 64)
			var fbox := StyleBoxFlat.new()
			fbox.bg_color = Color(0.086, 0.408, 0.659, 0.18)  # primary #1668A8 低饱和底
			fbox.set_corner_radius_all(32)
			fallback.add_theme_stylebox_override("panel", fbox)
			head.add_child(fallback)
			var fc := Label.new()
			fc.text = String(info["title"]).substr(0, 1)
			fc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			fc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			fallback.add_child(fc)
		var dt := Label.new()
		dt.text = String(info["title"])
		dt.theme_type_variation = &"Header"
		dt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		head.add_child(dt)
		var entries: Array = info["entries"]
		if entries.is_empty():
			var none := Label.new()
			none.theme_type_variation = &"Muted"
			none.text = "该域 manifest 就位但暂无有效条目"
			cv.add_child(none)
		# 条目列表内收紧间距（卡片间 12 由主题常量提供，条目间 8 更密）
		for e: Dictionary in entries:
			var b := Button.new()
			b.text = String(e["name"])
			b.custom_minimum_size = Vector2(0, 96)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT  # 列表语义：左对齐扫读
			var entry := e
			b.pressed.connect(func() -> void: open_entry.emit(entry))
			cv.add_child(b)
