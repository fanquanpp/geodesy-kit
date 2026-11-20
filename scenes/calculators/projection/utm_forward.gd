# scenes/calculators/projection/utm_forward.gd —— a7_utm_fwd UTM 正算（A7）
# 计算器契约：继承 GKCalculatorBase（经 proj_calc_base），run() 返回 §5 协议。
extends "res://scenes/calculators/projection/proj_calc_base.gd"

const _UT := preload("res://core/projection/utm.gd")

func get_title() -> String:
	return "UTM 正算（A7）"

func get_description() -> String:
	return "B/L → UTM 网格坐标（k0=0.9996，FE=500km，南半球 FN=10,000km；含挪威/斯瓦尔巴例外选带）。"

func _setup() -> void:
	_add_row("纬度 B（°或度分秒）", "lat_deg", "如 43.642556", true)
	_add_row("经度 L（°或度分秒）", "lon_deg", "如 -70.252228", true)
	_add_row("带号（可空自动）", "zone", "1..60，留空自动选带", false)
	_add_row("基准", "datum", "WGS84 / 其他", false)

func run() -> Dictionary:
	var p := _fail_or(_params())
	if bool(p.get("ok", true)) == false and p.has("error"):
		return p
	return _UT.forward(p)
