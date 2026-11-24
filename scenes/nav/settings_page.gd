# scenes/nav/settings_page.gd —— 设置页（施工包 P7 新建）
#
# 只调用 app/settings.gd 既有 API（不改契约）：
#   - GKSettings.get_value / set_value：decimals（1–12 步进器，越界 set_value 返回 false 回滚显示）
#     与 ui_scale（四档 0.8/1.0/1.25/1.5，档位枚举 GKSettings.UI_SCALE_TIERS）；
#   - ui_scale 变更后调 GKServices.settings.apply_ui_scale(get_window()) 立即生效（无障碍档位）。
# 不含主题切换（归顶栏图标按钮 / 抽屉入口，见 main.gd）。
class_name GKSettingsPage
extends Control

var _decimals_spin: SpinBox
var _ui_scale_group: Array[Button] = []
var _scale_labels := {"0.80": "小（0.8×）", "1.00": "标准（1.0×）", "1.25": "大（1.25×）", "1.50": "特大（1.5×）"}

func _ready() -> void:
	var scroll := GKTouchScroll.attach(false)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)

	var title := Label.new()
	title.text = "设置"
	title.theme_type_variation = &"Header"
	v.add_child(title)

	# —— 结果小数位数（既有 decimals 契约：1–12，越界回退默认 4）——
	var dec_card := _make_card()
	v.add_child(dec_card)
	var dec_row := HBoxContainer.new()
	dec_card.add_child(dec_row)
	var dec_label := Label.new()
	dec_label.text = "计算结果小数位数"
	dec_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dec_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dec_row.add_child(dec_label)
	_decimals_spin = SpinBox.new()
	_decimals_spin.min_value = 1
	_decimals_spin.max_value = 12
	_decimals_spin.step = 1
	_decimals_spin.value = float(GKServices.settings.get_decimals())
	_decimals_spin.custom_minimum_size = Vector2(160, GKThemeConstants.TOUCH_TARGET)
	_decimals_spin.value_changed.connect(_on_decimals_changed)
	dec_row.add_child(_decimals_spin)
	var dec_cap := Label.new()
	dec_cap.text = "范围 1–12 位，修改后立即保存"
	dec_cap.theme_type_variation = &"Caption"
	dec_card.add_child(dec_cap)

	# —— 界面缩放（既有 ui_scale 四档契约：0.8/1.0/1.25/1.5）——
	var scale_card := _make_card()
	v.add_child(scale_card)
	var scale_title := Label.new()
	scale_title.text = "界面显示大小"
	scale_title.theme_type_variation = &"Header"
	scale_card.add_child(scale_title)
	var scale_row := HBoxContainer.new()
	scale_row.add_theme_constant_override("separation", GKThemeConstants.MIN_TOUCH_SPACING)
	scale_card.add_child(scale_row)
	var cur := float(GKServices.settings.get_value("ui_scale"))
	var found := false
	for tier: float in GKSettings.UI_SCALE_TIERS:
		var b := Button.new()
		b.toggle_mode = true
		b.text = String(_scale_labels.get(_fmt_tier(tier), _fmt_tier(tier)))
		b.custom_minimum_size = Vector2(0, GKThemeConstants.TOUCH_TARGET)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tier_val := tier
		b.pressed.connect(func() -> void: _on_ui_scale_pressed(tier_val, b))
		scale_row.add_child(b)
		_ui_scale_group.append(b)
		if is_equal_approx(tier, cur):
			b.button_pressed = true
			found = true
	if not found and not _ui_scale_group.is_empty():
		_ui_scale_group[1].button_pressed = true  # 非法档兜底回落标准档（与 settings 默认 1.0 对齐）
	var scale_cap := Label.new()
	scale_cap.text = "四档显示大小，立即生效并保存（兼作大字无障碍模式）"
	scale_cap.theme_type_variation = &"Caption"
	scale_card.add_child(scale_cap)

func _make_card() -> PanelContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = &"Card"
	var cv := VBoxContainer.new()
	card.add_child(cv)
	return card

func _fmt_tier(tier: float) -> String:
	return "%.2f" % tier

func _on_decimals_changed(val: float) -> void:
	if not GKServices.settings.set_value("decimals", int(val)):
		# 既有契约：越界 set_value 返回 false 不落地 → 回滚显示为当前持久值
		_decimals_spin.set_value_no_signal(float(GKServices.settings.get_decimals()))

func _on_ui_scale_pressed(tier: float, btn: Button) -> void:
	# toggle_mode 单选：清掉同组其他按钮的按下态，保证视觉单选
	for b in _ui_scale_group:
		if b != btn:
			b.button_pressed = false
	if not GKServices.settings.set_value("ui_scale", tier):
		btn.button_pressed = false
		return
	GKServices.settings.apply_ui_scale(get_window())
	# 点击已选中档位时 toggle_mode 会把自身弹起；值已生效则必须恢复按下态，
	# 否则四钮全弹起、无选中视觉而设置值仍是该档（状态与视觉失配）
	btn.button_pressed = true
