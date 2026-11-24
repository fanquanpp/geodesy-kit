# scenes/calculators/transform/rtk_calc.gd —— RTK 参数计算（公共点求参 + 检核点回代检核）
# 模式：平面四参数（mode=plane）/ 空间七参数（mode=space）。
# 契约与输入口径同 bursa_calc.gd / four_param_calc.gd；
# 计算走 core/transform/rtk_params.gd（GKRTKParams）。
# 限差由用户输入（规范原文限差未核读，界面不预填默认值，basis 注明）。
extends "res://scenes/widgets/calculator_base.gd"

const RK := preload("res://core/transform/rtk_params.gd")

var _opts: Dictionary = {}
var _texts: Dictionary = {}  # key -> TextEdit（基类 register_field 仅收 LineEdit，多行文本框自管）
var _row_cache: Dictionary = {}

func get_entry_id() -> String:
	return "a11_rtk_params"

func get_title() -> String:
	return "RTK 参数计算（公共点求参与检核）"

func get_description() -> String:
	return "RTK 作业转换参数计算：用参与求参的公共点最小二乘求取四参数（平面）或七参数（空间），再用未参与求参的检核点回代转换、与已知坐标比较较差，按输入限差给出合格/超限结论。检核点较差限差由用户输入（请自行核对规范限差取值）。"

func _ready() -> void:
	super._ready()
	_build_rows()
	set_inputs(_example_inputs)

func _build_rows() -> void:
	_add_option_row("场景", "mode", [
		["plane", "平面四参数（每行 x, y）"],
		["space", "空间七参数（每行 x, y, z）"],
	])
	_add_option_row("旋转约定（空间）", "convention", [
		["PV", "PV 位置向量（EPSG:1033）"],
		["CF", "CF 坐标框架（EPSG:1032）"],
	])
	var lim := add_input_row("检核点较差限差（m）", "limit_m", "")
	_row_cache["limit_m"] = lim
	_add_points_row("公共点源坐标（每行 x, y[, z]）", "common_src", "1000, 1000\n3000, 2000")
	_add_points_row("公共点目标坐标（每行 X, Y[, Z]）", "common_dst", "")
	_add_points_row("检核点源坐标（每行 x, y[, z]）", "check_src", "")
	_add_points_row("检核点已知目标坐标（每行 X, Y[, Z]）", "check_dst", "")
	var mode_opt: OptionButton = _opts["mode"]
	mode_opt.item_selected.connect(func(_idx: int) -> void: _apply_mode_visibility())
	_apply_mode_visibility()

func _apply_mode_visibility() -> void:
	var space := _opt_value("mode") == "space"
	var src_row: Control = (_texts["common_src"] as Control).get_parent()
	var src_lab := src_row.get_child(0) as Label
	var dst_row: Control = (_texts["common_dst"] as Control).get_parent()
	var dst_lab := dst_row.get_child(0) as Label
	var ck_row: Control = (_texts["check_src"] as Control).get_parent()
	var ck_lab := ck_row.get_child(0) as Label
	var ckd_row: Control = (_texts["check_dst"] as Control).get_parent()
	var ckd_lab := ckd_row.get_child(0) as Label
	src_lab.text = "公共点源坐标（每行 x, %s）" % ("y, z" if space else "y")
	dst_lab.text = "公共点目标坐标（每行 X, %s）" % ("Y, Z" if space else "Y")
	ck_lab.text = "检核点源坐标（每行 x, %s）" % ("y, z" if space else "y")
	ckd_lab.text = "检核点已知目标坐标（每行 X, %s）" % ("Y, Z" if space else "Y")
	(_opts["convention"] as Control).get_parent().visible = space

func _opt_value(key: String) -> String:
	var ob: OptionButton = _opts[key]
	if ob.selected < 0:
		return String(ob.get_item_metadata(0))
	return String(ob.get_item_metadata(ob.selected))

func run() -> Dictionary:
	var inputs := get_inputs()
	var mode: String = inputs.get("mode", "plane")
	var space := mode == "space"
	var ncols := 3 if space else 2
	var csrc := _parse_points_text(String(inputs.get("common_src", "")), ncols, "公共点源坐标")
	if not csrc.ok:
		return _fail(csrc.error)
	var cdst := _parse_points_text(String(inputs.get("common_dst", "")), ncols, "公共点目标坐标")
	if not cdst.ok:
		return _fail(cdst.error)
	var p := {
		"mode": mode,
		"common_src": csrc.rows,
		"common_dst": cdst.rows,
		"limit_m": inputs.get("limit_m", ""),
	}
	if space:
		p["convention"] = inputs.get("convention", "PV")
	# 检核点可选：两栏都非空才传入
	var cks := _parse_points_text(String(inputs.get("check_src", "")), ncols, "检核点源坐标")
	var ckd := _parse_points_text(String(inputs.get("check_dst", "")), ncols, "检核点已知目标坐标")
	var has_ck_src := String(inputs.get("check_src", "")).strip_edges() != ""
	var has_ck_dst := String(inputs.get("check_dst", "")).strip_edges() != ""
	if has_ck_src != has_ck_dst:
		return _fail("检核点须成对输入：源坐标与已知目标坐标都要填写")
	if has_ck_src:
		if not cks.ok:
			return _fail(cks.error)
		if not ckd.ok:
			return _fail(ckd.error)
		if cks.rows.size() != ckd.rows.size():
			return _fail("检核点源/目标坐标行数不一致：%d 与 %d" % [cks.rows.size(), ckd.rows.size()])
		p["check_src"] = cks.rows
		p["check_dst"] = ckd.rows
	return RK.compute(p)

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

# ---------- 输入行构造与解析（与其他转换计算器同口径） ----------

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
		for pt: String in parts:
			if not pt.is_valid_float():
				return {"ok": false, "rows": [], "error": "%s 第 %d 行含非数字内容：「%s」" % [what, li + 1, pt]}
			vals.append(pt.to_float())
		rows.append(vals)
	if rows.is_empty():
		return {"ok": false, "rows": [], "error": "请输入至少 1 行坐标（每行 %d 个数字）" % ncols}
	return {"ok": true, "rows": rows, "error": ""}

func _fail(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": msg}
