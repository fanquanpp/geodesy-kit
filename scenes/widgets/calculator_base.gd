# scenes/widgets/calculator_base.gd —— 计算器场景契约基类（M0 提供，P6 改造）
#
# 契约（ARCHITECTURE.md §3.3）：
#   - 每个计算器场景根脚本 extends "res://scenes/widgets/calculator_base.gd"；
#   - 覆写 run() -> Dictionary（调 core，遵守 §5 forward 协议）、
#           get_inputs()/set_inputs()（历史回放与示例填充）、
#           get_title()/get_description()、可选 get_entry_id()；
#   - 输入行用 register_field(key, line_edit) 登记 → get/set_inputs 自动生效；
#   - 输入区/结果卡/步骤列表/公式折叠/限差面板/复制导出收藏骨架由本类内置；
#   - §5 协议渲染：ok=true → 结果+步骤四行卡片（title/formula/substitution/result）
#     + 公式折叠 + 限差检核；ok=false → 清空 value、步骤卡与公式折叠、红字中文 error。
#
# P6 改造要点：
#   - 结果键名经 ui_labels.gd 映射为中文标签（未知键回退 + 告警）；
#   - 失败分支清理：步骤卡清空、公式折叠隐藏、限差面板隐藏；
#   - focus_field(key)：校验失败定位（grab_focus + 红描边，输入变化即清除）；
#   - register_field 串联回车流转：text_submitted → 下一字段聚焦，末字段触发计算；
#   - 数值行数字键盘（virtual_keyboard_type）；
#   - 版面次序：结果卡 → 限差面板（紧随结果卡）→ 步骤区 → 公式折叠 → 操作行。
class_name GKCalculatorBase
extends Control

signal favorite_changed(entry_id: String, fav: bool)

const _Report := preload("res://app/report.gd")  # G3 报告导出（app/report.gd，GKReport）
const _Labels := preload("res://scenes/widgets/ui_labels.gd")  # GKUiLabels：键名 → 中文标签
const _GKAngles := preload("res://core/math/angles.gd")  # 度分秒解析（输入解释卡预览）

var _entry_id := ""
var _example_inputs := {}
var _pending_inputs := {}  # 未入树时的 set_inputs 快照（字段未建，register_field 时回填）
var _fields: Dictionary = {}  # key -> LineEdit
var _angle_keys: Dictionary = {}  # key -> 中文标签（角度字段登记，输入解释卡 DMS 预览用）
var _field_order: Array = []  # key 顺序（回车流转用）
var _last_result_text := ""
var _last_result: Dictionary = {}  # 供报告导出（G3）与子类读取的最近一次 §5 结果
var _focused_field: LineEdit = null  # 校验失败定位中的输入框（红描边态）

var _title_label: Label
var _desc_label: Label
var _inputs_root: VBoxContainer
var _status_label: Label
var _result_card: PanelContainer
var _result_label: Label
# —— 组件化控件（scenes/widgets/ 独立场景实例）与兼容别名 ——
var _steps_widget: Control          # step_list.tscn（GKStepList）
var _steps_root: VBoxContainer      # 兼容别名 = _steps_widget（P6 起自身即卡根）
var _formula_widget: Control        # formula_card.tscn（GKFormulaCard）
var _formula_text: Label            # 兼容别名 = _formula_widget 的文本 Label
var _limits_widget: Control         # limits_panel.tscn（GKLimitsPanel）
var _limits_card: PanelContainer    # 兼容别名 = _limits_widget
var _limits_label: Label            # 兼容别名 = _limits_widget 的结论 Label
# —— 折叠契约（本施工项①）：结果/步骤/公式三区块各包 FoldableContainer，
#    共用 FoldableGroup（探针确认 4.7.2 存在该类与 allow_folding_all 属性）——
#    组内互斥（同一时刻至多展开一块），allow_folding_all=true 允许全折；
#    默认全折（结果卡有兜底高度 148，占位态不空白）；展开/收起动画自写 Tween
#    （4.7.2 FoldableContainer 无内建展开时长属性，折叠态切换经 folding_changed
#    信号接管 min 高度过渡，0.18s）。
var _fold_group: FoldableGroup      # 三折叠块共用组
var _result_fold: FoldableContainer # 「结果」折叠块（内装 result_card + 限差面板）
var _result_body: VBoxContainer     # 结果折叠块内容 VBox（FoldableContainer 多子重叠布局，见 _build_ui 注释）
var _steps_fold: FoldableContainer  # 「计算步骤」折叠块（内装 step_list）
var _steps_body: VBoxContainer      # 步骤折叠块内容 VBox（同上）
var _formula_fold: FoldableContainer  # 「公式与依据」折叠块（内装 formula_card）
var _result_fold_ever_expanded := false  # 结果块是否被自动展开过（成功一次即置真；用户收起后不再强翻）
var _scroll: ScrollContainer        # 左列滚动容器（输入区；结果定位/回车流转用）
var _result_scroll: ScrollContainer  # 右列滚动容器（结果区；宽视口左右布局）
var _body: HBoxContainer            # 主体分栏（断点切换时左右布局重排）
var _left_v: VBoxContainer          # 左列内容容器（重排时结果构件回挂目标）
var _right_v: VBoxContainer         # 右列内容容器（单列态整列并入左列滚动流）
var _fav_button: Button
var _run_btn: Button  # 「计算」主按钮引用（busy 态禁用/恢复直接持有，不走节点路径）
# 软键盘避让等待态（_on_field_focus_entered → _process 逐帧检查）
var _scroll_wait_row: Control = null  # 待定位的输入行（键盘 inset 生效后滚到可视区）
var _scroll_wait_frames := 0  # 兜底超时帧数（键盘不弹时也能完成定位）
var _scroll_wait_active := false
var _bp_handle: GKResponsive.WatchHandle  # 断点连接句柄（退出/PREDELETE 时 unwatch）

func _ready() -> void:
	_build_ui()
	_title_label.text = get_title()
	_desc_label.text = get_description()
	_desc_label.visible = get_description() != ""
	set_inputs(_example_inputs)
	# 收藏按钮初态与 favorites 表同步（进入已收藏条目时按钮应显示"已收藏"）
	var id := get_entry_id()
	if not id.is_empty() and GKServices.ready_state() and GKServices.favorites.is_favorite(id):
		_fav_button.text = "已收藏"
	# 断点钩：视口尺寸变化时左右布局重排（单列↔双列）；退出/PREDELETE 时 unwatch
	_bp_handle = GKResponsive.watch(self, _apply_result_layout)

# ---------- 供子类覆写的契约方法 ----------

## 核心计算入口：调 core 模块，返回 §5 协议结果
func run() -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "",
			"error": "本计算器尚未接入计算逻辑，请检查模块安装。"}

## 输入快照（历史回放用）
func get_inputs() -> Dictionary:
	var out := {}
	for key: String in _fields:
		out[key] = _fields[key].text
	return out

## 填充输入（示例/历史回放）。字段未建（未入树，或 _ready 前半段行还没建）时
## 快照进 _pending_inputs，register_field 逐键回填后清空；字段已就绪则直接丢弃
## 缓存（正常路径由子类覆写完成填充）。pending 已有内容时新快照不再覆盖——
## 首次显式 set_inputs 是用户意图，_ready 尾部对空 example 的注入须退让。
func set_inputs(_inputs: Dictionary) -> void:
	if _fields.is_empty():
		if _pending_inputs.is_empty():
			_pending_inputs = _inputs.duplicate(true)
	elif not _pending_inputs.is_empty():
		_pending_inputs.clear()

func get_title() -> String:
	return "未命名计算器"

func get_description() -> String:
	return ""

## manifest 的功能编号 id（收藏/历史/报告命名用）
func get_entry_id() -> String:
	return _entry_id

## 示例输入由 manifest 注入（catalog 加载时设置），子类也可覆写
func set_example(inputs: Dictionary) -> void:
	_example_inputs = inputs

## 标签域：非空时渲染经 GKUiLabels.label_for(k, domain) 优先命中该域子表
## （如 utm 域 n_m=「北坐标（m）」覆盖通用表 n_m=「卯酉圈曲率半径」）。
## 默认空串走通用表；子类按需覆写。
func get_label_domain() -> String:
	return ""

# ---------- 机器键与限差键契约（渲染/报告侧共用谓词） ----------

## §5 value 中的机器键（P3 meta 契约）：不进结果卡/报告结果表——rows 由 G2
## 面板专用表格渲染，n_ok/n_err/pipeline/label/in_cols/out_cols 走摘要或 CSV。
## P2 report.gd 复用本谓词跳过机器键，tests/tools/test_tools.gd 无需改动。
static func is_meta_key(k: String) -> bool:
	return k == "rows" or k == "n_ok" or k == "n_err" or k == "pipeline" \
			or k == "label" or k == "in_cols" or k == "out_cols"

## 限差键谓词（§5 规则③键集合的唯一收口）：ok_limit/basis 与 f_/limit_/rel_ 前缀。
## f_ballistic_m 是球气差改正量（观测量改正，非限差），显式排除——
## 原 calculator_base 两处与 app/report.gd 一处的字面实现统一收口到本谓词。
static func is_limit_key(k: String) -> bool:
	if k == "f_ballistic_m":
		return false
	return k == "ok_limit" or k == "basis" or k.begins_with("f_") \
			or k.begins_with("limit_") or k.begins_with("rel_")

## 示意图挂载钩子：子面板需要点线图（纵断面线/导线点位连线）时覆写，
## 用 add_child 建 GKSketchPanel（scenes/widgets/sketch_panel.tscn）并保存引用；
## 在 _render_result 里按最近结果调用其 set_points()。默认不建（多数计算器无图）。
func _build_sketch() -> void:
	pass

# ---------- 输入行注册与校验定位 ----------

## 输入行注册与校验定位：入树前收到的 set_inputs 快照（_pending_inputs）
## 在此逐键回填——字段是随 _build_ui 动态建的，未入树时 _fields 为空，
## 子类 set_inputs 的遍历循环会静默丢值（示例/历史回放契约要求不丢）。
func register_field(key: String, edit: LineEdit) -> void:
	_fields[key] = edit
	if not _field_order.has(key):
		_field_order.append(key)
	if _pending_inputs.has(key):
		edit.text = String(_pending_inputs[key])
		if _fields.size() == _pending_inputs.size():
			_pending_inputs.clear()  # 全部键已回填，缓存使命完成
	# 回车流转：当前字段回车 → 聚焦下一字段；末字段回车 → 触发计算
	var idx := _field_order.size() - 1
	edit.text_submitted.connect(_on_field_submitted.bind(idx))
	# 校验失败红描边：输入变化即清除（与 focus_field 注释承诺对齐；
	# 仅当当前正处于该字段的红描边态时清除，不干扰其他字段的定位态）
	edit.text_changed.connect(_on_field_text_changed.bind(edit))
	# 移动端虚拟键盘：焦点进入字段即滚动定位（键盘弹出遮住下半屏，
	# ensure_control_visible 把该字段带到可视区上半段）
	edit.focus_entered.connect(_on_field_focus_entered.bind(edit))

## 虚拟键盘弹出避让：滚动定位延迟到键盘高度 > 0 那帧——call_deferred 只晚一帧，
## Android 键盘弹出动画期间窗口尚未平移/resize，iOS 窗口根本不 resize，均会把
## 字段滚到仍被键盘遮住的位置。改用逐帧等待：_process 每帧查
## virtual_keyboard_get_height()，> 0（或超时兜底）才执行定位；高度恒 0 的
## 桌面/iOS 无效场景走超时路径，行为退化为稍晚的一次普通定位。
func _on_field_focus_entered(edit: LineEdit) -> void:
	if _scroll == null or not is_instance_valid(_scroll):
		return
	var row := edit.get_parent() as Control
	if row == null:
		return
	_scroll_wait_row = row
	_scroll_wait_frames = 30  # 兜底超时：键盘不弹（对已聚焦内容再点击）也能定位
	_scroll_wait_active = true

func _process(_delta: float) -> void:
	if not _scroll_wait_active:
		return
	var kb := DisplayServer.virtual_keyboard_get_height()
	if kb <= 0 and _scroll_wait_frames > 0:
		_scroll_wait_frames -= 1
		return
	_scroll_wait_active = false
	if _scroll != null and is_instance_valid(_scroll) \
			and _scroll_wait_row != null and is_instance_valid(_scroll_wait_row):
		_scroll.ensure_control_visible(_scroll_wait_row)
	_scroll_wait_row = null

func _on_field_text_changed(_new_text: String, edit: LineEdit) -> void:
	if _focused_field == edit:
		_clear_field_highlight()

## 校验失败定位：聚焦出错字段并加红描边；输入变化即清除（fail_input 携带 key 时由子类调用）
func focus_field(key: String) -> void:
	var edit: LineEdit = _fields.get(key, null)
	if edit == null:
		return
	_clear_field_highlight()
	_focused_field = edit
	edit.add_theme_stylebox_override("normal", _error_field_style())
	edit.grab_focus()

## 便捷建行：标签 + LineEdit（组装 input_row.tscn 独立控件；触控目标 96px 由控件保证）
## keyboard_type：虚拟键盘类型，默认带小数点数字键盘 KEYBOARD_TYPE_NUMBER_DECIMAL
## （数值行；旧默认 NUMBER 无「.」输不了小数）。多行/含分隔符的文本字段应显式传
## LineEdit.KEYBOARD_TYPE_DEFAULT（Android 数字键盘无「;」「,」与换行）。
## 角度/度分秒行（可输 30 30 00 空格分隔）同样须 DEFAULT——数字键盘无空格。
## 约定传法：keyboard_angle=true（角度档，一处兜住全部角度行，免逐行散写）。
## pm_button：负值字段 opt-in 的「±」快捷按钮（透传 input_row.setup）。
func add_input_row(label_text: String, key: String, placeholder := "",
		keyboard_type: int = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL,
		suffix := "", mode := "row", keyboard_angle := false, pm_button := false) -> LineEdit:
	if keyboard_angle:
		keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
		_angle_keys[key] = label_text  # 输入解释卡：角度字段登记（DMS→十进制预览）
	var row: HBoxContainer = preload("res://scenes/widgets/input_row.tscn").instantiate()
	_inputs_root.add_child(row)
	# setup 必须在入树后调用：input_row 的 label/edit 是 @onready 变量，
	# 入树前为 null，setup 返回的 edit 才是有效的 LineEdit（供 register_field 登记）
	var edit: LineEdit = row.call("setup", label_text, key, placeholder,
			keyboard_type, suffix, mode, pm_button)
	register_field(key, edit)
	return edit

## 坐标对双列行（P9.4 坐标输入形式）：一行内左右两个 stacked 字段
## （如 BLH 的 B|L、xy 的 x|y），形成"坐标对"视觉分组。
## label_l/label_r 为左右字段标签，suffix_l/r 为单位后缀（°/m 等）。
## 角度档约定：suffix 含 °/′/″ 的坐标行是经纬度（可输度分秒，含空格），
## 该字段键盘自动回落 DEFAULT，免逐文件散改。
func add_coord_pair_row(label_l: String, key_l: String, label_r: String, key_r: String,
		suffix_l := "", suffix_r := "") -> void:
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", GKThemeConstants.MIN_TOUCH_SPACING / 2)
	_inputs_root.add_child(pair)
	for spec: Array in [[label_l, key_l, suffix_l], [label_r, key_r, suffix_r]]:
		var sfx := String(spec[2])
		var kb := LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
		if sfx.contains("°") or sfx.contains("′") or sfx.contains("″"):
			kb = LineEdit.KEYBOARD_TYPE_DEFAULT
			_angle_keys[String(spec[1])] = String(spec[0])  # 输入解释卡：经纬度字段登记
		var row: HBoxContainer = preload("res://scenes/widgets/input_row.tscn").instantiate()
		pair.add_child(row)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.size_flags_stretch_ratio = 1.0
		var edit: LineEdit = row.call("setup", spec[0], spec[1], "",
			kb, sfx, "stacked")
		register_field(spec[1], edit)

func _on_field_submitted(_text: String, idx: int) -> void:
	# 回车流转：末字段提交触发计算，否则聚焦下一字段
	if idx >= _field_order.size() - 1:
		_on_run()
	else:
		var next: LineEdit = _fields.get(_field_order[idx + 1], null)
		if next != null:
			next.grab_focus()

func _error_field_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.92, 0.92, 1.0)
	sb.set_border_width_all(3)
	# 错误描边取主题 ErrorLabel 字色（main.tres / dark.tres 各自的语义红），
	# 不再硬编码浅色主题色值——深色主题下描边同步变亮红。
	sb.border_color = get_theme_color("font_color", "ErrorLabel")
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 26
	sb.content_margin_bottom = 26
	return sb

func _clear_field_highlight() -> void:
	if _focused_field != null and is_instance_valid(_focused_field):
		_focused_field.remove_theme_stylebox_override("normal")
	_focused_field = null

# ---------- UI 骨架 ----------

## 折叠块展开/收起动画时长（秒）——自写 Tween 的统一节奏
const _FOLD_TWEEN_S := 0.18

## 建一个折叠块（折叠契约①）：标题即区块标题，入指定 FoldableGroup（互斥、
## 允许全折），默认折叠（folded=true，展开由计算成功后的定位逻辑按需驱动）。
## 展开动画自写 Tween：4.7.2 FoldableContainer 折叠态切换是瞬时裁剪（无内建
## 时长属性），此处经 folding_changed 信号对内部内容做 min 高度 0→全高过渡，
## 视觉平滑且不干预容器自身的折叠布局（动画只动 custom_minimum_size，收起侧
## 同步回落，结束时 min 归 0 不留残高）。
func _make_fold(title_text: String, _tween_s: float) -> FoldableContainer:
	var fc := FoldableContainer.new()
	fc.title = title_text
	fc.folded = true  # 默认全折（折叠契约：互斥默认全折）
	fc.foldable_group = _fold_group
	fc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 展开动画：记录内容首行高度，折叠切换那帧起 0→目标高（收起反向）
	fc.folding_changed.connect(func(_is_folded: bool) -> void:
		_animate_fold(fc))
	return fc

## 折叠动画（自写 Tween）：对折叠块当前内容区做高度过渡。展开侧 0→内容自然高，
## 收起侧自然高→0；tween 结束把 min 高度归 0（容器高度交还内容自适应）。
## 内容自然高在动画起点采样一次（布局稳定后的即时值，多行卡片足够准确）。
func _animate_fold(fc: FoldableContainer) -> void:
	if fc == null or not is_instance_valid(fc):
		return
	var target := 0.0
	for c: Control in fc.get_children():
		if c.visible:
			target = maxf(target, c.get_combined_minimum_size().y)
	if fc.folded:
		target = 0.0  # 收起：内容区高度归 0
	var tw := create_tween()
	if target > 0.0:
		fc.custom_minimum_size.y = 0.0  # 从 0 展开
	else:
		fc.custom_minimum_size.y = maxf(fc.custom_minimum_size.y, 0.0)
	tw.tween_property(fc, "custom_minimum_size:y", target, _FOLD_TWEEN_S) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		fc.custom_minimum_size.y = 0.0)  # 结束归 0：高度交还内容自适应

func _build_ui() -> void:
	# P9.2 左右布局（用户要求「采取左右布局」）：
	#   竖屏窄视口（<700 设计 px）维持单列纵排；宽视口/横屏左右两列——
	#   左列 = 输入区（可滚动），右列 = 结果区（结果/限差/步骤/公式，可滚动）。
	#   操作栏（计算/重置/示例/复制/收藏/导出）固定底部不随滚动（M3 表单惯例：
	#   主操作常驻可达，不再沉底需要滚到底才能按）。
	# 页面根 = VBox{ 主体(Expand 分栏) + 操作栏固定底 }；主体各列独立滚动。
	# P9.3 外层 MarginContainer：四边 12px 呼吸边距（内容不再贴屏幕边）。
	var page_margin := MarginContainer.new()
	page_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page_margin.add_theme_constant_override("margin_left", 12)
	page_margin.add_theme_constant_override("margin_right", 12)
	page_margin.add_theme_constant_override("margin_top", 8)
	page_margin.add_theme_constant_override("margin_bottom", 8)
	add_child(page_margin)
	var page_v := VBoxContainer.new()
	page_margin.add_child(page_v)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", GKThemeConstants.MIN_TOUCH_SPACING)
	page_v.add_child(body)
	_body = body  # 断点切换重排左右布局（_apply_result_layout）

	# —— 左列：标题/描述/状态/输入区（整列滚动，吃满左份额）——
	_scroll = GKTouchScroll.attach(false)
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_stretch_ratio = 0.42
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(v)
	_left_v = v  # 单列态：结果构件并入本列滚动流尾部

	_title_label = Label.new()
	_title_label.theme_type_variation = &"Header"
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_title_label)

	_desc_label = Label.new()
	_desc_label.theme_type_variation = &"Muted"
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_desc_label)

	_status_label = Label.new()
	_status_label.theme_type_variation = &"ErrorLabel"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.visible = false
	v.add_child(_status_label)

	_inputs_root = VBoxContainer.new()
	v.add_child(_inputs_root)
	var inputs_head := Label.new()
	inputs_head.text = "输入"
	inputs_head.theme_type_variation = &"Header"
	_inputs_root.add_child(inputs_head)

	# —— 右列：结果区（结果卡/限差/步骤/公式/示意图，整列独立滚动）——
	_result_scroll = GKTouchScroll.attach(false)
	_result_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result_scroll.size_flags_stretch_ratio = 0.58
	_result_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# 窄竖屏（<WIDE 900）收起右列：单列纵排时结果区并入左列滚动流（走 _apply_result_layout）
	body.add_child(_result_scroll)
	var rv := VBoxContainer.new()
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_result_scroll.add_child(rv)
	_right_v = rv  # 双列态：结果构件所在列（重排可整列搬回左列）
	# 右列标题与左列「输入」对位（宽屏左右布局下两列语义一目了然）
	var result_head := Label.new()
	result_head.name = "ResultHead"
	result_head.text = "结果"
	result_head.theme_type_variation = &"Header"
	rv.add_child(result_head)

	# —— 折叠契约：三区块各包 FoldableContainer（折叠头即区块标题，右列「结果」
	#    Header 撤销职责并入折叠头）——共用 FoldableGroup 互斥、允许全折、默认全折
	_fold_group = FoldableGroup.new()
	_fold_group.allow_folding_all = true
	_result_fold = _make_fold("结果", _FOLD_TWEEN_S)
	rv.add_child(_result_fold)
	_steps_fold = _make_fold("计算步骤", _FOLD_TWEEN_S)
	_steps_fold.visible = false  # 无步骤时整块隐藏（P6：自适应高度，不占空卡位）
	rv.add_child(_steps_fold)
	_formula_fold = _make_fold("公式与依据", _FOLD_TWEEN_S)
	_formula_fold.visible = false
	rv.add_child(_formula_fold)

	_result_card = preload("res://scenes/widgets/result_card.tscn").instantiate()
	_result_card.custom_minimum_size = Vector2(0, 148)  # 结果卡兜底高度：占位时视觉重心与输入区平衡
	_result_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# P11 布局根修：FoldableContainer 对多个子节点是重叠布局（探针实测两 Panel
	# 同 rect 叠放，非 VBox 语义）——每个折叠块内包一层 VBox 承载内容。
	_result_body = VBoxContainer.new()
	_result_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result_fold.add_child(_result_body)
	_result_body.add_child(_result_card)
	_result_label = _result_card.get("value_label")  # 兼容别名（tests/app/test_shell.gd 断言文本）
	var result_widget := _result_card as GKResultCard
	result_widget.copy_confirmed.connect(_on_line_copied)

	# 限差面板紧随结果卡（P6：结论一目了然，明细在步骤区之前）——同属结果折叠块
	_limits_widget = preload("res://scenes/widgets/limits_panel.tscn").instantiate()
	_limits_widget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result_body.add_child(_limits_widget)
	_limits_card = _limits_widget  # 兼容别名（tests/app/test_shell.gd 断言 visible）

	_steps_widget = preload("res://scenes/widgets/step_list.tscn").instantiate()
	_steps_widget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_steps_body = VBoxContainer.new()
	_steps_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_steps_fold.add_child(_steps_body)
	_steps_body.add_child(_steps_widget)
	_steps_root = _steps_widget  # 兼容别名：P6 起步骤卡直接挂在控件自身，get_child_count() 语义不变

	_formula_widget = preload("res://scenes/widgets/formula_card.tscn").instantiate()
	_formula_widget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_formula_fold.add_child(_formula_widget)
	_formula_text = _formula_widget.get("formula_label")  # 兼容别名
	_build_sketch()

	# —— 操作栏：固定底部（不随滚动），主操作常驻可达 ——
	# 本轮回滚 P9.3 压缩：6 按钮 72→96（GKThemeConstants.TOUCH_TARGET，触屏误触
	# 率优先）；指针设备（宽屏键鼠，DisplayServer 无触屏）降档 TOUCH_TARGET_POINTER
	# 56，与 main.gd 顶栏同口径——按设备能力而非断点。
	var action_h := GKThemeConstants.TOUCH_TARGET \
			if DisplayServer.is_touchscreen_available() \
			else GKThemeConstants.TOUCH_TARGET_POINTER
	var actions := HBoxContainer.new()
	actions.name = "ActionBar"
	actions.custom_minimum_size = Vector2(0, action_h)
	actions.add_theme_constant_override("separation", GKThemeConstants.MIN_TOUCH_SPACING / 2)
	page_v.add_child(actions)
	var run_btn := Button.new()
	_run_btn = run_btn
	run_btn.text = "计算"
	run_btn.theme_type_variation = &"PrimaryButton"
	run_btn.custom_minimum_size = Vector2(0, action_h)
	run_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	run_btn.size_flags_stretch_ratio = 3.0
	run_btn.pressed.connect(_on_run)
	actions.add_child(run_btn)
	var reset_btn := Button.new()
	reset_btn.text = "重置"
	reset_btn.custom_minimum_size = Vector2(0, action_h)
	reset_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_btn.pressed.connect(_on_reset)
	actions.add_child(reset_btn)
	var example_btn := Button.new()
	example_btn.text = "示例"
	example_btn.custom_minimum_size = Vector2(0, action_h)
	example_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	example_btn.pressed.connect(_on_example)
	actions.add_child(example_btn)
	var copy_btn := Button.new()
	copy_btn.text = "复制"
	copy_btn.custom_minimum_size = Vector2(0, action_h)
	copy_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy_btn.pressed.connect(_on_copy)
	actions.add_child(copy_btn)
	_fav_button = Button.new()
	_fav_button.text = "收藏"
	_fav_button.custom_minimum_size = Vector2(0, action_h)
	_fav_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fav_button.pressed.connect(_on_favorite)
	actions.add_child(_fav_button)
	var export_btn := Button.new()
	export_btn.text = "报告"
	export_btn.custom_minimum_size = Vector2(0, action_h)
	export_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	export_btn.pressed.connect(_on_export_report)
	actions.add_child(export_btn)

	# 竖屏窄视口（<WIDE 900）：右列并入左列（单列纵排），左右布局只在宽视口/横屏生效。
	# 行为后果明示：设计基准宽 720 原走 <700 单列，收口到 GKResponsive.WIDE=900 后
	# 手机竖屏（720）塌回单列、桌面 ≥900 才出右列——产品形态变更（720 宽下顶栏
	# 约 800px 需求溢出、双列拥挤）；中档预案为 MEDIUM 单列但结果卡置顶（未实施）。
	_apply_result_layout(GKResponsive.is_wide_now(self))

## 断点重排：wide=true 左右两列（结果区回右列），false 单列纵排（右列隐藏、
## 结果构件整列并入左列滚动流尾部）。构件在同一树内移动不重建，结果状态保持。
func _apply_result_layout(is_wide: bool) -> void:
	if _body == null or _right_v == null or _left_v == null:
		return  # _build_ui 未完成（watch 回调早于构建）不排
	var wide := is_wide or GKResponsive.is_wide_now(self)
	_result_scroll.visible = wide
	if wide:
		# 结果构件回挂右列（按右列语义次序重插；已在右列时跳过）
		if _result_card.get_parent() != _right_v:
			for c: Control in _left_v.get_children():
				if c != _title_label and c != _desc_label and c != _status_label \
						and c != _inputs_root:
					_left_v.remove_child(c)
					_right_v.add_child(c)
	else:
		# 结果构件整列并入左列滚动流尾部（输入之后）；_result_scroll 隐藏省空间
		if _result_card.get_parent() != _left_v:
			for c: Control in _right_v.get_children():
				_right_v.remove_child(c)
				_left_v.add_child(c)

# ---------- 按钮行为 ----------

## busy 态（观感缓解，非消除冻结）：run() 是同步的（如 c5_network.gd 的 NW.adjust
## 直接占用主线程），大网解算期间整帧仍会卡——这里只是把「计算中…」状态与按钮
## 禁用在让渡的一帧里画出来，用户立刻知道点了有效；真异步需 core 侧改造，不在本轮。
func _on_run() -> void:
	if _run_btn != null and is_instance_valid(_run_btn):
		_run_btn.disabled = true
	_status_label.theme_type_variation = &"Muted"
	_status_label.text = "计算中…"
	_status_label.visible = true
	await get_tree().process_frame  # 让渡一帧：busy 文案与禁用态先渲染
	var res := run()
	_last_result = res
	_render_result(res)
	if res.get("ok", false) and GKServices.ready_state():
		GKServices.history.add(get_entry_id(), get_title(), get_inputs(), res)
	if _run_btn != null and is_instance_valid(_run_btn):
		_run_btn.disabled = false

## G3 报告导出（app/report.gd）：把最近一次计算的 §5 协议（含输入回显、
## 步骤四列表、限差检核）渲染为 Markdown 报告写入用户文档目录。
## 未计算过时给中文提示；失败的计算同样可导出（含错误原因，可追溯）。
func _on_export_report() -> void:
	_status_label.theme_type_variation = &"Muted"
	if _last_result.is_empty():
		_status_label.text = "请先点击「计算」，再导出报告。"
		_status_label.visible = true
		return
	var res := _Report.save(get_title(), get_entry_id(), get_inputs(), _last_result)
	if bool(res.get("ok", false)):
		# toast 回显报告绝对路径（report.gd save 返回的 path 已 globalize）；
		# 路径超长截断显示（状态行换行会挤压版面），完整路径同时复制到剪贴板可取。
		var path := String(res.get("path", ""))
		var shown := path if path.length() <= 64 else "…" + path.substr(path.length() - 63)
		if GKClipboard.copy_text(path):
			_status_label.text = "报告已保存：%s（完整路径已复制到剪贴板）" % shown
		else:
			_status_label.text = "报告已保存到：%s" % shown
	else:
		_status_label.theme_type_variation = &"ErrorLabel"
		_status_label.text = String(res.get("error", "报告导出失败"))
	_status_label.visible = true

func _on_reset() -> void:
	for key: String in _fields:
		_fields[key].text = ""
	_last_result = {}
	_render_result({})

## 输入解释卡（WolframAlpha「输入解释」模式的教学落地）：角度字段写了度分秒
## 形式（含 °′″、'、": 或空格分隔）时，在状态行下方显示规范化预览
## 「纬度 B：53°48′33.82″ 已解析为 53.809394°」，防止十进制度/度分秒混淆。
## 纯十进制或空/非法文本不显示；标签用建行时登记的中文标签。
var _interp_label: Label = null  # 解释行（懒建；无角度字段解析时隐藏）

func _render_input_interpretation() -> void:
	var lines := PackedStringArray()
	for key: String in _angle_keys:
		var edit: LineEdit = _fields.get(key, null)
		if edit == null:
			continue
		var raw := edit.text.strip_edges()
		if raw.is_empty() or raw.is_valid_float():
			continue  # 空/纯十进制：无解释必要
		var deg := _GKAngles.parse_dms(raw)
		if is_nan(deg):
			continue  # 非法文本：错误路径另有提示，这里不打扰
		lines.append("%s：%s 已解析为 %.6f°" % [String(_angle_keys[key]), raw, deg])
	if lines.is_empty():
		if _interp_label != null and is_instance_valid(_interp_label):
			_interp_label.visible = false
		return
	if _interp_label == null or not is_instance_valid(_interp_label):
		_interp_label = Label.new()
		_interp_label.theme_type_variation = &"Muted"
		_interp_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_interp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_status_label.get_parent().add_child.call_deferred(_interp_label)
	_interp_label.text = "、".join(lines)
	_interp_label.visible = true

func _on_example() -> void:
	set_inputs(_example_inputs)
	# P6：填充后给状态行反馈（避免用户不知道是否生效）
	_clear_field_highlight()
	_status_label.theme_type_variation = &"Muted"
	_status_label.text = "已填入示例数据"
	_status_label.visible = true

func _on_copy() -> void:
	if _last_result_text.is_empty():
		# 无结果可复制：给中文提示而非静默（此前直接 return，按钮像坏了）
		_status_label.theme_type_variation = &"WarnLabel"
		_status_label.text = "还没有可复制的结果，请先点击「计算」。"
		_status_label.visible = true
		return
	if GKClipboard.copy_text(_last_result_text):
		_status_label.theme_type_variation = &"Muted"
		_status_label.text = "结果已复制到剪贴板"
		_status_label.visible = true

func _on_line_copied(line_digest: String) -> void:
	_status_label.theme_type_variation = &"Muted"
	# 反馈带行摘要（result_card 传前 24 字），多行卡里确认复制的是哪一行
	if line_digest.is_empty():
		_status_label.text = "该行已复制到剪贴板"
	else:
		_status_label.text = "已复制：%s" % line_digest
	_status_label.visible = true

func _on_favorite() -> void:
	if not GKServices.ready_state():
		return
	var id := get_entry_id()
	if id.is_empty():
		return
	var fav := GKServices.favorites.toggle(id)
	_fav_button.text = "已收藏" if fav else "收藏"
	favorite_changed.emit(id, fav)

# ---------- §5 协议渲染 ----------

func _render_result(res: Dictionary) -> void:
	_last_result_text = ""
	_clear_field_highlight()

	if res.is_empty():
		_steps_widget.call("clear")
		_steps_fold.visible = false  # 折叠契约：区块显隐上移到折叠块
		_steps_widget.visible = false  # 子控件标志同步（既有契约：tests/cogo/test_cogo_ui.gd 断言 widget.visible）
		_result_card.call("set_result", PackedStringArray())
		_result_card.set("theme_type_variation", &"Card")  # 重置态回落 Card 变体
		_result_label.visible = true  # 占位专用：重置态重新显示
		_result_label.text = "（尚未计算）"
		_formula_text.text = ""
		_formula_widget.call("set_visible_by_formula", false)
		_formula_fold.visible = false
		_limits_card.visible = false
		_status_label.visible = false
		return

	if not bool(res.get("ok", false)):
		# 失败：value 必空、error 必中文可读（§5 规则①）；步骤卡清空、公式折叠隐藏（P6）
		_result_card.call("set_result", PackedStringArray())
		(_result_card as GKResultCard).set_failed()  # ErrorCard 变体 + 红色状态条
		_result_label.visible = true  # 失败态经占位 label 提示（行区为空）
		_result_label.text = "计算未完成"
		_steps_widget.call("clear")
		_steps_fold.visible = false
		_steps_widget.visible = false  # 子控件标志同步（既有契约：tests/cogo/test_cogo_ui.gd 断言 widget.visible）
		_formula_text.text = ""
		_formula_widget.call("set_visible_by_formula", false)
		_formula_fold.visible = false
		_limits_card.visible = false
		_status_label.theme_type_variation = &"ErrorLabel"
		_status_label.text = String(res.get("error", "未知错误"))
		_status_label.visible = true
		return

	_status_label.visible = false
	var value: Dictionary = res.get("value", {})
	var decimals := 4
	if GKServices.ready_state():
		decimals = GKServices.settings.get_decimals()
	var domain := get_label_domain()
	var lines := PackedStringArray()
	for k: String in value.keys():
		# 限差键归限差面板、机器键由专用构件渲染，均不进结果卡（§5 规则③/meta 契约）
		if value.has("ok_limit") and is_limit_key(k):
			continue
		if is_meta_key(k):
			continue
		# 键名经 GKUiLabels 映射为中文标签（域子表优先，动态键如 x_P1_m /
		# ell_P1_A_mm 走前缀模板；未收录键回退原文 + push_warning 一次，
		# tests/cogo/test_cogo_ui.gd 断言全量 value 键无「未收录」回退）。
		# 键名原文保留在报告导出（app/report.gd）。
		lines.append("%s = %s" % [_Labels.label_for(k, domain), _format_num(value[k], _key_decimals(k, decimals))])
	_result_card.call("set_result", lines)
	(_result_card as GKResultCard).set_succeeded()  # Card 变体 + 绿色状态条

	# 步骤四行卡片：空字段跳过（§5 规则②）——经 step_list 组件渲染（内含同步清空）。
	# 折叠契约：步骤/公式区块显隐由折叠块承担；步骤块展开就近读结果（折叠组互斥
	# 自动收起结果块，长步骤不再把结果卡顶出可视区）
	var steps: Array = res.get("steps", [])
	_steps_widget.call("set_steps", steps)
	_steps_fold.visible = not steps.is_empty()
	_steps_widget.visible = not steps.is_empty()  # 子控件标志同步（既有契约：tests/cogo/test_cogo_ui.gd 断言 widget.visible）

	_formula_text.text = String(res.get("formula", ""))
	_formula_widget.call("set_visible_by_formula", _formula_text.text != "")
	_formula_fold.visible = _formula_text.text != ""

	# 输入解释卡（P11 调研②落地，对标 WolframAlpha「输入解释」）：角度字段
	# 显示 DMS→十进制度规范化预览——「65°30′15″ 已解析为 65.504167°」。
	# 消灭最高频学生错误（度分秒 vs 十进制度混输）；仅当解析值与原文不同
	# （即用户确实写了度分秒形式）才显示，纯十进制输入不重复。
	_render_input_interpretation()

	# 成功即展开结果折叠块（折叠默认全折；此前从未展开过才驱动一次，
	# 用户手动收起后不再被强行翻开——尊重交互意图）
	if _result_fold.folded and not _result_fold_ever_expanded:
		_result_fold.folded = false
	_result_fold_ever_expanded = not _result_fold.folded

	# 限差检核：ok_limit 键存在即渲染（§5 规则③）——经 limits_panel 组件渲染
	if value.has("ok_limit"):
		var ok := bool(value["ok_limit"])
		var detail := PackedStringArray()
		detail.append("检核结论：" + ("通过" if ok else "超限"))
		for k: String in value.keys():
			# ok_limit 已单独作结论行，明细只收 f_/limit_/rel_/basis（与原字面行为一致）
			if is_limit_key(k) and k != "ok_limit":
				detail.append("%s = %s" % [_Labels.label_for(k, domain), _format_num(value[k], _key_decimals(k, decimals))])
		_limits_widget.call("set_limits", ok, detail)
		# 兼容别名指向结论 Label（Verdict）：P6 起结论唯一归属 Verdict，
		# Detail 只放明细——旧消费方读 _limits_label.text 取「通过/超限」结论
		_limits_label = _limits_widget.get("verdict_label")
		if _limits_label == null:
			_limits_label = _limits_widget.get("limits_label")
	else:
		_limits_card.visible = false

	# 成功后滚动定位到结果卡（P6：用户点「计算」即见结果，不必手动翻找）。
	# 宽视口左右布局时结果卡在右列，_result_scroll 也定位；窄竖屏右列已隐藏
	# （结果构件并入左列滚动流），单滚 _scroll 即覆盖。
	if _scroll != null and is_instance_valid(_scroll):
		_scroll.call_deferred("ensure_control_visible", _result_card)
	if _result_scroll != null and is_instance_valid(_result_scroll) and _result_scroll.visible:
		_result_scroll.call_deferred("ensure_control_visible", _result_card)

	_last_result_text = _result_card.call("get_text")

## 数值 → 定点小数；容器（数组/矩阵）→ 摘要展示：逐元素逗号分隔，超过 4 个元素
## 截断加省略号（完整值在步骤区/导出报告，避免结果卡被 GDScript 原生表示撑爆）；
## 嵌套容器（矩阵行/残差表行）递归摘要；其余类型回退 str()。
## 格式化走 printf 定点（"%.*f"）而非 String.num：后者截尾零（String.num(1.5,4)="1.5"），
## 同卡小数位参差、违反测量成果固定位惯例；负零清洗 + 极小值科学计数回退
## （定点全零但 |f|>0 时，String.num_scientific 防止 1.2e-8 m 被误读为真零）。
func _format_num(v: Variant, decimals: int) -> String:
	if v is float or v is int:
		var f := float(v)
		if is_finite(f):
			if is_zero_approx(f):
				f = 0.0  # 清洗 "-0"（godot#86421）：闭合差恰为零时显示 -0.0000 困惑
			var s := "%.*f" % [decimals, f]
			if f != 0.0 and absf(f) < 5.0 * pow(10.0, -decimals - 1):
				s = String.num_scientific(f)  # 定点全零回退科学计数
			return s
		return "—"
	if v is PackedFloat64Array or v is PackedInt32Array or v is PackedInt64Array or v is Array:
		return _format_seq(v, decimals)
	if v is PackedStringArray or v is Array[String] or v is Dictionary:
		return _format_seq(v, decimals)
	if v is bool:
		return "是" if v else "否"
	return str(v)

const _SEQ_PREVIEW := 4  # 容器摘要：最多展示 4 个元素，其余以省略号代替

## 键名 → 精度分档后缀（测量学取位惯例，优先级从上到下首个命中生效）：
##   角度秒/度分秒键 → 1 位（0.1″，GB 50026 口径）；十进制度 → 4 位；
##   距离/坐标/高程/面积/体积（m/m2/m3）→ 3 位（mm 级）；
##   限差/中误差（mm）→ 1 位（0.1 mm，与闭合差检核同档）。
## 未命中回退 settings.decimals（用户全局档，默认 4）。
const _KEY_DECIMALS_TIERS := [
	["_s", 1],          # 角度秒（如 f_beta_s）
	["_dms", 1],        # 度分秒文本的秒位
	["_deg", 4],        # 十进制度
	["_gon", 4],        # 百分度
	["_mm", 1],         # 中误差/限差（0.1 mm）
	["_m2", 3],         # 面积
	["_m3", 3],         # 体积
	["_m", 3],          # 距离/坐标/高程（放 _mm/_m2 之后：避免 _m 前缀误吞）
	["_km", 3],
]

## 结果卡/限差明细的单键精度：键名分档优先，settings 全局档兜底。
## 角度键（_deg 后缀）不自动转 DMS——core 已有独立 _dms 键时结果卡会双列显示，
## 这里只管小数位，不做格式转换（保持 §5 协议「core 定格式、UI 只渲染」分工）。
func _key_decimals(k: String, fallback: int) -> int:
	for tier: Array in _KEY_DECIMALS_TIERS:
		if k.ends_with(String(tier[0])):
			return int(tier[1])
	return fallback

func _format_seq(v: Variant, decimals: int) -> String:
	var items: Array = []
	if v is PackedFloat64Array or v is PackedInt32Array or v is PackedInt64Array or v is PackedStringArray:
		items = Array(v)
	elif v is Array:
		items = v
	elif v is Dictionary:
		for k: Variant in v.keys():
			items.append("%s=%s" % [str(k), _format_num(v[k], decimals)])
	var parts := PackedStringArray()
	var truncated := false
	for i in mini(items.size(), _SEQ_PREVIEW):
		parts.append(_format_num(items[i], decimals))
	if items.size() > _SEQ_PREVIEW:
		truncated = true
	if parts.is_empty():
		return "（空）"
	return "，".join(parts) + ("，…（共 %d 项，完整值见导出报告）" % items.size() if truncated else "")

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# 断点句柄解绑（防视口销毁后 size_changed 悬挂连接）
		if _bp_handle != null:
			_bp_handle.unwatch()
			_bp_handle = null
