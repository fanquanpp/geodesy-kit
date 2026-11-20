# scenes/calculators/tools/batch_convert.gd —— G2 批量坐标转换面板
# 组件化组装：输入管线选择（OptionButton）+ 点文件文本（TextEdit）+ 参数行（LineEdit），
# 计算编排全部在 app/batch_convert.gd（复用 core §5 协议，不重写算法）；
# 本面板只做 UI 组装、示例填充、结果行卡片渲染与 CSV 导出。
extends "res://scenes/widgets/calculator_base.gd"

const BC := preload("res://app/batch_convert.gd")
const MAX_STEP_ROWS := 500  # 步骤卡片行数上限（超限只渲染摘要，防 UI 卡顿）

var _pipe_opt: OptionButton
var _file_edit: TextEdit
var _param_rows: Dictionary = {}   # param_key -> HBoxContainer（显隐切换）
const PARAM_KEYS_BY_PIPE := {
	"blh_to_xyz": ["datum"],
	"xyz_to_blh": ["datum"],
	"blh_to_gauss": ["datum", "l0_deg", "k0", "fe_m", "fn_m"],
	"gauss_to_blh": ["datum", "l0_deg", "k0", "fe_m", "fn_m"],
	"blh_to_utm": ["datum", "zone"],
	"utm_to_blh": ["datum", "zone", "hemisphere"],
	"bursa_fwd": ["tx_m", "ty_m", "tz_m", "rx_as", "ry_as", "rz_as", "scale_ppm", "convention", "three_param"],
	"four_param_fwd": ["dx_m", "dy_m", "scale", "alpha_deg"],
	"four_param_inv": ["dx_m", "dy_m", "scale", "alpha_deg"],
}

func get_title() -> String:
	return "批量坐标转换（G2）"

func get_description() -> String:
	return "一份点文件（每行：点名,值1,值2[,值3]）整批套用坐标类模块的转换函数（高斯/UTM/BLH↔XYZ/七参数/四参数）。逐行输出结果与中文错误，失败的行不中断整批；算法复用各单点计算器的 core 实现，结果与单点口径一致。"

func get_entry_id() -> String:
	return "g2_batch_convert"

func _ready() -> void:
	if _example_inputs.is_empty():
		_example_inputs = {
			"pipeline": "blh_to_xyz",
			"datum": "WGS84",
			"text": "P1, 39.9075, 116.3913, 43.5\nP2, 31.2304, 121.4737, 10.0\nP3, 30, 117, 50",
		}
	super._ready()
	_build_rows()
	_title_label.text = get_title()
	_desc_label.text = get_description()
	_desc_label.visible = true
	set_inputs(_example_inputs)
	_apply_pipe_visibility(_current_pipe_key())

func _build_rows() -> void:
	# 管线选择
	var prow := HBoxContainer.new()
	var plab := Label.new()
	plab.text = "转换类型"
	plab.custom_minimum_size = Vector2(180, 0)
	prow.add_child(plab)
	_pipe_opt = OptionButton.new()
	_pipe_opt.custom_minimum_size = Vector2(0, 96)
	_pipe_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var idx := 0
	for key: String in BC.PIPELINES.keys():
		var pipe: Dictionary = BC.PIPELINES[key]
		_pipe_opt.add_item("%s（%s）" % [String(pipe["label"]), String(pipe["in_cols"])])
		_pipe_opt.set_item_metadata(idx, key)
		idx += 1
	_pipe_opt.item_selected.connect(func(_i: int) -> void: _apply_pipe_visibility(_current_pipe_key()))
	prow.add_child(_pipe_opt)
	_inputs_root.add_child(prow)
	# 点文件文本
	var frow := VBoxContainer.new()
	var flab := Label.new()
	flab.text = "点文件内容（每行：点名,值1,值2[,值3]；# 注释行；分隔符支持逗号/空格/Tab）"
	frow.add_child(flab)
	_file_edit = TextEdit.new()
	_file_edit.placeholder_text = "P1, 39.9075, 116.3913, 43.5\nP2, 30, 117, 50"
	_file_edit.custom_minimum_size = Vector2(0, 200)
	_file_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_file_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	frow.add_child(_file_edit)
	_inputs_root.add_child(frow)
	# 参数行（全部建好，按管线显隐）
	_add_param_row("椭球/基准 datum", "datum", "CGCS2000 / WGS84 / 北京54 / 西安80 …")
	_add_param_row("中央子午线 l0（度）", "l0_deg", "117（3°带 L0=3n，6°带 L0=6n−3）")
	_add_param_row("比例因子 k0", "k0", "1.0（留空默认）")
	_add_param_row("东坐标加常数 FE(m)", "fe_m", "500000（留空默认）")
	_add_param_row("北坐标加常数 FN(m)", "fn_m", "0（留空默认）")
	_add_param_row("UTM/带号 zone", "zone", "1..60（留空自动选带；反算必填）")
	_add_param_row("半球 hemisphere", "hemisphere", "N 或 S（UTM 反算必填）")
	_add_param_row("平移 Tx(m)", "tx_m", "0")
	_add_param_row("平移 Ty(m)", "ty_m", "0")
	_add_param_row("平移 Tz(m)", "tz_m", "0")
	_add_param_row("旋转 Rx(″)", "rx_as", "0")
	_add_param_row("旋转 Ry(″)", "ry_as", "0")
	_add_param_row("旋转 Rz(″)", "rz_as", "0")
	_add_param_row("尺度 dS(ppm)", "scale_ppm", "0")
	_add_param_row("旋转约定 convention", "convention", "PV 或 CF（默认 PV）")
	_add_param_row("三参数模式 three_param", "three_param", "true 时忽略旋转/尺度")
	_add_param_row("平移 dx(m)", "dx_m", "0")
	_add_param_row("平移 dy(m)", "dy_m", "0")
	_add_param_row("尺度因子 scale", "scale", "1.0002")
	_add_param_row("旋转角 α(°)", "alpha_deg", "2")
	# CSV 导出按钮
	var csv_btn := Button.new()
	csv_btn.text = "导出结果 CSV"
	csv_btn.custom_minimum_size = Vector2(0, 96)
	csv_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	csv_btn.pressed.connect(_on_export_csv)
	_inputs_root.add_child(csv_btn)

func _add_param_row(label_text: String, key: String, placeholder: String) -> void:
	var row := HBoxContainer.new()
	var lab := Label.new()
	lab.text = label_text
	lab.custom_minimum_size = Vector2(180, 0)
	row.add_child(lab)
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size = Vector2(0, 96)
	row.add_child(edit)
	_inputs_root.add_child(row)
	register_field(key, edit)
	_param_rows[key] = row

func _current_pipe_key() -> String:
	var i := _pipe_opt.selected
	if i < 0:
		return ""
	return String(_pipe_opt.get_item_metadata(i))

func _apply_pipe_visibility(key: String) -> void:
	var keys: Array = PARAM_KEYS_BY_PIPE.get(key, [])
	for k: String in _param_rows:
		(_param_rows[k] as Control).visible = keys.has(k)

# ---------- 契约 ----------

func get_inputs() -> Dictionary:
	var out := {}
	for key: String in _fields:
		out[key] = (_fields[key] as LineEdit).text
	out["pipeline"] = _current_pipe_key()
	out["text"] = _file_edit.text
	return out

func set_inputs(inputs: Dictionary) -> void:
	for key: String in _fields:
		if inputs.has(key):
			(_fields[key] as LineEdit).text = String(inputs[key])
	# _file_edit/_pipe_opt 在基类 _ready 的首次 set_inputs 时还未建立（_build_rows 尚未执行），
	# 置空守卫：建好后 _ready 尾部会再应用一次示例。
	if _file_edit != null and inputs.has("text"):
		_file_edit.text = String(inputs["text"])
	if _pipe_opt != null and inputs.has("pipeline"):
		for i in _pipe_opt.item_count:
			if String(_pipe_opt.get_item_metadata(i)) == String(inputs["pipeline"]):
				_pipe_opt.select(i)
				_apply_pipe_visibility(String(inputs["pipeline"]))
				break

func run() -> Dictionary:
	var params := {}
	for key: String in _fields:
		var t := (_fields[key] as LineEdit).text.strip_edges()
		if not t.is_empty():
			params[key] = t
	return BC.convert({
		"pipeline": _current_pipe_key(),
		"text": _file_edit.text,
		"params": params,
	})

# ---------- 结果行渲染（复用基类步骤卡；行数多时截断为摘要） ----------

func _on_run() -> void:
	var res := run()
	_last_result = res
	if bool(res.get("ok", false)):
		var shown := res.duplicate(true)
		var rows: Array = (shown.get("value", {}) as Dictionary).get("rows", [])
		var disp: Array = []
		for i in mini(rows.size(), MAX_STEP_ROWS):
			disp.append(_row_to_step(rows[i]))
		if rows.size() > MAX_STEP_ROWS:
			disp.append({"title": "（截断提示）", "formula": "", "substitution": "",
					"result": "共 %d 行，步骤卡仅渲染前 %d 行；完整结果请导出 CSV" % [rows.size(), MAX_STEP_ROWS]})
		shown["steps"] = (res.get("steps", []) as Array) + disp
		_render_result(shown)
		if GKServices.ready_state():
			GKServices.history.add(get_entry_id(), get_title(), get_inputs(), res)
	else:
		_render_result(res)

func _row_to_step(r: Dictionary) -> Dictionary:
	var name := String(r.get("name", ""))
	if name.is_empty():
		name = "行%d" % int(r.get("line", 0))
	var vals: Array = r.get("values", [])
	var err := String(r.get("error", ""))
	var result_txt := ""
	if not err.is_empty():
		result_txt = "失败：%s" % err
	else:
		var parts := PackedStringArray()
		for i in vals.size():
			parts.append("%s = %s" % [_col_name(i), _num(vals[i])])
		result_txt = "；".join(parts)
	return {"title": "%s（第 %d 行）" % [name, int(r.get("line", 0))],
			"formula": "", "substitution": "", "result": result_txt}

func _col_name(i: int) -> String:
	var res: Dictionary = _last_result
	var cols: Array = res.get("value", {}).get("out_cols", [])
	return String(cols[i]) if i < cols.size() else "值%d" % (i + 1)

func _num(v: Variant) -> String:
	if v is float or v is int:
		return String.num(float(v), 6)
	return str(v)

## 结果行 → CSV 文件（user://batch/），状态栏显示绝对路径
func _on_export_csv() -> void:
	_status_label.theme_type_variation = &"ErrorLabel"
	var res: Dictionary = _last_result
	if res.is_empty() or not bool(res.get("ok", false)):
		_status_label.text = "请先点击「计算」成功后再导出 CSV。"
		_status_label.visible = true
		return
	var rows: Array = (res.get("value", {}) as Dictionary).get("rows", [])
	var csv := BC.rows_to_csv(rows)
	var stamp := "%04d%02d%02d_%02d%02d%02d" % _now_tuple()
	var rel := "user://batch/batch_%s.csv" % stamp
	if not GKFileIO.write_text(rel, csv):
		_status_label.text = "CSV 写入失败：%s" % ProjectSettings.globalize_path(rel)
	else:
		_status_label.theme_type_variation = &"Muted"
		_status_label.text = "CSV 已保存：%s" % ProjectSettings.globalize_path(rel)
	_status_label.visible = true

static func _now_tuple() -> Array:
	var d := Time.get_datetime_dict_from_system()
	return [d.year, d.month, d.day, d.hour, d.minute, d.second]
