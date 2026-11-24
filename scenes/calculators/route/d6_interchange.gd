# scenes/calculators/route/d6_interchange.gd —— D6 匝道复杂线型计算器
extends "res://scenes/widgets/calculator_base.gd"

const Core := preload("res://core/route/interchange.gd")
const Ui := preload("res://scenes/calculators/route/ui_common.gd")

var _type_opt: OptionButton

func _ready() -> void:
	super._ready()
	var row := HBoxContainer.new()
	var lab := Label.new()
	lab.text = "匝道线型"
	lab.custom_minimum_size = Vector2(180, 0)
	row.add_child(lab)
	_type_opt = OptionButton.new()
	_type_opt.add_item("基本型（直—缓—圆—缓—直）")
	_type_opt.add_item("S型（反向回旋衔接）")
	_type_opt.add_item("卵型（同向圆间回旋）")
	_type_opt.add_item("C型（同向回旋衔接）")
	_type_opt.add_item("回头曲线（|α|>180°）")
	_type_opt.custom_minimum_size = Vector2(0, 96)
	row.add_child(_type_opt)
	_inputs_root.add_child(row)
	add_input_row("起点 X 东（m）", "x_m", "如 1000")
	add_input_row("起点 Y 北（m）", "y_m", "如 2000")
	add_input_row("起点切线方位（°）", "bearing_deg", "如 10")
	add_input_row("转向 dir （+1右/-1左）", "dir", "默认 +1", LineEdit.KEYBOARD_TYPE_DEFAULT)
	add_input_row("半径 R / 大圆 R1（m）", "r_m", "基本型/回头用")
	add_input_row("小圆 R2（m）", "r2_m", "S型/卵型/C型用")
	add_input_row("缓和曲线长 l0 / l01（m）", "l0_m", "如 60")
	add_input_row("回旋线长 l02（m）", "l02_m", "S型/C型用")
	add_input_row("转角 α / 圆1转角（°）", "alpha_deg", "如 30；回头曲线填 >180")
	add_input_row("圆2转角（°）", "arc2_turn_deg", "S型/卵型/C型用")
	add_input_row("圆1转角 β1（°）", "arc1_turn_deg", "S型/卵型/C型用")
	add_input_row("C型夹直线长（m）", "straight_m", "仅 C 型，默认 0")
	set_inputs(_example_inputs)

func get_title() -> String:
	return "匝道复杂线型（D6）"

func get_description() -> String:
	return "C型/S型/卵型/回头曲线 = 线元序列组合（D2 引擎装配），自动检核接点曲率/坐标连续与总转角"

func get_entry_id() -> String:
	return "d6_interchange"

func run() -> Dictionary:
	var p := _common()
	if p.has("error"):
		return p
	match _type_opt.selected:
		0:
			return Core.basic(p)
		1:
			return Core.s_type(p)
		2:
			return Core.egg(p)
		3:
			return Core.c_type(p)
		_:
			return Core.hairpin(p)

func _common() -> Dictionary:
	var sx := Ui.to_f(_fields["x_m"].text)
	var sy := Ui.to_f(_fields["y_m"].text)
	var az := Ui.to_f(_fields["bearing_deg"].text)
	if is_nan(sx) or is_nan(sy) or is_nan(az):
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "请填写起点坐标与切线方位（数字）"}
	var p := {"start": {"x_m": sx, "y_m": sy, "bearing_deg": az}}
	var d := Ui.to_f(_fields["dir"].text)
	if not is_nan(d):
		p["dir"] = 1 if d >= 0.0 else -1
	for key in ["r_m", "r2_m", "l0_m", "l02_m", "alpha_deg", "arc1_turn_deg", "arc2_turn_deg", "straight_m"]:
		var f := Ui.to_f(_fields[key].text)
		if not is_nan(f):
			p[key] = f
	# 别名映射：卵型/S型/C型 用 r1_m = r_m
	if p.has("r_m"):
		p["r1_m"] = p["r_m"]
	if p.has("alpha_deg"):
		p["arc1_turn_deg"] = p["arc1_turn_deg"]
	return p

func get_inputs() -> Dictionary:
	var out := super.get_inputs()
	out["type"] = str(_type_opt.selected)
	return out

func set_inputs(inputs: Dictionary) -> void:
	super.set_inputs(inputs)
	for key: String in _fields:
		if inputs.has(key):
			_fields[key].text = str(inputs[key])
	if inputs.has("type"):
		var idx := int(Ui.to_f(str(inputs["type"])))
		if idx >= 0 and idx < _type_opt.item_count:
			_type_opt.select(idx)
