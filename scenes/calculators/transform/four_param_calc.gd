# scenes/calculators/transform/four_param_calc.gd —— A8 平面四参数转换计算器
# 模式：求参（公共点 → dx, dy, m, α）/ 正算（源 → 目标）/ 反算（目标 → 源）。
# 契约与输入校验口径同 bursa_calc.gd；计算走 core/transform/four_param.gd（GKFourParam）。
extends "res://scenes/widgets/calculator_base.gd"

const F := preload("res://core/transform/four_param.gd")

var _opts: Dictionary = {}
var _texts: Dictionary = {}  # key -> TextEdit（基类 register_field 仅收 LineEdit，多行文本框自管）

func get_entry_id() -> String:
	return "a8_four_param"

func get_title() -> String:
	return "平面四参数转换（A8）"

func get_description() -> String:
	return "平面四参数相似变换（平移 dx/dy + 尺度 m + 旋转 α）：公共点最小二乘求参输出残差表与 3σ 粗差提示；支持正算与反算。输入平面坐标每行 x, y。"

func _ready() -> void:
	super._ready()
	_build_rows()
	set_inputs(_example_inputs)

func _build_rows() -> void:
	_add_option_row("模式", "mode", [
		["solve", "求参（公共点 → 参数）"],
		["fwd", "正算（源 → 目标）"],
		["inv", "反算（目标 → 源）"],
	])
	for cfg: Array in [["dx_m", "平移 dx（m）"], ["dy_m", "平移 dy（m）"],
			["scale", "尺度 m"], ["alpha_deg", "旋转 α（°）"]]:
		var edit := add_input_row(cfg[1], cfg[0], "0")
		_row_cache[cfg[0]] = edit
	_add_points_row("源系平面坐标（每行 x, y）", "src_xy", "1000, 1000")
	_add_points_row("目标系平面坐标（每行 x, y）", "dst_xy", "1964.6842, 3034.4972")
	var mode_opt: OptionButton = _opts["mode"]
	mode_opt.item_selected.connect(func(_idx: int) -> void: _apply_mode_visibility())
	_apply_mode_visibility()

var _row_cache: Dictionary = {}

func _apply_mode_visibility() -> void:
	var mode := _opt_value("mode")
	var solve := mode == "solve"
	for key in ["dx_m", "dy_m", "scale", "alpha_deg"]:
		(_row_cache[key] as Control).get_parent().visible = not solve
	var src_row: Control = (_row_cache["src_xy"] as Control).get_parent()
	var dst_row: Control = (_row_cache["dst_xy"] as Control).get_parent()
	var src_lab := src_row.get_child(0) as Label
	var dst_lab := dst_row.get_child(0) as Label
	src_row.visible = true
	dst_row.visible = true
	if solve:
		src_lab.text = "源系公共点（每行 x, y）"
		dst_lab.text = "目标系公共点（每行 x, y）"
	elif mode == "fwd":
		src_lab.text = "源坐标（每行 x, y）"
		dst_row.visible = false
	else:
		src_row.visible = false
		dst_lab.text = "目标坐标（每行 x, y）"

func _opt_value(key: String) -> String:
	var ob: OptionButton = _opts[key]
	if ob.selected < 0:
		return String(ob.get_item_metadata(0))
	return String(ob.get_item_metadata(ob.selected))

func run() -> Dictionary:
	var inputs := get_inputs()
	var mode: String = inputs.get("mode", "solve")
	if mode == "solve":
		var src := _parse_points_text(String(inputs.get("src_xy", "")), 2, "源系公共点")
		if not src.ok:
			return _fail(src.error)
		var dst := _parse_points_text(String(inputs.get("dst_xy", "")), 2, "目标系公共点")
		if not dst.ok:
			return _fail(dst.error)
		return F.solve({"src_xy": src.rows, "dst_xy": dst.rows})
	if mode == "fwd" or mode == "inv":
		var key := "src_xy" if mode == "fwd" else "dst_xy"
		var what := "源坐标" if mode == "fwd" else "目标坐标"
		var pts := _parse_points_text(String(inputs.get(key, "")), 2, what)
		if not pts.ok:
			return _fail(pts.error)
		return F.apply({
			"mode": mode,
			"dx_m": inputs.get("dx_m", "0"), "dy_m": inputs.get("dy_m", "0"),
			"scale": inputs.get("scale", "1"), "alpha_deg": inputs.get("alpha_deg", "0"),
			"src_xy": pts.rows if mode == "fwd" else [],
			"dst_xy": pts.rows if mode == "inv" else [],
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
	super.set_inputs(inputs)
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

# ---------- 输入行构造与解析（与 bursa_calc.gd 同口径） ----------

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

func _add_points_row(label_text: String, key: String, placeholder: String) -> void:
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
	_row_cache[key] = te

func _parse_points_text(text: String, ncols: int, what: String) -> Dictionary:
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
			return {"ok": false, "rows": [], "error": "%s 第 %d 行应有 %d 个数字（逗号分隔），实际 %d 个：「%s」" % [what, li + 1, ncols, parts.size(), line]}
		var vals := []
		for p: String in parts:
			if not p.is_valid_float():
				return {"ok": false, "rows": [], "error": "%s 第 %d 行含非数字内容：「%s」" % [what, li + 1, p]}
			vals.append(p.to_float())
		rows.append(vals)
	if rows.is_empty():
		return {"ok": false, "rows": [], "error": "请输入至少 1 行%s坐标（每行 %d 个数字）" % [what, ncols]}
	return {"ok": true, "rows": rows, "error": ""}

func _fail(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": msg}
