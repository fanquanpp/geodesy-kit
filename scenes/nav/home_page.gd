# scenes/nav/home_page.gd —— 首页：8 个展示组折叠卡（P9.4 折叠回归）
#
# 用户要求：分类依旧加上折叠（不要把折叠删了），条目保持方块网格。
# 结构：每展示组一个 FoldableContainer（Card 样式），标题 = 组名（条目数）；
# 卡内 = GridContainer 3 列（窄屏 2 列）方块按钮，min 高 128 设计 px，文字换行居中。
# 列数断点走 GKResponsive（窄 COMPACT 2 列 / MEDIUM+WIDE 3 列），视口 resize 重算。
# 默认折叠、只展开第一个组（首屏一屏内可见全部分类入口，展开后网格满宽）。
# 分组数据 = GKDisplayGroups（展示层重分类；manifest 域结构不动）。
class_name GKHomePage
extends Control

signal open_entry(entry: Dictionary)

# 全部组网格（断点切换重算列数：size_changed 时逐网格按当前视口宽定列数）
var _grids: Array = []

func _ready() -> void:
	# 触屏滚动交引擎原生路径（deadzone 区分拖动/点击）
	var scroll := GKTouchScroll.attach(false)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	# v0.4 官方拖滚修复：子控件 STOP→PASS（godot#16318/#95532 口径）
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)

	var sub := Label.new()
	sub.theme_type_variation = &"Muted"
	sub.text = "全离线测绘计算器 · 点分类展开，点方块进入计算"
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 文本不拦点击（同 result_card）
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

	# 触屏设备方块更大（128px 高），键鼠 96px；列数走 GKResponsive（窄 2 列 / 中宽 3 列）
	var cell_h := 128.0 if DisplayServer.is_touchscreen_available() else 96.0
	var cols := 3 if GKResponsive.breakpoint_now(self) != GKResponsive.Breakpoint.COMPACT else 2
	var first := true
	for g: Dictionary in groups:
		var entries: Array = g["entries"]
		var card := FoldableContainer.new()
		card.theme_type_variation = &"Card"
		card.folded = not first  # 默认只展开第一个分类
		first = false
		card.title = "%s（%d 个计算器）" % [String(g["title"]), entries.size()]
		# 组图标：4.7.2 的 add_title_bar_control 实测不生效（探针确认控件被挂进
		# 隐藏内部层，真机截图同样不显示）——组标题不挂图标，图标只在条目方块上
		# 按"条目所属域"区分（display_groups.entry_icon，D/E 线路土方已拆分）。
		v.add_child(card)
		var grid := GridContainer.new()
		grid.columns = cols
		_grids.append(grid)  # 断点切换时统一重算列数
		grid.add_theme_constant_override("h_separation", GKThemeConstants.MIN_TOUCH_SPACING / 2)
		grid.add_theme_constant_override("v_separation", GKThemeConstants.MIN_TOUCH_SPACING / 2)
		card.add_child(grid)
		for e: Dictionary in entries:
			var b := Button.new()
			b.text = String(e["name"])
			# 条目图标按所属域取（display_groups.entry_icon）：route 域 D/E 条目
			# 已拆分为线路/土方两枚图标，不再共用组同源图标。
			var icon_path := GKDisplayGroups.entry_icon(String(e["id"]), e)
			if icon_path != "" and ResourceLoader.exists(icon_path):
				b.icon = load(icon_path)
				b.add_theme_constant_override("icon_max_width", 40)  # 图标放大到触屏可辨（默认随字高 16px 太小）
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.custom_minimum_size = Vector2(0, cell_h)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var entry := e
			b.pressed.connect(func() -> void: open_entry.emit(entry))
			grid.add_child(b)

## 视口尺寸变化：所有组网格按当前断点重算列数（窄屏 2 列 / 中档与宽屏 3 列）
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_grid_columns()

func _apply_grid_columns() -> void:
	var cols := 3 if GKResponsive.breakpoint_now(self) != GKResponsive.Breakpoint.COMPACT else 2
	for g: Control in _grids:
		if is_instance_valid(g) and g.columns != cols:
			g.columns = cols
