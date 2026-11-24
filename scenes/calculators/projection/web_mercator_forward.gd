# scenes/calculators/projection/web_mercator_forward.gd —— a14_web_mercator_fwd Web墨卡托正算（A14）
# 计算器契约：继承 GKCalculatorBase（经 proj_calc_base），run() 返回 §5 协议。
extends "res://scenes/calculators/projection/proj_calc_base.gd"

const _MC := preload("res://core/projection/mercator.gd")

func get_title() -> String:
	return "Web墨卡托正算（A14）"

func get_description() -> String:
	return "B/L → Web 地图米制坐标（球面公式，|B| ≤ 85.05112878°；EPSG:3857 定义）。"

func _setup() -> void:
	_add_row("纬度 B（°或度分秒）", "lat_deg", "如 39.9075276", true)
	_add_row("经度 L（°）", "lon_deg", "如 116.3912757", true)

func run() -> Dictionary:
	var p := _fail_or(_params())
	if bool(p.get("ok", true)) == false and p.has("error"):
		return p
	return _MC.forward(p)
