# themes/build_theme.gd —— 主题生成器（一次性工具脚本，可重复运行再生成）
#
# 用法（须先 --import 让字体资源就位）：
#   godot --headless --path . --script res://themes/build_theme.gd
#
# 为什么用脚本生成而不用手写 .tres：type variations、StyleBoxFlat 子资源等序列化
# 细节由 ResourceSaver 保证正确；生成后本脚本会重新加载并断言关键项（自校验）。
#
# 调研口径（docs.godotengine.org gui_skinning/gui_using_fonts/multiple_resolutions）：
#   - 六类 theme item：Color/Constant/Font/Font Size/Icon/StyleBox；
#   - focus 样式框是覆盖绘制 → 用描边+不填充（draw_center=false）；
#   - type variations：同一控件多套预设（Header/Muted/Card/PrimaryButton）；
#   - 720×1280 设计基准：触控目标 ≥96px → 按钮/输入框内容边距 26px+行高≈42px ≥96px。
extends SceneTree

# 光亮主题（main.tres，项目默认）与深色主题（dark.tres，热切换用）
const LIGHT := {
	"bg": Color("#F2F4F8"), "surface": Color("#FFFFFF"),
	"surface_alt": Color("#E7EBF1"), "btn_hover": Color("#DEE5EE"), "btn_pressed": Color("#D2DBE6"),
	"border": Color("#D3DAE3"), "text": Color("#1A1D21"), "text_muted": Color("#5C6672"),
	"primary": Color("#1668A8"), "primary_text": Color("#FFFFFF"),
	"success": Color("#1E8E4E"), "warning": Color("#B26A00"), "error": Color("#C62828"),
}
const DARK := {
	"bg": Color("#14161A"), "surface": Color("#1E2126"),
	"surface_alt": Color("#262B33"), "btn_hover": Color("#2F3640"), "btn_pressed": Color("#38404C"),
	"border": Color("#363D47"), "text": Color("#E8EAED"), "text_muted": Color("#9AA3AF"),
	"primary": Color("#6FB1E8"), "primary_text": Color("#0B2233"),
	"success": Color("#58BE8A"), "warning": Color("#E0A458"), "error": Color("#E57268"),
}

const FONT_REG := "res://assets/fonts/NotoSansSC-Regular.otf"
const FONT_BOLD := "res://assets/fonts/NotoSansSC-Bold.otf"

# ---------- 布局常量（全应用唯一出处；运行时代码统一引用 themes/theme_constants.gd） ----------
# 触控目标：720×1280 设计基准下 ≥96 设计 px（Material 3 ≥48dp 口径在 2× 缩放下的等值）。
const TOUCH_TARGET := 96
# 触控控件最小间距：Material 3 相邻触控目标 ≥8dp，本应用取 16 设计 px 保证误触余量。
const MIN_TOUCH_SPACING := 16
# 结果值字号（≈48 设计 px，结果卡主值）与次级说明字号（≈22 设计 px，Caption）。
const FONT_RESULT := 48
const FONT_CAPTION := 22
# 多行中文说明行距（Label theme constant line_spacing，30px 字号下试定 4px）
const FONT_LABEL_SPACING := 4

func _initialize() -> void:
	var problems := PackedStringArray()
	if not _build("res://themes/main.tres", LIGHT, problems):
		printerr("main.tres 构建失败")
	if not _build("res://themes/dark.tres", DARK, problems):
		printerr("dark.tres 构建失败")
	for p in problems:
		printerr("[BUILD-WARN] " + p)
	if problems.is_empty():
		print("主题构建完成并自校验通过：res://themes/main.tres, res://themes/dark.tres")
		quit(0)
	else:
		quit(1)

func _build(save_path: String, pal: Dictionary, problems: PackedStringArray) -> bool:
	var font_reg := load(FONT_REG)
	var font_bold := load(FONT_BOLD)
	if font_reg == null or font_bold == null:
		problems.append("字体资源未就位（先跑 --import）：%s / %s" % [FONT_REG, FONT_BOLD])
		return false

	var th := Theme.new()
	th.default_font = font_reg
	th.default_font_size = 30
	th.set_meta("bg_color", pal.bg)
	th.set_meta("primary_color", pal.primary)

	# ---------- Label ----------
	th.set_color("font_color", "Label", pal.text)
	th.set_font("font", "Label", font_reg)
	th.set_font_size("font_size", "Label", 30)

	# type variation：Header（标题，粗体大字）/ Muted（弱化说明文字）
	th.set_type_variation("Header", "Label")
	th.set_font("font", "Header", font_bold)
	th.set_font_size("font_size", "Header", 40)
	th.set_color("font_color", "Header", pal.text)

	th.set_type_variation("Muted", "Label")
	th.set_font_size("font_size", "Muted", 26)
	th.set_color("font_color", "Muted", pal.text_muted)

	# type variation：Caption（次级信息/注记小字，≈22 设计 px）
	th.set_type_variation("Caption", "Label")
	th.set_font_size("font_size", "Caption", FONT_CAPTION)
	th.set_color("font_color", "Caption", pal.text_muted)

	# type variation：ResultValue（结果卡主值，≈48 设计 px）
	th.set_type_variation("ResultValue", "Label")
	th.set_font("font", "ResultValue", font_bold)
	th.set_font_size("font_size", "ResultValue", FONT_RESULT)
	th.set_color("font_color", "ResultValue", pal.text)

	# type variation：ResultAccent（结果/结论强调行：加粗 + 主题色，区别于 Header 区块标题）
	th.set_type_variation("ResultAccent", "Label")
	th.set_font("font", "ResultAccent", font_bold)
	th.set_font_size("font_size", "ResultAccent", 30)
	th.set_color("font_color", "ResultAccent", pal.primary)

	# 多行中文说明行距：Noto Sans SC 全角字形默认行距偏挤（多行公式/说明观感），
	# 试加 4px——30px 字号下 ≈13% 行高，中文阅读舒适区 1.4~1.6 倍的补差量。
	# 实测观感（720×1280 设计稿）：4px 时多行说明不再贴行、公式上下标可读；
	# 6px 过松（说明区与数值行疏密不齐），故取 4px。
	th.set_constant("line_spacing", "Label", FONT_LABEL_SPACING)

	# ---------- Button ----------
	th.set_color("font_color", "Button", pal.text)
	th.set_color("font_hover_color", "Button", pal.text)
	th.set_color("font_pressed_color", "Button", pal.text)
	th.set_color("font_focus_color", "Button", pal.text)
	th.set_color("font_disabled_color", "Button", pal.text_muted)
	th.set_stylebox("normal", "Button", _btn_box(pal.surface_alt, pal.border))
	th.set_stylebox("hover", "Button", _btn_box(pal.btn_hover, pal.border))
	th.set_stylebox("pressed", "Button", _btn_box(pal.btn_pressed, pal.primary))
	th.set_stylebox("disabled", "Button", _btn_box(pal.bg, pal.border))
	th.set_stylebox("focus", "Button", _focus_box(pal.primary))

	# type variation：PrimaryButton（主操作按钮）
	th.set_type_variation("PrimaryButton", "Button")
	th.set_color("font_color", "PrimaryButton", pal.primary_text)
	th.set_color("font_hover_color", "PrimaryButton", pal.primary_text)
	th.set_color("font_pressed_color", "PrimaryButton", pal.primary_text)
	th.set_color("font_focus_color", "PrimaryButton", pal.primary_text)
	th.set_stylebox("normal", "PrimaryButton", _btn_box(pal.primary, pal.primary))
	th.set_stylebox("hover", "PrimaryButton", _btn_box(pal.primary.lightened(0.12), pal.primary))
	th.set_stylebox("pressed", "PrimaryButton", _btn_box(pal.primary.darkened(0.12), pal.primary))
	th.set_stylebox("disabled", "PrimaryButton", _btn_box(pal.primary.darkened(0.6), pal.primary))

	# ---------- LineEdit ----------
	th.set_color("font_color", "LineEdit", pal.text)
	th.set_color("font_placeholder_color", "LineEdit", pal.text_muted)
	th.set_color("caret_color", "LineEdit", pal.primary)
	th.set_color("selection_color", "LineEdit", Color(pal.primary, 0.35))
	th.set_stylebox("normal", "LineEdit", _field_box(pal.surface, pal.border))
	th.set_stylebox("focus", "LineEdit", _field_box(pal.surface, pal.primary))
	th.set_stylebox("read_only", "LineEdit", _field_box(pal.bg, pal.border))

	# ---------- Panel / PanelContainer ----------
	# 基础 panel：透明承载（背景由窗口清屏色=bg 提供）
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(pal.surface, 0.0)
	th.set_stylebox("panel", "Panel", panel)
	th.set_stylebox("panel", "PanelContainer", panel)

	# type variation：Card（结果卡/步骤卡，实底+描边+内边距）
	th.set_type_variation("Card", "PanelContainer")
	var card := _panel_box(pal.surface, pal.border, 16, 24)
	th.set_stylebox("panel", "Card", card)

	# type variation：ErrorCard（失败态卡片：错误红描边语言，与 limits_panel 超限一致；
	# 供 calculator_base 失败分支按同名变体切换，变体缺失回退默认不报错）
	th.set_type_variation("ErrorCard", "PanelContainer")
	var err_card := _panel_box(pal.surface, pal.error, 16, 24)
	th.set_stylebox("panel", "ErrorCard", err_card)

	# type variation：DrawerPanel（抽屉/浮层，更强投影感的描边）
	th.set_type_variation("DrawerPanel", "PanelContainer")
	var drawer := _panel_box(pal.surface, pal.primary, 16, 20)
	th.set_stylebox("panel", "DrawerPanel", drawer)

	# ---------- TextEdit（多行输入，adj_panel/batch_convert 网形与点文件用）----------
	# TextEdit 的主题类型链不到 Button（Container→Control），须显式给样式才与 LineEdit 同观感。
	th.set_color("font_color", "TextEdit", pal.text)
	th.set_color("font_placeholder_color", "TextEdit", pal.text_muted)
	th.set_color("caret_color", "TextEdit", pal.primary)
	th.set_color("selection_color", "TextEdit", Color(pal.primary, 0.35))
	th.set_font_size("font_size", "TextEdit", 26)
	th.set_stylebox("normal", "TextEdit", _field_box(pal.surface, pal.border, 20, 14))
	th.set_stylebox("focus", "TextEdit", _field_box(pal.surface, pal.primary, 20, 14))
	th.set_stylebox("read_only", "TextEdit", _field_box(pal.bg, pal.border, 20, 14))

	# ---------- FoldableContainer（公式折叠卡；类型链 Container→Control 同样无 Button 样式）----------
	# item 名经 headless 探测 ThemeDB.get_default_theme() 实测（title_panel/panel/font 等）。
	th.set_font("font", "FoldableContainer", font_bold)
	th.set_font_size("font_size", "FoldableContainer", 28)
	th.set_color("font_color", "FoldableContainer", pal.text)
	th.set_color("hover_font_color", "FoldableContainer", pal.primary)
	th.set_color("collapsed_font_color", "FoldableContainer", pal.text_muted)
	# 折叠头：可点击目标，上下边距拉到接近 96px 触控口径
	var fc_title := _panel_box(pal.surface_alt, pal.border, 10, 16)
	fc_title.content_margin_top = 24
	fc_title.content_margin_bottom = 24
	th.set_stylebox("title_panel", "FoldableContainer", fc_title)
	th.set_stylebox("title_hover_panel", "FoldableContainer", _panel_box(pal.btn_hover, pal.border, 10, 16))
	th.set_stylebox("title_collapsed_panel", "FoldableContainer", fc_title)
	th.set_stylebox("title_collapsed_hover_panel", "FoldableContainer", _panel_box(pal.btn_hover, pal.border, 10, 16))
	th.set_stylebox("panel", "FoldableContainer", _panel_box(pal.surface, pal.border, 10, 20))

	# ---------- TabBar（窄屏底部导航；类型链到 Control，全部默认灰样）----------
	th.set_font_size("font_size", "TabBar", 26)
	th.set_color("font_selected_color", "TabBar", pal.primary)
	th.set_color("font_unselected_color", "TabBar", pal.text_muted)
	th.set_color("font_hovered_color", "TabBar", pal.text)
	th.set_constant("h_separation", "TabBar", MIN_TOUCH_SPACING)  # Material 3：触控目标间距 ≥16 设计 px
	th.set_stylebox("tab_selected", "TabBar", _tab_box(Color(pal.primary, 0.16)))
	th.set_stylebox("tab_hovered", "TabBar", _tab_box(pal.btn_hover))
	th.set_stylebox("tab_unselected", "TabBar", StyleBoxEmpty.new())
	th.set_stylebox("tab_disabled", "TabBar", StyleBoxEmpty.new())
	th.set_stylebox("tab_focus", "TabBar", _focus_box(pal.primary))

	# ---------- 容器间距常量（统一 12 的疏密节奏；面板内容密、卡片间 16 由布局自理）----------
	th.set_constant("separation", "VBoxContainer", 12)
	th.set_constant("separation", "HBoxContainer", 12)
	th.set_constant("h_separation", "GridContainer", 12)
	th.set_constant("v_separation", "GridContainer", 12)
	th.set_constant("separation", "MarginContainer", 0)

	# ---------- 限差检核语义色（供 UI 引用：ok 绿 / 超限红 / 注意黄）----------
	th.set_color("font_color", "OkLabel", pal.success)
	th.set_color("font_color", "WarnLabel", pal.warning)
	th.set_color("font_color", "ErrorLabel", pal.error)

	# ---------- 保存 ----------
	var err := ResourceSaver.save(th, save_path)
	if err != OK:
		problems.append("保存失败 %s：err=%d" % [save_path, err])
		return false

	# ---------- 自校验（重新加载）----------
	var back := load(save_path) as Theme
	if back == null:
		problems.append("重载失败：" + save_path)
		return false
	if back.default_font == null:
		problems.append(save_path + " default_font 丢失")
	if back.get_type_variation_base("Header") != &"Label":
		problems.append(save_path + " Header variation 基类错误")
	if back.get_type_variation_base("Card") != &"PanelContainer":
		problems.append(save_path + " Card variation 基类错误")
	if back.get_type_variation_base("PrimaryButton") != &"Button":
		problems.append(save_path + " PrimaryButton variation 基类错误")
	if back.get_type_variation_base("ResultValue") != &"Label":
		problems.append(save_path + " ResultValue variation 基类错误")
	if back.get_type_variation_base("ResultAccent") != &"Label":
		problems.append(save_path + " ResultAccent variation 基类错误")
	if back.get_type_variation_base("ErrorCard") != &"PanelContainer":
		problems.append(save_path + " ErrorCard variation 基类错误")
	if back.get_type_variation_base("Caption") != &"Label":
		problems.append(save_path + " Caption variation 基类错误")
	if back.get_font_size("font_size", "ResultValue") != FONT_RESULT:
		problems.append(save_path + " ResultValue 字号缺失/不符")
	if back.get_font_size("font_size", "Caption") != FONT_CAPTION:
		problems.append(save_path + " Caption 字号缺失/不符")
	if back.get_constant("line_spacing", "Label") != FONT_LABEL_SPACING:
		problems.append(save_path + " Label line_spacing 缺失/不符")
	if back.get_constant("h_separation", "TabBar") < MIN_TOUCH_SPACING:
		problems.append(save_path + " TabBar h_separation 低于触控间距下限")
	if not back.has_color("font_color", "ErrorLabel"):
		problems.append(save_path + " ErrorLabel 色缺失")
	if back.get_stylebox("title_panel", "FoldableContainer") == null:
		problems.append(save_path + " FoldableContainer title_panel 缺失")
	if back.get_stylebox("tab_selected", "TabBar") == null:
		problems.append(save_path + " TabBar tab_selected 缺失")
	if back.get_stylebox("normal", "TextEdit") == null:
		problems.append(save_path + " TextEdit normal 缺失")
	if back.get_meta("bg_color") == null:
		problems.append(save_path + " bg_color 元数据缺失")
	return problems.is_empty()

func _btn_box(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(2)
	sb.border_color = border
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 32
	sb.content_margin_right = 32
	sb.content_margin_top = 26
	sb.content_margin_bottom = 26
	return sb

func _field_box(bg: Color, border: Color, radius := 10, margin := 26) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(2)
	sb.border_color = border
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = margin
	sb.content_margin_bottom = margin
	return sb

## 底部导航 TabBar 的条目样式：圆角高亮块 + 96px 高（触控目标，Material 3 ≥48dp 口径）
func _tab_box(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 28
	sb.content_margin_bottom = 28
	return sb

func _focus_box(primary: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false  # focus 为覆盖绘制：只画描边，不填充（调研 gui_skinning 口径）
	sb.set_border_width_all(3)
	sb.border_color = Color(primary, 0.9)
	sb.set_corner_radius_all(12)
	return sb

func _panel_box(bg: Color, border: Color, radius: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(2)
	sb.border_color = border
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin
	sb.content_margin_bottom = margin
	return sb
