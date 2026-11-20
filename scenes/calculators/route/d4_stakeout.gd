# scenes/calculators/route/d4_stakeout.gd —— D4 中边桩/极坐标放样计算器
extends "res://scenes/widgets/calculator_base.gd"

const Core := preload("res://core/route/stakeout.gd")
const Ui := preload("res://scenes/calculators/route/ui_common.gd")

func _ready() -> void:
	super._ready()
	add_input_row("起点 X 东 (m)", "x_m", "如 1000")
	add_input_row("起点 Y 北 (m)", "y_m", "如 2000")
	add_input_row("起点切线方位 (°)", "bearing_deg", "如 0")
	add_input_row("线元表 类型,长,k0,k1（分号分行）", "elements", "如 line,100; arc,235.6,0.0025,0.0025")
	add_input_row("桩号列表 (m)", "chains", "空格/逗号分隔，如 50 150 200")
	add_input_row("偏距列表 (m)", "offsets", "右正左负，与桩号对应；留空全为 0")
	add_input_row("测站 X 东 (m)", "st_x", "极坐标放样可选")
	add_input_row("测站 Y 北 (m)", "st_y", "可选")
	add_input_row("后视方位 (°)", "bs_bearing", "与后视点二选一")
	add_input_row("后视点 X 东 (m)", "bs_x", "可选")
	add_input_row("后视点 Y 北 (m)", "bs_y", "可选")
	set_inputs(_example_inputs)

func get_title() -> String:
	return "中边桩与极坐标放样（D4）"

func get_description() -> String:
	return "中桩/边桩坐标（偏距右正左负）；给测站+后视时输出极坐标放样数据（平距+放样角）"

func get_entry_id() -> String:
	return "d4_stakeout"

func run() -> Dictionary:
	var sx := Ui.to_f(_fields["x_m"].text)
	var sy := Ui.to_f(_fields["y_m"].text)
	var az := Ui.to_f(_fields["bearing_deg"].text)
	if is_nan(sx) or is_nan(sy) or is_nan(az):
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "请填写起点坐标与切线方位（数字）"}
	var rows := Ui.to_list_multi(_fields["elements"].text, ";")
	var els := []
	var errs := PackedStringArray()
	for i in rows.size():
		var parts := Ui.to_list(rows[i])
		if parts.is_empty():
			continue
		var typ := String(parts[0]).to_lower()
		if typ == "line" and parts.size() >= 2:
			els.append({"type": "line", "len": parts[1], "k0": 0.0, "k1": 0.0})
			continue
		if parts.size() < 4:
			errs.append("第 %d 行应为：类型,长度,k0,k1" % (i + 1))
			continue
		els.append({"type": typ, "len": parts[1], "k0": parts[2], "k1": parts[3]})
	if not errs.is_empty():
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "线元表格式有误：" + "；".join(errs)}
	if els.is_empty():
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "请输入线元表"}
	var chains := Ui.to_list(_fields["chains"].text)
	if chains.is_empty():
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "请输入桩号列表"}
	var offsets := Ui.to_list(_fields["offsets"].text)
	if not offsets.is_empty() and offsets.size() != chains.size():
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "偏距列表与桩号数量不一致（%d 对 %d）" % [offsets.size(), chains.size()]}
	var stakes := []
	for i in chains.size():
		var row := {"chain_m": chains[i]}
		if offsets.size() == chains.size():
			row["offset_m"] = offsets[i]
		stakes.append(row)
	var p := {"elements": els, "start": {"x_m": sx, "y_m": sy, "bearing_deg": az}, "stakes": stakes}
	var stx := Ui.to_f(_fields["st_x"].text)
	var sty := Ui.to_f(_fields["st_y"].text)
	if not is_nan(stx) and not is_nan(sty):
		p["station"] = {"x_m": stx, "y_m": sty}
		var bsb := Ui.to_f(_fields["bs_bearing"].text)
		var bsx := Ui.to_f(_fields["bs_x"].text)
		var bsy := Ui.to_f(_fields["bs_y"].text)
		if not is_nan(bsb):
			p["backsight_bearing_deg"] = bsb
		elif not is_nan(bsx) and not is_nan(bsy):
			p["backsight"] = {"x_m": bsx, "y_m": bsy}
	return Core.forward(p)

func set_inputs(inputs: Dictionary) -> void:
	for key: String in _fields:
		if inputs.has(key):
			_fields[key].text = str(inputs[key])
