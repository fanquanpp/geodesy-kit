# scenes/calculators/route/e6_profile.gd —— E6 纵断面内插/横断面数据计算器
extends "res://scenes/widgets/calculator_base.gd"

const Core := preload("res://core/earthwork/profile.gd")
const Ui := preload("res://scenes/calculators/route/ui_common.gd")

var _mode_opt: OptionButton

func _ready() -> void:
	super._ready()
	var row := HBoxContainer.new()
	var lab := Label.new()
	lab.text = "计算模式"
	lab.custom_minimum_size = Vector2(180, 0)
	row.add_child(lab)
	_mode_opt = OptionButton.new()
	_mode_opt.add_item("纵断面内插")
	_mode_opt.add_item("横断面挖填高与面积")
	_mode_opt.custom_minimum_size = Vector2(0, 96)
	row.add_child(_mode_opt)
	_inputs_root.add_child(row)
	add_input_row("地面线数据（分号分行）", "points", "纵：桩号,高程；横：偏距,高程。如 0,100; 100,102; 200,101")
	add_input_row("查询桩号/偏距", "query", "空格分隔，如 150")
	add_input_row("设计中心高程 (m)", "design_elev_m", "横断面用，如 103")
	add_input_row("路拱横坡 i (%)", "cross_slope_pct", "横断面用，默认 0")
	add_input_row("越界截断 clamp（1=是）", "clamp", "纵断面可选，默认报错")
	set_inputs(_example_inputs)

func get_title() -> String:
	return "纵断面内插/横断面（E6）"

func get_description() -> String:
	return "纵断面地面线线性内插；横断面设计线（对称路拱）逐点挖填高与分段精确积分填挖面积（供 E2 断面法）"

func get_entry_id() -> String:
	return "e6_profile"

func run() -> Dictionary:
	var kv := Ui.to_kv_rows(_fields["points"].text, ["a", "b"])
	if not kv["errors"].is_empty():
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "地面线格式有误：" + "；".join(kv["errors"])}
	var rows: Array = kv["rows"]
	if rows.size() < 2:
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "地面线至少 2 点（每行 桩号/偏距,高程）"}
	var q := Ui.to_list(_fields["query"].text)
	if _mode_opt.selected == 0:
		if q.is_empty():
			return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "请输入查询桩号列表"}
		var pts := []
		for r: Dictionary in rows:
			pts.append({"chain_m": r["a"], "elev_m": r["b"]})
		var p := {"points": pts, "query_chains_m": q}
		var cl := Ui.to_f(_fields["clamp"].text)
		if not is_nan(cl) and cl != 0.0:
			p["clamp"] = true
		return Core.interp_forward(p)
	var pd := Ui.to_f(_fields["design_elev_m"].text)
	if is_nan(pd):
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "横断面模式请填写设计中心高程"}
	var secs := []
	for r: Dictionary in rows:
		secs.append({"offset_m": r["a"], "elev_m": r["b"]})
	var p2 := {"section": secs, "design_elev_m": pd}
	var ii := Ui.to_f(_fields["cross_slope_pct"].text)
	if not is_nan(ii):
		p2["cross_slope_pct"] = ii
	return Core.cross_section(p2)

func get_inputs() -> Dictionary:
	var out := super.get_inputs()
	out["mode"] = str(_mode_opt.selected)
	return out

func set_inputs(inputs: Dictionary) -> void:
	for key: String in _fields:
		if inputs.has(key):
			_fields[key].text = str(inputs[key])
	if inputs.has("mode"):
		var idx := int(Ui.to_f(str(inputs["mode"])))
		if idx >= 0 and idx < _mode_opt.item_count:
			_mode_opt.select(idx)
