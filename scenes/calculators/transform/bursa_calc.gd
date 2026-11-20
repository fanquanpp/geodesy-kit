# scenes/calculators/transform/bursa_calc.gd —— A9 七参数布尔莎转换计算器
# 契约：继承 GKCalculatorBase，覆写 run()/get_inputs()/set_inputs()（scenes/widgets/calculator_base.gd）。
# 两种模式：正算（参数 → 坐标）/ 求参（公共点 → 参数，含残差表与 3σ 中文粗差提示）。
# 旋转约定 PV（EPSG:1033）/ CF（EPSG:1032）用 OptionButton 选择；触控行高 ≥96px 由主题与
# add_input_row/OptionButton custom_minimum_size 保证；输入校验失败给中文错误不崩溃。
extends "res://scenes/widgets/calculator_base.gd"

const B := preload("res://core/transform/bursa.gd")

var _opts: Dictionary = {}  # key -> OptionButton（选项不入 _fields，基类 reset 只清文本）
var _texts: Dictionary = {}  # key -> TextEdit（基类 register_field 仅收 LineEdit，多行文本框自管）
var _rows: Dictionary = {}  # key -> 输入行控件（模式显隐用）

func get_entry_id() -> String:
	return "a9_bursa"

func get_title() -> String:
	return "七参数布尔莎转换（A9）"

func get_description() -> String:
	return "空间直角坐标七参数（布尔莎）转换：PV 位置向量（EPSG:1033）与 CF 坐标框架（EPSG:1032）双约定互为反号；支持三参数（仅平移）；公共点最小二乘求参输出残差表与 3σ 粗差提示。"

func _ready() -> void:
	super._ready()
	_build_rows()
	set_inputs(_example_inputs)

func _build_rows() -> void:
	_add_option_row("模式", "mode", [
		["fwd", "正算（参数 → 坐标）"],
		["solve", "求参（公共点 → 参数）"],
	])
	_add_option_row("旋转约定", "convention", [
		["PV", "PV 位置向量（EPSG:1033）"],
		["CF", "CF 坐标框架（EPSG:1032）"],
	])
	for cfg: Array in [["tx_m", "平移 Tx (m)"], ["ty_m", "平移 Ty (m)"], ["tz_m", "平移 Tz (m)"],
			["rx_as", "旋转 Rx (″)"], ["ry_as", "旋转 Ry (″)"], ["rz_as", "旋转 Rz (″)"],
			["scale_ppm", "尺度 dS (ppm)"]]:
		var edit := add_input_row(cfg[1], cfg[0], "0")
		_rows[cfg[0]] = edit
	_add_option_row("求参模型", "three_param", [
		["0", "七参数（平移+旋转+尺度）"],
		["1", "三参数（仅平移）"],
	])
	_rows["src_xyz"] = _add_points_row("源坐标 X1（每行 x, y, z）", "src_xyz", "3657660.66, 255768.55, 5201382.11")
	_rows["dst_xyz"] = _add_points_row("目标系公共点（每行 x, y, z）", "dst_xyz", "")
	var mode_opt: OptionButton = _opts["mode"]
	mode_opt.item_selected.connect(func(_idx: int) -> void: _apply_mode_visibility())
	_apply_mode_visibility()

func _apply_mode_visibility() -> void:
	var mode := _opt_value("mode")
	var solve := mode == "solve"
	for key in ["rx_as", "ry_as", "rz_as", "scale_ppm", "dst_xyz"]:
		(_rows[key] as Control).get_parent().visible = solve
	# 正算模式平移是输入；求参模式平移是输出（求参行隐藏输入平移行）
	(_rows["tx_m"] as Control).get_parent().visible = not solve
	(_rows["ty_m"] as Control).get_parent().visible = not solve
	(_rows["tz_m"] as Control).get_parent().visible = not solve
	(_opts["three_param"] as Control).get_parent().visible = solve

func _opt_value(key: String) -> String:
	var ob: OptionButton = _opts[key]
	if ob.selected < 0:
		return String(ob.get_item_metadata(0))
	return String(ob.get_item_metadata(ob.selected))

func run() -> Dictionary:
	var inputs := get_inputs()
	var mode: String = inputs.get("mode", "fwd")
	var convention: String = inputs.get("convention", "PV")
	var src := _parse_points_text(String(inputs.get("src_xyz", "")), 3)
	if not src.ok:
		return _fail(src.error)
	if mode == "fwd":
		return B.transform({
			"src_xyz": src.rows,
			"tx_m": inputs.get("tx_m", "0"), "ty_m": inputs.get("ty_m", "0"), "tz_m": inputs.get("tz_m", "0"),
			"rx_as": inputs.get("rx_as", "0"), "ry_as": inputs.get("ry_as", "0"), "rz_as": inputs.get("rz_as", "0"),
			"scale_ppm": inputs.get("scale_ppm", "0"),
			"convention": convention,
		})
	if mode == "solve":
		var dst := _parse_points_text(String(inputs.get("dst_xyz", "")), 3)
		if not dst.ok:
			return _fail("目标系公共点解析失败：" + dst.error)
		return B.solve({
			"src_xyz": src.rows,
			"dst_xyz": dst.rows,
			"convention": convention,
			"three_param": inputs.get("three_param", "0") == "1",
		})
	return _fail("未知模式：%s" % mode)

func get_inputs() -> Dictionary:
	var out := super.get_inputs()
	for key: String in _opts:
		out[key] = _opt_value(key)
	for key: String in _texts:
		out[key] = String(_texts[key].text)
	return out

## reset 需同时清空多行文本框（基类只清 LineEdit 的 _fields）
func _on_reset() -> void:
	for key: String in _texts:
		_texts[key].text = ""
	super._on_reset()

func set_inputs(inputs: Dictionary) -> void:
	for key: String in inputs:
		var v: Variant = inputs[key]
		if _opts.has(key):
			var ob: OptionButton = _opts[key]
			var vs := String(v)
			for i in ob.item_count:
				if String(ob.get_item_metadata(i)) == vs:
					ob.select(i)
					break
		elif _fields.has(key):
			_fields[key].text = String(v)
		elif _texts.has(key):
			_texts[key].text = String(v)
	if _opts.has("mode"):
		_apply_mode_visibility()

# ---------- 输入行构造 ----------

func _add_option_row(label_text: String, key: String, items: Array) -> void:
	var row := HBoxContainer.new()
	var lab := Label.new()
	lab.text = label_text
	lab.custom_minimum_size = Vector2(180, 0)
	row.add_child(lab)
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(0, 96)
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in items.size():
		ob.add_item(String(items[i][1]))
		ob.set_item_metadata(i, String(items[i][0]))
	ob.select(0)
	row.add_child(ob)
	_inputs_root.add_child(row)
	_opts[key] = ob

func _add_points_row(label_text: String, key: String, placeholder: String) -> TextEdit:
	var row := HBoxContainer.new()
	var lab := Label.new()
	lab.text = label_text
	lab.custom_minimum_size = Vector2(180, 0)
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(lab)
	var te := TextEdit.new()
	te.placeholder_text = placeholder
	te.custom_minimum_size = Vector2(0, 132)
	te.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	te.scroll_fit_content_height = true
	row.add_child(te)
	_inputs_root.add_child(row)
	_texts[key] = te
	return te

# ---------- 文本解析 ----------

## 多行文本 → 点集。每行 2/3 个数字，分隔符支持中英文逗号/分号/空格/制表符。
## 非法输入返回 {ok:false, error:中文}，行号可读。
func _parse_points_text(text: String, ncols: int) -> Dictionary:
	var rows := []
	var lines := text.split("\n")
	for li in lines.size():
		var line := String(lines[li]).strip_edges()
		if line.is_empty():
			continue
		var cleaned := line.replace("，", " ").replace("；", " ").replace(",", " ").replace(";", " ").replace("\t", " ")
		while "  " in cleaned:
			cleaned = cleaned.replace("  ", " ")
		var parts := cleaned.strip_edges().split(" ", false)
		if parts.size() != ncols:
			return {"ok": false, "rows": [], "error": "第 %d 行应有 %d 个数字（逗号分隔），实际 %d 个：“%s”" % [li + 1, ncols, parts.size(), line]}
		var vals := []
		for p: String in parts:
			if not p.is_valid_float():
				return {"ok": false, "rows": [], "error": "第 %d 行含非数字内容：“%s”" % [li + 1, p]}
			vals.append(p.to_float())
		rows.append(vals)
	if rows.is_empty():
		return {"ok": false, "rows": [], "error": "请输入至少 1 行坐标（每行 %d 个数字）" % ncols}
	return {"ok": true, "rows": rows, "error": ""}

func _fail(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": msg}
