# scenes/calculators/topics/i_photo_collinearity.gd —— I-摄影 共线方程/后方/前方交会（三模式）
extends "res://scenes/calculators/topics/topics_calc_base.gd"

const CORE := preload("res://core/topics/photogrammetry.gd")

func _init() -> void:
	_entry_id = "i_photo_collinearity"
	_example_inputs = {
		"mode": "共线方程",
		"f": "100",
		"controls": "-20,-20,0,20,15;20,-20,0,-20,15;20,20,0,-20,-15;-20,20,0,20,-15",
		"Xs": "0", "Ys": "0", "Zs": "100",
		"phi_deg": "0", "omega_deg": "0", "kappa_deg": "180",
		"points": "-20,-15,0;20,-15,0;20,15,0;-20,15,0",
		"pt_left": "", "ext_right": "",
	}

func get_title() -> String:
	return "共线方程/后方/前方交会（I）"

func get_description() -> String:
	return "模式一（共线方程正算）：输入外方位与物点列表 X,Y,Z;… → 像平面坐标。模式二（空间后方交会）：控制点 X,Y,Z,x,y;…（≥3 点，建议 ≥4 且非共面）迭代解 6 个外方位元素。模式三（前方交会）：左右片外方位与同名像点 x,y → 物方坐标。φ-ω-κ 主轴系，角度为度。"

func _build_rows() -> void:
	add_input_row("计算模式", "mode", "共线方程")
	add_input_row("焦距 f", "f", "100")
	add_input_row("控制点（X,Y,Z,x,y;…）", "controls", "-20,-20,0,20,15;…")
	add_input_row("Xs", "Xs", "0")
	add_input_row("Ys", "Ys", "0")
	add_input_row("Zs", "Zs", "100")
	add_input_row("φ（°）", "phi_deg", "0")
	add_input_row("ω（°）", "omega_deg", "0")
	add_input_row("κ（°）", "kappa_deg", "180")
	add_input_row("物点列表（X,Y,Z;…）", "points", "")
	add_input_row("左片像点（x,y）", "pt_left", "")
	add_input_row("右片外方位（JSON 或留空）", "ext_right", "")
	add_input_row("右片像点（x,y）", "pt_right", "")

func _ext_dict(bad: Array) -> Dictionary:
	var p := {
		"f": num_field(_fields["f"], "焦距", bad),
		"Xs": num_field(_fields["Xs"], "Xs", bad),
		"Ys": num_field(_fields["Ys"], "Ys", bad),
		"Zs": num_field(_fields["Zs"], "Zs", bad),
		"phi_deg": num_field(_fields["phi_deg"], "φ", bad),
		"omega_deg": num_field(_fields["omega_deg"], "ω", bad),
		"kappa_deg": num_field(_fields["kappa_deg"], "κ", bad),
	}
	return p

func run() -> Dictionary:
	var bad := []
	var mode: String = _fields["mode"].text.strip_edges()
	var f := num_field(_fields["f"], "焦距", bad)
	if not bad.is_empty():
		return fail_input(bad)
	if mode == "共线方程":
		var p := _ext_dict(bad)
		var pts := text_field(_fields["points"], "物点列表", bad)
		if not bad.is_empty():
			return fail_input(bad)
		p["points"] = pts
		return CORE.collinearity(p)
	if mode == "前方交会":
		var p2 := {"f": f}
		var pt_left := text_field(_fields["pt_left"], "左片像点", bad)
		var pt_right := text_field(_fields["pt_right"], "右片像点", bad)
		var ext_r_text: String = _fields["ext_right"].text.strip_edges()
		if not bad.is_empty():
			return fail_input(bad)
		if ext_r_text.is_empty():
			return {"ok": false, "value": {}, "steps": [], "formula": "",
					"error": "前方交会需右片外方位：请提供 JSON（含 f,Xs,Ys,Zs,phi_deg,omega_deg,kappa_deg）"}
		var parsed: Variant = JSON.parse_string(ext_r_text)
		if not (parsed is Dictionary):
			return {"ok": false, "value": {}, "steps": [], "formula": "",
					"error": "右片外方位 JSON 解析失败（应为含 f/Xs/Ys/Zs/phi_deg/omega_deg/kappa_deg 的对象）"}
		p2["ext_left"] = _ext_dict(bad)
		if not bad.is_empty():
			return fail_input(bad)
		p2["ext_right"] = parsed
		p2["pt_left"] = pt_left
		p2["pt_right"] = pt_right
		return CORE.forward_intersection(p2)
	# 默认：空间后方交会
	var controls := text_field(_fields["controls"], "控制点", bad)
	if not bad.is_empty():
		return fail_input(bad)
	var p3 := {"f": f, "controls": controls}
	for key in ["Xs", "Ys", "Zs", "phi_deg", "omega_deg", "kappa_deg"]:
		var v := opt_num_field(_fields[key], NAN, key, bad)
		if not bad.is_empty():
			return fail_input(bad)
		if is_finite(v):
			p3["init_" + key if key.begins_with("phi") or key.begins_with("omega") or key.begins_with("kappa") else key] = v
	return CORE.resection(p3)
