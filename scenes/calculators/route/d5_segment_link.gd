# scenes/calculators/route/d5_segment_link.gd —— D5 超高/加宽/断链计算器
extends "res://scenes/widgets/calculator_base.gd"

const Core := preload("res://core/route/segment_link.gd")
const Ui := preload("res://scenes/calculators/route/ui_common.gd")

var _mode_opt: OptionButton
var _dir_opt: OptionButton

func _ready() -> void:
	super._ready()
	add_input_row("断链表 前=后（分号分行）", "breaks", "如 5000=5200; 8000=7900（前桩号=后桩号）")
	var row := HBoxContainer.new()
	var lab := Label.new()
	lab.text = "断链方向"
	lab.custom_minimum_size = Vector2(180, 0)
	row.add_child(lab)
	_dir_opt = OptionButton.new()
	_dir_opt.add_item("设计 → 实际")
	_dir_opt.add_item("实际 → 设计")
	_dir_opt.custom_minimum_size = Vector2(0, 96)
	row.add_child(_dir_opt)
	_inputs_root.add_child(row)
	add_input_row("待换算里程 (m)", "chains", "空格分隔，如 1000 4000 6000 9000")
	var row2 := HBoxContainer.new()
	var lab2 := Label.new()
	lab2.text = "超高/加宽模式"
	lab2.custom_minimum_size = Vector2(180, 0)
	row2.add_child(lab2)
	_mode_opt = OptionButton.new()
	_mode_opt.add_item("断链换算")
	_mode_opt.add_item("超高/加宽")
	_mode_opt.custom_minimum_size = Vector2(0, 96)
	row2.add_child(_mode_opt)
	_inputs_root.add_child(row2)
	add_input_row("半径 R (m)", "r_m", "超高用，如 500")
	add_input_row("缓和曲线长 l0 (m)", "l0_m", "如 60")
	add_input_row("转角 α (°)", "alpha_deg", "如 30")
	add_input_row("全超高 e_max (%)", "e_max_pct", "如 6")
	add_input_row("全加宽 w_max (m)", "w_max_m", "如 1.5，可选")
	add_input_row("查询弧长（自 ZH，m）", "query_m", "空格分隔，如 0 30 60 160.9")
	set_inputs(_example_inputs)

func get_title() -> String:
	return "超高/加宽/断链（D5）"

func get_description() -> String:
	return "断链里程双向换算（Δ=后−前，Δ<0 长链/桩号重复）；对称基本型曲线超高/加宽线性过渡取值（教学口径）"

func get_entry_id() -> String:
	return "d5_segment_link"

func run() -> Dictionary:
	if _mode_opt.selected == 0:
		return _run_breaks()
	return _run_super()

func _run_breaks() -> Dictionary:
	# 支持 "前=后" 或 "前 后" 两种行内写法
	var kv := Ui.to_kv_rows(_fields["breaks"].text.replace("=", " "), ["before_chain_m", "after_chain_m"])
	if not kv["errors"].is_empty():
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "断链表格式有误：" + "；".join(kv["errors"])}
	var rows: Array = kv["rows"]
	if rows.is_empty():
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "请输入断链表（每行 前=后 桩号）"}
	var chains := Ui.to_list(_fields["chains"].text)
	if chains.is_empty():
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "请输入待换算里程列表"}
	return Core.chain_convert({"breaks": rows, "chains_m": chains,
		"direction": "a2d" if _dir_opt.selected == 1 else "d2a"})

func _run_super() -> Dictionary:
	var p := {}
	for key in ["r_m", "l0_m", "alpha_deg", "e_max_pct", "w_max_m"]:
		var f := Ui.to_f(_fields[key].text)
		if not is_nan(f):
			p[key] = f
	var q := Ui.to_list(_fields["query_m"].text)
	if q.is_empty():
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "请输入查询弧长列表（自 ZH 起，m）"}
	p["query_m"] = q
	return Core.superelevation(p)

func get_inputs() -> Dictionary:
	var out := super.get_inputs()
	out["mode"] = str(_mode_opt.selected)
	out["dir"] = str(_dir_opt.selected)
	return out

func set_inputs(inputs: Dictionary) -> void:
	for key: String in _fields:
		if inputs.has(key):
			_fields[key].text = str(inputs[key])
	if inputs.has("mode"):
		var idx := int(Ui.to_f(str(inputs["mode"])))
		if idx >= 0 and idx < _mode_opt.item_count:
			_mode_opt.select(idx)
	if inputs.has("dir"):
		var idx2 := int(Ui.to_f(str(inputs["dir"])))
		if idx2 >= 0 and idx2 < _dir_opt.item_count:
			_dir_opt.select(idx2)
