# scenes/calculators/route/e6_profile.gd —— E6 纵断面内插/横断面数据计算器
extends "res://scenes/widgets/calculator_base.gd"

const Core := preload("res://core/earthwork/profile.gd")
const Ui := preload("res://scenes/calculators/route/ui_common.gd")
const SketchScene := preload("res://scenes/widgets/sketch_panel.tscn")  # GKSketchPanel

var _mode_opt: OptionButton
var _sketch: Control  # 地面线示意图（GKSketchPanel）

## 地面线示意图挂在公式折叠卡之后；计算后按地面线点位重绘
func _build_sketch() -> void:
	_sketch = SketchScene.instantiate()
	add_child(_sketch)

## 地面线文本 → 米制点位（桩号/偏距为 x、高程为 y）；非法行跳过
func _ground_points(text: String) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for r: Dictionary in Ui.to_kv_rows(text, ["a", "b"])["rows"]:
		var x := Ui.to_f(String(r["a"]))
		var y := Ui.to_f(String(r["b"]))
		if not is_nan(x) and not is_nan(y):
			pts.append(Vector2(x, y))
	return pts

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
	add_input_row("地面线数据（分号分行）", "points", "纵：桩号,高程；横：偏距,高程。如 0,100; 100,102; 200,101", LineEdit.KEYBOARD_TYPE_DEFAULT)
	add_input_row("查询桩号/偏距", "query", "空格分隔，如 150", LineEdit.KEYBOARD_TYPE_DEFAULT)
	add_input_row("设计中心高程（m）", "design_elev_m", "横断面用，如 103")
	add_input_row("路拱横坡 i（%）", "cross_slope_pct", "横断面用，默认 0")
	add_input_row("越界截断 clamp（1=是）", "clamp", "纵断面可选，默认报错", LineEdit.KEYBOARD_TYPE_DEFAULT)
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
		if _sketch != null:
			_sketch.call("set_points", PackedVector2Array())
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "地面线格式有误：" + "；".join(kv["errors"])}
	var rows: Array = kv["rows"]
	if rows.size() < 2:
		if _sketch != null:
			_sketch.call("set_points", PackedVector2Array())
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "地面线至少 2 点（每行 桩号/偏距,高程）"}
	# 点位数 ≥2 才画地面线（纵断面 x=桩号、y=高程；横断面 x=偏距、y=高程）
	if _sketch != null:
		_sketch.call("set_points", _ground_points(_fields["points"].text))
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
	super.set_inputs(inputs)
	for key: String in _fields:
		if inputs.has(key):
			_fields[key].text = str(inputs[key])
	if inputs.has("mode"):
		var idx := int(Ui.to_f(str(inputs["mode"])))
		if idx >= 0 and idx < _mode_opt.item_count:
			_mode_opt.select(idx)
