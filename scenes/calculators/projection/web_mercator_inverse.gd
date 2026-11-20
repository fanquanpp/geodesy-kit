# scenes/calculators/projection/web_mercator_inverse.gd —— a14_web_mercator_inv Web墨卡托反算（A14）
# 计算器契约：继承 GKCalculatorBase（经 proj_calc_base），run() 返回 §5 协议。
extends "res://scenes/calculators/projection/proj_calc_base.gd"

const _MC := preload("res://core/projection/mercator.gd")

func get_title() -> String:
	return "Web墨卡托反算（A14）"

func get_description() -> String:
	return "Web 地图米制坐标 → B/L。"

func _setup() -> void:
	_add_row("x（m）", "x_m", "如 12956617.544", true)
	_add_row("y（m）", "y_m", "如 4852513.528", true)

func run() -> Dictionary:
	var p := _fail_or(_params())
	if bool(p.get("ok", true)) == false and p.has("error"):
		return p
	return _MC.inverse(p)
