# scenes/calculators/ellipsoid/f2_geoid_egm2008.gd —— F2 高程异常（EGM2008）计算器
# 数据链：GKDataService.egm2008_grid() 读盘 → core 解析字节并插值（core 不读盘）。
# 精度诚实：5′ 格网三次插值误差约 ±0.1~0.3 m（山区更差），见步骤说明。
extends GKCalculatorBase

func get_title() -> String:
	return "高程异常查询（EGM2008）（F2）"

func get_description() -> String:
	return "查 EGM2008 5′ 格网的大地水准面差距（高程异常 ζ）：ζ = h_大地 − H_正常。三次插值（GeographicLib 口径），离线数据随包内置。"

func get_entry_id() -> String:
	return "f2_geoid_egm2008"

func _ready() -> void:
	super._ready()
	add_input_row("纬度 B（度/度分秒）", "lat_deg", "39°54′27.1″ 或 39.9075")
	add_input_row("经度 L（度/度分秒）", "lon_deg", "116°23′28.6″ 或 116.3913")
	set_inputs(_example_inputs)

func get_inputs() -> Dictionary:
	return _snapshot(["lat_deg", "lon_deg"])

func set_inputs(inputs: Dictionary) -> void:
	super.set_inputs(inputs)
	for key: String in ["lat_deg", "lon_deg"]:
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
	var lat_txt := _txt("lat_deg")
	var lon_txt := _txt("lon_deg")
	if lat_txt == "" or lon_txt == "":
		return _err("请填写纬度与经度")
	var lat := GKCalcInputParse.parse_angle(lat_txt)
	var lon := GKCalcInputParse.parse_angle(lon_txt)
	if is_nan(lat) or is_nan(lon):
		return _err("经纬度格式不合法：支持十进制度（39.9075）或度分秒（39°54′27.1″）")
	var grid := GKDataService.egm2008_grid()
	if grid == null:
		return _err("EGM2008 格网数据未就位：res://data/geoids/egm2008-5.pgm 缺失或损坏")
	var r := GKGeoidEGM2008.query({"grid": grid, "lat_deg": lat, "lon_deg": lon})
	if not bool(r.get("ok", false)):
		return r
	var v: Dictionary = r["value"]
	v["note"] = "5′ 格网三次插值误差约 ±0.1~0.3 m（山区更大），教学演示口径"
	return r

func _err(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "EGM2008 高程异常（PGM 5′）", "error": msg}
