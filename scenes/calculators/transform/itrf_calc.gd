# scenes/calculators/transform/itrf_calc.gd —— F7 ITRF 历元传播 / 14 参数框架转换计算器
# 模式：14 参数框架转换（frame_from → frame_to，可含速度场）/ 历元传播（同框架内速度场外推）。
# 数据：data/itrf_params.json（官方参数表，本场景经 GKFileIO 只读装载——UI 层读盘、core 纯计算，
# 符合 ARCHITECTURE.md §1.1"core 不读盘，由调用方装载后传参"分层）。
# 计算走 core/transform/itrf.gd（GKITRF）。
extends "res://scenes/widgets/calculator_base.gd"

const I := preload("res://core/transform/itrf.gd")

const PARAMS_PATH := "res://data/itrf_params.json"

var _opts: Dictionary = {}
var _texts: Dictionary = {}  # key -> TextEdit（基类 register_field 仅收 LineEdit，多行文本框自管）
var _row_cache: Dictionary = {}

func get_entry_id() -> String:
	return "f7_itrf"

func get_title() -> String:
	return "ITRF 历元传播与 14 参数转换（F7）"

func get_description() -> String:
	return "ITRF 框架间转换（平移/旋转/尺度及其年速率，14 参数；速率全零自动退化为七参数）与同一框架内的历元传播 X(t2)=X(t1)+V·Δt。参数表为 ITRF 官方发布（论文 Table 6 与 EPSG 注册表互证）；坐标每行 x, y, z，可附速度每行再加 vx, vy, vz（m/年）。"

func _ready() -> void:
	super._ready()
	_build_rows()
	set_inputs(_example_inputs)

func _build_rows() -> void:
	_add_option_row("模式", "mode", [
		["transform", "14 参数框架转换"],
		["propagate", "历元传播（速度场）"],
	])
	var ff := add_input_row("源框架（如 ITRF2020）", "frame_from", "ITRF2020")
	_row_cache["frame_from"] = ff
	var ft := add_input_row("目标框架（如 ITRF2014）", "frame_to", "ITRF2014")
	_row_cache["frame_to"] = ft
	var ep := add_input_row("求值历元 t（年）", "epoch", "2015.0")
	_row_cache["epoch"] = ep
	var ef := add_input_row("起始历元 t1（年）", "epoch_from", "2015.0")
	_row_cache["epoch_from"] = ef
	var et := add_input_row("目标历元 t2（年）", "epoch_to", "2023.0")
	_row_cache["epoch_to"] = et
	_add_points_row("坐标/速度（每行 x, y, z[, vx, vy, vz]）", "points", "4000000, 500000, 4933000")
	var mode_opt: OptionButton = _opts["mode"]
	mode_opt.item_selected.connect(func(_idx: int) -> void: _apply_mode_visibility())
	_apply_mode_visibility()

func _apply_mode_visibility() -> void:
	var propagate := _opt_value("mode") == "propagate"
	(_row_cache["frame_from"] as Control).get_parent().visible = not propagate
	(_row_cache["frame_to"] as Control).get_parent().visible = not propagate
	(_row_cache["epoch"] as Control).get_parent().visible = not propagate
	(_row_cache["epoch_from"] as Control).get_parent().visible = propagate
	(_row_cache["epoch_to"] as Control).get_parent().visible = propagate

func _opt_value(key: String) -> String:
	var ob: OptionButton = _opts[key]
	if ob.selected < 0:
		return String(ob.get_item_metadata(0))
	return String(ob.get_item_metadata(ob.selected))

func run() -> Dictionary:
	var inputs := get_inputs()
	var mode: String = inputs.get("mode", "transform")
	var pts := _parse_points_text(String(inputs.get("points", "")))
	if not pts.ok:
		return _fail(pts.error)
	if mode == "propagate":
		if not pts.vel_ok:
			return _fail("历元传播需要速度场：每行应为 6 个数字（x, y, z, vx, vy, vz，m/年）")
		return I.propagate({
			"src_xyz": pts.rows,
			"vel": pts.vels,
			"epoch_from": inputs.get("epoch_from", "2015.0"),
			"epoch_to": inputs.get("epoch_to", "2023.0"),
		})
	if mode == "transform":
		var data_v: Variant = GKFileIO.read_json(PARAMS_PATH)
		if not (data_v is Dictionary) or (data_v as Dictionary).is_empty():
			return _fail("ITRF 参数库 data/itrf_params.json 读取失败（文件缺失或损坏）")
		var data: Dictionary = data_v
		var row := I.lookup(data, String(inputs.get("frame_from", "")), String(inputs.get("frame_to", "")))
		if row.is_empty():
			return _fail("参数表未收录 %s → %s 的官方转换参数（可改用 A9 七参数求参自行求取，或在 data/itrf_params.json 补充官方参数）" % [String(inputs.get("frame_from", "?")), String(inputs.get("frame_to", "?"))])
		var p := {
			"src_xyz": pts.rows,
			"params_row": row,
			"epoch": inputs.get("epoch", ""),
		}
		if pts.vel_ok:
			p["vel"] = pts.vels
		return I.transform(p)
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
	te.custom_minimum_size = Vector2(0, 132)
	te.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	te.scroll_fit_content_height = true
	row.add_child(te)
	_inputs_root.add_child(row)
	_texts[key] = te
	_row_cache[key] = te

## 每行 3 个（仅坐标）或 6 个（坐标+速度）数字；全部行必须一致（3 或 6）。
func _parse_points_text(text: String) -> Dictionary:
	var rows := []
	var vels := []
	var has_vel := false
	var has_plain := false
	var lines := text.split("\n")
	for li in lines.size():
		var line := String(lines[li]).strip_edges()
		if line.is_empty():
			continue
		var cleaned := line.replace("，", " ").replace("；", " ").replace(",", " ").replace(";", " ").replace("\t", " ")
		while "  " in cleaned:
			cleaned = cleaned.replace("  ", " ")
		var parts := cleaned.strip_edges().split(" ", false)
		if parts.size() != 3 and parts.size() != 6:
			return {"ok": false, "rows": [], "vels": [], "vel_ok": false, "error": "第 %d 行应有 3 个数字（x, y, z）或 6 个数字（含速度 vx, vy, vz），实际 %d 个：“%s”" % [li + 1, parts.size(), line]}
		var vals := []
		for p: String in parts:
			if not p.is_valid_float():
				return {"ok": false, "rows": [], "vels": [], "vel_ok": false, "error": "第 %d 行含非数字内容：“%s”" % [li + 1, p]}
			vals.append(p.to_float())
		if parts.size() == 6:
			has_vel = true
			rows.append([vals[0], vals[1], vals[2]])
			vels.append([vals[3], vals[4], vals[5]])
		else:
			has_plain = true
			rows.append([vals[0], vals[1], vals[2]])
	if rows.is_empty():
		return {"ok": false, "rows": [], "vels": [], "vel_ok": false, "error": "请输入至少 1 行坐标（每行 x, y, z，可附 vx, vy, vz）"}
	if has_vel and has_plain:
		return {"ok": false, "rows": [], "vels": [], "vel_ok": false, "error": "各行格式需一致：要么全部带速度（6 个数字），要么全部不带（3 个数字）"}
	return {"ok": true, "rows": rows, "vels": vels, "vel_ok": has_vel, "error": ""}

func _fail(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": msg}
