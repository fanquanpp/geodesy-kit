# scenes/calculators/ellipsoid/a11_geodesic.gd —— A11 大地线正反解 计算器
# 双向：填 B2/L2 → 反解（方位与距离）；填 α₁/s₁₂ → 正解（终点坐标与反方位）。
# Karney 算法（移植 geographiclib-js v2.2.0，MIT），容差 s12 相对 1e-9、方位 1e-8°。
extends GKCalculatorBase

func get_title() -> String:
	return "大地线正反解（A11）"

func get_description() -> String:
	return "反解：两点 → 正反方位角与大地线长；正解：起点+方位+距离 → 终点。填 B₂/L₂ 走反解，填 α₁/s₁₂ 走正解。角度支持度分秒或十进制度。近对跖情形若不收敛会给出中文提示。"

func get_entry_id() -> String:
	return "a11_geodesic"

func _ready() -> void:
	super._ready()
	add_input_row("椭球（datum 名）", "datum", "CGCS2000 / WGS84，留空按 WGS84", LineEdit.KEYBOARD_TYPE_DEFAULT)
	add_input_row("B₁（度/度分秒）", "lat1_deg", "起点纬度")
	add_input_row("L₁（度/度分秒）", "lon1_deg", "起点经度")
	add_input_row("B₂（度/度分秒）", "lat2_deg", "反解：终点纬度")
	add_input_row("L₂（度/度分秒）", "lon2_deg", "反解：终点经度")
	add_input_row("α₁ 方位角（度/度分秒）", "azi1_deg", "正解：起点方位角")
	add_input_row("s₁₂ 距离（米）", "s12_m", "正解：大地线长")
	set_inputs(_example_inputs)

func get_inputs() -> Dictionary:
	return _snapshot(["datum", "lat1_deg", "lon1_deg", "lat2_deg", "lon2_deg", "azi1_deg", "s12_m"])

func set_inputs(inputs: Dictionary) -> void:
	super.set_inputs(inputs)
	for key: String in ["datum", "lat1_deg", "lon1_deg", "lat2_deg", "lon2_deg", "azi1_deg", "s12_m"]:
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
	var p := {"datum": _txt("datum")}
	var inv_given := _txt("lat2_deg") != "" or _txt("lon2_deg") != ""
	var fwd_given := _txt("azi1_deg") != "" or _txt("s12_m") != ""
	if inv_given and fwd_given:
		return _err("反解（B₂/L₂）与正解（α₁/s₁₂）输入同时存在，请清空其中一组")
	if not inv_given and not fwd_given:
		return _err("请填写 B₂/L₂（反解）或 α₁/s₁₂（正解）其中一组")
	# 公共起点
	var a1 := _angle_or_err("lat1_deg", "B₁")
	if bool(a1["nan"]):
		return _err(String(a1["err"]))
	var o1 := _angle_or_err("lon1_deg", "L₁")
	if bool(o1["nan"]):
		return _err(String(o1["err"]))
	p["lat1_deg"] = float(a1["v"])
	p["lon1_deg"] = float(o1["v"])
	if inv_given:
		var a2 := _angle_or_err("lat2_deg", "B₂")
		if bool(a2["nan"]):
			return _err(String(a2["err"]))
		var o2 := _angle_or_err("lon2_deg", "L₂")
		if bool(o2["nan"]):
			return _err(String(o2["err"]))
		p["lat2_deg"] = float(a2["v"])
		p["lon2_deg"] = float(o2["v"])
		var r := GKGeodesic.inverse(p)
		if not bool(r.get("ok", false)):
			return r
		r["value"]["note"] = "s12 相对精度 1e-9，方位角精度 1e-8°"
		return r
	var az := _angle_or_err("azi1_deg", "α₁")
	if bool(az["nan"]):
		return _err(String(az["err"]))
	var s_txt := _txt("s12_m")
	var s := GKCalcInputParse.parse_number(s_txt)
	if is_nan(s):
		return _err("s₁₂ 需为数字（米）")
	p["azi1_deg"] = float(az["v"])
	p["s12_m"] = s
	var r2 := GKGeodesic.direct(p)
	if not bool(r2.get("ok", false)):
		return r2
	r2["value"]["note"] = "终点精度：坐标 1e-8°"
	return r2

func _err(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "大地线正反解（Karney / geographiclib-js）", "error": msg}
