# scenes/calculators/projection/ups_inverse.gd —— ups_inv UPS 反算
# 计算器契约：继承 GKCalculatorBase（经 proj_calc_base），run() 返回 §5 协议。
extends "res://scenes/calculators/projection/proj_calc_base.gd"

const _UP := preload("res://core/projection/ups.gd")

func get_title() -> String:
	return "UPS 反算"

func get_description() -> String:
	return "UPS 网格坐标 → B/L。南北半球网格重叠，南半球请显式填半球 S（留空按北半球处理）。"

func _setup() -> void:
	_add_row("东坐标 E（m）", "e_m", "如 2277728.6957", true)
	_add_row("北坐标 N（m）", "n_m", "如 1518959.7883", true)
	_add_row("半球", "hemisphere", "N / S，留空按北半球处理", false, LineEdit.KEYBOARD_TYPE_DEFAULT)
	_add_row("基准", "datum", "WGS84", false, LineEdit.KEYBOARD_TYPE_DEFAULT)

func run() -> Dictionary:
	var p := _fail_or(_params())
	if bool(p.get("ok", true)) == false and p.has("error"):
		return p
	return _UP.inverse(p)
