# scenes/calculators/ellipsoid/m2_1_ellipsoid_params.gd —— M2-1 椭球参数与派生量计算器
# UI 契约：继承 GKCalculatorBase（scenes/widgets/calculator_base.gd），覆写 run()/get_inputs()/set_inputs()。
extends GKCalculatorBase

func get_title() -> String:
	return "椭球参数与派生量（M2-1）"

func get_description() -> String:
	return "内置椭球常数（CGCS2000/北京54/西安80/WGS84/GRS80 等）与派生量：b、e²、e′²、曲率半径 N/M、子午线弧长 X(B)、平均/等面积半径。可输入纬度 B 计算随纬度变化的量。"

func get_entry_id() -> String:
	return "m2_1_ellipsoid_params"

func _ready() -> void:
	# 顺序约定：先 super._ready()（基类建 UI 骨架并应用示例），再注册输入行，
	# 最后再应用一次示例（保证后注册的字段也拿到示例/历史回放值）
	super._ready()
	add_input_row("椭球名（可留空）", "datum", "CGCS2000 / WGS84 / KRASOVSKY / IUGG75 …", LineEdit.KEYBOARD_TYPE_DEFAULT)
	add_input_row("赤道半径 a（米）", "a_m", "留空则用椭球名查表")
	add_input_row("扁率倒数 1/f", "inv_f", "留空则用椭球名查表")
	add_input_row("纬度 B（度/度分秒）", "lat_deg", "30 或 30°00′00″，用于 N/M/X(B)")
	set_inputs(_example_inputs)

func get_inputs() -> Dictionary:
	return {
		"datum": _text_of("datum"),
		"a_m": _text_of("a_m"),
		"inv_f": _text_of("inv_f"),
		"lat_deg": _text_of("lat_deg"),
	}

func set_inputs(inputs: Dictionary) -> void:
	super.set_inputs(inputs)
	_set_text_of("datum", inputs)
	_set_text_of("a_m", inputs)
	_set_text_of("inv_f", inputs)
	_set_text_of("lat_deg", inputs)

func _text_of(key: String) -> String:
	var f: LineEdit = _fields.get(key, null)
	return "" if f == null else f.text

func _set_text_of(key: String, inputs: Dictionary) -> void:
	var f: LineEdit = _fields.get(key, null)
	if f != null and inputs.has(key):
		f.text = String(inputs[key])

func run() -> Dictionary:
	var datum := _text_of("datum").strip_edges()
	var a_txt := _text_of("a_m").strip_edges()
	var invf_txt := _text_of("inv_f").strip_edges()
	var el := {}
	if a_txt != "" and invf_txt != "":
		var a := GKCalcInputParse.parse_number(a_txt)
		var invf := GKCalcInputParse.parse_number(invf_txt)
		if is_nan(a) or is_nan(invf):
			return _err("赤道半径 a 与扁率倒数 1/f 需为数字（如 6378137 / 298.257222101）")
		el = GKEllipsoid.derived(a, invf)
		if el.is_empty():
			return _err("椭球参数不合法：要求 a > 0 且 1/f > 0")
	elif datum != "":
		el = GKEllipsoid.params(datum)
		if el.is_empty():
			return _err("未内置该椭球：%s（可选：%s）" % [datum, "、".join(GKEllipsoid.list_builtin())])
	elif datum == "" and a_txt == "" and invf_txt == "":
		el = GKEllipsoid.params("CGCS2000")
	else:
		return _err("a 与 1/f 需同时填写，或改用椭球名查表")
	var a: float = el["a"]
	var e2: float = el["e2"]
	var b: float = el["b"]
	# 纬度量（可选）
	var lat_txt := _text_of("lat_deg").strip_edges()
	var lat := 30.0
	var lat_given := false
	if lat_txt != "":
		lat = GKCalcInputParse.parse_angle(lat_txt)
		lat_given = true
		if not GKCalcInputParse.is_lat_ok(lat):
			return _err("纬度不合法：需 |B| ≤ 90° 且为数字或度分秒格式")
	var n := GKEllipsoid.radius_prime_vertical(a, e2, lat)
	var m := GKEllipsoid.radius_meridian(a, e2, lat)
	var x := GKEllipsoid.meridian_arc(a, e2, lat)
	var value := {
		"a_m": a, "inv_f": float(el["inv_f"]), "f": float(el["f"]),
		"b_m": b, "e2": e2, "ep2": float(el["ep2"]),
		"N_m": n, "M_m": m, "X_m": x,
		"R1_m": GKEllipsoid.mean_radius(a, b),
	}
	var steps := [
		{"title": "1. 椭球选择与基本常数",
			"formula": "f = 1/(1/f)；b = a(1−f)；e² = 2f − f²；e′² = e²/(1−e²)",
			"substitution": "a = %s m，1/f = %s" % [String.num(a, 4), String.num(float(el["inv_f"]), 9)],
			"result": "b = %s m，e² = %s，e′² = %s" % [String.num(b, 4), String.num(e2, 12), String.num(float(el["ep2"]), 12)]},
		{"title": "2. 曲率半径（B = %s°）" % String.num(lat, 4),
			"formula": "N = a/√(1−e²sin²B)；M = a(1−e²)/(1−e²sin²B)^1.5",
			"substitution": "sin B = %s" % String.num(sin(deg_to_rad(lat)), 9),
			"result": "N = %s m；M = %s m" % [String.num(n, 4), String.num(m, 4)]},
		{"title": "3. 子午线弧长（赤道起）",
			"formula": "X = a(1−e²)·Σ c_k·e^(2k)·I_k(B)（10 项级数，截断误差 < 1 nm）",
			"substitution": "B = %s°" % String.num(lat, 4),
			"result": "X = %s m" % String.num(x, 4)},
		{"title": "4. 平均半径与等面积半径",
			"formula": "R1 = (2a+b)/3；R2 = √[(a² + b²·atanh(e)/e)/2]",
			"substitution": "a、b 代入",
			"result": "R1 = %s m；R2 = %s m" % [String.num(value["R1_m"], 4), String.num(GKEllipsoid.authalic_radius(a, e2), 4)]},
	]
	if not lat_given:
		steps[1]["title"] = "2. 曲率半径（B 未填，按默认 30° 计算）"
	return {"ok": true, "value": value, "steps": steps,
			"formula": "椭球几何派生量（GB 22021-2008 / NIMA TR8350.2 常数口径）", "error": ""}

func _err(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "椭球几何派生量", "error": msg}
