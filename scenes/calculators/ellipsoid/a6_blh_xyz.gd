# scenes/calculators/ellipsoid/a6_blh_xyz.gd —— A6 大地坐标↔空间直角坐标 计算器
# 双向：填 B/L/h → 正算 XYZ；填 X/Y/Z → 反算 BLH（两组都填或都空给中文提示）。
# 角度输入支持度分秒（53°48′33.82″）与十进制度（53.8094）。
extends GKCalculatorBase

func get_title() -> String:
	return "大地坐标 BLH ↔ 空间直角坐标 XYZ（A6）"

func get_description() -> String:
	return "EPSG 9602 闭式正算 + Bowring 闭式反算（EPSG Guidance Note 7-2 §4.1.1）。纬度/经度支持度分秒（53°48′33.82″）或十进制度。"

func get_entry_id() -> String:
	return "a6_blh_xyz"

func _ready() -> void:
	super._ready()
	add_input_row("椭球（datum 名）", "datum", "CGCS2000 / WGS84，留空按 WGS84")
	add_input_row("纬度 B（度/度分秒）", "lat_deg", "53°48′33.82″ 或 53.8094")
	add_input_row("经度 L（度/度分秒）", "lon_deg", "2°07′46.38″ 或 2.12955")
	add_input_row("大地高 h（米）", "h_m", "73")
	add_input_row("X（米）", "x_m", "反算时填写")
	add_input_row("Y（米）", "y_m", "反算时填写")
	add_input_row("Z（米）", "z_m", "反算时填写")
	set_inputs(_example_inputs)

func get_inputs() -> Dictionary:
	return _snapshot(["datum", "lat_deg", "lon_deg", "h_m", "x_m", "y_m", "z_m"])

func set_inputs(inputs: Dictionary) -> void:
	for key: String in ["datum", "lat_deg", "lon_deg", "h_m", "x_m", "y_m", "z_m"]:
		_fill(key, inputs)

func _snapshot(keys: Array) -> Dictionary:
	var out := {}
	for k: String in keys:
		var f: LineEdit = _fields.get(k, null)
		out[k] = "" if f == null else f.text
	return out

func _fill(key: String, inputs: Dictionary) -> void:
	var f: LineEdit = _fields.get(key, null)
	if f != null and inputs.has(key):
		f.text = String(inputs[key])

func _txt(key: String) -> String:
	var f: LineEdit = _fields.get(key, null)
	return "" if f == null else f.text.strip_edges()

func run() -> Dictionary:
	var p := {"datum": _txt("datum")}
	var lat_txt := _txt("lat_deg")
	var lon_txt := _txt("lon_deg")
	var h_txt := _txt("h_m")
	var x_txt := _txt("x_m")
	var y_txt := _txt("y_m")
	var z_txt := _txt("z_m")
	var fwd_given := lat_txt != "" or lon_txt != "" or h_txt != ""
	var inv_given := x_txt != "" or y_txt != "" or z_txt != ""
	if fwd_given and inv_given:
		return _err("BLH 与 XYZ 两组输入同时填写，请清空其中一组")
	if not fwd_given and not inv_given:
		return _err("请填写 B/L/h（正算）或 X/Y/Z（反算）其中一组")
	if fwd_given:
		p["lat_deg"] = GKCalcInputParse.parse_angle(lat_txt)
		p["lon_deg"] = GKCalcInputParse.parse_angle(lon_txt)
		p["h_m"] = GKCalcInputParse.parse_number(h_txt)
		if is_nan(float(p["lat_deg"])) or is_nan(float(p["lon_deg"])):
			return _err("纬度/经度格式不合法：支持十进制度（53.8094）或度分秒（53°48′33.82″）")
		if is_nan(float(p["h_m"])):
			return _err("大地高 h 需为数字（米）")
		var r := GKBlhXYZ.forward(p)
		if not bool(r.get("ok", false)):
			return r
		r["formula"] = "BLH→XYZ 闭式正算（EPSG 9602，Bowring ε 参数反算同族）"
		return r
	p["x_m"] = GKCalcInputParse.parse_number(x_txt)
	p["y_m"] = GKCalcInputParse.parse_number(y_txt)
	p["z_m"] = GKCalcInputParse.parse_number(z_txt)
	if is_nan(float(p["x_m"])) or is_nan(float(p["y_m"])) or is_nan(float(p["z_m"])):
		return _err("X/Y/Z 需为数字（米）")
	var r2 := GKBlhXYZ.inverse(p)
	if not bool(r2.get("ok", false)):
		return r2
	r2["formula"] = "XYZ→BLH 闭式反算（Bowring 法，EPSG Guidance Note 7-2）"
	return r2

func _err(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "BLH↔XYZ（EPSG 9602 / Bowring）", "error": msg}
