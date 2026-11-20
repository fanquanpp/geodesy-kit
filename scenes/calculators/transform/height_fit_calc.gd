# scenes/calculators/transform/height_fit_calc.gd —— A10 GNSS 高程拟合计算器
# 模式：拟合（公共点 → 拟合参数与残差表）/ 预测（用最近一次拟合模型算待定点高程）。
# 模型：平面（3 参数）/ 曲面（6 参数）/ 带状分段（沿 x 或 y 轴等宽分段）。
# 计算走 core/transform/height_fit.gd（GKHeightFit）；拟合结果模型字典仅存本页内存。
extends "res://scenes/widgets/calculator_base.gd"

const HF := preload("res://core/transform/height_fit.gd")

var _opts: Dictionary = {}
var _texts: Dictionary = {}  # key -> TextEdit（基类 register_field 仅收 LineEdit，多行文本框自管）
var _row_cache: Dictionary = {}
var _last_model: Dictionary = {}  # 最近一次成功拟合的模型字典（预测模式复用）

func get_entry_id() -> String:
	return "a10_height_fit"

func get_title() -> String:
	return "GNSS 高程拟合（A10）"

func get_description() -> String:
	return "GNSS 高程拟合：平面（3 参数）/ 曲面（6 参数）/ 带状分段模型，最小二乘求参输出残差表与 3σ 粗差提示；拟合后可预测待定点高程（带状分段超出覆盖范围会提示外插）。坐标每行 x, y, h。"

func _ready() -> void:
	super._ready()
	_build_rows()
	set_inputs(_example_inputs)

func _build_rows() -> void:
	_add_option_row("模式", "mode", [
		["fit", "拟合（公共点求参数）"],
		["predict", "预测点高程（用最近拟合模型）"],
	])
	_add_option_row("模型", "model", [
		["plane", "平面拟合（3 参数）"],
		["surface", "曲面拟合（6 参数）"],
		["strip", "带状分段拟合"],
	])
	_add_option_row("带状轴向", "axis", [
		["x", "沿 x 轴（东）分段"],
		["y", "沿 y 轴（北）分段"],
	])
	var seg_edit := add_input_row("分段数 segments", "segments", "2")
	_row_cache["segments"] = seg_edit
	var order_edit := add_input_row("每段阶数 order (1/2)", "order", "1")
	_row_cache["order"] = order_edit
	var px := add_input_row("预测点 x", "predict_x", "1500")
	_row_cache["predict_x"] = px
	var py := add_input_row("预测点 y", "predict_y", "2500")
	_row_cache["predict_y"] = py
	_add_points_row("公共点（每行 x, y, h）", "points", "0, 0, 10.0")
	var mode_opt: OptionButton = _opts["mode"]
	mode_opt.item_selected.connect(func(_idx: int) -> void: _apply_mode_visibility())
	var model_opt: OptionButton = _opts["model"]
	model_opt.item_selected.connect(func(_idx: int) -> void: _apply_mode_visibility())
	_apply_mode_visibility()

func _apply_mode_visibility() -> void:
	var predict := _opt_value("mode") == "predict"
	var strip := _opt_value("model") == "strip" and not predict
	for key in ["segments", "order"]:
		(_row_cache[key] as Control).get_parent().visible = strip
	(_opts["axis"] as Control).get_parent().visible = strip
	(_opts["model"] as Control).get_parent().visible = not predict
	(_row_cache["points"] as Control).get_parent().visible = not predict
	(_row_cache["predict_x"] as Control).get_parent().visible = predict
	(_row_cache["predict_y"] as Control).get_parent().visible = predict

func _opt_value(key: String) -> String:
	var ob: OptionButton = _opts[key]
	if ob.selected < 0:
		return String(ob.get_item_metadata(0))
	return String(ob.get_item_metadata(ob.selected))

func run() -> Dictionary:
	var inputs := get_inputs()
	var mode: String = inputs.get("mode", "fit")
	if mode == "fit":
		var pts := _parse_fit_points(String(inputs.get("points", "")))
		if not pts.ok:
			return _fail(pts.error)
		var res := HF.fit({
			"xy": pts.xy,
			"h": pts.h,
			"model": inputs.get("model", "plane"),
			"segments": inputs.get("segments", "2"),
			"order": inputs.get("order", "1"),
			"axis": inputs.get("axis", "x"),
		})
		if bool(res.get("ok", false)):
			_last_model = res["value"]["model"]
		return res
	if mode == "predict":
		if _last_model.is_empty():
			return _fail("请先在本页完成一次拟合（预测使用最近一次拟合的模型参数）")
		var xr := _parse_one(String(inputs.get("predict_x", "")), "预测点 x")
		if not xr.ok:
			return _fail(xr.error)
		var yr := _parse_one(String(inputs.get("predict_y", "")), "预测点 y")
		if not yr.ok:
			return _fail(yr.error)
		return HF.predict({"model": _last_model, "x": xr.val, "y": yr.val})
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

# ---------- 输入行构造与解析 ----------

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
	te.custom_minimum_size = Vector2(0, 180)
	te.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	te.scroll_fit_content_height = true
	row.add_child(te)
	_inputs_root.add_child(row)
	_texts[key] = te
	_row_cache[key] = te

## 每行 x, y, h → {ok, xy: [[x,y]...], h: [h...], error}
func _parse_fit_points(text: String) -> Dictionary:
	var xy := []
	var h := []
	var lines := text.split("\n")
	for li in lines.size():
		var line := String(lines[li]).strip_edges()
		if line.is_empty():
			continue
		var cleaned := line.replace("，", " ").replace("；", " ").replace(",", " ").replace(";", " ").replace("\t", " ")
		while "  " in cleaned:
			cleaned = cleaned.replace("  ", " ")
		var parts := cleaned.strip_edges().split(" ", false)
		if parts.size() != 3:
			return {"ok": false, "xy": [], "h": [], "error": "第 %d 行应为 3 个数字（x, y, h），实际 %d 个：“%s”" % [li + 1, parts.size(), line]}
		var vals := []
		for p: String in parts:
			if not p.is_valid_float():
				return {"ok": false, "xy": [], "h": [], "error": "第 %d 行含非数字内容：“%s”" % [li + 1, p]}
			vals.append(p.to_float())
		xy.append([vals[0], vals[1]])
		h.append(vals[2])
	if xy.is_empty():
		return {"ok": false, "xy": [], "h": [], "error": "请输入至少 1 行公共点（每行 x, y, h）"}
	return {"ok": true, "xy": xy, "h": h, "error": ""}

func _parse_one(text: String, what: String) -> Dictionary:
	var s := text.strip_edges()
	if s.is_empty():
		return {"ok": false, "val": NAN, "error": "%s 为空，请填写数值" % what}
	if not s.is_valid_float():
		return {"ok": false, "val": NAN, "error": "%s 不是有效数字：“%s”" % [what, s]}
	return {"ok": true, "val": s.to_float(), "error": ""}

func _fail(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": msg}
