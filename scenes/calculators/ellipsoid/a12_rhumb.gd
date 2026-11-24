# scenes/calculators/ellipsoid/a12_rhumb.gd —— A12 恒向线（等角航线）计算器
# 双向：填 B₂/L₂ → 正解（距离与方位）；填 α/s → 反解（终点）。
# 精确 Mercator 参数法（Δψ 等量纬度），R₁=(2a+b)/3 可用自定义半径覆盖。
extends GKCalculatorBase

func get_title() -> String:
	return "恒向线计算（等角航线）（A12）"

func get_description() -> String:
	return "恒向线（loxodrome）：方位角处处相等的航线。精确 Mercator 参数法：Δψ = ln tan(π/4+φ/2)。填 B₂/L₂ 走正解，填 α/s 走反解。半径默认 WGS84 R₁=(2a+b)/3=6371008.7714 m。"

func get_entry_id() -> String:
	return "a12_rhumb"

func _ready() -> void:
	super._ready()
	add_input_row("平均半径 R（米，可留空）", "radius_m", "留空用 WGS84 R₁")
	add_input_row("椭球（datum 名）", "datum", "CGCS2000 / WGS84", LineEdit.KEYBOARD_TYPE_DEFAULT)
	add_input_row("B₁（度/度分秒）", "lat1_deg", "起点纬度")
	add_input_row("L₁（度/度分秒）", "lon1_deg", "起点经度")
	add_input_row("B₂（度/度分秒）", "lat2_deg", "正解：终点纬度")
	add_input_row("L₂（度/度分秒）", "lon2_deg", "正解：终点经度")
	add_input_row("α 恒向线方位（度/度分秒）", "az_deg", "反解：恒向方位角")
	add_input_row("s 航程（米）", "distance_m", "反解：航程")
	set_inputs(_example_inputs)

func get_inputs() -> Dictionary:
	return _snapshot(["radius_m", "datum", "lat1_deg", "lon1_deg", "lat2_deg", "lon2_deg", "az_deg", "distance_m"])

func set_inputs(inputs: Dictionary) -> void:
	super.set_inputs(inputs)
	for key: String in ["radius_m", "datum", "lat1_deg", "lon1_deg", "lat2_deg", "lon2_deg", "az_deg", "distance_m"]:
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

func _angle_or_err(key: String, label: String) -> Dictionary:
	var t := _txt(key)
	if t.is_empty():
		return {"nan": true, "err": "%s 未填写" % label}
	var v := GKCalcInputParse.parse_angle(t)
	if is_nan(v):
		return {"nan": true, "err": "%s 格式不合法：支持十进制度或度分秒" % label}
	return {"nan": false, "v": v}

func run() -> Dictionary:
	var p := {}
	var r_txt := _txt("radius_m")
	var datum := _txt("datum")
	if r_txt != "":
		var r := GKCalcInputParse.parse_number(r_txt)
		if is_nan(r):
			return _err("平均半径 R 需为数字（米）")
		p["radius_m"] = r
	elif datum != "":
		p["datum"] = datum
	var fwd_given := _txt("lat2_deg") != "" or _txt("lon2_deg") != ""
	var inv_given := _txt("az_deg") != "" or _txt("distance_m") != ""
	if fwd_given and inv_given:
		return _err("正解（B₂/L₂）与反解（α/s）输入同时存在，请清空其中一组")
	if not fwd_given and not inv_given:
		return _err("请填写 B₂/L₂（正解）或 α/s（反解）其中一组")
	var a1 := _angle_or_err("lat1_deg", "B₁")
	if bool(a1["nan"]):
		return _err(String(a1["err"]))
	var o1 := _angle_or_err("lon1_deg", "L₁")
	if bool(o1["nan"]):
		return _err(String(o1["err"]))
	p["lat1_deg"] = float(a1["v"])
	p["lon1_deg"] = float(o1["v"])
	if fwd_given:
		var a2 := _angle_or_err("lat2_deg", "B₂")
		if bool(a2["nan"]):
			return _err(String(a2["err"]))
		var o2 := _angle_or_err("lon2_deg", "L₂")
		if bool(o2["nan"]):
			return _err(String(o2["err"]))
		p["lat2_deg"] = float(a2["v"])
		p["lon2_deg"] = float(o2["v"])
		return GKRhumb.forward(p)
	var az := _angle_or_err("az_deg", "方位角 α")
	if bool(az["nan"]):
		return _err(String(az["err"]))
	var d := GKCalcInputParse.parse_number(_txt("distance_m"))
	if is_nan(d):
		return _err("航程 s 需为数字（米）")
	p["az_deg"] = float(az["v"])
	p["distance_m"] = d
	return GKRhumb.inverse(p)

func _err(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "恒向线（精确 Mercator 参数法）", "error": msg}
