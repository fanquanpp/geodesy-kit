# scenes/calculators/projection/utm_inverse.gd —— a7_utm_inv UTM 反算（A7）
# 计算器契约：继承 GKCalculatorBase（经 proj_calc_base），run() 返回 §5 协议。
extends "res://scenes/calculators/projection/proj_calc_base.gd"

const _UT := preload("res://core/projection/utm.gd")

func get_title() -> String:
	return "UTM 反算（A7）"

func get_description() -> String:
	return "UTM 网格坐标 → B/L（需带号与半球）。"

func _setup() -> void:
	_add_row("带号", "zone", "1..60", true)
	_add_row("半球", "hemisphere", "N / S（或 北/南）", true)
	_add_row("东坐标 E（m）", "e_m", "如 399002.5708", true)
	_add_row("北坐标 N（m）", "n_m", "如 4832935.3412", true)
	_add_row("基准", "datum", "WGS84 / 其他", false)

func run() -> Dictionary:
	var p := _fail_or(_params())
	if bool(p.get("ok", true)) == false and p.has("error"):
		return p
	return _UT.inverse(p)
