# scenes/calculators/projection/mgrs_inverse.gd —— a13_mgrs_inv MGRS 解码（A13）
# 计算器契约：继承 GKCalculatorBase（经 proj_calc_base），run() 返回 §5 协议。
extends "res://scenes/calculators/projection/proj_calc_base.gd"

const _MG := preload("res://core/projection/mgrs.gd")

func get_title() -> String:
	return "MGRS 解码（A13）"

func get_description() -> String:
	return "MGRS 串 → B/L（结果为方格中心；1m 精度时偏差 ≤0.5m）。"

func _setup() -> void:
	_add_row("MGRS 串", "mgrs", "如 50SMK4796917671", true, LineEdit.KEYBOARD_TYPE_DEFAULT)

func run() -> Dictionary:
	var p := _fail_or(_params())
	if bool(p.get("ok", true)) == false and p.has("error"):
		return p
	return _MG.inverse(p)
