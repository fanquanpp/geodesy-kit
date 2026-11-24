# scenes/calculators/projection/kml_point.gd —— a15_kml_point KML 点导出（A15）
# 计算器契约：继承 GKCalculatorBase（经 proj_calc_base），run() 返回 §5 协议。
extends "res://scenes/calculators/projection/proj_calc_base.gd"

const _KM := preload("res://core/projection/kml_export.gd")

func get_title() -> String:
	return "KML 点导出（A15）"

func get_description() -> String:
	return "生成 KML 2.2 Placemark 文本（坐标顺序 lon,lat,alt）；KMZ 压缩由平台层 ZIPPacker 完成。"

func _setup() -> void:
	_add_row("名称", "name", "如 天安门", false, LineEdit.KEYBOARD_TYPE_DEFAULT)
	_add_row("描述", "description", "可空", false, LineEdit.KEYBOARD_TYPE_DEFAULT)
	_add_row("纬度 B（°）", "lat_deg", "如 39.9075（WGS84）", true)
	_add_row("经度 L（°）", "lon_deg", "如 116.3913", true)
	_add_row("海拔 h（m）", "alt_m", "缺省 0", false)

func run() -> Dictionary:
	var p := _fail_or(_params())
	if bool(p.get("ok", true)) == false and p.has("error"):
		return p
	if not p.has("name"):
		p["name"] = "点位"
	return _KM.placemark(p)