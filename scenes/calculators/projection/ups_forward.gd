# scenes/calculators/projection/ups_forward.gd —— ups_fwd UPS 正算
# 计算器契约：继承 GKCalculatorBase（经 proj_calc_base），run() 返回 §5 协议。
extends "res://scenes/calculators/projection/proj_calc_base.gd"

const _UP := preload("res://core/projection/ups.gd")

func get_title() -> String:
	return "UPS 正算"

func get_description() -> String:
	return "极区 B/L → UPS 网格坐标（k0=0.994，FE/FN=2,000km；北域 B≥84°，南域 B<−80°）。"

func _setup() -> void:
	_add_row("纬度 B（°或度分秒）", "lat_deg", "如 85（北域）或 -85（南域）", true)
	_add_row("经度 L（°）", "lon_deg", "如 30", true)
	_add_row("半球（可空自动）", "hemisphere", "N / S，留空按纬度判定", false)
	_add_row("基准", "datum", "WGS84", false)

func run() -> Dictionary:
	var p := _fail_or(_params())
	if bool(p.get("ok", true)) == false and p.has("error"):
		return p
	return _UP.forward(p)
