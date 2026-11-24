# scenes/calculators/route/e3_dtm_volume.gd —— E3 DTM 三棱柱土方计算器
extends "res://scenes/widgets/calculator_base.gd"

const Core := preload("res://core/earthwork/dtm_volume.gd")
const Ui := preload("res://scenes/calculators/route/ui_common.gd")

func _ready() -> void:
	super._ready()
	add_input_row("设计高程（m）", "design_elev_m", "平面设计面，如 0")
	add_input_row("斜面 ix（z=z0+ix·x+iy·y）", "ix", "可选，平面 X 向坡")
	add_input_row("斜面 iy", "iy", "可选")
	add_input_row("三角形 x,y,z ×3（分号分行）", "triangles", "如 0,0,1; 100,0,2; 0,100,3", LineEdit.KEYBOARD_TYPE_DEFAULT)
	set_inputs(_example_inputs)

func get_title() -> String:
	return "DTM 法土方（E3）"

func get_description() -> String:
	return "V_tri = A·(h1+h2+h3)/3 逐三角形累加（线性高度场精确）；符号混合按零线分割精确分列填挖"

func get_entry_id() -> String:
	return "e3_dtm_volume"

func run() -> Dictionary:
	var rows := Ui.to_list_multi(_fields["triangles"].text, ";")
	if rows.size() % 3 != 0 or rows.is_empty():
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "三角形须为 3 的倍数行（每行 x,y,z，分号分行）"}
	var tris := []
	var errs := PackedStringArray()
	for i in range(0, rows.size(), 3):
		var vs := []
		for j in 3:
			var parts := Ui.to_list(rows[i + j])
			if parts.size() != 3:
				errs.append("第 %d 行应为 x,y,z 三个数" % (i + j + 1))
				vs = []
				break
			vs.append({"x_m": parts[0], "y_m": parts[1], "z_m": parts[2]})
		if vs.size() == 3:
			tris.append({"v1": vs[0], "v2": vs[1], "v3": vs[2]})
	if not errs.is_empty():
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "三角形格式有误：" + "；".join(errs)}
	var p := {"triangles": tris}
	var zd := Ui.to_f(_fields["design_elev_m"].text)
	var ix := Ui.to_f(_fields["ix"].text)
	var iy := Ui.to_f(_fields["iy"].text)
	if not is_nan(zd):
		p["design_elev_m"] = zd
	if not is_nan(ix) or not is_nan(iy):
		p["plane"] = {"z0": zd, "ix": ix, "iy": iy}
	return Core.forward(p)

func set_inputs(inputs: Dictionary) -> void:
	super.set_inputs(inputs)
	for key: String in _fields:
		if inputs.has(key):
			_fields[key].text = str(inputs[key])
